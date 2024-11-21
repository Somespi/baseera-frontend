import 'package:image/image.dart' as imglib;
import 'package:flutter/material.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:yuv_converter/yuv_converter.dart';

bool objectDetection = false;

Future<OrtSession?> loadModel() async {
  const assetFileName = 'assets/models/yolov5nu.onnx';
  try {
    OrtEnv.instance.init();
    final rawAssetFile = await rootBundle.load(assetFileName);
    print4d(
        "Model file loaded successfully: ${rawAssetFile.lengthInBytes} bytes");
    final bytes = rawAssetFile.buffer.asUint8List();
    final sessionOptions = OrtSessionOptions();
    OrtSession ortSession = OrtSession.fromBuffer(bytes, sessionOptions);
    print4d("Model loaded successfully.");
    return ortSession;
  } catch (e) {
    print4d("Error loading model: $e");
  }
  return null;
}

Future<void> runObjectDetection(Nv21Image image, OrtSession? session) async {
  try {
    final rgbImage = _convertNV21(image);
    // print4d("Converted image dimensions: ${rgbImage.width}x${rgbImage.height}");

    final resizedImage = imglib.copyResize(rgbImage, width: 640, height: 640);
    // print4d(
    //     "Resized image dimensions: ${resizedImage.width}x${resizedImage.height}");

    final normalizedPixels = resizedImage.data!
        .map((pixel) {
          final r = (pixel.r) / 255.0;
          final g = (pixel.g) / 255.0;
          final b = (pixel.b) / 255.0;
          return [r, g, b];
        })
        .expand((rgb) => rgb)
        .toList(); 

    // print4d(
    //     "First few normalized pixels: ${normalizedPixels.take(10).toList()}");
    // print4d(
    //     "Normalized pixels length: ${normalizedPixels.length}, Expected: ${1 * 3 * 640 * 640}");

    final inputShape = [1, 3, 640, 640];
    if (normalizedPixels.length != inputShape.reduce((a, b) => a * b)) {
      throw Exception(
          "Image size mismatch: Expected ${inputShape.reduce((a, b) => a * b)}, but got ${normalizedPixels.length}");
    }

    final inputTensor =
        OrtValueTensor.createTensorWithDataList(normalizedPixels, inputShape);
    final inputs = {'images': inputTensor};
    final runOptions = OrtRunOptions();
    print4d(session);
    dynamic outputs;
    if (session != null) outputs = await session.runAsync(runOptions, inputs);

    print4d("Outputs: $outputs");
  } catch (e) {
    print4d("Error during object detection: $e");
  }
}

imglib.Image _convertNV21(Nv21Image image) {
  Uint8List rgbga1 = YuvConverter.yuv420NV21ToRgba8888(
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
      int r = rgbga1[index++];
      int g = rgbga1[index++];
      int b = rgbga1[index++];
      int a = rgbga1[index++];
      outImg.setPixelRgba(x, y, r, g, b, a);
    }
  }
  return outImg;
}

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

void print4d(value) {
  if (kDebugMode) {
    print(value);
  }
}

class _MyHomePageState extends State<MyHomePage> {
  OrtSession? _model;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> analyzeImage(dynamic image, OrtSession? session) async {
    if (session == null) {
      print4d("Model not loaded yet. Skipping image analysis.");
      return;
    }
    await runObjectDetection(image, session);
  }

  Future<void> _initializeModel() async {
    try {
      final model = await loadModel();
      setState(() {
        _model = model; 
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

    if (_model == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(
          child: Text('Error loading model. Please restart the app.'),
        ),
      );
    }

    return CameraAwesomeBuilder.awesome(
      saveConfig: SaveConfig.photo(),
      onImageForAnalysis: (image) async {
        await analyzeImage(image, _model);
      },
      imageAnalysisConfig: AnalysisConfig(
        androidOptions: const AndroidAnalysisOptions.nv21(
          width: 640,
        ),
        autoStart: true,
        maxFramesPerSecond: 20,
      ),
    );
  }
}
