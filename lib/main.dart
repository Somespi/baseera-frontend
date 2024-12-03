import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:basera/pages/ar_route.dart';
import 'package:basera/pages/ocr_route.dart';
import 'package:basera/services/ocr/ocr.dart';
import 'package:basera/services/speech_to_text.dart';
import 'package:basera/services/vqa.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:serialport_plus/serialport_plus.dart';
import 'package:usb_serial/usb_serial.dart';

import 'services/help_utilities.dart';
import 'services/priority_manager.dart' as priority_manager;
import 'services/text_to_speech.dart';
import 'services/yolo.dart' as yolo;

late List<String> labels;
DateTime lastImageTime = DateTime.now();
TextToSpeechService ttsService = TextToSpeechService();
SpeechToTextService speechToTextService = SpeechToTextService();
const routes = <Widget?>[null, DocumentsPage(), ARroutePage()];

const titles = <String>["الصفحة الرئيسية", "المستندات", "الماسح الضوئي"];
var assistiveUnits = [
  {
    "name": "خلية برايل",
    "isUsing": false,
    "image": "assets/icons/braille.png",
    "description":
        "جهاز بريل يترجم النصوص المكتوبة إلى نقاط بارزة لتمكين الأشخاص ذوي الاحتياج البصري والسمعي من قراءتها بشكل مستقل.",
    "bleAddress": "3C:84:27:C3:33:99",
  }
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

/// Performs a static action in the background using the provided parameters.
///
/// This function takes a map of parameters, extracts the 'weight' and 'nv21Image',
/// and uses them to perform a static action through the `PriorityItem` class in
/// the `priority_manager` package. The action is executed asynchronously in the
/// background, and the result is returned as a `Future<String?>`.
///
/// - Parameters:
///   - params: A map containing the parameters 'weight' and 'nv21Image' required
///             to perform the action.
///
/// - Returns: A `Future<String?>` containing the result of the action.
Future<void> _performActionInBackground(Map<String, dynamic> params) async {
  final weight = params['weight'];
  final nv21Image = params['nv21Image'];

  await priority_manager.PriorityItem.performStaticAction(weight, nv21Image);
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
  // ignore: unused_field
  UsbPort? _port;
  JpegImage? _currentImg;
  Uint8List _currentImgBuffer = Uint8List(0);
  final _serialportFlutterPlugin = SerialportPlus();
  bool isPersonMoving = false;
  bool _isStreamingPort = false;
  // ignore: prefer_final_fields
  List<Isolate?> _isolates = List.filled(1, null, growable: false);
  Nv21Image? lastFrame;
  StreamSubscription? _gyroscopeSubscription;
  bool isUsingCamera = false;
  priority_manager.PriorityItem? _lastItem;
  late List<String> terms;
  int _selectedIndex = 0;

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
    terms = await Ocr.loadTerms();

    setState(() {
      _isLoading = false;
    });
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
    await _port?.close();
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
          await Future.delayed(const Duration(milliseconds: 1000));
        },
        imageAnalysisConfig: AnalysisConfig(
          androidOptions: const AndroidAnalysisOptions.nv21(width: 480),
          autoStart: true,
          maxFramesPerSecond: 5,
        ),
        builder: (controller, preview) {
          () async {
            if (!isUsingCamera) {
              for (var isolate in _isolates) {
                if (isolate == null) continue;
                isolate.kill(priority: Isolate.immediate);
              }
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
                FloatingActionButton(
                    heroTag: "camera",
                    onPressed: () async {
                      printDebug("Detecting press...");
                      if (isUsingCamera) {
                        _cleanUp();
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
                SizedBox(height: 10.0),
                FloatingActionButton(
                  heroTag: "serial",
                  child: (!_isStreamingPort)
                      ? const Icon(Icons.usb)
                      : const Icon(Icons.usb_off),
                  onPressed: () {
                    if (_isStreamingPort) {
                      _serialportFlutterPlugin.close();
                      _isStreamingPort = false;
                      return;
                    }
                    _isStreamingPort = true;
                    isUsingCamera = false;
                    _readDataFromSerial();
                  },
                ),
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
                              color: Color.fromARGB(255, 168, 168, 168),
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
                                        onPressed: () => _connectToAU(au),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color.fromARGB(
                                              255, 90, 181, 255),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8.0),
                                          ),
                                          fixedSize: const Size(100, 30),
                                        ),
                                        child: Text(
                                          "اتصل",
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

  /// Reads data from the serial port, runs object detection on the received
  /// images and performs the appropriate action based on the object detection
  /// results.
  ///
  /// This function opens the serial port, sets the port parameters, and listens
  /// to the input stream. When a delimiter is found in the input stream, the
  /// function decodes the image data and runs object detection on the image.
  /// The results of the object detection are used to determine the weight of
  /// the detected objects. The function then performs the appropriate action
  /// based on the weight of the detected objects.
  ///
  /// The function also listens to the gyroscope data stream and sets the
  /// [isPersonMoving] flag to true if the magnitude of the gyroscope data
  /// exceeds a certain threshold. This flag is used to determine the weight
  /// of the detected objects.
  void _readDataFromSerial() async {
    List<UsbDevice> devices = await UsbSerial.listDevices();
    printDebug("Found ${devices.length} devices");
    if (devices.isEmpty) {
      return;
    }

    UsbPort? port = await devices[0].create();
    if (port == null) {
      printDebug("Failed to create port");
      return;
    }
    _port = port;

    bool openResult = await port.open();
    if (!openResult) {
      printDebug("Failed to open port");
      return;
    }

    await port.setDTR(true);
    await port.setRTS(true);

    port.setPortParameters(
      115200,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    isUsingCamera = false;
    _isStreamingPort = true;

    port.inputStream?.listen((Uint8List event) async {
      try {
        if (isUsingCamera || !_isStreamingPort) {
          await port.close();
          return;
        }
        _currentImgBuffer = Uint8List.fromList(_currentImgBuffer + event);
        const delimiter = '\nDone...';
        final delimiterIndex =
            String.fromCharCodes(_currentImgBuffer).indexOf(delimiter);

        if (delimiterIndex != -1) {
          final imageData = _currentImgBuffer.sublist(0, delimiterIndex);

          _currentImgBuffer =
              _currentImgBuffer.sublist(delimiterIndex + delimiter.length);

          var image = img.decodeJpg(imageData);
          if (image != null) {
            //image = img.Image.fromBytes(bytes: image.buffer, height: image.height, width: image.width);

            final detectedObjects =
                // ignore: use_build_context_synchronously
                await _runObjectDetectionInBackground(image);

            final maxObject = _weightOfObjects(detectedObjects, image);
            if (maxObject != null) {
              final params = {
                'weight': maxObject.measureWeight(),
                'nv21Image': image,
              };
              await compute(_performActionInBackground, params);
            }
          } else {
            printDebug('Failed to decode JPEG image');
            printDebug('Image data length: ${imageData.length}');
          }
        }
      } catch (e) {
        printDebug('Error: $e');
      }
    }, onError: (error) {
      printDebug('Stream read error: $error');
    }, onDone: () {
      printDebug('Image stream closed');
    });
  }

  void _readDataFromCameraStream(JpegImage image) async {
    if (!isUsingCamera) {
      return;
    }
    final imageIm = await compute(yolo.fromJpegToImg, image);
    final detectedObjects = await _runObjectDetectionInBackground(imageIm);
    final maxObject = _weightOfObjects(detectedObjects, imageIm);

    if (maxObject != null) {
      final params = {
        'weight': maxObject.measureWeight(),
        'nv21Image': imageIm,
      };

      printDebug(detectedObjects);

      if (_lastItem == null ||
          maxObject.itemInitializedAt
                  .difference(_lastItem!.itemInitializedAt)
                  .inSeconds >
              5) {
        _lastItem = maxObject;
        await _taskEntryPoint(params);
      }
    }
  }

  bool isIsolateActive(Isolate isolate) {
    try {
      isolate.ping(RawReceivePort().sendPort);
      return true;
    } catch (e) {
      return false;
    }
  }

  void _cleanUp() {
    if (_isolates.length >= 2) {
      final isolatesToKill = List<Isolate?>.from(_isolates);

      for (final isolate in isolatesToKill) {
        try {
          // ignore: unnecessary_null_comparison
          if (isolate == null) {
            printDebug("Isolate is null.");
            continue;
          }
          try {
            isolate.ping(RawReceivePort().sendPort);
          } catch (e) {
            printDebug("Isolate is already dead.");
            _isolates.remove(isolate);
            continue;
          }
          isolate.kill(priority: Isolate.immediate);
          _isolates.remove(isolate);
          printDebug("Killed isolate. Remaining isolates: ${_isolates.length}");
        } catch (e) {
          printDebug("Error handling isolate: $e");
          _isolates.remove(isolate);
        }
      }
    }
  }

  static Future<void> _taskEntryPoint(Map<String, dynamic> params) async {
    BackgroundIsolateBinaryMessenger.ensureInitialized(
        RootIsolateToken.instance!);
    final weight = params['weight'];
    final nv21Image = params['nv21Image'];
    if (weight == null || nv21Image == null) {
      return;
    }
    HapticFeedback.mediumImpact();
    if (weight == 'HIGH') {
      String? caption = await VQA().caption(nv21Image);
      if (caption == null) {
        printDebug("Caption is null");
      } else {
        printDebug("Caption: $caption");
        await ttsService.speak(caption);
      }
    } else if (weight == 'MEDIUM') {
      HapticFeedback.vibrate();
    }
    //priority_manager.PriorityItem.performStaticAction(weight, nv21Image);
    //params['port'].send('done');
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

    var previousFrameObjects = <String,
        List<double>>{}; // Map to store previous frame objects' positions

    // Iterate over each detected object to determine movement and weight
    for (var objectData in detectedObjects) {
      String label =
          objectData['className']; // Get the label of the detected object
      List<int> currentBox =
          objectData['bbox']; // Get the bounding box of the detected object

      // Create a PriorityItem for the current object
      priority_manager.PriorityItem item = priority_manager.PriorityItem(
          label: label,
          isPersonMoving: isPersonMoving,
          isObjectMoving: false,
          weight: 1.0,
          direction: '',
          frame: image);
      item.initTTS();
      // Check if the object was present in the previous frame
      if (previousFrameObjects.containsKey(labels[objectData['classIndex']])) {
        // Calculate movement based on the change in position
        double previousX =
            previousFrameObjects[labels[objectData['classIndex']]]?[0] ?? 0.0;
        double previousY =
            previousFrameObjects[labels[objectData['classIndex']]]?[1] ?? 0.0;

        double dx = currentBox[0] - previousX;
        double dy = currentBox[1] - previousY;

        bool isMoving =
            (dx.abs() + dy.abs()) > 5; // Determine if the object is moving
        String direction = '';
        if (isMoving) {
          // Determine the direction of movement
          if (dx.abs() > dy.abs()) {
            direction = dx > 0 ? 'right' : 'left';
          } else {
            direction = dy > 0 ? 'down' : 'up';
          }
        }
        item.isObjectMoving = isMoving;
        item.direction = direction;
      }

      // Measure the weight of the current object
      var itemWeight = item.measureWeight();
      // Update maxWeight and maxObject based on itemWeight
      if (itemWeight == 'HIGH') {
        maxWeight = 'HIGH';
        maxObject = item;
      } else if (itemWeight == 'MEDIUM' && maxWeight != 'HIGH') {
        maxWeight = 'MEDIUM';
        maxObject = item;
      } else if (itemWeight == 'LOW' && maxWeight == 'LOW') {
        maxObject ??= item;
      }
    }

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

    // Calculate the difference
    int differenceCount = 0;
    const int tolerance = 10; // Allow some pixel differences
    for (int i = 0; i < lastPixels.length; i++) {
      if ((lastPixels[i] - currentPixels[i]).abs() > tolerance) {
        differenceCount++;
      }
    }

    const int differenceThreshold = 800419;
    return differenceCount < differenceThreshold;
  }

  Future<void> _askQuestion() async {
    await speechToTextService.stopListening();
    await speechToTextService.startListening((text) async {
      if (Ocr.isRequestingOCR(text, terms)) {
        if (_currentImg == null) {
          await ttsService.speak("عذرا, يجب فتح الكَمِرا أولََا");
        } else {
          await ttsService.speak("يتم التحقق من الصورة");
          final extracted =
              await Ocr.performOcrVQA(yolo.fromJpegToImg(_currentImg!));

          await ttsService.speak(extracted!);
          printDebug(extracted);
        }
      } else {
        if (_currentImg == null) {
          await ttsService.speak("عذرا, يجب فتح الكَمِرا أولََا");
        } else {
          await ttsService.speak(await VQA().ask(
              "Be as a Visual Question Answerer for a blind, answer the question: '$text' with short answer IN ARABIC. Do not say anything else also note that the question is in arabic and is latinized, so deal with that",
              yolo.fromJpegToImg(_currentImg!)) as String);
        }
      }
      printDebug(text);
    });
    // await Future.delayed(Duration(seconds: 5, milliseconds: 2), () async {
    // });
  }

  _connectToAU(Map<String, Object> au) async {
    var subscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        ScanResult r = results.last;
        printDebug(
            '${r.device.remoteId}: "${r.advertisementData.advName}" found!');
      },
      onError: (e) => printDebug(e),
    );

    FlutterBluePlus.cancelWhenScanComplete(subscription);
    await FlutterBluePlus.adapterState
        .where((val) => val == BluetoothAdapterState.on)
        .first;

    await FlutterBluePlus.startScan(
        withServices: [Guid("180D")], timeout: Duration(seconds: 5));

    var device =
        await FlutterBluePlus.isScanning.where((val) => val == false).first;
  }
}
