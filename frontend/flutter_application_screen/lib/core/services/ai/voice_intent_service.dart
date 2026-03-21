import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';
import 'gemini_client.dart';
import 'gemini_parser.dart';

/// ユーザーの音声から意図（インテント）を読み取る AI サービス
class VoiceIntentService {
  final GeminiClient _client = GeminiClient();

  /// 音声バイナリから、ユーザーがポジティブな反応を示しているかを判定します。
  Future<bool> classifyIntent(Uint8List audioBytes) async {
    final prompt = _buildPrompt();
    final content = [Content.multi([TextPart(prompt), DataPart('audio/aac', audioBytes)])];

    try {
      final response = await _client.model.generateContent(
        content,
        generationConfig: GenerationConfig(responseMimeType: "application/json"),
      );

      final responseText = response.text;
      if (responseText == null || responseText.isEmpty) return false;

      return GeminiParser.parseVoiceIntentResponse(responseText);
    } catch (e) {
      debugPrint("Voice intent classification failed: $e");
      return false;
    }
  }

  String _buildPrompt() {
    return '''
提供された音声を聞き、ユーザーが目的地へ「行きたい（肯定・承諾）」か、「行きたくない（否定・拒否）」かを判定してJSONで返してください。

{ "positive": boolean }
''';
  }
}
