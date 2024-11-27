import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ImagePreprocessor {

  static  int targetWidth = 640;
  static  int targetHeight = 640;
  static  double normalizationFactor = 255.0;

  static Uint8List process(img.Image frame) {

    img.Image resizedImage = img.copyResize(
      frame, 
      width: targetWidth, 
      height: targetHeight
    ).convert(numChannels: 3);

    Float32List float32Data = Float32List(1 * 3 * targetWidth * targetHeight);
    
    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        final pixel = resizedImage.getPixel(x, y);
        
        float32Data[y * targetWidth + x] = pixel.r / normalizationFactor;
        float32Data[targetWidth * targetHeight + y * targetWidth + x] = pixel.g / normalizationFactor;
        float32Data[2 * targetWidth * targetHeight + y * targetWidth + x] = pixel.b / normalizationFactor;
      }
    }
    
    return float32Data.buffer.asUint8List();
  }
}