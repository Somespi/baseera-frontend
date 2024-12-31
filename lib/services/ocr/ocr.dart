import 'dart:convert';
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

class Ocr {
  static double isRequestingOCR(String phrase, List<String> terms) {
    int i = 0;
    final sims = TfIdf(terms.map((e) => Document("${i++}", e)).toList()
      ..add(Document("$i", phrase)));
    var similarity = 0.0;
    for (int j = 0; j < terms.length; j++) {
      similarity = max(similarity, sims.calculateCosineSimilarity("$j", "$i"));
    }
    similarity = similarity;
    printDebug("Mean similarity: $similarity");
    return similarity;
  }

  static Future<List<String>> loadTerms() async {
    return (await rootBundle.loadString("assets/ocr/ocr_phrases.txt"))
        .split('\n');
  }

  static Future<String> getWorkingDir() async {
    return (await getApplicationDocumentsDirectory()).path;
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

    final title = await VQA().askWithoutImage(
      "I'm going to give you an analyzed summary from an OCR (document), you HAVE to provide a concise title for it. The title should be a single sentence and should be short and to the point. The title should be in Arabic and should not be more than 4 words. the summary is: $text",
    );
    final documents = await getConfigFileJSON();

    if (documents is List) {
      documents.add({
        'title': title,
        'summary': text,
        'image_path': file.path,
      });
      await File(
              '${(await getApplicationDocumentsDirectory()).path}/config_documents.json')
          .writeAsString(jsonEncode(documents));
    }

    return text;
  }

  static void downloadImage(String path) {
    File(path).copy("/storage/emulated/0/Download/${path.split("/").last}");
  }

  static void deleteImage(String e) async {
    var config = await getConfigFileJSON();
    File(e).delete();
    config.removeWhere((element) => element['image_path'] == e);
    File(
            '${(await getApplicationDocumentsDirectory()).path}/config_documents.json')
        .writeAsString(jsonEncode(config));
  }

  static Future<dynamic> getConfigFileJSON() async {
    final file = File(
        '${(await getApplicationDocumentsDirectory()).path}/config_documents.json');
    if (!file.existsSync()) {
      await file.create();
      await file.writeAsString('[]');
    }

    return await jsonDecode(await file.readAsString());
  }
}
