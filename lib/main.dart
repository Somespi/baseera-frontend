import 'package:flutter/services.dart';
import 'package:serialport_plus/serialport_plus.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:usb_serial/usb_serial.dart';
import 'help_utilities.dart';
import 'yolo.dart' as yolo;

late List<String> labels;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  labels = await yolo.loadLabels();

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

Uint8List encodeAsPng(Uint8List rawData, int width, int height) {
  final image =
      img.Image.fromBytes(bytes: rawData.buffer, height: height, width: width);
  return Uint8List.fromList(img.encodePng(image));
}

class _MyHomePageState extends State<MyHomePage> {
  bool _isLoading = false;
  late Interpreter _interpreter;
  Uint8List? _img;
  UsbPort? _port;
  List _devices = [];
  Uint8List? _buffer;
  Uint8List _currentImgBuffer = Uint8List(0);
  final _serialportFlutterPlugin = SerialportPlus();

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    setState(() {
      _isLoading = false;
    });

    _interpreter = await yolo.loadModel();
    _interpreter.allocateTensors();

    setState(() {
      _isLoading = false;
    });
  }

  @override
  void dispose() async {
    _interpreter.close();
    await _serialportFlutterPlugin.close();
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

    return CameraAwesomeBuilder.analysisOnly(
      onImageForAnalysis: (image) async {
        // final detections = await yolo.runObjectDetectionInBackground(
        //     yolo.fromJpegToImg(image as JpegImage), _interpreter, labels);
        // printDebug(detections);
      },
      imageAnalysisConfig: AnalysisConfig(
        androidOptions: const AndroidAnalysisOptions.jpeg(
          width: 1080,
        ),
        autoStart: true,
        maxFramesPerSecond: 5,
      ),
      builder: (CameraState state, Preview preview) {
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
              port.inputStream?.listen((Uint8List event) {
                _currentImgBuffer =
                    Uint8List.fromList(_currentImgBuffer + event);
                const delimiter = '\nDone...';
                final delimiterIndex =
                    String.fromCharCodes(_currentImgBuffer).indexOf(delimiter);
                if (delimiterIndex != -1) {
                  final imageData =
                      _currentImgBuffer.sublist(0, delimiterIndex);
                  _currentImgBuffer = _currentImgBuffer
                      .sublist(delimiterIndex + delimiter.length);

                  final image = img.decodeJpg(imageData);
                  if (image != null) {
                  showDialog(
                      // ignore: use_build_context_synchronously
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title:  Text("Image data length: ${imageData.length}"),
                          content: Image.memory(encodeAsPng(
                              imageData, image.width, image.height)),
                        );
                      }); 
                    setState(() {
                      _img = encodeAsPng(imageData, image.width, image.height);
                    });
                  } else {
                    showDialog(
                      // ignore: use_build_context_synchronously
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title:  Text("Image data length: ${imageData.length}"),
                          content: Text("Error decoding JPEG image."),
                        );
                      }); 
                  }
                }
              }, onError: (error) {
                printDebug("Error reading from port: $error");
              }, onDone: () {
                printDebug("Port closed");
              });

              setState(() {
                _devices = devices.map((e) => e.deviceName).toList();
              });
            },
            child: const Icon(Icons.usb),
          ),
          body: Center(
            child: _img != null ? Image.memory(_img!) : const Text('No image'),
          ),
        );
      },
    );
  }
}
