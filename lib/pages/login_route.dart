import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginPageApp extends StatelessWidget {
  const LoginPageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تسجيل الدخول',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<StatefulWidget> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String? selected = 'blind';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Color.fromRGBO(243, 243, 243, 1),
        appBar: AppBar(
          title: const Text(
            'تسجيل الدخول',
            style: TextStyle(fontFamily: 'Changa', fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
            child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const SizedBox(height: 10),
                    const Text(
                      "حدد فئتك",
                      style: TextStyle(
                          fontFamily: 'Changa',
                          fontWeight: FontWeight.w500,
                          fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                        child: GridView.count(
                            crossAxisCount: 2,
                            semanticChildCount: 2,
                            crossAxisSpacing: 10,
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(15.0),
                            onTap: () async {
                              setState(() {
                                selected = 'blind';
                              });
                            },
                            child: Card(
                              color: Color.fromRGBO(236, 246, 255, 1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15.0),
                                side: BorderSide(
                                  color: selected == 'blind'
                                      ? Color.fromRGBO(0, 0, 0, 1)
                                      : Color.fromRGBO(0, 76, 168, 1),
                                  width: selected == 'blind' ? 2.0 : 0.7,
                                ),
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Flex(
                                        direction: Axis.vertical,
                                        children: [
                                          Image(
                                            image: AssetImage(
                                                'assets/icons/blind.png'),
                                            width: 100.0,
                                            height: 100.0,
                                          ),
                                          //const Spacer(),
                                          Center(
                                            child: Text(
                                              "كفيف",
                                              style: GoogleFonts.rubik(
                                                textStyle: const TextStyle(
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
                          InkWell(
                            borderRadius: BorderRadius.circular(15.0),
                            onTap: () async {
                              setState(() {
                                selected = 'assist';
                              });
                            },
                            child: Card(
                              color: Color.fromRGBO(236, 246, 255, 1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15.0),
                                side: BorderSide(
                                  color: selected == 'assist'
                                      ? Color.fromRGBO(0, 0, 0, 1)
                                      : Color.fromRGBO(0, 76, 168, 1),
                                  width: selected == 'assist' ? 2.0 : 0.7,
                                ),
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Flex(
                                        direction: Axis.vertical,
                                        children: [
                                          Image(
                                            image: AssetImage(
                                                'assets/icons/assist.png'),
                                            width: 100.0,
                                            height: 100.0,
                                          ),
                                          //const Spacer(),
                                          Center(
                                            child: Text(
                                              "مُساعد",
                                              style: GoogleFonts.rubik(
                                                textStyle: const TextStyle(
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
                        ])),
                    const SizedBox(
                      height: 30,
                    ),
                    TextField(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15.0),
                        ),
                        labelText: 'اسم المستخدم',
                      ),
                    ),
                    const SizedBox(
                      height: 15,
                    ),
                    TextField(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15.0),
                        ),
                        labelText: 'كلمة المرور',
                      ),
                    ),
                    const SizedBox(
                      height: 15,
                    ),
                    TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Color.fromRGBO(0, 76, 168, 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15.0),
                          ),
                        ),
                        child: const Text(
                          'تسجيل الدخول',
                          style: TextStyle(
                              fontFamily: 'Changa',
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        onPressed: () {
                          Navigator.pushNamed(context, '/home');
                        }),
                  ],
                ))));
  }
}
