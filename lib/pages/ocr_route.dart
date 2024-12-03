import 'dart:io';
import 'package:flutter/material.dart';
import 'package:basera/services/help_utilities.dart';
import 'package:basera/services/ocr/ocr.dart';

Future<List<String>> getImagesFromOCR() async {
  final workingDir = await Ocr.getWorkingDir();
  final directory = Directory(workingDir);
  final files = directory.listSync();
  final paths = <String>[];

  for (var file in files) {
    if (file.path.endsWith(".jpg") || file.path.endsWith(".png")) {
      paths.add(file.path);
    }
  }
  printDebug(paths);
  return paths;
}

class DocumentsPage extends StatelessWidget {
  const DocumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: getImagesFromOCR(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('لا توجد مستندات'));
        } else {
          final images = snapshot.data!;
          return GridView.count(
            crossAxisCount: 2,
            children: images.map((e) {
              return Card(
                child: Column(
                  children: [
                    Expanded(
                      child: Image.file(
                        File(e),
                        fit: BoxFit.cover,
                      ),
                    ),
                    SizedBox(
                      height: 10,
                    ),
                    Row(children: [
                      IconButton(
                        icon: const Icon(Icons.delete),
                        color: Colors.red[400],
                        onPressed: () {
                          Ocr.deleteImage(e);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.download),
                        color: Colors.blue[400],
                        onPressed: () {
                          Ocr.downloadImage(e);
                        },
                      ),
                    ])
                  ],
                ),
              );
            }).toList(),
          );
        }
      },
    );
  }
}
