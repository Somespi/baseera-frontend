import 'dart:io';
import 'dart:math';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as imglib;
import 'package:yuv_converter/yuv_converter.dart';

Future<List<String>> loadLabels() async {
  return (await rootBundle.loadString("assets/models/labels.txt")).split('\n');
}

late List<String> labels;

void printDebug(value) {
  if (kDebugMode) print(value);
}

// Load TensorFlow Lite model
Future<Interpreter> loadModel() async {
  const assetFileName = 'assets/models/yolov10n_float32.tflite';
  try {
    final options = InterpreterOptions()..useNnApiForAndroid = true;
    options.threads = 4;
    return Interpreter.fromAsset(assetFileName, options: options);
  } catch (nnapiError) {
    debugPrint("NNAPI also failed: $nnapiError. Falling back to CPU.");
    return Interpreter.fromAsset(assetFileName);
  }
}

Future<String> runObjectDetectionInBackground(
    Nv21Image image, Interpreter interpreter) async {
  final inputDetails = interpreter.getInputTensors();
  final outputDetails = interpreter.getOutputTensors();
  final result = _detectObjects(
      await compute(_processImageForDetection,
          [image, inputDetails[0].shape, outputDetails[0].shape]),
      interpreter);

  final detections = processYoloOutput(await result, 0.4);

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
    var outputs = List.filled(1 * 300 * 6, 0).reshape(message[2]);

    return [inputImage, outputs];
  } catch (e) {
    printDebug("Error during image processing: $e");
    return [];
  }
}

double sigmoid(double x) => 1 / (1 + exp(-x));
List<Map<String, dynamic>> processYoloOutput(
    List<List<List<dynamic>>> output, double confidenceThreshold) {
  List<Map<String, dynamic>> detections = [];

  // Iterate through the output of the YOLO model
  for (var out in output[0]) {
    // Flattening the list for easier processing
    List<double> gridCellData = (out as List<double>)
        .map((e) => e.toDouble()) // Convert to double if necessary
        .toList();

    var boxConfidence = gridCellData[4];

    // Check if the box confidence meets the threshold
    if (boxConfidence < confidenceThreshold) continue;

    var confidence =
        sigmoid(boxConfidence); 
    List<double> classProbs = gridCellData.sublist(5);
    int class_ = classProbs.indexOf(classProbs.reduce(max));
    double classProb = classProbs[class_];

    if (classProb < confidenceThreshold) continue; 
      var cx = gridCellData[0] * 1080;
      var cy = gridCellData[1] * 1080;
      var w = gridCellData[2] * 1080; 
      var h = gridCellData[3] * 1080; 

      var x = (cx - w / 2).round();
      var y = (cy - h / 2).round();
      var box = [x, y, w.round(), h.round()];

    if (box[2] <= 0 || box[3] <= 0 || box[0] < 0 || box[1] < 0) continue;

    var detection = {
      'boundingBox': box,
      'confidence': confidence,
      'class': class_ % labels.length,
      'classProb': classProb,
      'name': labels[class_ % labels.length]
    };

    detections.add(detection);
  }

  return applyNMS(detections, 0.5);
}

double calculateIoU(List<double> box1, List<double> box2) {
  double x1 = box1[0], y1 = box1[1], x2 = box1[2], y2 = box1[3];
  double x1b = box2[0], y1b = box2[1], x2b = box2[2], y2b = box2[3];

  double xi1 = x1 > x1b ? x1 : x1b;
  double yi1 = y1 > y1b ? y1 : y1b;
  double xi2 = x2 < x2b ? x2 : x2b;
  double yi2 = y2 < y2b ? y2 : y2b;

  double intersectionArea = (xi2 - xi1).clamp(0.0, double.infinity) *
      (yi2 - yi1).clamp(0.0, double.infinity);
  double box1Area = (x2 - x1) * (y2 - y1);
  double box2Area = (x2b - x1b) * (y2b - y1b);

  double unionArea = box1Area + box2Area - intersectionArea;
  return intersectionArea / unionArea;
}

List<Map<String, dynamic>> applyNMS(
    List<Map<String, dynamic>> detections, double iouThreshold) {
  detections.sort((a, b) => b['confidence'].compareTo(a['confidence']));
  List<Map<String, dynamic>> filteredDetections = [];

  for (var i = 0; i < detections.length; i++) {
    bool keep = true;
    for (var j = 0; j < filteredDetections.length; j++) {
      double iou = calculateIoU(
          detections[i]['boundingBox'], filteredDetections[j]['boundingBox']);
      if (iou > iouThreshold) {
        keep = false;
        break;
      }
    }
    if (keep) {
      filteredDetections.add(detections[i]);
    }
  }

  return filteredDetections;
}

imglib.Image _convertNV21(Nv21Image image) {
  Uint8List rgba = YuvConverter.yuv420NV21ToRgba8888(
    image.bytes,
    image.width,
    image.height,
  );

  

  final img = imglib.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: rgba.buffer,
      format: imglib.Format.uint8,
      numChannels: 4 // r, g, b, a
      );


  return img;
}


List<Map<String, dynamic>> postProcess(List<List<List<dynamic>>> out,
    double confidenceThreshold, double nmsThreshold) {
  List<Map<String, dynamic>> detections = [];
  List<List<double>> output = out[0] as List<List<double>>;

  for (int i = 0; i < output.length; i++) {
    List<double> row = output[i];
    final confidence = row[4];
    if (confidence > 0.3) {
      final xCenter = row[0];
      final yCenter = row[1];
      final width = row[2];
      final height = row[3];

      detections.add({
        'box': Rect.fromLTWH(
            xCenter - width / 2, yCenter - height / 2, width, height),
        'confidence': confidence,
        'classId': i,
        'name': labels[i]
      });
    }
  }

  return detections;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  labels = await loadLabels();
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
    _interpreter.allocateTensors();

    setState(() {
      _isLoading = false;
    });
  }

  Future<String> analyzeImage(dynamic image) async {
    return await runObjectDetectionInBackground(image, _interpreter);
  }

  @override
  void dispose() {
    _interpreter.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return CameraAwesomeBuilder.awesome(
      onImageForAnalysis: (image) async {
        String val = await analyzeImage(image);
        printDebug(val);
        setState(() {
          _out = val;
        });
      },
      imageAnalysisConfig: AnalysisConfig(
        androidOptions: const AndroidAnalysisOptions.nv21(
          width: 1080,
        ),
        autoStart: true,
        maxFramesPerSecond: 5,
      ),
      saveConfig: SaveConfig.photo(),
      // builder: (CameraState state, Preview preview) {
      //   return Scaffold(
      //     body: Center(child: Text(_out ?? "Analyzing...")),
      //   );
      // },
    );
  }
}
