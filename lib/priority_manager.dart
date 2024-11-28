import 'package:baseerah/help_utilities.dart';

import 'text_to_speech.dart' as tts;
import 'speech_to_text.dart' as stt;
import 'package:image/image.dart';
import 'vqa.dart';


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

  /// Measure the weight of the object.
  ///
  /// The weight is determined by the label of the object and the distance
  /// from the person. If the object is a person and is moving, or if the
  /// object is within 5 meters and is moving, the weight is HIGH. If the
  /// object is within 10 meters and is moving, the weight is MEDIUM. Otherwise,
  /// the weight is LOW.
  ///
  /// If the label is not found in the [labelDistances] map, the weight is
  /// also LOW.
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


  
  /// Perform an action based on the given weight and image frame.
  ///
  /// The [weight] parameter is the weight of the object, which can be
  /// HIGH, MEDIUM, or LOW. The action performed depends on the weight.
  /// If the weight is HIGH, the action is to generate a caption for the
  /// given [frame] and return it. If the weight is MEDIUM, the action is
  /// to perform a medium priority action.
  /// If the weight is LOW, the action does nothing and returns null.
  static Future<String?> performStaticAction(String weight, Image frame) async {
    printDebug("Performing action with weight $weight");
    if (weight == 'HIGH') {
      final caption = await VQA().caption(frame);
      return (caption);

    } else if (weight == 'MEDIUM') {
      // Perform medium priority action
    }
    return null;
  }
}
