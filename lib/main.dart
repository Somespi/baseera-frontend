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
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:serialport_plus/serialport_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'services/help_utilities.dart';
import 'services/priority_manager.dart' as priority_manager;
import 'services/text_to_speech.dart';
import 'services/yolo.dart' as yolo;

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
    "deviceName": "ESP32_Braille_Device",
    "connectedDevice": null,
    "connectedCharacteristic": null,
    "connectedService": null,
    "isConnected": false,
    "image": "assets/icons/braille.png",
    "description":
        "جهاز بريل يترجم النصوص المكتوبة إلى نقاط بارزة لتمكين الأشخاص ذوي الاحتياج البصري والسمعي من قراءتها بشكل مستقل.",
  },
  {
    "name": "هزازات الحركة",
    "deviceName": "NanoESP32_BuzzerControl",
    "connectedDevice": null,
    "connectedCharacteristic": null,
    "connectedService": null,
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
  labels = await yolo.loadLabels();
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
  late OrtSession _interpreter;
  JpegImage? _currentImg;
  final _serialportFlutterPlugin = SerialportPlus();
  bool isPersonMoving = false;
  Nv21Image? lastFrame;
  StreamSubscription? _gyroscopeSubscription;
  bool isUsingCamera = false;
  priority_manager.PriorityItem? _lastItem;

  late List<String> oCRterms;
  late List<String> mapsTerms;
  late List<String> taxiTerms;

  int _selectedIndex = 0;
  bool isPerformingAction = false;

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

    _interpreter = await yolo.loadModel();
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

  /// Initializes the gyroscope listener to monitor device movement.
  ///
  /// This function listens to the gyroscope event stream and updates the
  /// [isPersonMoving] state variable based on the magnitude of the gyroscope
  /// readings. If the magnitude exceeds [movementThreshold], [isPersonMoving]
  /// is set to true, indicating that the device is moving.
  ///
  /// The [movementThreshold] is set to 0.2, which is a common value to
  /// detect movement.
  void _initializeGyroscope() {
    const double movementThreshold = 0.2; // Threshold for movement detection
    // Subscribe to the gyroscope event stream
    _gyroscopeSubscription =
        gyroscopeEventStream().listen((GyroscopeEvent event) {
      // Calculate the magnitude of the gyroscope reading
      final double magnitude =
          (event.x * event.x) + (event.y * event.y) + (event.z * event.z);
      setState(() {
        // Update the movement state based on the calculated magnitude
        isPersonMoving = magnitude > movementThreshold;
      });
    });
  }

  @override
  void dispose() async {
    _interpreter.release();
    await _serialportFlutterPlugin.close();
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

  /// Builds the main home page widget.
  ///
  /// This widget displays a floating action button that reads data from the
  /// serial port and runs object detection on the received images. The
  /// results of the object detection are displayed in the center of the
  /// screen.
  ///
  /// The widget also displays a spinner while the model is being loaded.
  ///
  /// The widget listens to the gyroscope data stream and sets the
  /// [isPersonMoving] flag to true if the magnitude of the gyroscope data
  /// exceeds a certain threshold. This flag is used to determine the weight
  /// of the detected objects.
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

    return CameraAwesomeBuilder.analysisOnly(
        onImageForAnalysis: (image) async {
          if (!isUsingCamera) {
            return;
          }
          handleDirecting();
          if (lastFrame == null) {
            lastFrame = image as Nv21Image;
            return;
          }
          final bool isIdentical =
              _compareImages(lastFrame!, image as Nv21Image);
          if (isIdentical) {
            return;
          }
          lastFrame = image;
          image = await (image).toJpeg();
          _currentImg = image as JpegImage?;
          _readDataFromCameraStream(image as JpegImage);
        },
        imageAnalysisConfig: AnalysisConfig(
          androidOptions: const AndroidAnalysisOptions.nv21(width: 480),
          autoStart: true,
          maxFramesPerSecond: 5,
        ),
        builder: (controller, preview) {
          () async {
            if (!isUsingCamera) {
              try {
                await controller.analysisController?.stop();
              } catch (e) {}
              await controller.analysisController?.imageSubscription?.cancel();
              controller.analysisController?.imageSubscription = null;
            }
          }();
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
                    fontFamily: 'Changa',
                    fontWeight: FontWeight.bold,
                    fontSize: 20),
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
                      if (isUsingCamera) {
                        try {
                          await controller.analysisController?.stop();
                        } catch (e) {}
                        await controller.analysisController?.imageSubscription
                            ?.cancel();
                        controller.analysisController?.imageSubscription = null;

                        isUsingCamera = false;
                      } else {
                        controller.analysisController?.start();
                        isUsingCamera = true;
                      }
                    },
                    child: !isUsingCamera
                        ? const Icon(Icons.camera)
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
                              side: const BorderSide(
                                color: Color.fromRGBO(0, 76, 168, 1),
                                width: 0.7,
                              ),
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Flex(
                                      direction: Axis.horizontal,
                                      children: [
                                        Image(
                                          image: AssetImage(
                                              'assets/icons/eye.png'),
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
                                        image:
                                            AssetImage(au['image'] as String),
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
                                            borderRadius:
                                                BorderRadius.circular(8.0),
                                          ),
                                          fixedSize: const Size(100, 30),
                                        ),
                                        child: Text(
                                          !(au['isConnected'] as bool)
                                              ? "اقتران"
                                              : "انفصال",
                                          style: GoogleFonts.rubik(
                                              textStyle: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.white)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        )
                      ],
                    ),
            ),
          );
        });
  }

  Future<void> _readDataFromCameraStream(JpegImage image) async {
    if (!isUsingCamera) return;

    final convertedImage = yolo.fromJpegToImg(image);
    final detectedObjects =
        await _runObjectDetectionInBackground(convertedImage);
    if (detectedObjects.isEmpty) return;
    final priorityObject = _weightOfObjects(detectedObjects, convertedImage);
    printDebug(detectedObjects);

    if (priorityObject != null) {
      final parameters = {
        'weight': priorityObject.measureWeight(),
        'nv21Image': convertedImage,
        'label': priorityObject.label,
        'confidence': detectedObjects.firstWhere(
            (obj) => obj['className'] == priorityObject.label)['confidence'],
        'isPersonMoving': priorityObject.isPersonMoving,
        'isObjectMoving': priorityObject.isObjectMoving,
        'direction': priorityObject.direction
      };

      if (_lastItem == null ||
          priorityObject.itemInitializedAt
                  .difference(_lastItem!.itemInitializedAt)
                  .inSeconds >
              2.5) {
        _lastItem = priorityObject;

        if (isPerformingAction) return;
        isPerformingAction = true;
        printDebug("Performing action...");
        _taskEntryPoint(parameters).then((_) => isPerformingAction = false);
      }
    }
  }

  static Future<void> _taskEntryPoint(Map<String, dynamic> objectData) async {
    final weight = objectData['weight'] as String;
    final image = objectData['nv21Image'] as img.Image;
    final label = objectData['label'] as String;
    final confidence = objectData['confidence'] as double;

    await HapticFeedback.vibrate();
    if (objectData['isObjectMoving'] as bool) {
      await vibrate(objectData['direction'] as String);
    }
    if (weight == 'HIGH') {
      await writeToBraille("مهلا");
      await ttsService.speak("مهلا");
      final caption = await VQA().caption(image);
      if (caption != null) {
        await writeToBraille(caption);
        await ttsService.speak(caption);
      } else {
        await writeToBraille(yolo.labelsToArabic[label]!);
        await ttsService.speak(yolo.labelsToArabic[label]!);
      }
    } else if (weight == 'MEDIUM') {
      await HapticFeedback.mediumImpact();
      if (confidence > 0.7) {
        await writeToBraille(yolo.labelsToArabic[label]!);
        await ttsService.speak(yolo.labelsToArabic[label]!);
      }
    }
  }

  static Future<void> writeToBraille(String caption) async {
    if ((assistiveUnits[0]['isConnected'] as bool)) {
      BluetoothCharacteristic? characteristic = assistiveUnits[0]
          ['connectedCharacteristic'] as BluetoothCharacteristic?;
      if (characteristic != null) {
        await characteristic.write(utf8.encode(caption));
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

  /// Analyzes detected objects and determines the object with the maximum weight.
  ///
  /// This function processes a list of detected objects, each represented as a map
  /// containing information such as class name and bounding box. It calculates
  /// the movement and direction of each object based on its bounding box and
  /// compares it to previous frame data. The weight of each object is measured
  /// using the `measureWeight` method of `PriorityItem`. The object with the
  /// highest weight ('HIGH' > 'MEDIUM' > 'LOW') is identified, and if multiple
  /// objects have the same weight, the first one is selected.
  ///
  /// - Parameters:
  ///   - detectedObjects: A list of maps, where each map contains details about
  ///     a detected object, including its class name and bounding box.
  ///
  /// - Returns: The `PriorityItem` object with the highest weight among the
  ///   detected objects, or null if no objects are detected.
  priority_manager.PriorityItem? _weightOfObjects(
      List<Map<String, dynamic>> detectedObjects, img.Image image) {
    var maxWeight = 'LOW'; // Variable to track the maximum weight found
    priority_manager.PriorityItem?
        maxObject; // Variable to store the object with the highest weight

    // Iterate over each detected object to determine movement and weight
    for (var objectData in detectedObjects) {
      String label =
          objectData['className']; // Get the label of the detected object

      // Create a PriorityItem for the current object
      priority_manager.PriorityItem item = priority_manager.PriorityItem(
          label: label,
          isPersonMoving: isPersonMoving,
          isObjectMoving: false,
          weight: 1.0,
          direction: '',
          frame: image);
      if (item.ttsServiceNotInitialized()) {
        item.initTTS();
      }
      Map<String, dynamic>? previousObject;
      // ignore: unnecessary_null_comparison
      if (previousObjects != null &&
          previousObjects.isNotEmpty &&
          previousObjects.length > 1 &&
          // ignore: unnecessary_null_comparison
          label != null) {
        previousObject = previousObjects
            .firstWhere((element) => element?['className'] == label);
      }

      // is object moving - check if the object is moving based on its bounding box
      if (objectData['boundingBox'] != null &&
          previousObjects.isNotEmpty &&
          previousObject != null) {
        item.isObjectMoving =
            _isObjectMoving(objectData['boundingBox'], previousObject);
      }

      if (item.isObjectMoving && previousObject != null) {
        item.direction =
            _getDirection(objectData['boundingBox'], previousObject);
      }

      // Measure the weight of the current object
      var itemWeight = item.measureWeight();
      // Update maxWeight and maxObject based on itemWeight
      if (itemWeight == 'HIGH' ||
          (itemWeight == 'MEDIUM' && maxWeight != 'HIGH') ||
          (itemWeight == 'LOW' && maxWeight == 'LOW')) {
        maxWeight = itemWeight;
        maxObject = item;
      }
    }

    previousObjects = detectedObjects;

    return maxObject; // Return the object with the highest weight
  }

  Future<List<Map<String, dynamic>>> _runObjectDetectionInBackground(
      img.Image image) async {
    final detectedObjects = yolo.runObjectDetection({
      'image': image,
      'labels': labels,
      'height': image.height,
      'width': image.width,
      'interpreter': _interpreter
    });
    return detectedObjects;
  }

  bool _compareImages(Nv21Image lastFrame, Nv21Image currentFrame) {
    // Check if dimensions are the same
    if (lastFrame.width != currentFrame.width ||
        lastFrame.height != currentFrame.height) {
      return false; // Different dimensions mean images are not the same
    }

    // Compare pixel data
    final lastPixels = lastFrame.bytes;
    final currentPixels = currentFrame.bytes;
    if (lastPixels.length != currentPixels.length) {
      return false; // Different data size means images are not the same
    }

    int differenceCount = 0;
    for (int i = 0; i < lastPixels.length; i += 4) {
      final int rDiff = (lastPixels[i] - currentPixels[i]).abs();
      final int gDiff = (lastPixels[i + 1] - currentPixels[i + 1]).abs();
      final int bDiff = (lastPixels[i + 2] - currentPixels[i + 2]).abs();
      if (rDiff > 10 || gDiff > 10 || bDiff > 10) {
        differenceCount++;
      }
    }
    return ((differenceCount - 0) / 320000) < 0.73;
  }

  Future<void> _askQuestion() async {
    await speechToTextService.stopListening();

    await speechToTextService.startListening((text) async {
      await writeToBraille('لحظة');
      await ttsService.speak('لحظةً');
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
          await writeToBraille("لم يتم العثور على موقعك");
          await ttsService.speak("لم يتم العثور على موقعك");
          return;
        }
        if (loc == null) {
          return;
        }
        destination = Position.fromMap(loc['position']);
        printDebug("going to ${loc['name']}, ${loc['position']}");
        await writeToBraille("سَيَتِم توجيهك إلى ${loc['name']}");
        await ttsService.speak("سَيَتِم توجيهك إلى ${loc['name']}");

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
            await writeToBraille("لم أعثر على شيء, عذرََا");
            await ttsService.speak("لم أعثر على شيء, عذرََا");
          }
          await writeToBraille("عثرت على ${place!['name']}, سأطلب سائق أُجرةِِ إليه");
          await ttsService.speak("عثرت على ${place['name']}, سأطلب سائق أُجرةِِ إليه");
          return;
        }
        destination = Position.fromMap(loc['position']);
        printDebug("going to ${loc['name']}, ${loc['position']}");

       

        if (origin == null) {
          await writeToBraille("لم يتم العثور على موقعك");
          await ttsService.speak("لم يتم العثور على موقعك");
          return;
        }
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

        await writeToBraille("قُمتُ بطلب سائق أُجرَة إلى ${loc['name']}");
        await ttsService.speak("قُمتُ بطلب سائق أُجرَة ليوصلَك إلى ${loc['name']}");
      }

      if (UberService.isRequestingTaxi(text, taxiTerms)) {
        await writeToBraille("سأعمل على طلب سائق أُجرَة, إلى أين تريد الذهاب؟");
        await ttsService.speak("سأعمل على طلب سائق أُجرَة, إلى أين تريد الذهاب؟");
        isListeningToPlaceForTaxi = true;
      } else if (Maps.isRequestingDirections(text, mapsTerms)) {
        await writeToBraille("إلى أين تريد الذهاب؟");
        await ttsService.speak("إلى أين تريد الذهاب؟");
        printDebug("listening to place...");
        isListeningToPlace = true;
      } else if (Ocr.isRequestingOCR(text, oCRterms)) {
        if (_currentImg == null) {
          await writeToBraille("يجب فتح الكَمِرا");
          await ttsService.speak("يجب فتح الكاميرا");
        } else {
          final extracted =
              await Ocr.performOcrVQA(yolo.fromJpegToImg(_currentImg!));
          await writeToBraille(extracted ?? "لم أستطع تحديد النص");
          await ttsService.speak(extracted ?? "لم أستطع تحديد النص");
        }
      } else {
        if (_currentImg == null) {
          await writeToBraille("يجب فتح الكَمِرا");
          await ttsService.speak("يجب فتح الكاميرا");
        } else {
          Position? origin;
          await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.best)
              .then((Position position) {
            origin = position;
          });

          final location = await placemarkFromCoordinates(
              origin?.latitude ?? 0, origin?.longitude ?? 0);
          final answer = await VQA().ask(
              """Be as a Visual Question Answerer for a blind, answer the question: '$text' with short answer IN ARABIC. Do not say anything else also note that the question is in arabic and is latinized, so deal with that 
              ${origin != null ? "Also, note that you are currently at ${location[0].locality}, ${location[0].subLocality}: ${location[0].name} location, so make sure to answer the question based on that." : ""}
              ${isDirectionServiceRunning ? " In addition, note that the blind is trying to go to a destination, so add this to your context when answering." : ""}""",
              yolo.fromJpegToImg(_currentImg!));
          await writeToBraille(answer as String);
          await ttsService.speak(answer);
        }
      }
    });
  }

  void _connectToAU(Map<String, Object?> au) async {
    var targetDeviceName = au["deviceName"] as String;
    const targetServiceUuid = "00001800-0000-1000-8000-00805f9b34fb";
    const targetCharacteristicUuid = "00002a00-0000-1000-8000-00805f9b34fb";

    try {
      printDebug("Scanning for devices...");
      FlutterBluePlus.startScan(timeout: Duration(seconds: 5));

      var subscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult result in results) {
          printDebug(
              'Found device: ${result.device.advName}, ID: ${result.device.remoteId}');
          if (result.device.advName == targetDeviceName) {
            await FlutterBluePlus.stopScan();
            printDebug("Connecting to ${result.device.advName}...");

            au["connectedDevice"] = result.device;
            await (au["connectedDevice"] as BluetoothDevice?)!.connect();
            printDebug("Connected!");

            var services = await (au["connectedDevice"] as BluetoothDevice?)!
                .discoverServices();
            for (var service in services) {
              printDebug('Service: ${service.uuid}');
              if (service.uuid.toString() == targetServiceUuid) {
                au["connectedService"] = service;

                for (var characteristic in service.characteristics) {
                  printDebug('Characteristic: ${characteristic.uuid}');
                  if (characteristic.uuid.toString() ==
                      targetCharacteristicUuid) {
                    au["connectedCharacteristic"] = characteristic;
                    setState(() {
                      au["isConnected"] = true;
                    });
                    printDebug("Target characteristic saved!");
                    break;
                  }
                }
                break;
              }
            }
          }
        }
      });

      await Future.delayed(Duration(seconds: 5));
      subscription.cancel();
    } catch (e) {
      printDebug("Error: $e");
    }
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
      await writeToBraille(instruction);
      await ttsService.speak(instruction);
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
