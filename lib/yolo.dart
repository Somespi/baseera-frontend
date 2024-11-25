// yolo_functions.dart
import 'dart:math';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as imglib;
import 'package:yuv_converter/yuv_converter.dart';

import 'help_utilities.dart';

Future<List<String>> loadLabels() async {
  return (await rootBundle.loadString("assets/models/labels.txt")).split('\n');
}

late List<String> labels;


Future<Interpreter> loadModel() async {
  const assetFileName = 'assets/models/yolov5.tflite';
  try {
    final options = InterpreterOptions()..useNnApiForAndroid = true;
    options.threads = 4;
    return Interpreter.fromAsset(assetFileName, options: options);
  } catch (nnapiError) {
    debugPrint("NNAPI also failed: $nnapiError. Falling back to CPU.");
    return Interpreter.fromAsset(assetFileName);
  }
}

Future<String> runObjectDetectionInBackground(
    Nv21Image image, Interpreter interpreter) async {
  final inputDetails = interpreter.getInputTensors();
  final outputDetails = interpreter.getOutputTensors();
  final result = await _detectObjects(
      await compute(_processImageForDetection,
          [image, inputDetails[0].shape, outputDetails[0].shape]),
      interpreter);

  final detections = processOutputs(result[0], image.width, image.height, labels, 0.5, 0.5);

  return detections;
}

List<Map<String, dynamic>> processOutputs(
    List<List<dynamic>> output,
    int imgWidth,
    int imgHeight,
    List<String> labels,
    double boxThreshold,
    double classThreshold) {
  List<Map<String, dynamic>> detections = [];
  List<List<double>> outputs = output.cast<List<double>>();
  for (final output in outputs) {
    final boxConfidence = output[4];
    if (boxConfidence < boxThreshold) continue;

    final classProbs = output.sublist(5);
    final classIndex = classProbs.indexOf(classProbs.reduce(max));
    final classProb = classProbs[classIndex];

    if (classProb < classThreshold) continue;

    final x = (output[0] * imgWidth - output[2] * imgWidth / 2).round();
    final y = (output[1] * imgHeight - output[3] * imgHeight / 2).round();
    final w = (output[2] * imgWidth).round();
    final h = (output[3] * imgHeight).round();

    detections.add({
      'bbox': [x, y, w, h],
      'classIndex': classIndex,
      'className': labels[classIndex],
      'confidence': boxConfidence * classProb,
    });
  }
  detections.removeWhere((detection) => detection['bbox'][2] < 5 || detection['bbox'][3] < 5);

  return applyNMS(detections, 0.5);
}

Future<List<List<List<dynamic>>>> _detectObjects(
    List<dynamic> inout, Interpreter interpreter) async {
  if (inout[0] == null) throw Exception("Input tensor is null.");
  List<List<List<dynamic>>> out = List<num>.filled(1 * 6300 * 85, 0)
      .reshape([1, 6300, 85] ) as List<List<List<dynamic>>>;
  interpreter.run(inout[0], out);
  return out;
}

Future<List> _processImageForDetection(dynamic message) async {
  try {
    final rgbImage = _convertNV21(message[0]);

    final resizedImage = imglib.copyResize(rgbImage,
        width: message[1][2], height: message[1][1]);

    var dat = resizedImage.data!.buffer.asUint8List();

    final normalizedPixels =
        List.generate(dat.length ~/ 3, (i) => [dat[i * 3], dat[i * 3 + 1], dat[i * 3 + 2]]).expand((rgb) => rgb).toList();

    var inputImage = Uint8List.fromList(normalizedPixels).reshape(message[1]);

    var shape = 1;
    for (var m in message[2]) {
      shape *= m as int;
    }

    var outputs = List.filled(shape, 0).reshape(message[2]);

    return [inputImage, outputs];
  } catch (e) {
    printDebug("Error during image processing: $e");
    return [];
  }
}

List<Map<String, dynamic>> applyNMS(List<Map<String, dynamic>> detections, double iouThreshold) {
  detections.sort((a, b) => b['confidence'].compareTo(a['confidence']));
  List<Map<String, dynamic>> nmsDetections = [];

  while (detections.isNotEmpty) {
    final best = detections.removeAt(0);
    nmsDetections.add(best);

    detections.removeWhere((detection) =>
        detection['classIndex'] == best['classIndex'] &&
        computeIoU(best['bbox'], detection['bbox']) > iouThreshold);
  }

  return nmsDetections;
}

double computeIoU(List<int> boxA, List<int> boxB) {
  final xA = max(boxA[0], boxB[0]);
  final yA = max(boxA[1], boxB[1]);
  final xB = min(boxA[0] + boxA[2], boxB[0] + boxB[2]);
  final yB = min(boxA[1] + boxA[3], boxB[1] + boxB[3]);

  final intersectionArea = max(0, xB - xA + 1) * max(0, yB - yA + 1);

  final boxAArea = boxA[2] * boxA[3];
  final boxBArea = boxB[2] * boxB[3];

  return intersectionArea / (boxAArea + boxBArea - intersectionArea);
}

imglib.Image _convertNV21(Nv21Image image) {
  Uint8List rgba = YuvConverter.yuv420NV21ToRgba8888(
    image.bytes,
    image.width,
    image.height,
  );

  final img = imglib.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: rgba.buffer,
      format: imglib.Format.uint8,
      numChannels: 4);

  return img.convert(numChannels: 3);
}
