import 'dart:async';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
// ignore: unused_import
import 'help_utilities.dart';
import 'yolo.dart' as yolo;
import 'package:sensors_plus/sensors_plus.dart';
import 'priority_manager.dart' as priority_manager;

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

Future<void> _performActionInBackground(Map<String, dynamic> params) async {
  final weight = params['weight'];
  final nv21Image = params['nv21Image'];

  await priority_manager.PriorityItem.performStaticAction(weight, nv21Image);
}

class _MyHomePageState extends State<MyHomePage> {
  bool _isLoading = true;
  late Interpreter _interpreter;
  String? _out;
  late List<String> _labels;
  bool isPersonMoving = false;
  StreamSubscription? _gyroscopeSubscription;

  @override
  void initState() {
    super.initState();
    _initializeModel();
    _initializeGyroscope();
  }

  Future<void> _initializeModel() async {
    setState(() {
      _isLoading = true;
    });
    _labels = await yolo.loadLabels();
    _interpreter = await yolo.loadModel();
    _interpreter.allocateTensors();

    setState(() {
      _isLoading = false;
    });
  }

  void _initializeGyroscope() {
    const movementThreshold = 0.3;
    _gyroscopeSubscription =
        gyroscopeEventStream().listen((GyroscopeEvent event) {
      final magnitude =
          (event.x * event.x) + (event.y * event.y) + (event.z * event.z);
      setState(() {
        isPersonMoving = magnitude > movementThreshold;
      });
    });
  }

  @override
  void dispose() {
    _interpreter.close();
    _gyroscopeSubscription?.cancel();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> analyzeImage(dynamic image) async {
    return await yolo.runObjectDetectionInBackground(
        image, _interpreter, _labels);
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
        
        List<Map<String, dynamic>> detectedObjects = await analyzeImage(image);
        printDebug("Detected objects: $detectedObjects");
        var maxWeight = 'LOW';
        priority_manager.PriorityItem? maxObject;

        var previousFrameObjects = <String, List<double>>{};

        for (var objectData in detectedObjects) {
          String label = objectData['className'];
          List<int> currentBox = objectData['bbox'];

          priority_manager.PriorityItem item = priority_manager.PriorityItem(
            label: label,
            isPersonMoving: isPersonMoving,
            isObjectMoving: false,
            weight: 1.0,
            direction: '',
          );

          if (previousFrameObjects
              .containsKey(_labels[objectData['classIndex']])) {
            double previousX =
                previousFrameObjects[_labels[objectData['classIndex']]]?[0] ??
                    0.0;
            double previousY =
                previousFrameObjects[_labels[objectData['classIndex']]]?[1] ??
                    0.0;

            double dx = currentBox[0] - previousX;
            double dy = currentBox[1] - previousY;

            bool isMoving = (dx.abs() + dy.abs()) > 5;
            String direction = '';
            if (isMoving) {
              if (dx.abs() > dy.abs()) {
                direction = dx > 0 ? 'right' : 'left';
              } else {
                direction = dy > 0 ? 'down' : 'up';
              }
            }
            item.isObjectMoving = isMoving;
            item.direction = direction;
          }

          var itemWeight = item.measureWeight();
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
        printDebug("Max weight: $maxWeight");
        if (maxObject != null) {
          final params = {
            'weight': maxObject.measureWeight(),
            'nv21Image': yolo.convertNV21(image as Nv21Image),
          };
          await compute(_performActionInBackground, params);
        }
      },
      imageAnalysisConfig: AnalysisConfig(
        androidOptions: const AndroidAnalysisOptions.nv21(width: 1080),
        autoStart: true,
        maxFramesPerSecond: 5,
      ),
      builder: (CameraState state, Preview preview) {
        return Scaffold(
          body: Stack(
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _out ?? "Analyzing...",
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
