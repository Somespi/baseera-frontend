import 'dart:isolate';
import 'package:flutter/material.dart';

import 'help_utilities.dart';
import 'dart:typed_data';
import 'package:baseerah/background_service.dart';
import 'package:baseerah/yolo.dart';
import 'package:bluetooth_classic/bluetooth_classic.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class BluetoothImageRetriever {
  final BluetoothClassic _bluetoothClassic = BluetoothClassic();
  Uint8List _imageBuffer = Uint8List(0);
  RootIsolateToken? token;

  static const String _serialUUID = "00001101-0000-1000-8000-00805f9b34fb";

  Future<void> initializeBluetoothConnection(String macAddress) async {
    try {
      await _bluetoothClassic.initPermissions();
      await _bluetoothClassic.connect(macAddress, _serialUUID);

      _bluetoothClassic.onDeviceDataReceived().listen(_onDataReceived,
          onError: (error) {
        printDebug('Bluetooth data receive error: $error');
        _resetImageBuffer();
      }, cancelOnError: false);
    } catch (e) {
      printDebug('Bluetooth connection error: $e');
    }
  }

  void _onDataReceived(Uint8List data) {
    _imageBuffer = Uint8List.fromList([..._imageBuffer, ...data]);
    if (_isImageComplete()) {
      _processImage();
    }
  }

  bool _isImageComplete() {
    return _imageBuffer.length > 1024 * 100; // More than 100KB
  }

  Future<void> _processImage() async {
    try {
      final image = img.decodeJpg(_imageBuffer);

      if (image != null) {
        final interpreter = await loadModel();
        final detections =
            await runObjectDetectionInBackground(image, interpreter, labels);
        printDebug('Detections: $detections');
        _resetImageBuffer();
      }
    } catch (e) {
      printDebug('Image processing error: $e');
      _resetImageBuffer();
    }
  }

  void _resetImageBuffer() {
    _imageBuffer = Uint8List(0);
  }

  Future<void> disconnectDevice() async {
    try {
      await _bluetoothClassic.disconnect();
    } catch (e) {
      printDebug('Disconnect error: $e');
    }
  }

  Future<void> startImageProcessing(String macAddress, token) async {

    await compute((token) async {
      printDebug(token);
      BackgroundIsolateBinaryMessenger.ensureInitialized(token!);
      await initializeBluetoothConnection(macAddress);

      await Future.delayed(const Duration(hours: 1));
    }, token);
  }
}
