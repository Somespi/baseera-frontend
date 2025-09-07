import 'dart:io';

import 'package:basera/services/ocr/ocr.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DocumentsPageRoute extends StatelessWidget {
  const DocumentsPageRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
          textDirection: TextDirection.rtl, child: DocumentsPage()),
    );
  }
}

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  void _showDocumentBottomSheet(BuildContext context, Map entry, VoidCallback onDelete) {
  showModalBottomSheet(
    isScrollControlled: true,
    context: context,
    builder: (context) => SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16.0,
          right: 16.0,
          top: 8.0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 30,
              width: double.infinity,
            ),
            Text(
              entry['title'],
              style: GoogleFonts.changa(
                textStyle: TextStyle(
                  color: Colors.blue[500],
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Row(children: [
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[500],
                ),
                label: Text(
                  "اغلاق",
                  style: GoogleFonts.rubik(
                    textStyle: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w300),
                  ),
                ),
                icon: Icon(
                  Icons.close_fullscreen_rounded,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => Ocr.downloadImage(entry['image_path']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[500],
                ),
                label: Text(
                  "تحميل",
                  style: GoogleFonts.changa(
                    textStyle: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w300),
                  ),
                ),
                icon: Icon(
                  Icons.download_rounded,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  onDelete();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[500],
                ),
                label: Text(
                  "حذف",
                  style: GoogleFonts.rubik(
                    textStyle: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w300),
                  ),
                ),
                icon: Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.white,
                ),
              ),
            ]),
            const SizedBox(height: 5),
            Image.file(
              File(entry['image_path']),
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 15),
            Center(
              widthFactor: double.infinity,
              child: Text(
                entry['summary'],
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: GoogleFonts.rubik(
                  textStyle: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: FutureBuilder<dynamic>(
          future: Ocr.getConfigFileJSON(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text("Error: ${snapshot.error}"));
            } else if (snapshot.hasData) {
              if (snapshot.data!.isEmpty) {
                return Center(child: Text("لا توجد بيانات"));
              }

              // Convert the dynamic data into a List<Widget>
              List<Widget> locationCards = snapshot.data!.map<Widget>((entry) {
                return InkWell(
                onTap: () => _showDocumentBottomSheet(context, entry, () { 
                    setState(() {
        Ocr.deleteImage(entry['image_path']);
      });
                  }),
                  child: Card(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 5,
                      ),
                      Text(
                        (entry['title']),
                        style: GoogleFonts.changa(
                          textStyle: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      Image.file(
                        File(entry['image_path']),
                        fit: BoxFit.cover,
                        height: 70,
                        width: double.infinity,
                      ),
                      SizedBox(
                        height: 5,
                      ),
                      ElevatedButton(
                          onPressed: () => _showDocumentBottomSheet(context, entry, () { 
                            setState(() {
        Ocr.deleteImage(entry['image_path']);
      });
                          }),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[500],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                          ),
                          child: Text("قراءة المستند",
                              style: GoogleFonts.changa(
                                textStyle: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w200),
                              )))
                    ],
                  ),
                ));
              }).toList();

              return GridView.count(
                crossAxisCount: 2,

                children: locationCards, // Use the List<Widget> here
              );
            } else {
              return Center(child: Text("No data available"));
            }
          },
        ),
      )
    ]);
  }
}
