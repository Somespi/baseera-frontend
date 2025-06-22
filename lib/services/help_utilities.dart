import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as imglib;

void printDebug(value) {
  if (kDebugMode) print(value);
}


/// Converts a JpegImage to an imglib.Image.
///
/// Returns null if the image could not be decoded.
imglib.Image fromJpegToImg(image) {
  final img = imglib.decodeJpg(image.bytes);
  if (img == null) throw Exception("Error decoding JPEG image.");
  return img;
}


Map<String, dynamic> createAssistiveUnitMap(String displayName, String deviceAddress, String deviceCharacteristic, String displayImagePath, String displayDescription) {
  return {
    "name": displayName,
    "deviceName": deviceAddress,
    "connectedDevice": null,
    "connectedCharacteristic": null,
    "isPaused": false,
    "connectedService": null,
    "chars": deviceCharacteristic,
    "isConnected": false,
    "image": displayImagePath,
    "description": displayDescription,
  };
}