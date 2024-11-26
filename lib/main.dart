import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: unused_import
import 'help_utilities.dart';
import 'background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final token = ServicesBinding.rootIsolateToken;
  printDebug(token);
  BackgroundIsolateBinaryMessenger.ensureInitialized(token!);
  await initializeService(token);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'بصيرة',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'بصيرة'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    initial();
  }

  void initial() async {
    //await start();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Stack(
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "Analyzing...",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
