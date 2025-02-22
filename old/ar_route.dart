import 'dart:io';

import 'package:ar_flutter_plugin_flutterflow/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_flutterflow/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_session_manager.dart';
import 'package:basera/services/help_utilities.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(ARroute());

class ARroute extends StatelessWidget {
  const ARroute({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ARroutePage(),
    );
  }
}

class ARroutePage extends StatefulWidget {
  const ARroutePage({super.key});

  @override
  State<ARroutePage> createState() => _ARroutePageState();
}

class _ARroutePageState extends State<ARroutePage> {
  bool isScanning = false;
  @override
  Widget build(BuildContext context) {
    return !isScanning
        ? Column(children: [
            InkWell(
              borderRadius: BorderRadius.circular(15.0),
              onTap: () async {
                setState(() {
                  isScanning = true;
                });
              },
              child: Card(
                color: const Color.fromRGBO(236, 246, 255, 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15.0),
                  side: const BorderSide(
                    color: Color.fromRGBO(0, 76, 168, 1),
                    width: 0.7,
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Flex(direction: Axis.horizontal, children: [
                        const Image(
                          image: AssetImage('assets/icons/scan.png'),
                          width: 100.0,
                          height: 100.0,
                        ),
                        const SizedBox(
                          width: 30,
                        ),
                        Align(
                          child: Text(
                            "بدء مسح المحيط",
                            style: GoogleFonts.rubik(
                              textStyle: TextStyle(
                                color: Colors.black,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        ),
                      ])),
                ),
              ),
            ),
            const SizedBox(height: 30.0),
            Text("الأماكن الممسوحة",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Changa',
                  color: Color.fromARGB(255, 0, 0, 0),
                  fontSize: 14,
                )),
            const SizedBox(height: 20.0),
            Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
              future: getConfigFile(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                } else if (snapshot.hasData) {
                  if (snapshot.data!.isEmpty) {
                    return Center(child: Text("لا توجد بيانات"));
                  }
                  return GridView.count(
                      crossAxisCount: 2,
                      children: snapshot.data!.entries.map((entry) {
                        return Card(
                          child: Column(
                            children: [
                              Text(
                                (entry.key),
                                style: GoogleFonts.changa(
                                  textStyle: TextStyle(
                                      color: Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                              SizedBox(
                                height: 25,
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  final TextEditingController titleController = TextEditingController(text: entry.value['acronyms'].join('\n'));
                                  showModalBottomSheet(
                                    isScrollControlled: true,
                                    context: context,
                                    builder: (context) => SingleChildScrollView(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          bottom: MediaQuery.of(context)
                                              .viewInsets
                                              .bottom,
                                          left: 16.0,
                                          right: 16.0,
                                          top: 8.0,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const SizedBox(height: 30),
                                            Text(
                                              "تعديل مفردات المحيط",
                                              style: GoogleFonts.changa(
                                                textStyle: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 30),
                                            TextFormField(
                                              minLines: 6,
                                              keyboardType:
                                                  TextInputType.multiline,
                                              maxLines: null,
                                              textDirection: TextDirection.rtl,
                                              controller: titleController,
                                              decoration: const InputDecoration(
                                                border: OutlineInputBorder(),
                                                labelText: "مفردات المحيط",
                                              ),
                                            ),
                                            const SizedBox(height: 30),
                                            ElevatedButton(
                                              child: const Text("حفظ"),
                                              onPressed: () {
                                                saveAcronymsToConfigFile(entry.key, titleController.text.split('\n'));
                                                setState(() {
                                                  entry.value['acronyms'] = titleController.text.split('\n');
                                                });
                                                Navigator.pop(context);

                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.edit),
                                label: Text(
                                  "رؤية المفردات",
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 5,
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  deleteIdFromConfigFile(entry.key);
                                },
                                icon: const Icon(Icons.delete),
                                label: Text(
                                  "حذف المحيط",
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                  ),
                                ),
                              )
                            ],
                          ),
                        );
                      }).toList());
                } else {
                  return Center(child: Text("No data available"));
                }
              },
            )),
          ])
        : Center(
            child: ARView(
              onARViewCreated: onARViewCreated,
              planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
            ),
          );
  }
}

void onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager) {
  arSessionManager.onInitialize(
    showFeaturePoints: false,
    showPlanes: true,
    customPlaneTexturePath: "assets/triangle.png",
    showWorldOrigin: false,
  );
  arObjectManager.onInitialize();
  // ARLocationManager arLocationManager = ARLocationManager();
  printDebug(arLocationManager.getLastKnownPosition());
}

Future<Map<String, dynamic>> getConfigFile() async {
  final workingDir = (await getApplicationDocumentsDirectory()).path;
  final file = File('$workingDir/ar_config.json');
  if (!file.existsSync()) {
    await file.create();
    await file.writeAsString(json.encode({}), mode: FileMode.write);
  }

  return await json.decode(await file.readAsString());
}

void appendToConfigFile(String id) async {
  final workingDir = (await getApplicationDocumentsDirectory()).path;
  final file = File('$workingDir/ar_config.json');
  if (!file.existsSync()) {
    await file.create();
    await file.writeAsString(json.encode({}), mode: FileMode.write);
  }
  Map<String, dynamic> data = json.decode(await file.readAsString());
  data[id] = {
    "acronyms": [id]
  };
  await file.writeAsString(json.encode(data), mode: FileMode.write);
}

void deleteIdFromConfigFile(String id) async {
  final workingDir = (await getApplicationDocumentsDirectory()).path;
  final file = File('$workingDir/ar_config.json');
  if (!file.existsSync()) {
    await file.create();
    await file.writeAsString(json.encode({}), mode: FileMode.write);
  }
  Map<String, dynamic> data = json.decode(await file.readAsString());
  data.remove(id);
  await file.writeAsString(json.encode(data), mode: FileMode.write);
}

void saveAcronymsToConfigFile(String id, List<String> acronyms) async {
  final workingDir = (await getApplicationDocumentsDirectory()).path;
  final file = File('$workingDir/ar_config.json');
  if (!file.existsSync()) {
    await file.create();
    await file.writeAsString(json.encode({}), mode: FileMode.write);
  }
  Map<String, dynamic> data = json.decode(await file.readAsString());
  data[id]['acronyms'] = acronyms;
  await file.writeAsString(json.encode(data), mode: FileMode.write);
}