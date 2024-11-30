import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:serialport_plus/serialport_plus.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:usb_serial/usb_serial.dart';
import 'help_utilities.dart';
import 'yolo.dart' as yolo;
import 'priority_manager.dart' as priority_manager;
import 'package:camerawesome/camerawesome_plugin.dart';

late List<String> labels;
DateTime lastImageTime = DateTime.now();
void main() async {
  OrtEnv.instance.init();
  WidgetsFlutterBinding.ensureInitialized();
  final rootIsolateToken = RootIsolateToken.instance;
  if (rootIsolateToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
  } else {
    printDebug(
        "Error: Root Isolate Token is null. Ensure this runs on the main isolate.");
  }
  labels = await yolo.loadLabels();

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
      title: 'بصيرة',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'بصيرة'),
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
  String? _out;
  Uint8List _currentImgBuffer = Uint8List(0);
  final _serialportFlutterPlugin = SerialportPlus();
  bool isPersonMoving = false;
  bool _isStreamingPort = false;
  Uint8List? _img;
  // ignore: prefer_final_fields
  List<Isolate> _isolates = [];
  Nv21Image? lastFrame;
  StreamSubscription? _gyroscopeSubscription;
  bool isUsingCamera = false;

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
    _gyroscopeSubscription?.cancel();
    super.dispose();
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
        appBar: AppBar(title: Text(widget.title)),
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
            //return;
          }
          lastFrame = image;
          image = await (image).toJpeg();
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
              for (var isolate in _isolates) {
                isolate.kill(priority: Isolate.immediate);
              }
              await controller.analysisController?.imageSubscription?.cancel();
              controller.analysisController?.imageSubscription = null;
            }
          }();
          return Scaffold(
            floatingActionButton: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                    heroTag: "camera",
                    onPressed: () async {
                        printDebug("Detecting press...");
                      if (isUsingCamera) {
                        _cleanUp();
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
            body: Center(
              child: Column(
                children: [
                  _out != null ? Text(_out!) : const Text("No data"),
                  _img != null
                      ? Image.memory(_img!)
                      // : isUsingCamera
                      //     ? CameraPreview(controller)
                      : const Text("No image"),
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

      _performTaskInIsolate(params);
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

  /// Spawns a new isolate to perform a task with the provided parameters.
  ///
  /// This function manages a pool of isolates, ensuring that no more than
  /// three isolates are running concurrently. If the limit is exceeded, the
  /// oldest isolate is terminated before starting a new one. The task to be
  /// performed in the isolate is specified by `_taskEntryPoint`, and the
  /// `params` map contains the necessary parameters for the task. Errors in
  /// the isolate are set to non-fatal to allow recovery without crashing the
  /// main application.
  ///
  /// - Parameters:
  ///   - params: A map containing the parameters required for the task.
  ///
  /// This function is typically used to offload heavy computations from the
  /// main thread to improve application responsiveness.
  void _performTaskInIsolate(Map<String, dynamic> params) async {
    _cleanUp();
    final isolate = await Isolate.spawn(_taskEntryPoint, params);
    isolate.setErrorsFatal(false);
    printDebug("Started task in isolate #${_isolates.length}.");
    _isolates.add(isolate);
  }

  void _cleanUp() {
    if (_isolates.length >= 2) {
      // Create a copy of the list to avoid modification during iteration
      final isolatesToKill = List<Isolate>.from(_isolates);
    
      for (final isolate in isolatesToKill) {
        try {
          // ignore: unnecessary_null_comparison
          if (isolate == null) {
            printDebug("Isolate is null.");
            _isolates.remove(isolate);
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

  static void _taskEntryPoint(Map<String, dynamic> params) {
    final weight = params['weight'];
    final nv21Image = params['nv21Image'];
    priority_manager.PriorityItem.performStaticAction(weight, nv21Image);
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

    const int differenceThreshold = 50419;
    return differenceCount < differenceThreshold;
  }
}
