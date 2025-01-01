import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:basera/services/help_utilities.dart';
import 'package:basera/services/document.dart';
import 'package:basera/services/tfidf.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
