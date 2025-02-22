import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:basera/services/help_utilities.dart';

Future<List<ScanResult>> performScan() async {
  try {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    await FlutterBluePlus.stopScan();
    return await FlutterBluePlus.scanResults.first;
  } catch (e) {
    printDebug("Error during scan: $e");
    return [];
  }
}

Future<BluetoothDevice?> selectDevice(BuildContext context) async {
  List<ScanResult> scanResults = await performScan();

  BluetoothDevice? selectedDevice;
  bool isSearching = false;

  await showDialog(
    // ignore: use_build_context_synchronously
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              'اختر الجهاز للإرتباط',
              style: GoogleFonts.changa(),
            ),
            content: scanResults.isNotEmpty
                ? SizedBox(
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: scanResults.length,
                      itemBuilder: (context, index) {
                        final res = scanResults[index];
                        return ListTile(
                          title: Text(
                              "${res.device.advName} - ${res.device.platformName}"),
                          onTap: () {
                            setState(() {
                              selectedDevice = res.device;
                            });
                          },
                          selected: selectedDevice == res.device,
                        );
                      },
                    ),
                  )
                : Text('لم يتم العثور على اجهزة'),
            actions: [
              TextButton(
                onPressed: () async {
                  setState(() => isSearching = true);
                  scanResults = await performScan();
                  setState(() {
                    isSearching = false;
                  });
                },
                child: isSearching
                    ? CircularProgressIndicator()
                    : Text('إعادة البحث'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('حفظ الإعداد'),
              ),
            ],
          );
        },
      );
    },
  );

  return selectedDevice;
}

Future<Map<String, BluetoothCharacteristic?>> findCharacteristics(
    List<BluetoothService> services) async {
  BluetoothCharacteristic? wifi;
  BluetoothCharacteristic? txrx;
  BluetoothCharacteristic? ip;

  for (var service in services) {
    for (var characteristic in service.characteristics) {
      switch (characteristic.characteristicUuid.str) {
        case 'ff4b4830-efb2-4eac-8b70-32cd4d7c0996':
          wifi = characteristic;
          printDebug("Connected wifi char...");
          break;
        case '5c8be1d7-a6d8-4590-9370-b1380de38fb5':
          txrx = characteristic;
          printDebug("Connected txrx char...");
          break;
        case '792af15e-ffce-46cc-b98d-e85e6c66dbf3':
          ip = characteristic;
          printDebug("Connected ip char...");
          break;
      }
    }
  }

  return {
    'wifi': wifi,
    'txrx': txrx,
    'ip': ip,
  };
}

Future<void> connectToAssistiveDevice(
    Map<String, Object?> au, BuildContext context) async {

  try {
    var result = await selectDevice(context);
    if (result == null) {
      printDebug("No device selected.");
      return;
    }
    
    au["connectedDevice"] = result;
    await (au["connectedDevice"] as BluetoothDevice?)!.connect();

    var services = await (au["connectedDevice"] as BluetoothDevice?)!
        .discoverServices();

    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.characteristicUuid.str ==
            'beb5483e-36e1-4688-b7f5-ea07361b26a1') {
          printDebug("Found characteristic: ${characteristic.characteristicUuid}");
          au["connectedCharacteristic"] = characteristic;
          au["connectedService"] = service;
          printDebug("Connected characteristic...");
          (context as Element).markNeedsBuild();
          printDebug("Target characteristic saved!");
          break;
        }
      }
    }
  } catch (e) {
    printDebug("Error: $e");
  }
}

Future<void> disconnectFromAssistiveDevice(
    Map<String, Object?> au, BuildContext context) async {
  if ((au["connectedDevice"] as BluetoothDevice?) != null) {
    try {
      printDebug(
          "Disconnecting from ${(au["connectedDevice"] as BluetoothDevice?)!.advName}...");
      await (au["connectedDevice"] as BluetoothDevice?)!.disconnect();
      printDebug("Disconnected successfully!");

      au["connectedDevice"] = null;
      au["connectedService"] = null;
      au["connectedCharacteristic"] = null;

      printDebug("Resources cleared.");
      (context as Element).markNeedsBuild();
    } catch (e) {
      printDebug("Error during disconnection: $e");
    }
  } else {
    printDebug("No device connected.");
  }
}

  Future<Map<String, dynamic>> connectToRPi5(BuildContext context) async {
    BluetoothDevice? device;

    try {
      device = await selectDevice(context);

      await device!.connect();
      var services = await device.discoverServices();
      Map<String, dynamic> characteristics =
          await findCharacteristics(services);
      characteristics.addEntries({"device": device}.entries);
      return characteristics;
    } catch (e) {
      printDebug("Error: $e");
      return {
        'wifi': null,
        'txrx': null,
        'ip': null,
        'device': null,
      };
    }
  }