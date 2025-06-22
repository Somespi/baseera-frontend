// ignore_for_file: empty_catches, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:getwidget/getwidget.dart';

//import 'package:basera/pages/ar_route.dart';
import 'package:basera/pages/maps_route.dart';
import 'package:basera/pages/ocr_route.dart';
import 'package:basera/services/maps.dart';
import 'package:basera/services/ocr/ocr.dart';
import 'package:basera/services/speech_to_text.dart';
import 'package:basera/services/uber_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'services/help_utilities.dart';
import 'services/text_to_speech.dart';
import 'services/ble_service.dart';

import 'package:fluttertoast/fluttertoast.dart' as fluttertoast;
import 'package:http/http.dart' as http;

late List<String> labels;
DateTime lastImageTime = DateTime.now();
TextToSpeechService ttsService = TextToSpeechService();
SpeechToTextService speechToTextService = SpeechToTextService();
String? lastRecievedClassification;
Position? destination;
bool isDirectionServiceRunning = false;
bool isListeningToPlace = false;
int lastDirectedStep = -1;
dynamic directionsSegments;

bool isListeningToPlaceForTaxi = false;
bool isConfirmingTaxiForOuterPlace = false;
String lastAskedQuestion = "";
String lastSentData = "";
bool isRasberryConnected = false;
bool isRasberryPaused = false;
String connectedIp = "";

const routes = <Widget?>[
  null,
  DocumentsPage(),
  MapsRoutePage(),
]; //ARroutePage()];
const titles = <String>[
  "الصفحة الرئيسية",
  "المستندات",
  "المواقع",
  //"الماسح الضوئي"
];

var assistiveUnits = [
  createAssistiveUnitMap(
    "خلية برايل",
    "3C:84:27:C3:33:99",
    "beb5483e-36e1-4688-b7f5-ea07361b26a",
    "assets/icons/braille.png",
    "جهاز بريل يترجم النصوص المكتوبة إلى نقاط بارزة لتمكين الأشخاص ذوي الاحتياج البصري والسمعي من قراءتها بشكل مستقل.",
  ),
  createAssistiveUnitMap(
      "هزازات الحركة",
      "24:D7:EB:0F:09:02",
      "beb5483e-36e1-4688-b7f5-ea07361b26a",
      "assets/icons/motion.png",
      "جهاز هزازات الحركة يترجم النصوص المكتوبة في الحركة بشكل مستقل."),
];

void main() async {
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
        fontFamily: GoogleFonts.cairo().fontFamily,
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
  bool isElementMovingEnabled = true;
  StreamSubscription? _gyroscopeSubscription;
  bool isUsingCamera = false;

  late List<String> oCRterms;
  late List<String> mapsTerms;
  late List<String> taxiTerms;

  int _selectedIndex = 0;
  BluetoothCharacteristic? _txRxDevice;
  BluetoothDevice? _rasberryDevice;
  bool _lastIsPersonMoving = false;
  bool isPerformingAction = false;
  bool _isAsking = false;
  String foundDeviceName = "";
  bool isScanning = false;

  final answerQuestionsStreamController = StreamController<String>();

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

    answerQuestionsStreamController.stream.listen((event) async {
      final classification = event.split(",")[0];
      final question = event.split(",")[1];
      printDebug("Writing from stream about \"$question\"");
      await answerQuestion(classification, question);
    });
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
    const double movementThreshold = 0.32;
    // Subscribe to the gyroscope event stream
    _gyroscopeSubscription =
        gyroscopeEventStream().listen((GyroscopeEvent event) async {
      // Calculate the magnitude of the gyroscope reading
      final double magnitude =
          (event.x * event.x) + (event.y * event.y) + (event.z * event.z);
      setState(() {
        isPersonMoving = magnitude > movementThreshold;
        if (isPersonMoving != _lastIsPersonMoving) {
          _lastIsPersonMoving = isPersonMoving;
        }
      });
      if (_txRxDevice != null && !isRasberryPaused) {
        await _txRxDevice
            ?.write(utf8.encode("gyro,${_lastIsPersonMoving ? 1 : 0}"));
      }
    });
  }

  @override
  void dispose() async {
    speechToTextService.dispose();
    _gyroscopeSubscription?.cancel();
    answerQuestionsStreamController.close();
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
                  onPressed: () async {
                    setState(() {
                      isListeningToPlace = false;
                      isDirectionServiceRunning = false;
                      lastDirectedStep = -1;
                      directionsSegments = null;
                    });
                    await ttsService.speak("تم إيقاف التنقل");
                    await writeToBraille("تم إيقاف التنقل");
                  },
                )
              : SizedBox(height: 0.0),
          SizedBox(height: 10.0),
          isRasberryConnected
              ? FloatingActionButton(
                  heroTag: "pause",
                  onPressed: () async {
                    if (isRasberryConnected) {
                      if (isRasberryPaused) {
                        await _txRxDevice?.write(utf8.encode("pause,0"));
                        isRasberryPaused = false;
                      } else {
                        await _txRxDevice?.write(utf8.encode("pause,1"));
                        isRasberryPaused = true;
                      }
                    }
                  },
                  child: !isRasberryConnected
                      ? isScanning
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.camera)
                      : isRasberryPaused
                          ? const Icon(Icons.play_arrow_rounded)
                          : const Icon(Icons.stop_rounded))
              : SizedBox(height: 0.0),
          SizedBox(height: 10.0),
          FloatingActionButton(
              heroTag: "camera",
              onPressed: () async {
                if (isRasberryConnected) {
                  await _txRxDevice?.write(utf8.encode("pause,1"));
                  await _rasberryDevice?.disconnect();
                  setState(() {
                    isRasberryPaused = true;
                    isRasberryConnected = false;
                  });
                } else {
                  readFromBLEStream();
                }
              },
              child: !isRasberryConnected
                  ? isScanning
                      ? const CircularProgressIndicator()
                      : const Icon(Icons.camera)
                  : const Icon(Icons.bluetooth_disabled_rounded))
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _selectedIndex != 0
            ? routes[_selectedIndex]!
            : Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: !isElementMovingEnabled
                        ? 400.0
                        : 150.0,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15.0),
                      onLongPress: () {
                        setState(() {
                          isElementMovingEnabled = !isElementMovingEnabled;
                        });
                        fluttertoast.Fluttertoast.showToast(
                            msg: !isElementMovingEnabled
                                ? "تم تفعيل الحركة"
                                : "تم إيقاف الحركة",
                            toastLength: fluttertoast.Toast.LENGTH_SHORT,
                            gravity: fluttertoast.ToastGravity.BOTTOM_LEFT,
                            timeInSecForIosWeb: 1,
                            backgroundColor: Colors.green,
                            textColor: Colors.white,
                            fontSize: 16.0);
                      },
                      onTap: () async {
                        await _askQuestion();
                        //await speechToTextService.stopListening();
                      },
                      child: Card(
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
                              child:
                                  Flex(direction: Axis.horizontal, children: [
                                Image(
                                  image: AssetImage('assets/icons/eye.png'),
                                  width: 100.0,
                                  height: 100.0,
                                ),
                                //const Spacer(),
                                Center(
                                  child: Text(
                                    "استفسر عن ما يحيطك",
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                              ])),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30.0),
                  Text("الوحدات المساعدة (AUs)",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 0, 0, 0),
                        fontSize: 16,
                      )),
                  const SizedBox(height: 10.0),
                  Expanded(
                    child: ListView.builder(
                        itemCount: assistiveUnits.length,
                        itemBuilder: (context, index) => Card(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                              child: Stack(children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    //const SizedBox(height: 8.0),
                                    Image(
                                      image: AssetImage(assistiveUnits[index]
                                          ['image'] as String),
                                      width: 100.0,
                                    ),
                                    Column(children: [
                                      Text(
                                        assistiveUnits[index]['name'] as String,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20),
                                      ),

                                      //const SizedBox(height: 5.0),
                                      Row(children: [
                                        TextButton(
                                          onPressed: () async {
                                            if (assistiveUnits[index]
                                                ['isConnected'] as bool) {
                                              await disconnectFromAssistiveDevice(
                                                  assistiveUnits[index],
                                                  context);
                                              await fluttertoast.Fluttertoast
                                                  .showToast(
                                                      msg: "تم الإنفصال بنجاح",
                                                      toastLength: fluttertoast
                                                          .Toast.LENGTH_SHORT,
                                                      gravity: fluttertoast
                                                          .ToastGravity
                                                          .BOTTOM_RIGHT,
                                                      timeInSecForIosWeb: 1,
                                                      backgroundColor:
                                                          Colors.green,
                                                      textColor: Colors.white,
                                                      fontSize: 16.0);
                                            } else {
                                              await connectToAssistiveDevice(
                                                  assistiveUnits[index],
                                                  context);
                                            }
                                          },

                                          //fixedSize: const Size(100, 30),

                                          child: Text(
                                              !(assistiveUnits[index]
                                                      ['isConnected'] as bool)
                                                  ? "اقتران"
                                                  : "انفصال",
                                              style: TextStyle(
                                                fontSize: 16,
                                              )),
                                        ),
                                        TextButton(
                                          onPressed: (assistiveUnits[index]
                                                  ['isConnected'] as bool)
                                              ? () async {
                                                  assistiveUnits[index]
                                                          ['isPaused'] =
                                                      !(assistiveUnits[index]
                                                          ['isPaused'] as bool);
                                                  await fluttertoast.Fluttertoast
                                                      .showToast(
                                                          msg: (assistiveUnits[
                                                                          index]
                                                                      [
                                                                      'isPaused']
                                                                  as bool)
                                                              ? "تم ايقاف التشغيل"
                                                              : "تم استئناف التشغيل",
                                                          toastLength:
                                                              fluttertoast.Toast
                                                                  .LENGTH_SHORT,
                                                          gravity: fluttertoast
                                                              .ToastGravity
                                                              .BOTTOM_RIGHT,
                                                          timeInSecForIosWeb: 1,
                                                          backgroundColor:
                                                              Colors.green,
                                                          textColor:
                                                              Colors.white,
                                                          fontSize: 16.0);
                                                  stopDevice(
                                                      assistiveUnits[index]);
                                                }
                                              : null,
                                          child: Text(
                                              assistiveUnits[index]['isPaused']
                                                      as bool
                                                  ? "استئناف"
                                                  : "إيقاف",
                                              style: TextStyle(
                                                fontSize: 16,
                                              )),
                                        ),
                                      ]),
                                    ]),
                                  ],
                                ),
                                Positioned(
                                    left: 10,
                                    child: GFButton(
                                        onPressed: () {},
                                        text: assistiveUnits[index]
                                                ['isConnected'] as bool
                                            ? "متصل"
                                            : "غير متصل",
                                        shape: GFButtonShape.pills,
                                        size: GFSize.SMALL,
                                        color: assistiveUnits[index]
                                                ['isConnected'] as bool
                                            ? GFColors.SUCCESS
                                            : GFColors.WARNING,
                                        textStyle: GoogleFonts.cairo(
                                          color: assistiveUnits[index]
                                                  ['isConnected'] as bool
                                              ? GFColors.SUCCESS
                                              : GFColors.WARNING,
                                        ),
                                        type: GFButtonType.outline,
                                        icon: Icon(
                                          assistiveUnits[index]['isConnected']
                                                  as bool
                                              ? Icons.link
                                              : Icons.link_off_rounded,
                                          color: assistiveUnits[index]
                                                  ['isConnected'] as bool
                                              ? GFColors.SUCCESS
                                              : GFColors.WARNING,
                                        ))),
                              ]),
                            )),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> readFromBLEStream() async {
    isScanning = true;
    final bleConnection = await connectToRPi5(context);
    if (bleConnection['device'] == null) {
      isScanning = false;
      fluttertoast.Fluttertoast.showToast(
          msg: "لم يتم العثور على الجهاز",
          toastLength: fluttertoast.Toast.LENGTH_SHORT,
          gravity: fluttertoast.ToastGravity.BOTTOM_RIGHT,
          timeInSecForIosWeb: 1,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0);
      return;
    }

    final device = bleConnection['device'] as BluetoothDevice;
    final wifiChar = bleConnection['wifi'] as BluetoothCharacteristic;
    final txrxChar = bleConnection['txrx'] as BluetoothCharacteristic;
    final ipChar = bleConnection['ip'] as BluetoothCharacteristic;

    _rasberryDevice = device;

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
                        : [
                            DropdownMenuItem(child: Text('لا توجد شبكات متاحة'))
                          ],
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
                        txrxChar.onValueReceived.listen(onValueStreamReceived);
                    device.cancelWhenDisconnected(subscription);
                    await txrxChar.setNotifyValue(true);
                    await _txRxDevice?.write(utf8.encode("pause,0"));
                    fluttertoast.Fluttertoast.showToast(
                        msg: "تم الإقتران بنجاح",
                        toastLength: fluttertoast.Toast.LENGTH_SHORT,
                        gravity: fluttertoast.ToastGravity.BOTTOM_RIGHT,
                        timeInSecForIosWeb: 1,
                        backgroundColor: Colors.green,
                        textColor: Colors.white,
                        fontSize: 16.0);
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

  void onValueStreamReceived(value) async {
    final data = utf8.decode(value);
    printDebug(data);
    if (isRasberryPaused) return;
    if (data.startsWith("identify")) {
      final classification = data.split(',')[1];
      lastRecievedClassification = classification;
    }
    if (data.startsWith("answer")) {
      final answer = data.split(',')[1];
      await Future.delayed(Duration(milliseconds: 50));
      ttsService.speak(answer);
      writeToBraille(answer);
    }
    await HapticFeedback.vibrate();
  }

  Future<void> answerQuestion(String classification, String question) async {
    if (classification == 'taxi') {
      await ttsService.speak("سأعمل على طلب سائق أُجرَة, إلى أين تريد الذهاب؟");
      await writeToBraille("سأعمل على طلب سائق أُجرَة, إلى أين تريد الذهاب؟");
      isListeningToPlaceForTaxi = true;
    } else if (classification == 'maps') {
      await ttsService.speak("إلى أين تريد الذهاب؟");
      await writeToBraille("إلى أين تريد الذهاب؟");
      printDebug("listening to place...");
      isListeningToPlace = true;
    } else if (classification == 'ocr') {
      if (!isRasberryConnected) {
        await ttsService.speak("يجب فتح الكَمِرا");
        await writeToBraille("يجب فتح الكَمِرا");
      } else {
        await _txRxDevice?.write(utf8.encode("""ocr, $question."""));
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
        await Geolocator.getCurrentPosition()
            .then((Position position) {
          origin = position;
        });

        final location = await placemarkFromCoordinates(
            origin?.latitude ?? 0, origin?.longitude ?? 0);
        printDebug("Trying to ask question....................");
        await _txRxDevice?.write(utf8.encode(
          """question,answer the question: '$question' 
              ${origin != null ? "Also, note that you are currently at ${location[0].locality}, ${location[0].subLocality}: ${location[0].name} location, so make sure to answer the question based on that." : ""}
              ${isDirectionServiceRunning ? " In addition, note that the blind is trying to go to a destination, so add this to your context when answering." : "Also, Note that the blind is currently not requesting to head to a specefiec location."}
              
              """,
        ));

        await _txRxDevice?.write(utf8.encode(
          """question,'$question'""",
        ));
      }
    }
  }

  static Future<void> writeToBraille(String caption) async {
    if ((assistiveUnits[0]['isConnected'] as bool) &&
        (assistiveUnits[0]['isPaused'] as bool) == false) {
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

  // ignore: unused_element
  static Future<void> _vibrate(String direction) async {
    if ((assistiveUnits[1]['isConnected'] as bool) &&
        (assistiveUnits[1]['isPaused'] as bool) == false) {
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
    await speechToTextService.startListening((question) async {
      setState(() {
        _isAsking = false;
      });
      lastAskedQuestion = question;
      await ttsService.speak('لحظةً');
      await writeToBraille('لحظة');
      if (isListeningToPlace) {
        isListeningToPlace = false;
        final loc = await Maps.getPositionOf(question);
        Position? origin;
        await Geolocator.getCurrentPosition()
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
        await Geolocator.getCurrentPosition()
            .then((Position position) {
          origin = position;
        });

        final loc = await Maps.getPositionOf(question);
        if (loc == null) {
          final place = await Maps.getClosestLocation(
              latitude: origin!.latitude,
              longitude: origin!.longitude,
              placeName: question);
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
      await _txRxDevice?.write(utf8.encode("identify,$question"));
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 10));
        return lastRecievedClassification == null;
      });
      printDebug("Last Updated value $lastRecievedClassification");
      if (lastRecievedClassification != null) {
        await answerQuestion(lastRecievedClassification!, lastAskedQuestion);

        lastRecievedClassification = null;
      }
    });
  }

  Future<void> handleDirecting() async {
    Position? origin;
    await Geolocator.getCurrentPosition()
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

  stopDevice(Map<String, Object?> au) {
    if (au['name'] == "خلية برايل") {
      BluetoothCharacteristic? characteristic =
          au['connectedCharacteristic'] as BluetoothCharacteristic?;
      if (characteristic != null) {
        try {
          characteristic.write(utf8.encode("STOP"));
        } catch (e) {
          printDebug("ERROR!");
          fluttertoast.Fluttertoast.showToast(
              msg: "حدث خطأ أثناء إيقاف الجهاز",
              toastLength: fluttertoast.Toast.LENGTH_SHORT,
              gravity: fluttertoast.ToastGravity.BOTTOM_RIGHT,
              timeInSecForIosWeb: 1,
              backgroundColor: Colors.red,
              textColor: Colors.white,
              fontSize: 16.0);
        }
      } else {
        printDebug("Characteristic is null.");
        fluttertoast.Fluttertoast.showToast(
            msg: "حدث خطأ أثناء إيقاف الجهاز",
            toastLength: fluttertoast.Toast.LENGTH_SHORT,
            gravity: fluttertoast.ToastGravity.BOTTOM_RIGHT,
            timeInSecForIosWeb: 1,
            backgroundColor: Colors.red,
            textColor: Colors.white,
            fontSize: 16.0);
      }
    }
  }
}
