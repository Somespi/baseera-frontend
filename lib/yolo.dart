// yolo_functions.dart
import 'dart:math';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as imglib;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'help_utilities.dart';

Future<List<String>> loadLabels() async {
  return (await rootBundle.loadString("assets/models/labels.txt")).split('\n');
}

Future<OrtSession> loadModel() async {
  final sessionOptions = OrtSessionOptions();
  const assetFileName = 'assets/models/yolo_model.onnx';
  final rawAssetFile = await rootBundle.load(assetFileName);
  final bytes = rawAssetFile.buffer.asUint8List();
  return OrtSession.fromBuffer(bytes, sessionOptions);
}

Future<List<Map<String, dynamic>>> runObjectDetectionInBackground(
    imglib.Image image, OrtSession interpreter, List<String> labels, context) async {
  try {
  final result = await _detectObjects(
      await compute(_processImageForDetection, [
        image,
        [1, 3, 640, 640],
        [1, 84, 8400]
      ]),
      interpreter);

  final detections = postprocessor(
      result!, [image.width, image.height], 0.35, 0.35, 640, 640, labels);

  return detections;
    } catch (e) {
      showAboutDialog(context: context, children: [Text(e.toString())]);
      return [];
    }
}

List<int> nms(List<List<int>> boxes, List<double> scores, double confidence,
    double iouThreshold) {
  List<int> indices = [];
  List<int> sortedIndices = List.generate(scores.length, (i) => i);
  sortedIndices.sort((a, b) => scores[b].compareTo(scores[a]));

  while (sortedIndices.isNotEmpty) {
    int bestIdx = sortedIndices.removeAt(0);
    indices.add(bestIdx);

    sortedIndices.removeWhere((idx) {
      double iou = computeIoU(boxes[bestIdx], boxes[idx]);
      return iou > iouThreshold;
    });
  }

  return indices;
}

double computeIoU(List<int> box1, List<int> box2) {
  int x1 = max(box1[0], box2[0]);
  int y1 = max(box1[1], box2[1]);
  int x2 = min(box1[0] + box1[2], box2[0] + box2[2]);
  int y2 = min(box1[1] + box1[3], box2[1] + box2[3]);

  int intersection = max(0, x2 - x1) * max(0, y2 - y1);
  int box1Area = box1[2] * box1[3];
  int box2Area = box2[2] * box2[3];
  int unionArea = box1Area + box2Area - intersection;

  return unionArea > 0 ? intersection / unionArea : 0.0;
}

List<List<double>> transposeMatrix(List<List<double>> matrix) {
  int rows = matrix.length;
  int cols = matrix[0].length;

  List<List<double>> transposed =
      List.generate(cols, (_) => List<double>.filled(rows, 0));

  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      transposed[j][i] = matrix[i][j];
    }
  }

  return transposed;
}

List<Map<String, dynamic>> postprocessor(
    List<OrtValue?> results,
    List<int> frameShape,
    double confidence,
    double iouThreshold,
    int inputWidth,
    int inputHeight,
    List<String>? labels) {
  int imgHeight = frameShape[0];
  int imgWidth = frameShape[1];

  double xFactor = imgWidth / inputWidth;
  double yFactor = imgHeight / inputHeight;

  List<List<int>> boxes = [];
  List<double> scores = [];
  List<int> classIds = [];
  final c = transposeMatrix(
      (results[0] as OrtValueTensor).value[0] as List<List<double>>);
  printDebug(c.shape);
  for (var output in c) {
    double maxScore = output
        .skip(4)
        .fold<double>(-double.infinity, (prev, current) => max(prev, current));
    if (maxScore >= confidence) {
      int classId = output.skip(4).toList().indexOf(maxScore);
      printDebug(output);
      double x = output[0];
      double y = output[1];
      double w = output[2];
      double h = output[3];

      int left = ((x - w / 2) * xFactor).toInt();
      int top = ((y - h / 2) * yFactor).toInt();
      int width = (w * xFactor).toInt();
      int height = (h * yFactor).toInt();

      classIds.add(classId);
      scores.add(maxScore);
      boxes.add([left, top, width, height]);
    }
  }

  List<int> indices = nms(boxes, scores, confidence, iouThreshold);
  printDebug(classIds);
  List<Map<String, dynamic>> objects = indices.map((i) {
    return {
      'classIndex': classIds[i],
      'confidence': scores[i],
      'bbox': boxes[i],
      'className': labels![classIds[i]]
    };
  }).toList();

  return objects;
}

Future<List<OrtValue?>?> _detectObjects(
    List<dynamic> inout, OrtSession interpreter) async {
  if (inout.isEmpty || inout[0] == null) {
    throw ArgumentError("Input tensor is invalid or null.");
  }

  final inputOrt =
      OrtValueTensor.createTensorWithDataList(inout[0], [1, 3, 640, 640]);
  final inputs = {'images': inputOrt};
  final runOptions = OrtRunOptions();

  try {
    final outputs = await interpreter.runAsync(runOptions, inputs);
    return outputs;
  } finally {
    inputOrt.release();
    runOptions.release();
  }
}

Future<List> _processImageForDetection(dynamic message) async {
  try {
    final imglib.Image img = message[0];

    final resizedImage =
        imglib.copyResize(img, width: message[1][3], height: message[1][2]);

    final normalizedPixels = resizedImage.data
        ?.map((pixel) {
          final r = ((pixel.r as int) & 0xFF) / 255.0;
          final g = (((pixel.b as int) >> 8) & 0xFF) / 255.0;
          final b = (((pixel.g as int) >> 16) & 0xFF) / 255.0;
          return [r, g, b];
        })
        .expand((rgb) => rgb)
        .toList();

    final channels = 3;
    final height = 640;
    final width = 640;
    final transposed = List.generate(channels, (channel) {
      return List.generate(height, (y) {
        return List.generate(width, (x) {
          return normalizedPixels![
              y * width * channels + x * channels + channel];
        });
      });
    });

    final floatData = transposed.expand((c) => c.expand((r) => r)).toList();
    final float32Data = Float32List.fromList(floatData);
    return [
      float32Data.buffer.asFloat32List(),
      [1]
    ];
  } catch (e) {
    printDebug("Error during image processing: $e");
    return [];
  }
}

List<Map<String, dynamic>> applyNMS(
    List<Map<String, dynamic>> detections, double iouThreshold) {
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

imglib.Image fromJpegToImg(JpegImage image) {
  final img = imglib.decodeJpg(image.bytes);
  if (img == null) throw Exception("Error decoding JPEG image.");
  return img;
}
