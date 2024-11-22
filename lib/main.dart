import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as imglib;
import 'package:yuv_converter/yuv_converter.dart';
import 'dart:math';

// Global variables
bool objectDetection = false;

// Debug utility
void printDebug(value) {
  if (kDebugMode) print(value);
}

// Load TensorFlow Lite model
Future<Interpreter> loadModel() async {
  const assetFileName = 'assets/models/yolov5nu_float32.tflite';
  Interpreter inter = await Interpreter.fromAsset(assetFileName);
  return inter;
}

Future<String> runObjectDetectionInBackground(
    Nv21Image image, Interpreter interpreter) async {
  interpreter.allocateTensors();
  final inputDetails = interpreter.getInputTensors();
  final outputDetails = interpreter.getOutputTensors();
  final result = _detectObjects(
      await compute(_processImageForDetection,
          [image, inputDetails[0].shape, outputDetails[0].shape]),
      interpreter);
  final detections = postProcess(
      await result, 0.5, 0.4); // Confidence threshold: 0.5, NMS threshold: 0.4
  return "Post Processed Detections: $detections";
}

_detectObjects(List inout, Interpreter inter) async {
  dynamic out = inout[1];
  inter.run(inout[0], out);
  return out;
}

Future<List> _processImageForDetection(dynamic message) async {
  try {
    final rgbImage = _convertNV21(message[0]);

    final resizedImage = imglib.copyResize(rgbImage,
        width: message[1][2], height: message[1][1]);

    final normalizedPixels = resizedImage.data!
        .map((pixel) =>
            [(pixel.r / 255.0), (pixel.g / 255.0), (pixel.b / 255.0)])
        .expand((rgb) => rgb)
        .toList();

    var inputImage = Float32List.fromList(normalizedPixels).reshape(message[1]);
    var outputs = List.filled(1 * 84 * 8400, 0).reshape(message[2]);

    return [inputImage, outputs];
  } catch (e) {
    printDebug("Error during image processing: $e");
    return [];
  }
}

imglib.Image _convertNV21(Nv21Image image) {
  Uint8List rgbga = YuvConverter.yuv420NV21ToRgba8888(
    image.bytes,
    image.width.toInt(),
    image.height.toInt(),
  );

  final outImg = imglib.Image(
    width: image.width.toInt(),
    height: image.height.toInt(),
  );

  int index = 0;
  for (int y = 0; y < image.height.toInt(); y++) {
    for (int x = 0; x < image.width.toInt(); x++) {
      int r = rgbga[index++];
      int g = rgbga[index++];
      int b = rgbga[index++];
      int a = rgbga[index++];
      outImg.setPixelRgba(x, y, r, g, b, a);
    }
  }
  return outImg;
}

// Post-processing function (apply confidence threshold and NMS)
List<Map<String, dynamic>> postProcess(List<List<List<dynamic>>> out,
    double confidenceThreshold, double nmsThreshold) {
  List<Map<String, dynamic>> detections = [];
  List<List<double>> output = out[0] as List<List<double>>;
  // Iterate over the model's outputs (bounding boxes)
  for (var row in output) {
    printDebug(row);
    final confidence = row[4]; // Confidence score
    if (confidence > confidenceThreshold) {
      final xCenter = row[0];
      final yCenter = row[1];
      final width = row[2];
      final height = row[3];
      final classId =
          row.sublist(5).indexWhere((val) => val == row.sublist(5).reduce(max));

      // Create a detection
      detections.add({
        'box': Rect.fromLTWH(
            xCenter - width / 2, yCenter - height / 2, width, height),
        'confidence': confidence,
        'classId': classId,
      });
    }
  }

  return detections;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
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

class _MyHomePageState extends State<MyHomePage> {
  bool _isLoading = true;
  late Interpreter _interpreter;
  String? _out;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    setState(() {
      _isLoading = true;
    });

    _interpreter = await loadModel();
    setState(() {
      _isLoading = false;
    });
  }

  Future<String> analyzeImage(dynamic image) async {
    return await runObjectDetectionInBackground(image, _interpreter);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return CameraAwesomeBuilder.analysisOnly(
      onImageForAnalysis: (image) async {
        String val = await analyzeImage(image);
        setState(() {
          _out = val;
        });
      },
      imageAnalysisConfig: AnalysisConfig(
        androidOptions: const AndroidAnalysisOptions.nv21(
          width: 320,
        ),
        autoStart: true,
        maxFramesPerSecond: 4,
      ),
      builder: (CameraState state, Preview preview) {
        return Scaffold(
          body: Center(child: Text(_out ?? "Analyzing...")),
        );
      },
    );
  }
}
