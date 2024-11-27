import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:baseerah/preprocess_image.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'help_utilities.dart';
import 'yolo.dart' as yolo;

late List<String> labels;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  labels = await yolo.loadLabels();
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
Uint8List encodeAsPng(Uint8List rawData, int width, int height) {
  final image = img.Image.fromBytes(bytes: rawData.buffer, height: height, width: width);
  return Uint8List.fromList(img.encodePng(image));
}
class _MyHomePageState extends State<MyHomePage> {
  bool _isLoading = false;
  late Interpreter _interpreter;
  Uint8List? _img;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    setState(() {
      _isLoading = false;
    });

    _interpreter = await yolo.loadModel();
    _interpreter.allocateTensors();

    setState(() {
      _isLoading = false;
    });
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


    return CameraAwesomeBuilder.analysisOnly(
      onImageForAnalysis: (image) async {
        final detections = await yolo.runObjectDetectionInBackground(yolo.fromJpegToImg(image as JpegImage), _interpreter, labels);
        printDebug( detections);
      },
      imageAnalysisConfig: AnalysisConfig(
        androidOptions: const AndroidAnalysisOptions.jpeg(
          width: 1080,
        ),
        autoStart: true,
        maxFramesPerSecond: 5,
      ),
      builder: (CameraState state, Preview preview) {
        return  Scaffold(
          body: _img != null 
    ?  Center(child: Image(image: MemoryImage(_img!), height: 640, width: 640,))
    : const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
