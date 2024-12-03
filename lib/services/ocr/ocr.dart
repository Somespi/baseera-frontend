import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'scan_module.dart';
import 'package:basera/services/help_utilities.dart';
import 'package:basera/services/ocr/document.dart';
import 'package:basera/services/ocr/tfidf.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart';
import 'package:ocr_scan_text/ocr_scan_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class Ocr {
  static bool isRequestingOCR(String phrase, List<String> terms) {
    int i = 0;
    final sims = TfIdf(terms.map((e) => Document("${i++}", e)).toList()
      ..add(Document("$i", phrase)));
    var similarity = 0.0;
    for (int j = 0; j < terms.length; j++) {
      similarity = max(similarity, sims.calculateCosineSimilarity("$j", "$i"));
    }
    similarity = similarity;
    printDebug("Mean similarity: $similarity");
    return similarity > 0.5;
  }

  static Future<List<String>> loadTerms() async {
    return (await rootBundle.loadString("assets/ocr/ocr_phrases.txt"))
        .split('\n');
  }

  static Future<String> getWorkingDir() async {
    return (await getApplicationDocumentsDirectory()).path;
  }


  static Future<OcrTextRecognizerResult?> performOcr(Image image) async {
    final imgPath = (await getApplicationDocumentsDirectory()).path;
    final uuid = Uuid().v1();
    final file = File('$imgPath/$uuid.png');
    await file.writeAsBytes(encodeJpg(image).buffer.asUint8List(),
        mode: FileMode.write);
    final text = await OcrScanService([ScanAllModule()]).startScanProcess(file);
    printDebug("OCR Result: $text");
    return text;
  }
  


}

