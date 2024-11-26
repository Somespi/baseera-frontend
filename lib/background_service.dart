// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'yolo.dart';

late List<String> labels;
late FlutterBackgroundService service;

Future<void> initializeService() async {
  labels = await loadLabels();
  service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStartOnBoot: true,
      autoStart: true,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
    ),
  );
}

Future<void> onStart(ServiceInstance service) async {
  Timer.periodic(const Duration(seconds: 10), (_) {
    performObjectDetection();
  });
}

void performObjectDetection() async {
  try {
    await Isolate.run(() => _objectDetectionIsolate());
  } catch (e) {
    print('Object detection error: $e');
  }
}

Future<void> _objectDetectionIsolate() async {
  try {
    final interpreter = await loadModel();
    final receivePort = ReceivePort();

    // Implement a mechanism to control the loop
    bool shouldContinue = true;
    while (shouldContinue) {
      try {
        final imageBuffer = await _getImageBuffer();
        if (imageBuffer != null) {
          final image = img.decodeImage(imageBuffer);
          if (image != null) {
            final detections =
                await _runDetection(interpreter, image as Nv21Image);
            // Send results back or process them
          }
        }

        await Future.delayed(const Duration(milliseconds: 1000));
      } catch (e) {
        print('Detection cycle error: $e');
        shouldContinue = false;
      }
    }
  } catch (e) {
    print('Isolate initialization error: $e');
  }
}

Future<Uint8List?> _getImageBuffer() async {
  return null;
}

Future<List> _runDetection(Interpreter interpreter, Nv21Image image) async {
  return await runObjectDetectionInBackground(image, interpreter, labels);
}
