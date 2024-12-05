import 'dart:io';
import 'dart:math';
import 'package:basera/services/vqa.dart';
import 'package:basera/services/help_utilities.dart';
import 'package:basera/services/document.dart';
import 'package:basera/services/tfidf.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

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
    return similarity > 0.8;
  }

  static Future<List<String>> loadTerms() async {
    return (await rootBundle.loadString("assets/ocr/ocr_phrases.txt"))
        .split('\n');
  }

  static Future<String> getWorkingDir() async {
    return (await getApplicationDocumentsDirectory()).path;
  }

  static Future<String?> performOcr(Image image) async {
    final workingDir = (await getApplicationDocumentsDirectory());
    if (!File("${workingDir.path}/config.json").existsSync()) {
      File('${workingDir.path}/config.json').createSync();
    }
    final uuid = Uuid().v1();
    final file = File('${workingDir.path}/$uuid.png');
    await file.writeAsBytes(
        encodeJpg(copyRotate(image, angle: 90)).buffer.asUint8List(),
        mode: FileMode.write);
    final text = await FlutterTesseractOcr.extractText(file.path,
        language: 'ara+eng',
        args: {
          "psm": "4",
          "preserve_interword_spaces": "1",
        });
    printDebug("OCR Result: $text");
    return text;
  }

  static Future<String?> performOcrVQA(Image image) async {
    final imgPath = (await getApplicationDocumentsDirectory()).path;
    final uuid = Uuid().v1();
    final file = File('$imgPath/$uuid.jpg');

    var copyRotate2 = copyRotate(image, angle: 90);
    await file.writeAsBytes(encodeJpg(copyRotate2).buffer.asUint8List(),
        mode: FileMode.write);
    final text = await VQA().ask(
        "Analyze the text from the provided image and summarize the main ideas clearly and concisely as a paragraph. Return only the summary without additional comments or explanations.",
        copyRotate2);
    printDebug("OCR Result: $text");
    return text;
  }

  static void downloadImage(String path) {
    File(path).copy("/storage/emulated/0/Download/${path.split("/").last}");
  }

  static void deleteImage(String e) {
    File(e).delete();
  }
}
