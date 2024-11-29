import 'dart:math';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as imglib;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'help_utilities.dart';

/// Loads the COCO labels from the assets/models/labels.txt file.
///
/// The file contains a newline-separated list of object class labels,
/// which are used to describe the objects detected in an image.
///
/// The function returns a List of Strings, where each string is a label.
///
/// The list will be empty if the file does not exist or if there is an error
/// reading the file.
Future<List<String>> loadLabels() async {
  return (await rootBundle.loadString("assets/models/labels.txt")).split('\n');
}

/// Loads the YOLO model from the specified ONNX file in the assets directory.
///
/// This function reads the YOLO model file as a byte buffer and creates an
/// OrtSession using these bytes along with default session options. The session
/// is used for running object detection.
///
/// Returns a [Future] that resolves to an [OrtSession] initialized with the
/// model's data.
Future<OrtSession> loadModel() async {
  final sessionOptions = OrtSessionOptions();
  const assetFileName = 'assets/models/yolo_model.onnx';
  final rawAssetFile = await rootBundle.load(assetFileName);
  final bytes = rawAssetFile.buffer.asUint8List();
  return OrtSession.fromBuffer(bytes, sessionOptions);
}

/// Runs object detection on the provided image in the background.
///
/// This function processes the image and applies the YOLO model using the given
/// `interpreter` and `labels` to detect objects. It returns a list of detected
/// objects with their properties such as bounding boxes and class names.
///
/// The function uses a predefined input size and thresholds for confidence and
/// IoU during detection. If an error occurs during the processing, it displays
/// an error dialog and returns an empty list.
///
/// - Parameters:
///   - image: The image to be analyzed for object detection.
///   - interpreter: The OrtSession used for running the YOLO model.
///   - labels: A list of labels representing the classes the model can detect.
///   - context: The BuildContext used for displaying error dialogs.
///
/// - Returns: A `Future` that resolves to a list of maps, where each map
///   contains details about a detected object.
Future<List<Map<String, dynamic>>> runObjectDetectionInBackground(
    imglib.Image image,
    OrtSession interpreter,
    List<String> labels,
    context) async {
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

/// Runs object detection on the provided image using the YOLO model.
///
/// This function processes the image data provided in the `message` map,
/// converting the raw bytes into an [imglib.Image] and using the specified
/// width and height. The image is then processed for object detection using
/// the YOLO model and the given interpreter. The detected objects are further
/// refined using a post-processing step that applies confidence and IoU
/// thresholds to filter and extract meaningful detections.
///
/// - Parameters:
///   - message: A map containing the following keys:
///     - 'image': The raw bytes of the image to be detected.
///     - 'width': The width of the image.
///     - 'height': The height of the image.
///     - 'interpreter': The ONNX runtime session used for running the model.
///     - 'labels': A list of class labels that the model can detect.
///
/// - Returns: A `Future` that resolves to a list of maps, where each map
///   contains details about a detected object, including class name, class ID,
///   confidence score, and bounding box coordinates. If an error occurs,
///   an empty list is returned.
Future<List<Map<String, dynamic>>> runObjectDetection(
    Map<String, dynamic> message) async {
  try {
    final result = await _detectObjects(
        await compute(_processImageForDetection, [
          message['image'],
          [1, 3, 640, 640],
          [1, 84, 8400]
        ]),
        message['interpreter']);

    final detections = postprocessor(
      result!,
      [message['width'], message['height']],
      0.35,
      0.35,
      640,
      640,
      message['labels'],
    );

    return detections;
  } catch (e) {
    printDebug(e.toString());
    return [];
  }
}

/// Non-Maximum Suppression algorithm for object detection.
///
/// This function takes the list of detected bounding boxes and their
/// corresponding scores and applies non-maximum suppression to them.
///
/// The function sorts the boxes by their scores in descending order and then
/// iterates through the sorted list. For each box, it removes all the boxes
/// that have an IoU greater than the specified threshold with the current
/// box. The indices of the remaining boxes are returned as the output.
///
/// - Parameters:
///   - boxes: A list of lists of integers, where each sublist contains the
///     coordinates and dimensions of a bounding box in the format [x, y, w, h].
///   - scores: A list of doubles, where each double represents the score of a
///     bounding box.
///   - confidence: A double that represents the minimum score for a bounding box
///     to be considered a valid detection.
///   - iouThreshold: A double that represents the IoU threshold for two boxes
///     to be considered overlapping.
///
/// - Returns: A list of integers, where each integer is the index of a valid
///   bounding box in the input lists.
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

/// Computes the Intersection over Union (IoU) of two bounding boxes.
///
/// This function calculates the IoU metric, which is a measure of the overlap
/// between two bounding boxes. The IoU is defined as the area of the
/// intersection divided by the area of the union of the two boxes.
///
/// - Parameters:
///   - box1: A list of integers representing the first bounding box
///     in the format [x, y, width, height].
///   - box2: A list of integers representing the second bounding box
///     in the format [x, y, width, height].
///
/// - Returns: A double value representing the IoU of the two bounding boxes,
///   ranging from 0.0 (no overlap) to 1.0 (perfect overlap).
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

/// Runs postprocessing on the output of the YOLO model.
///
/// The postprocessor takes the output of the model and performs the following
/// operations:
///
/// 1. Transposes the output tensor to have the shape [Num of detections, 84].
/// 2. Iterates over the detections and checks if the maximum score of the
///    detection is greater than or equal to the given [confidence] threshold.
///    If so, it extracts the bounding box coordinates and the class ID of the
///    detection.
/// 3. Computes the absolute coordinates of the bounding box by multiplying the
///    relative coordinates by the factors [xFactor] and [yFactor].
/// 4. Runs non-maximum suppression on the bounding boxes to remove overlapping
///    boxes.
/// 5. Returns a list of maps, where each map contains the class name, class ID,
///    confidence score, and bounding box coordinates of a detected object.
///
/// - Parameters:
///   - results: A list of OrtValue objects representing the output of the YOLO
///     model.
///   - frameShape: A list of two integers representing the shape of the input
///     frame.
///   - confidence: A double value representing the confidence threshold for
///     the detections.
///   - iouThreshold: A double value representing the IoU threshold for the
///     non-maximum suppression.
///   - inputWidth: An integer representing the width of the input frame.
///   - inputHeight: An integer representing the height of the input frame.
///   - labels: A list of strings representing the class names of the objects
///     that can be detected.
///
/// - Returns: A list of maps, where each map contains the class name, class ID,
///   confidence score, and bounding box coordinates of a detected object.
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
  for (var output in c) {
    double maxScore = output
        .skip(4)
        .fold<double>(-double.infinity, (prev, current) => max(prev, current));
    if (maxScore >= confidence) {
      int classId = output.skip(4).toList().indexOf(maxScore);
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

/// Processes an image for object detection.
///
/// The [message] parameter is expected to contain the image as an
/// [imglib.Image] and the image size as a list with the following structure:
///
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

/// Converts a JpegImage to an imglib.Image.
///
/// Returns null if the image could not be decoded.
imglib.Image fromJpegToImg(JpegImage image) {
  final img = imglib.decodeJpg(image.bytes);
  if (img == null) throw Exception("Error decoding JPEG image.");
  return img;
}
