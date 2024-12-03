import 'package:basera/services/help_utilities.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_to_text.dart';

class SpeechToTextService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _text = "Say something...";

  Future<bool> initialize() async {
    bool available = await _speech.initialize();
    if (available) {
      _text = "Ready to listen";
    } else {
      _text = "Speech recognition not available";
    }
    return available;
  }

  // Start listening to speech
  Future<dynamic> startListening(Function(String) onResult) async {
    return await _speech.listen(
      onResult: (result) {
        _text = result.recognizedWords;
        onResult(_text);
      },
      listenOptions: stt.SpeechListenOptions(partialResults: false),
      listenFor: Duration(seconds: 4, milliseconds: 500),
      localeId: 'ar-SA',
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  void dispose() {
    _speech.stop();
  }

  String get text => _text;
  bool get isListening => _isListening;
}
