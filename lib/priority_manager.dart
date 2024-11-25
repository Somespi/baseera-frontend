import 'package:baseerah/help_utilities.dart';

import 'text_to_speech.dart' as tts;
import 'speech_to_text.dart' as stt;
import 'package:image/image.dart';
import 'vqa.dart';


class PriorityItem {
  static const Map<String, double> labelDistances = {
    'person': 5,
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
  final String? directionMoving;

  PriorityItem({
    required this.isPersonMoving,
    required this.isObjectMoving,
    required this.label,
    required this.weight,
    required this.direction,
    this.directionMoving,
  });

  double getOutmostDistance(String label) {
    return labelDistances[label] ?? double.infinity;
  }

  String measureWeight() {
    if (labelDistances.containsKey(label)) {
      if (isPersonMoving && isObjectMoving && getOutmostDistance(label) <= 5) {
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


  
  static Future<void> performStaticAction(String weight, Image frame) async {
    printDebug("Performing action with weight $weight");
    if (weight == 'HIGH') {
      final caption = await VQA().caption(frame);
      printDebug(caption);

    } else if (weight == 'MEDIUM') {
      // Perform medium priority action
    }
  }
}
