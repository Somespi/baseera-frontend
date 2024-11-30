import 'package:basera/help_utilities.dart';
import 'package:flutter/services.dart';
import 'text_to_speech.dart' as tts;
import 'package:image/image.dart';
import 'vqa.dart';

import 'dart:collection';

class PriorityItem {
  static const Map<String, double> labelDistances = {
    'person': 10,
    'car': 25,
    'bus': 30,
    'motorcycle': 15,
    'truck': 35,
    'bicycle': 10,
    'traffic light': 20,
    'stop sign': 15,
    'fire hydrant': 5,
  };

  final bool isPersonMoving;
  late final bool isObjectMoving;
  final String label;
  final double weight;
  late final String direction;
  late DateTime itemInitializedAt;
  static tts.TextToSpeechService ttsService = tts.TextToSpeechService();
  final String? directionMoving;
  final Image frame;

  PriorityItem({
    required this.isPersonMoving,
    required this.isObjectMoving,
    required this.label,
    required this.weight,
    required this.direction,
    this.directionMoving,
    required this.frame,
  }) {
    ttsService.initTTS();
    itemInitializedAt = DateTime.now();
  }

  double getOutmostDistance(String label) {
    return labelDistances[label] ?? double.infinity;
  }

  String measureWeight() {
    if (labelDistances.containsKey(label)) {
      if (isPersonMoving && isObjectMoving && getOutmostDistance(label) <= 5) {
        return 'HIGH';
      } else if (getOutmostDistance(label) <= 10) {
        return 'HIGH';
      } else if ((isPersonMoving || isObjectMoving) &&
          getOutmostDistance(label) <= 10) {
        return 'MEDIUM';
      } else {
        return 'LOW';
      }
    }
    return 'LOW';
  }

  /// Compare the current frame with the previous frame.
  /// Returns true if there is a significant change.
  bool hasSignificantChange(PriorityItem otherItem) {
    Image otherFrame = otherItem.frame;
    int width = otherFrame.width;
    int height = otherFrame.height;
    int diffPixels = 0;
    int totalPixels = width * height;

    // Calculate the step to sample pixels for efficiency
    int step =
        totalPixels ~/ 500; // Adjust 500 to control accuracy and performance
    step = step > 0 ? step : 1; // Ensure step is at least 1

    for (int i = 0; i < totalPixels; i += step) {
      int x = i % width;
      int y = i ~/ width;
      if (frame.getPixel(x, y) != otherFrame.getPixel(x, y)) {
        diffPixels++;
      }
    }

    const int threshold =
        1000; // The threshold for significant change in pixel count
    return diffPixels * step > threshold;
  }

  static Future<void> performStaticAction(String weight, Image frame) async {

    if (weight == 'HIGH') {
      //final caption = await VQA().caption(frame);
      //printDebug("Caption: $caption");
      //if (caption == null) {
      //  return;
      //}
      //HapticFeedback.heavyImpact();
      //await ttsService.speak("مرحبا");
    } else if (weight == 'MEDIUM') {
      //HapticFeedback.mediumImpact();
      // Perform medium priority action
    } else if (weight == 'LOW') {
      //HapticFeedback.lightImpact();
      // Perform low priority action
    }
  }
}

class TaskQueue {
  final Queue<PriorityItem> _queue = Queue<PriorityItem>();

  void addTask(PriorityItem item) {
    if (_queue.isNotEmpty) {
      PriorityItem firstItem = _queue.last;
      printDebug(_queue);
      if (!item.hasSignificantChange(firstItem) ||
          DateTime.now().difference(firstItem.itemInitializedAt).inSeconds <
              10) {
        printDebug("No significant change in frame. Skipping task.");
        return;
      }
    }
    _queue.add(item);
    printDebug("Task added to the queue.");
  }

  Future<void> processTasks() async {
    while (_queue.isNotEmpty) {
      PriorityItem item = _queue.removeFirst();
      String weight = item.measureWeight();
      await PriorityItem.performStaticAction(weight, item.frame);
    }
  }
}
