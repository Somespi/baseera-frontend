import 'dart:math';

import 'package:basera/ocr/document.dart';
import 'package:basera/ocr/tfidf.dart';
import 'package:flutter/services.dart';

class Ocr {
  static bool isRequestingOCR(String phrase, List<String> terms) {
    int i = 0;
    final sims = TfIdf(terms.map((e) => Document("${i++}", e)).toList()
      ..add(Document("$i", phrase)));
    var similarity = 0.9;
    for (int j = 0; j < terms.length; j++) {
      similarity = max(similarity, sims.calculateCosineSimilarity("$j", "$i"));
    }
    return similarity > 0.5;
  }

  static Future<List<String>> loadTerms() async {
  return (await rootBundle.loadString("assets/ocr/ocr_phrases.txt")).split('\n');
}
}
