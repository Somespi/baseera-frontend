// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:baseerah/image_retriever.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:image/image.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'yolo.dart';

late List<String> labels;
late FlutterBackgroundService service;
final imageRetriever = BluetoothImageRetriever();
RootIsolateToken? token;

Future<void> initializeService(tok) async {
  token = tok;
  labels = await loadLabels();
  service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStartOnBoot: true,
        autoStart: true,
        isForegroundMode: true,
        foregroundServiceTypes: [
          AndroidForegroundType.mediaPlayback,
          AndroidForegroundType.location,
          AndroidForegroundType.microphone
        ]),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
    ),
  );
}

Future<void> onStart(ServiceInstance service) async {
  Timer.periodic(const Duration(seconds: 1), (_) {
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
    final localToken = ServicesBinding.rootIsolateToken;
    if (localToken != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(localToken);
    }

    await imageRetriever.startImageProcessing('24:D7:EB:0F:09:02', token);
  } catch (e) {
    print('Isolate initialization error: $e');
  }
}

Future<Uint8List?> _getImageBuffer() async {
  return null;
}

Future<List> _runDetection(Interpreter interpreter, Image image) async {
  return await runObjectDetectionInBackground(image, interpreter, labels);
}
