import 'dart:math';
import 'package:basera/services/help_utilities.dart';
import 'package:basera/services/ocr/document.dart';
import 'package:basera/services/ocr/tfidf.dart';
import 'package:flutter/services.dart';

class Ocr {
  static bool isRequestingOCR(String phrase, List<String> terms) {
    int i = 0;
    final sims = TfIdf(terms.map((e) => Document("${i++}", e)).toList()
      ..add(Document("$i", phrase)));
    var similarity = 0.0;
    for (int j = 0; j < terms.length; j++) {
      similarity += sims.calculateCosineSimilarity("$j", "$i");
    }
    similarity = similarity / terms.length;
    printDebug("Mean similarity: $similarity");
    return similarity > 0.35;
  }

  static Future<List<String>> loadTerms() async {
    return (await rootBundle.loadString("assets/ocr/ocr_phrases.txt"))
        .split('\n');
  }
}
