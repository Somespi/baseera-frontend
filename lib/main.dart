// ignore_for_file: empty_catches, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basera/pages/ar_route.dart';
import 'package:basera/pages/maps_route.dart';
import 'package:basera/pages/ocr_route.dart';
import 'package:basera/services/maps.dart';
import 'package:basera/services/ocr/ocr.dart';
import 'package:basera/services/speech_to_text.dart';
import 'package:basera/services/uber_service.dart';
import 'package:basera/services/vqa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'services/help_utilities.dart';
import 'services/priority_manager.dart' as priority_manager;
import 'services/text_to_speech.dart';

import 'package:http/http.dart' as http;

late List<String> labels;
DateTime lastImageTime = DateTime.now();
TextToSpeechService ttsService = TextToSpeechService();
SpeechToTextService speechToTextService = SpeechToTextService();

Position? destination;
bool isDirectionServiceRunning = false;
bool isListeningToPlace = false;
int lastDirectedStep = -1;
dynamic directionsSegments;

bool isListeningToPlaceForTaxi = false;
bool isConfirmingTaxiForOuterPlace = false;

String lastSentData = "";
bool isRasberryConnected = false;

String connectedIp = "";

const routes = <Widget?>[null, DocumentsPage(), MapsRoutePage(), ARroutePage()];
const titles = <String>[
  "الصفحة الرئيسية",
  "المستندات",
  "المواقع",
  "الماسح الضوئي"
];
var assistiveUnits = [
  {
    "name": "خلية برايل",
    "deviceName": "3C:84:27:C3:33:99",
    "connectedDevice": null,
    "connectedCharacteristic": null,
    "connectedService": null,
    "isConnected": false,
    "chars": "beb5483e-36e1-4688-b7f5-ea07361b26a",
    "image": "assets/icons/braille.png",
    "description":
        "جهاز بريل يترجم النصوص المكتوبة إلى نقاط بارزة لتمكين الأشخاص ذوي الاحتياج البصري والسمعي من قراءتها بشكل مستقل.",
  },
  {
    "name": "هزازات الحركة",
    "deviceName": "24:D7:EB:0F:09:02",
    "connectedDevice": null,
    "connectedCharacteristic": null,
    "connectedService": null,
    "chars": "beb5483e-36e1-4688-b7f5-ea07361b26a",
    "isConnected": false,
    "image": "assets/icons/motion.png",
    "description":
        "جهاز هزازات الحركة يترجم النصوص المكتوبة في الحركة بشكل مستقل.",
  },
];

void main() async {
  OrtEnv.instance.init();
  WidgetsFlutterBinding.ensureInitialized();
  final rootIsolateToken = RootIsolateToken.instance;
  if (rootIsolateToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
  } else {
    printDebug(
        "Error: Root Isolate Token is null. Ensure this runs on the main isolate.");
    exit(1);
  }
  await ttsService.initTTS();
  await speechToTextService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'بصيرة',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        fontFamily: GoogleFonts.rubik().fontFamily,
      ),
      home: Directionality(
        // add this
        textDirection: TextDirection.rtl, // set this property
        child: const MyHomePage(title: 'بصيرة'),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

Uint8List encodeAsPng(Uint8List rawData, int width, int height) {
  final image =
      img.Image.fromBytes(bytes: rawData.buffer, height: height, width: width);
  return Uint8List.fromList(img.encodePng(image));
}

class _MyHomePageState extends State<MyHomePage> {
  bool _isLoading = false;
  bool isPersonMoving = false;
  StreamSubscription? _gyroscopeSubscription;
  bool isUsingCamera = false;

  late List<String> oCRterms;
  late List<String> mapsTerms;
  late List<String> taxiTerms;

  int _selectedIndex = 0;
  BluetoothCharacteristic? _txRxDevice;
  bool _lastIsPersonMoving = false;
  bool isPerformingAction = false;
  bool _isAsking = false;
  String foundDeviceName = "";
  bool isScanning = false;

  List<Map<String, dynamic>?> previousObjects = [];

  @override

  /// Initializes the object detection model and starts listening to the
  /// gyroscope.
  ///
  /// This function is called when the widget is inserted into the tree.
  /// It loads the model and starts listening to the gyroscope event stream.
  void initState() {
    super.initState();
    _initializeModel();
    _initializeGyroscope();
    getPermissions();
    _handleLocationPermission();
  }

  /// Initializes the object detection model.
  ///
  /// This function loads the model from a file and assigns it to the
  /// [_interpreter] field. It also sets the [_isLoading] field to true
  /// while the model is loading, and false when it is finished.
  ///
  /// The model is loaded in a separate isolate, so that it does not block
  /// the main thread.
  Future<void> _initializeModel() async {
    setState(() {
      _isLoading = false;
    });

    oCRterms = await Ocr.loadTerms();
    mapsTerms = await Maps.loadTerms();
    taxiTerms = await UberService.loadTerms();

    setState(() {
      _isLoading = false;
    });
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Location services are disabled. Please enable the services')));
      return false;
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')));
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Location permissions are permanently denied, we cannot request permissions.')));
      return false;
    }
    return true;
  }

  void _initializeGyroscope() {
    const double movementThreshold = 0.2;
    // Subscribe to the gyroscope event stream
    _gyroscopeSubscription =
        gyroscopeEventStream().listen((GyroscopeEvent event) {
      // Calculate the magnitude of the gyroscope reading
      final double magnitude =
          (event.x * event.x) + (event.y * event.y) + (event.z * event.z);
      setState(() {
        isPersonMoving = magnitude > movementThreshold;
        if (isPersonMoving != _lastIsPersonMoving) {
          _lastIsPersonMoving = isPersonMoving;
          if (_txRxDevice != null) {
            _txRxDevice!
                .write(utf8.encode("gyro,${_lastIsPersonMoving ? 1 : 0}"));
          }
        }
      });
    });
  }

  @override
  void dispose() async {
    OrtEnv.instance.release();
    speechToTextService.dispose();
    _gyroscopeSubscription?.cancel();
    super.dispose();
  }

  Future getPermissions() async {
    try {
      await Permission.bluetooth.request();
    } catch (e) {
      printDebug(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
            title: Text(
          titles[_selectedIndex],
          style: TextStyle(fontFamily: 'Changa'),
        )),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        selectedIndex: _selectedIndex,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.document_scanner),
            label: 'المستندات',
          ),
          NavigationDestination(
            icon: Icon(Icons.location_pin),
            label: 'المواقع',
          ),
          NavigationDestination(
            icon: Icon(Icons.crop_square_rounded),
            label: 'الماسح الضوئي',
          ),
        ],
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
      backgroundColor: Color.fromRGBO(243, 243, 243, 1),
      appBar: AppBar(
        title: Text(
          titles[_selectedIndex],
          style: TextStyle(
              fontFamily: 'Changa', fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          isDirectionServiceRunning || isListeningToPlace
              ? FloatingActionButton(
                  heroTag: "أيقاف الموقع",
                  child: Icon(Icons.location_pin),
                  onPressed: () {
                    setState(() async {
                      isListeningToPlace = false;
                      isDirectionServiceRunning = false;
                      lastDirectedStep = -1;
                      directionsSegments = null;
                      await ttsService.speak("تم إيقاف التنقل");
                      await writeToBraille("تم إيقاف التنقل");
                    });
                  },
                )
              : SizedBox(height: 0.0),
          SizedBox(height: 10.0),
          FloatingActionButton(
              heroTag: "camera",
              onPressed: () async {
                printDebug("Detecting press...");
                readFromBLEStream();
              },
              child: !isRasberryConnected
                  ? isScanning
                      ? const CircularProgressIndicator()
                      : const Icon(Icons.camera)
                  : const Icon(Icons.stop_circle_outlined)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _selectedIndex != 0
            ? routes[_selectedIndex]!
            : Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(15.0),
                    onTap: () async {
                      await _askQuestion();
                      //await speechToTextService.stopListening();
                    },
                    child: Card(
                      color: Color.fromRGBO(236, 246, 255, 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15.0),
                        side: BorderSide(
                          color: _isAsking
                              ? Color.fromRGBO(0, 168, 129, 1)
                              : Color.fromRGBO(0, 76, 168, 1),
                          width: _isAsking ? 2.0 : 0.7,
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Flex(direction: Axis.horizontal, children: [
                              Image(
                                image: AssetImage('assets/icons/eye.png'),
                                width: 100.0,
                                height: 100.0,
                              ),
                              //const Spacer(),
                              Center(
                                child: Text(
                                  "استفسر عن ما يحيطك",
                                  style: GoogleFonts.rubik(
                                    textStyle: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ])),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30.0),
                  Text("الوحدات المساعدة (AUs)",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Changa',
                        color: Color.fromARGB(255, 0, 0, 0),
                        fontSize: 14,
                      )),
                  const SizedBox(height: 10.0),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,
                      children: assistiveUnits.map((au) {
                        return Card(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15.0),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  au['name'] as String,
                                  style: GoogleFonts.rubik(
                                    textStyle: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20),
                                  ),
                                ),
                                //const SizedBox(height: 8.0),
                                Image(
                                  image: AssetImage(au['image'] as String),
                                  width: 100.0,
                                ),
                                //const SizedBox(height: 5.0),
                                ElevatedButton(
                                  onPressed: () async {
                                    if (au['isConnected'] as bool) {
                                      _disconnectFromAU(au);
                                    } else {
                                      _connectToAU(au);
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        !(au['isConnected'] as bool)
                                            ? Colors.blue[500]
                                            : Colors.red[500],
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    fixedSize: const Size(100, 30),
                                  ),
                                  child: Text(
                                    !(au['isConnected'] as bool)
                                        ? "اقتران"
                                        : "انفصال",
                                    style: GoogleFonts.rubik(
                                        textStyle: TextStyle(
                                            fontSize: 16, color: Colors.white)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Future<void> _readDataFromCameraStream(JpegImage image) async {
  //   if (!isUsingCamera) return;

  //   final detectedObjects = [];
  //   if (detectedObjects.isEmpty) return;
  //   final priorityObject = ""; //_analyzeObjects(detectedObjects);
  //   printDebug(detectedObjects);

  //   if (priorityObject != null) {
  //     final parameters = {
  //       'weight': priorityObject.measureWeight(),
  //       'label': priorityObject.label,
  //       'confidence': detectedObjects.firstWhere(
  //           (obj) => obj['className'] == priorityObject.label)['confidence'],
  //       'isPersonMoving': priorityObject.isPersonMoving,
  //       'isObjectMoving': priorityObject.isObjectMoving,
  //       'direction': priorityObject.direction
  //     };

  //     if (_lastItem == null ||
  //         priorityObject.itemInitializedAt
  //                 .difference(_lastItem!.itemInitializedAt)
  //                 .inSeconds >
  //             2.5) {
  //       _lastItem = priorityObject;

  //       if (isPerformingAction) return;
  //       isPerformingAction = true;
  //       printDebug("Performing action...");
  //       _taskEntryPoint(parameters).then((_) => isPerformingAction = false);
  //     }
  //   }
  // }

  Future<void> readFromBLEStream() async {
    isScanning = true;
    final bleConnection = await _connectToRPi5();
    if (bleConnection['device'] == null) {
      isScanning = false;
      return;
    }

    final device = bleConnection['device'] as BluetoothDevice;
    final wifiChar = bleConnection['wifi'] as BluetoothCharacteristic;
    final txrxChar = bleConnection['txrx'] as BluetoothCharacteristic;
    final ipChar = bleConnection['ip'] as BluetoothCharacteristic;

    final iPChangeSubscribtion = ipChar.onValueReceived.listen((value) async {
      final data = utf8.decode(value);
      printDebug(data);
      connectedIp = data.split(" ")[0];
    });
    device.cancelWhenDisconnected(iPChangeSubscribtion);
    await ipChar.setNotifyValue(true);

    var wifiList = [""];

    final wifiListSubscription = wifiChar.onValueReceived.listen((value) async {
      final data = utf8.decode(value);
      printDebug(data);
      setState(() {
        wifiList = data.split(',').toSet().toList();
      });
    });
    device.cancelWhenDisconnected(wifiListSubscription);
    await wifiChar.setNotifyValue(true);

    try {
      await wifiChar.write(utf8.encode('list'));
    } catch (e) {}

    TextEditingController password = TextEditingController();
    String? selectedSSID;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                'اختر إحدى الشبكات للإرتباط',
                style: GoogleFonts.changa(),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton(
                    hint: Text('اختر معرّف الشبكة'),
                    value: selectedSSID,
                    onChanged: (newValue) {
                      setState(() {
                        selectedSSID = newValue as String?;
                      });
                    },
                    items: wifiList.isNotEmpty
                        ? wifiList.map((ssid) {
                            return DropdownMenuItem(
                              value: ssid,
                              child: Text(ssid),
                            );
                          }).toList()
                        : [DropdownMenuItem(child: Text('No Networks Found'))],
                  ),
                  SizedBox(height: 10),
                  TextField(
                    controller: password,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15.0),
                      ),
                      labelText: 'كلمة المرور',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    setState(() {
                      wifiList = ["Refreshing..."];
                    });
                    await wifiChar.write(utf8.encode('list'));
                  },
                  child: Text('تحديث الشبكات'),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      await wifiChar
                          .write(utf8.encode('$selectedSSID,${password.text}'));
                    } catch (e) {}
                    setState(() {
                      isRasberryConnected = true;
                    });
                    _txRxDevice = txrxChar;
                    wifiListSubscription.cancel();
                    final subscription =
                        txrxChar.onValueReceived.listen((value) async {
                      final data = utf8.decode(value);
                      printDebug(data);
                      await HapticFeedback.vibrate();
                      await writeToBraille(data);
                      Future.delayed(Duration(milliseconds: 100), () async {
                        await ttsService.speak(data);
                      });
                    });
                    device.cancelWhenDisconnected(subscription);
                    await txrxChar.setNotifyValue(true);
                    Navigator.of(context).pop();
                  },
                  child: isRasberryConnected
                      ? CircularProgressIndicator()
                      : Text('حفظ الإعداد'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<void> writeToBraille(String caption) async {
    if ((assistiveUnits[0]['isConnected'] as bool)) {
      BluetoothCharacteristic? characteristic = assistiveUnits[0]
          ['connectedCharacteristic'] as BluetoothCharacteristic?;
      if (characteristic != null) {
        try {
          await characteristic.write(utf8.encode(caption));
        } catch (e) {
          printDebug("ERROR!");
        }
      } else {
        printDebug("Characteristic is null.");
      }
    }
  }

  static Future<void> vibrate(String direction) async {
    if ((assistiveUnits[1]['isConnected'] as bool)) {
      BluetoothCharacteristic? characteristic = assistiveUnits[1]
          ['connectedCharacteristic'] as BluetoothCharacteristic?;
      if (characteristic != null) {
        String vibratorCommand = '';
        if (direction == 'front') {
          vibratorCommand = 'ON1';
        } else if (direction == 'back') {
          vibratorCommand = 'ON3';
        } else if (direction == 'left') {
          vibratorCommand = 'ON4';
        } else if (direction == 'right') {
          vibratorCommand = 'ON2';
        }
        if (vibratorCommand.isNotEmpty) {
          await characteristic.write(utf8.encode(vibratorCommand));
        }
      } else {
        printDebug("Characteristic is null.");
      }
    }
  }

  Future<void> _askQuestion() async {
    if (_isAsking) return;

    await speechToTextService.stopListening();

    _isAsking = true;
    await speechToTextService.startListening((text) async {
      setState(() {
        _isAsking = false;
      });

      await ttsService.speak('لحظةً');
      await writeToBraille('لحظة');
      if (isListeningToPlace) {
        isListeningToPlace = false;
        final loc = await Maps.getPositionOf(text);
        Position? origin;
        await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.best)
            .then((Position position) {
          origin = position;
        });
        if (origin == null) {
          await ttsService.speak("لم يتم العثور على موقعك");
          await writeToBraille("لم يتم العثور على موقعك");
          return;
        }
        if (loc == null) {
          return;
        }
        destination = Position.fromMap(loc['position']);
        printDebug("going to ${loc['name']}, ${loc['position']}");
        await ttsService.speak("سَيَتِم توجيهك إلى ${loc['name']}");
        await writeToBraille("سَيَتِم توجيهك إلى ${loc['name']}");

        directionsSegments = await Maps.fetchSegmentsfromAPI(
            [origin!.longitude, origin!.latitude],
            [destination!.longitude, destination!.latitude]);
        printDebug(directionsSegments);
        printDebug("direction service running...");
        isDirectionServiceRunning = true;
        return;
      }

      if (isListeningToPlaceForTaxi) {
        isListeningToPlaceForTaxi = false;
        Position? origin;
        await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.best)
            .then((Position position) {
          origin = position;
        });

        final loc = await Maps.getPositionOf(text);
        if (loc == null) {
          final place = await Maps.getClosestLocation(
              latitude: origin!.latitude,
              longitude: origin!.longitude,
              placeName: text);
          if (place == null) {
            await ttsService.speak("لم أعثر على شيء, عذرََا");
            await writeToBraille("لم أعثر على شيء, عذرََا");
          }
          await ttsService
              .speak("عثرت على ${place!['name']}, سأطلب سائق أُجرةِِ إليه");
          await writeToBraille(
              "عثرت على ${place['name']}, سأطلب سائق أُجرةِِ إليه");
          return;
        }
        destination = Position.fromMap(loc['position']);
        printDebug("going to ${loc['name']}, ${loc['position']}");

        if (origin == null) {
          await ttsService.speak("لم يتم العثور على موقعك");
          await writeToBraille("لم يتم العثور على موقعك");
          return;
        }
        try {
          String runId = await UberService().createSandboxRun(pickupLocation: {
            "latitude": origin!.latitude,
            "longitude": origin!.longitude
          }, dropoffLocation: {
            "latitude": destination!.latitude,
            "longitude": destination!.longitude
          }, parentProductTypeId: "b1afcc8d-02ff-4bfb-be88-b0afed2a0ef2");

          await UberService().updateDriverState(
              runId: runId,
              driverId: "d7a1a6a4-1c7d-4c4b-9c9b-4b8b9b8b9b8b",
              driverState: "ACCEPT");

          await ttsService
              .speak("قُمتُ بطلب سائق أُجرَة ليوصلَك إلى ${loc['name']}");
          await writeToBraille("قُمتُ بطلب سائق أُجرَة إلى ${loc['name']}");
        } catch (e) {
          printDebug(e);
          await ttsService.speak("لم يتم العثور على سائق أُجرَة");
          await writeToBraille("لم يتم العثور على سائق أُجرَة");
        }
      }

      final bestClassification = {
        'taxi': UberService.isRequestingTaxi(text, taxiTerms),
        'maps': Maps.isRequestingDirections(text, mapsTerms),
        'ocr': Ocr.isRequestingOCR(text, oCRterms),
      };
      final maxClassify = bestClassification.entries.reduce(
          (current, next) => current.value > next.value ? current : next);
      printDebug("maxClassify: $maxClassify");
      if (maxClassify.key == 'taxi' && !(bestClassification['maps']! >= 0.3)) {
        await ttsService
            .speak("سأعمل على طلب سائق أُجرَة, إلى أين تريد الذهاب؟");
        await writeToBraille("سأعمل على طلب سائق أُجرَة, إلى أين تريد الذهاب؟");
        isListeningToPlaceForTaxi = true;
      } else if (maxClassify.key == 'maps' ||
          bestClassification['maps']! >= 0.4) {
        await ttsService.speak("إلى أين تريد الذهاب؟");
        await writeToBraille("إلى أين تريد الذهاب؟");
        printDebug("listening to place...");
        isListeningToPlace = true;
      } else if (maxClassify.key == 'ocr' && maxClassify.value > 0.6) {
        if (!isRasberryConnected) {
          await ttsService.speak("يجب فتح الكَمِرا");
          await writeToBraille("يجب فتح الكَمِرا");
        } else {
          await _txRxDevice?.write(utf8.encode(
              """ocr,Analyze the text from the provided image and summarize the main ideas clearly and concisely as a paragraph. Return only the summary without additional comments or explanations."""));
          await Future.delayed(const Duration(seconds: 5), () async {
            final response =
                await http.get(Uri.parse("http://$connectedIp:8080/"));
            printDebug(response.body);
            final decodedJson = jsonDecode(response.body);
            final documents = await Ocr.getConfigFileJSON();
            final uuid = Uuid().v1();
            final file = File(
                '${(await getApplicationDocumentsDirectory()).path}/$uuid.jpg');
            file.writeAsBytes(base64Decode(decodedJson['document']));
            if (documents is List) {
              documents.add({
                'title': decodedJson['title'],
                'summary': decodedJson['summary'],
                'image_path': file.path,
              });
              await File(
                      '${(await getApplicationDocumentsDirectory()).path}/config_documents.json')
                  .writeAsString(jsonEncode(documents));
            }
          });
        }
      } else {
        if (!isRasberryConnected) {
          await ttsService.speak("يجب فتح الكَمِرا");
          await writeToBraille("يجب فتح الكَمِرا");
        } else {
          Position? origin;
          await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.best)
              .then((Position position) {
            origin = position;
          });

          final location = await placemarkFromCoordinates(
              origin?.latitude ?? 0, origin?.longitude ?? 0);
          await _txRxDevice?.write(utf8.encode(
            """question,Be as a Visual Question Answerer for a blind, answer the question: '$text' with short answer IN ARABIC. Do not say anything else also note that the question is in arabic and is latinized, so deal with that
              ${origin != null ? "Also, note that you are currently at ${location[0].locality}, ${location[0].subLocality}: ${location[0].name} location, so make sure to answer the question based on that." : ""}
              ${isDirectionServiceRunning ? " In addition, note that the blind is trying to go to a destination, so add this to your context when answering." : ""}""",
          ));
        }
      }
    });
  }

  void _connectToAU(Map<String, Object?> au) async {
    var targetDeviceName = au["deviceName"] as String;

    try {
      printDebug("Scanning for devices...");
      FlutterBluePlus.startScan(timeout: Duration(seconds: 5));

      var subscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult result in results) {
          printDebug(
              'Found device: ${result.device.advName}, ID: ${result.device.remoteId}');
          if (result.device.remoteId.str == targetDeviceName) {
            await FlutterBluePlus.stopScan();
            printDebug("Connecting to ${result.device.advName}...");

            au["connectedDevice"] = result.device;
            await (au["connectedDevice"] as BluetoothDevice?)!.connect();
            printDebug("Connected!");

            var services = await (au["connectedDevice"] as BluetoothDevice?)!
                .discoverServices();

            //for (var service in services) {
            //printDebug('Service: ${service.uuid}, service: ${service.characteristics}');
            //if (service.uuid.toString() == targetServiceUuid) {
            int i = 1;
            for (var char in services) {
              printDebug("SCANNING IN SERVICE #$i");
              for (var prop in char.characteristics) {
                if (prop.characteristicUuid.str ==
                    'beb5483e-36e1-4688-b7f5-ea07361b26a1') {
                  printDebug(
                      "Found=================== ${prop.characteristicUuid}");
                  au["connectedCharacteristic"] = prop;
                  au["connectedService"] = char;
                  printDebug("Connected char...");
                  setState(() {
                    au["isConnected"] = true;
                  });
                  printDebug("Target characteristic saved!");
                  break;
                }
              }
              i++;
            }
          }
          break;
        }
        //}
      });

      await Future.delayed(Duration(seconds: 5));
      subscription.cancel();
    } catch (e) {
      printDebug("Error: $e");
    }
  }

  Future<Map<String, dynamic>> _connectToRPi5() async {
    BluetoothCharacteristic? wifi;
    BluetoothCharacteristic? txrx;
    BluetoothCharacteristic? ip;
    BluetoothDevice? device;

    try {
      // Initial quick scan
      await FlutterBluePlus.startScan(
          timeout: const Duration(milliseconds: 100));
      await FlutterBluePlus.stopScan();

      // Main scan
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 5),
        oneByOne: true,
      );

      final scanResults = await _waitForScanResults();

      for (ScanResult result in scanResults) {
        printDebug(
          'Found device: ${result.device.platformName}, ID: ${result.device.remoteId}',
        );

        if (result.device.platformName.toUpperCase() == "RPI5-BLE-SERVER") {
          await FlutterBluePlus.stopScan();
          printDebug("Connecting to ${result.device.advName}...");

          await result.device.connect();
          printDebug("Connected!");
          device = result.device;

          final services = await result.device.discoverServices();
          final characteristics = await _findCharacteristics(services);

          wifi = characteristics['wifi'];
          txrx = characteristics['txrx'];
          ip = characteristics['ip'];

          if (wifi != null && txrx != null && ip != null) {
            break;
          }
        }
      }

      return {
        'wifi': wifi,
        'txrx': txrx,
        'ip': ip,
        'device': device,
      };
    } catch (e) {
      printDebug("Error: $e");
      return {
        'wifi': null,
        'txrx': null,
        'ip': null,
        'device': null,
      };
    }
  }

// Helper function to wait for scan results
  Future<List<ScanResult>> _waitForScanResults() {
    return Future.delayed(
      const Duration(seconds: 5),
      () => FlutterBluePlus.scanResults.first,
    );
  }

// Helper function to find characteristics
  Future<Map<String, BluetoothCharacteristic?>> _findCharacteristics(
    List<BluetoothService> services,
  ) async {
    BluetoothCharacteristic? wifi;
    BluetoothCharacteristic? txrx;
    BluetoothCharacteristic? ip;

    for (var service in services) {
      for (var characteristic in service.characteristics) {
        switch (characteristic.characteristicUuid.str) {
          case 'ff4b4830-efb2-4eac-8b70-32cd4d7c0996':
            wifi = characteristic;
            printDebug("Connected wifi char...");
            break;
          case '5c8be1d7-a6d8-4590-9370-b1380de38fb5':
            txrx = characteristic;
            printDebug("Connected txrx char...");
            break;
          case '792af15e-ffce-46cc-b98d-e85e6c66dbf3':
            ip = characteristic;
            printDebug("Connected ip char...");
            break;
        }
      }
    }

    return {
      'wifi': wifi,
      'txrx': txrx,
      'ip': ip,
    };
  }

  void _disconnectFromAU(Map<String, Object?> au) async {
    if ((au["connectedDevice"] as BluetoothDevice?) != null) {
      try {
        printDebug(
            "Disconnecting from ${(au["connectedDevice"] as BluetoothDevice?)!.advName}...");
        await (au["connectedDevice"] as BluetoothDevice?)!.disconnect();
        printDebug("Disconnected successfully!");

        au["connectedDevice"] = null;
        au["connectedService"] = null;
        au["connectedCharacteristic"] = null;

        printDebug("Resources cleared.");
        setState(() {
          au["isConnected"] = false;
        });
      } catch (e) {
        printDebug("Error during disconnection: $e");
      }
    } else {
      printDebug("No device connected.");
    }
  }

  Future<void> handleDirecting() async {
    Position? origin;
    await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best)
        .then((Position position) {
      origin = position;
    });
    if (origin == null) {
      return;
    }
    if (origin == null || destination == null || !isDirectionServiceRunning) {
      return;
    }

    if (directionsSegments == null) {
      return;
    }

    final steps = directionsSegments[0][0]['steps'];
    printDebug(steps);
    final polyline = directionsSegments[1];
    int? stepIndex = Maps.findCurrentStep(
            polyline, steps, origin!.latitude, origin!.longitude) ??
        0;
    final stepInstruction = steps[stepIndex]['type'];
    String instruction = Maps.instructionType[stepInstruction];
    if (lastDirectedStep != stepIndex) {
      lastDirectedStep = stepIndex;
      await ttsService.speak(instruction);
      await writeToBraille(instruction);
    }
    if (stepIndex == steps.length - 1) {
      directionsSegments = null;
      isDirectionServiceRunning = false;
      lastDirectedStep = -1;
    }
  }

  bool _isObjectMoving(Map<String, dynamic>? objectData,
      Map<String, dynamic>? previousObjectData) {
    if (objectData == null || previousObjectData == null) return false;
    const threshold = 10;

    final dx = (objectData['x'] - previousObjectData['x']).abs();
    final dy = (objectData['y'] - previousObjectData['y']).abs();
    return dx > threshold || dy > threshold;
  }

  String _getDirection(objectData, Map<String, dynamic>? previousObjectData) {
    if (objectData == null || previousObjectData == null) return '';
    final dx = objectData['x'] - previousObjectData['x'];
    final dy = objectData['y'] - previousObjectData['y'];
    int threshold = 10;
    // Check if the object has moved in any direction (left, right, front, back)
    if (dx.abs() > threshold) {
      return dx > 0 ? 'right' : 'left';
    } else if (dy.abs() > threshold) {
      return dy > 0 ? 'front' : 'back';
    }
    return '';
  }
}
