import 'dart:io';
import 'package:basera/help_utilities.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart';
import 'package:ocr_scan_text/ocr_scan_text.dart';
import 'package:path_provider/path_provider.dart';
import 'module.dart';
import 'package:uuid/uuid.dart';
import 'package:text_analysis/text_analysis.dart';



class Ocr {


  static loadTerms() async {
    final text = await rootBundle.loadString('assets/ocr/ocr_phrases.txt');
    return text.split('\n');
  }
  static Future<OcrTextRecognizerResult?> scanTextFromImage(Image image) async {
    final imgPath = (await getApplicationDocumentsDirectory()).path;
    final uuid = Uuid().v1();
    final file = File('$imgPath/$uuid.png');
    await file.writeAsBytes(encodeJpg(image).buffer.asUint8List(),
        mode: FileMode.write);
    final text = await OcrScanService([ScanAllModule()]).startScanProcess(file);
    printDebug("OCR Result: $text");
    return text;
  }

  static bool isRequestingOCR(String phrase, List<String> terms) {
    final sims = TermSimilarity.termSimilarities(phrase, terms);
    printDebug(sims.map((s) => s.similarity).toList());
    return sims.any((sim) => sim.similarity > 0.6);
  }
}
