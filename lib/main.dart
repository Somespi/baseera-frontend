import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:serialport_plus/serialport_plus.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:usb_serial/usb_serial.dart';
import 'help_utilities.dart';
import 'yolo.dart' as yolo;
import 'priority_manager.dart' as priority_manager;

late List<String> labels;

void main() async {
  OrtEnv.instance.init();
  WidgetsFlutterBinding.ensureInitialized();
  labels = await yolo.loadLabels();

  runApp(const MyApp());
}

Future<String?> _performActionInBackground(Map<String, dynamic> params) async {
  final weight = params['weight'];
  final nv21Image = params['nv21Image'];

  return await priority_manager.PriorityItem.performStaticAction(
      weight, nv21Image);
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

Uint8List encodeAsPng(Uint8List rawData, int width, int height) {
  final image =
      img.Image.fromBytes(bytes: rawData.buffer, height: height, width: width);
  return Uint8List.fromList(img.encodePng(image));
}

class _MyHomePageState extends State<MyHomePage> {
  bool _isLoading = false;
  late OrtSession _interpreter;
  // ignore: unused_field
  UsbPort? _port;
  String? _out;
  Uint8List _currentImgBuffer = Uint8List(0);
  final _serialportFlutterPlugin = SerialportPlus();
  bool isPersonMoving = false;
  Uint8List? _img;
  StreamSubscription? _gyroscopeSubscription;

  @override
  void initState() {
    super.initState();
    _initializeModel();
    _initializeGyroscope();
  }

  Future<void> _initializeModel() async {
    setState(() {
      _isLoading = false;
    });

    _interpreter = await yolo.loadModel();

    setState(() {
      _isLoading = false;
    });
  }

  void _initializeGyroscope() {
    const movementThreshold = 0.2;
    _gyroscopeSubscription =
        gyroscopeEventStream().listen((GyroscopeEvent event) {
      final magnitude =
          (event.x * event.x) + (event.y * event.y) + (event.z * event.z);
      setState(() {
        isPersonMoving = magnitude > movementThreshold;
      });
    });
  }

  @override
  void dispose() async {
    _interpreter.release();
    await _serialportFlutterPlugin.close();
    await _port?.close();
    _gyroscopeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          List<UsbDevice> devices = await UsbSerial.listDevices();
          printDebug("Found ${devices.length} devices");
          if (devices.isEmpty) {
            return;
          }

          UsbPort? port = await devices[0].create();
          if (port == null) {
            printDebug("Failed to create port");
            return;
          }
          _port = port;

          bool openResult = await port.open();
          if (!openResult) {
            printDebug("Failed to open port");
            return;
          }

          await port.setDTR(true);
          await port.setRTS(true);

          port.setPortParameters(
            115200,
            UsbPort.DATABITS_8,
            UsbPort.STOPBITS_1,
            UsbPort.PARITY_NONE,
          );

          port.inputStream?.listen((Uint8List event) async {
            try {
              _currentImgBuffer = Uint8List.fromList(_currentImgBuffer + event);
              const delimiter = '\nDone...';
              final delimiterIndex =
                  String.fromCharCodes(_currentImgBuffer).indexOf(delimiter);

              if (delimiterIndex != -1) {
                final imageData = _currentImgBuffer.sublist(0, delimiterIndex);

                _currentImgBuffer = _currentImgBuffer
                    .sublist(delimiterIndex + delimiter.length);

                var image = img.decodeJpg(imageData);
                if (image != null) {
                  image = img.Image.fromBytes(
                      bytes: image.buffer,
                      height: image.height,
                      width: image.width);
                  
                  final detectedObjects =
                      await yolo.runObjectDetectionInBackground(
                          image, _interpreter, labels, context);
                  
                  setState(() {
                    _out =
                        '\n $detectedObjects';
                    _img = encodeAsPng(
                        image!.buffer.asUint8List(), image.width, image.height);
                  });
                } else {
                  printDebug('Failed to decode JPEG image');
                  printDebug('Image data length: ${imageData.length}');
                }
              }
            } catch (e) {
              printDebug('Error: $e');
            }
          }, onError: (error) {
            printDebug('Stream read error: $error');
          }, onDone: () {
            printDebug('Image stream closed');
          });
        },
        child: const Icon(Icons.usb),
      ),
      body: Center(
          child: Column(children: [
        _out != null ? Text(_out!) : const Text("No data"),
        _img != null ? Image.memory(_img!) : const Text("No image"),
      ])),
    );
  }
}
