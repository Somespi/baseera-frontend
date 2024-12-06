import 'package:basera/services/help_utilities.dart';
import 'package:basera/services/maps.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(MapsRoute());

class MapsRoute extends StatelessWidget {
  const MapsRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
          textDirection: TextDirection.rtl, child: MapsRoutePage()),
    );
  }
}

class MapsRoutePage extends StatefulWidget {
  const MapsRoutePage({super.key});

  @override
  State<MapsRoutePage> createState() => _MapsRoutePageState();
}

class _MapsRoutePageState extends State<MapsRoutePage> {
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      InkWell(
        borderRadius: BorderRadius.circular(15.0),
        onTap: () async {
          final TextEditingController titleController =
              TextEditingController(text: '');
          final TextEditingController acronymsController =
              TextEditingController(text: '');
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
                    const SizedBox(height: 30),
                    Text(
                      "إضافة موقع جديد",
                      style: GoogleFonts.changa(
                        textStyle: TextStyle(
                          color: Colors.black,
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    TextField(
                      controller: titleController,
                      textDirection: TextDirection.rtl,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintTextDirection: TextDirection.rtl,
                        labelText: "اسم الموقع",
                      ),
                    ),
                    const SizedBox(
                      height: 15,
                    ),
                    TextFormField(
                      minLines: 6,
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
                      textDirection: TextDirection.rtl,
                      controller: acronymsController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintTextDirection: TextDirection.rtl,
                        labelText: "مفردات الموقع",
                      ),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      child: const Text("حفظ"),
                      onPressed: () async {
                        await Maps.addLocation(titleController.text,
                            acronymsController.text.split(','));
                        // ignore: use_build_context_synchronously
                        Navigator.pop(context);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
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
                    image: AssetImage('assets/icons/map.png'),
                    width: 100.0,
                    height: 100.0,
                  ),
                  const SizedBox(
                    width: 30,
                  ),
                  Align(
                    child: Text(
                      "إضافة هذا الموقع",
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
      Text("المواقع المحفوظة",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'Changa',
            color: Color.fromARGB(255, 0, 0, 0),
            fontSize: 14,
          )),
      const SizedBox(height: 20.0),
      Expanded(
        child: FutureBuilder<dynamic>(
          future: Maps.getSavedLocationsJSON(),
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
                printDebug(entry['position']);
                return Card(
                  child: Column(
                    children: [
                      Text(
                        (entry['name']),
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
                        onPressed: () async {
                          await Maps.deleteLocation(
                              snapshot.data!.indexOf(entry));
                          setState(() {});
                        },
                        icon: const Icon(Icons.delete),
                        label: Text(
                          "حذف الموقع",
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                          ),
                        ),
                      )
                    ],
                  ),
                );
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
