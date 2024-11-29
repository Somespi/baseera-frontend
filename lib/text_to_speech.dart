import 'package:basera/help_utilities.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TextToSpeechService {
  final FlutterTts _flutterTts = FlutterTts();

  // Initialize the TTS engine
  Future<void> initTTS() async {
    await _flutterTts.setLanguage("ar-SA");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);
  }

  Future<void> speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.speak(text);
    } else {
      printDebug('Text is empty');
    }
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  Future<void> setLanguage(String languageCode) async {
    await _flutterTts.setLanguage(languageCode);
  }

  Future<void> setPitch(double pitch) async {
    await _flutterTts.setPitch(pitch);
  }

  Future<void> setRate(double rate) async {
    await _flutterTts.setSpeechRate(rate);
  }
}
