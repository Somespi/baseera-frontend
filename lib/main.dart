import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'help_utilities.dart';
import 'yolo.dart' as yolo; 
import 'assistive_units/braille_display.dart' as braille_display;

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

    _interpreter = await yolo.loadModel();
    _interpreter.allocateTensors();

    setState(() {
      _isLoading = false;
    });
  }

  Future<List<Map<String, dynamic>>> analyzeImage(dynamic image) async {
    return await yolo.runObjectDetectionInBackground(image, _interpreter);
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
        List<Map<String, dynamic>> val = await analyzeImage(image);
        printDebug(val);
        
      },
      imageAnalysisConfig: AnalysisConfig(
        androidOptions: const AndroidAnalysisOptions.nv21(
          width: 1080,
        ),
        autoStart: true,
        maxFramesPerSecond: 5,
      ),
      builder: (CameraState state, Preview preview) {
        return Scaffold(
          body: Center(child: Text(_out ?? "Analyzing...")),
        );
      },
    );
  }
}
