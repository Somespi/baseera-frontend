import 'dart:typed_data';

import 'package:basera/help_utilities.dart';
import 'package:record/record.dart';

class AudioRecord {
  AudioRecorder? _recorder;
  Stream<Uint8List>? stream;

  /// Initializes the audio recorder by creating an instance of [AudioRecorder].
  ///
  /// This method checks if the application has the necessary permissions
  /// to record audio. If the permissions are not granted, it throws an
  /// exception indicating that permission to record audio is not granted.
  ///
  /// Throws:
  ///   - [Exception] if the permission to record audio is not granted.
  Future<void> init() async {
    _recorder = AudioRecorder();
    bool permissionGranted = await _recorder!.hasPermission();
    if (!permissionGranted) {
      throw Exception("Permission to record audio is not granted.");
    }
  }

  /// Start recording audio from the user's default input device.
  ///
  /// This method will check if the recorder has been initialized and if
  /// the app has permission to record audio. If the permission has not
  /// been granted, then this method will return without doing anything.
  ///
  /// The audio will be recorded with 16-bit PCM encoding.
  Future<void> startRecording() async {
    if (_recorder == null) {
      printDebug('Recorder not initialized');
      return;
    }
    if (await _recorder!.hasPermission()) {
      stream = await _recorder
          ?.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits));
      printDebug('Recording started');
    } else {
      printDebug('Permission not granted');
    }
  }

  /// Stops the audio recording.
  ///
  /// This method will check if the recorder has been initialized. If it has,
  /// the recording will be stopped. If the recorder is not initialized,
  /// a debug message is printed and the method returns null.
  ///
  /// Returns a [Stream] of [Uint8List] containing the recorded audio data
  /// if the recording was successfully stopped, or null if the recorder
  /// was not initialized.
  Future<Stream<Uint8List>?> stopRecording() async {
    if (_recorder == null) {
      printDebug('Recorder not initialized');
      return null;
    }

    // Stop the recording and return the stream.
    final _ = await _recorder?.stop();
    printDebug('Recording stopped');
    _recorder?.dispose();
    return stream;
  }
}
