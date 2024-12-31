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
