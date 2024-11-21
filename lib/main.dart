import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as imglib;
import 'package:yuv_converter/yuv_converter.dart';

bool objectDetection = false;
IsolateInterpreter? interpreter;

// Utility debug print
void print4d(value) {
  if (kDebugMode) print(value);
}

// Load the TensorFlow Lite model
Future<void> loadModel() async {
  const assetFileName = 'assets/models/yolov5nu_float32.tflite';
  try {
    Interpreter inter = await Interpreter.fromAsset(assetFileName);
    interpreter = await IsolateInterpreter.create(address: inter.address);
    print4d("Model loaded successfully.");
  } catch (e) {
    print4d("Error loading model: $e");
  }
}

// Run object detection in the background
Future<void> runObjectDetectionInBackground(Nv21Image image) async {
  try {
    final result = await compute(_processImageForDetection, image);
    print4d("Detection Outputs: $result");
  } catch (e) {
    print4d("Error during object detection: $e");
  }
}

// Background function to process image and run detection
Future<List> _processImageForDetection(Nv21Image image) async {
  try {
    final rgbImage = _convertNV21(image);
    final resizedImage = imglib.copyResize(rgbImage, width: 320, height: 320);

    final normalizedPixels = resizedImage.data!
        .map((pixel) {
          final r = (pixel.r) / 255.0;
          final g = (pixel.g) / 255.0;
          final b = (pixel.b) / 255.0;
          return [r, g, b];
        })
        .expand((rgb) => rgb)
        .toList();

    final inputImage = Uint8List.fromList(
        normalizedPixels.map((e) => (e * 255).toInt()).toList());

    assert(inputImage.length == 320 * 320 * 3,
        "Expected input size does not match!");

    var outputs = List.filled(1 * 84 * 8400, 0).reshape([1, 84, 8400]);
    await interpreter?.run(inputImage, outputs);

    return outputs;
  } catch (e) {
    print4d("Error during image processing: $e");
    return [];
  }
}

// Convert NV21 image format to RGB
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

// Utility function to reshape a flat list into a 4D list
List<List<List<List<double>>>> reshape(List<double> data, List<int> shape) {
  int index = 0;
  int dim1 = shape[0];
  int dim2 = shape[1];
  int dim3 = shape[2];
  int dim4 = shape[3];

  return List.generate(
      dim1,
      (_) => List.generate(
          dim2,
          (_) => List.generate(
              dim3, (_) => List.generate(dim4, (_) => data[index++]))));
}

// Main entry point of the app
void main() {
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

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> analyzeImage(dynamic image) async {
    await runObjectDetectionInBackground(image);
  }

  Future<void> _initializeModel() async {
    try {
      await loadModel();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print4d("Error initializing model: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return CameraAwesomeBuilder.custom(
      builder: (cameraState, previewSize, previewRect) {
      },
      saveConfig: SaveConfig.photo(),
      onImageForAnalysis: (image) async {
        await analyzeImage(image);
      },
      imageAnalysisConfig: AnalysisConfig(
        androidOptions: const AndroidAnalysisOptions.nv21(
          width: 640,
        ),
        autoStart: true,
        maxFramesPerSecond: 10,
      ),
    );
  }
}
