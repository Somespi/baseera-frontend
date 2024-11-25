import 'dart:convert';
import 'dart:typed_data';

import 'package:baseerah/help_utilities.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class AssistiveUnit {
  final String name;
  final String description;
  final String bleAddress;
  BluetoothConnection? _bluetoothDevice;

  AssistiveUnit({
    required this.name,
    required this.description,
    required this.bleAddress,
  });

  /// Establishes a connection to the device.
  ///
  /// Returns a [Future] that resolves when the connection is established.
  /// If the device is already connected, does nothing.
  ///
  /// The connection is established by sending a connection request to the
  /// device with the given [bleAddress].
  ///
  /// If the connection is established successfully, the method listens
  /// for incoming data and forwards it to the device. If the device sends
  /// a message containing the character "", the connection is closed.
  Future<void> connect() async {
    try {
      _bluetoothDevice =
          await BluetoothConnection.toAddress(bleAddress);
      printDebug('Connected to the device');

      _bluetoothDevice?.input?.listen((Uint8List data) {
        printDebug('Data incoming: ${ascii.decode(data)}');
        _bluetoothDevice?.output.add(data);

        if (ascii.decode(data).contains('!')) {
          _bluetoothDevice?.finish();
          printDebug('Disconnecting by local host');
        }
      }).onDone(() {
        printDebug('Disconnected by remote request');
      });
    } catch (exception) {
      printDebug('Cannot connect, exception occured');
    }
  }

  /// Disconnect from the connected assistive unit.
  ///
  /// If the device is null, i.e., not connected, does nothing.
  /// Otherwise, sends a disconnect request to the device.
  Future<void> disconnect() async {
    if (_bluetoothDevice != null) {
      await _bluetoothDevice!.finish();
    }
  }

  /// Send data to the connected assistive unit.
  ///
  /// The [data] should be a string, which is encoded into a base64 string
  /// and sent to the device.
  ///
  /// If the device is not connected, this function will simply return without
  /// doing anything.
  ///
  /// The data is sent by writing it to the output of the Bluetooth device.
  ///
  Future<void> sendData(String data) async {
    if (_bluetoothDevice != null) {
      var encoded = base64Decode(data);
      var bytes = Uint8List.fromList(encoded);
      _bluetoothDevice?.output.add(bytes);
      printDebug('Data sent to $name: $data');
    }
  }

  @override
  /// Returns a string representation of the assistive unit.
  ///
  /// The string includes the assistive unit's name, description and BLE address.
  ///
  /// The format of the string is:
  /// AssistiveUnit(name: $name, description: $description, bleAddress: $bleAddress)
  String toString() {
    return 'AssistiveUnit(name: $name, description: $description, bleAddress: $bleAddress)';
  }
}
