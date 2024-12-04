import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image/image.dart';

class VQA {
  static const apiKey = "AIzaSyCB9XjvywWfUPJg4KLcE4Ul7iVeLiqrxU4";
  final model = GenerativeModel(
    model: 'gemini-1.5-flash-latest',
    apiKey: apiKey,
  );

  /// Asks a question about the given image and returns the answer.
  ///
  /// The answer is limited to 30 words and is generated using the Gemini AI model.
  ///
  /// The prompt used to generate the answer is:
  /// "Be as a Visual Question Answerer, and for a blind, answer the question: '$question' with short answer IN ARABIC."
  ///
  /// The function returns null if the AI model fails to generate an answer.
  Future<String?> ask(String question, Image image) async {
    final prompt =
        "Be as a Visual Question Answerer, and for a blind, answer the question: '$question' with short answer IN ARABIC.";
    final content = [
      Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', JpegEncoder().encode(image)),
      ])
    ];
    final response = await model.generateContent(content);
    return response.text;
  }

  /// Returns a short description of the given image in Arabic suitable for a blind person.
  ///
  /// The description is limited to 30 words and is generated using the Gemini AI model.
  ///
  /// The prompt used to generate the description is:
  /// "Describe this scene for a blind with as short description as possible, limit is 30 words AND IN ARABIC."
  ///
  /// The function returns null if the AI model fails to generate a description.
  Future<String?> caption(dynamic image) async {
    const prompt =
        "Describe this scene for a blind with as short description as possible, limit is 60 words IN ARABIC DO NOT SAY ANYTHING ELSE.";
    final content = [
      Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', JpegEncoder().encode(image)),
      ])
    ];
    final response = await model.generateContent(content);
    return response.text;
  }
}
