import 'package:speech_to_text/speech_to_text.dart' as stt;

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
  Future<void> startListening(Function(String) onResult) async {
    await _speech.listen(
      onResult: (result) {
        _text = result.recognizedWords;
        onResult(_text); 
      },
    );
    _isListening = true;
  }

  Future<void> stopListening() async {
    await _speech.stop();
    _isListening = false;
  }

  void dispose() {
    _speech.stop();
  }

  String get text => _text;
  bool get isListening => _isListening;
}
