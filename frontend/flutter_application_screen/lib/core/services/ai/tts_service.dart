import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import '../../constants/app_constants.dart';
import '../../errors/exceptions.dart';

/// Google Cloud Text-to-Speech API を利用した音声合成サービス
class TtsService {
  String? _serviceAccountJson;

  void initialize(String? serviceAccountJson) {
    _serviceAccountJson = serviceAccountJson;
  }

  /// テキストを MP3 音声データに変換します。
  Future<Uint8List?> synthesize(String text) async {
    if (_serviceAccountJson == null || _serviceAccountJson!.isEmpty) {
      debugPrint("TTS Error: Service Account JSON is empty");
      return null;
    }

    final jsonStr = _extractJson(_serviceAccountJson!);
    if (jsonStr == null) return null;

    try {
      final accountCredentials = auth.ServiceAccountCredentials.fromJson(jsonStr);
      final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
      final authClient = await auth.clientViaServiceAccount(accountCredentials, scopes);

      final url = Uri.parse('https://texttospeech.googleapis.com/v1beta1/text:synthesize');

      try {
        final response = await authClient.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(_buildRequestBody(text)),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final audioContent = data['audioContent'];
          if (audioContent != null) {
            return base64Decode(audioContent);
          }
        }
      } finally {
        authClient.close();
      }
    } catch (e) {
      debugPrint("TTS Request failed: $e");
      throw GeminiException("音声合成中にエラーが発生しました: $e");
    }
    return null;
  }

  String? _extractJson(String input) {
    final firstBrace = input.indexOf('{');
    final lastBrace = input.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      return input.substring(firstBrace, lastBrace + 1);
    }
    return null;
  }

  Map<String, dynamic> _buildRequestBody(String text) {
    return {
      "audioConfig": {
        "audioEncoding": "MP3",
        "pitch": 0,
        "speakingRate": 1
      },
      "input": {
        "prompt": "バスの添乗員のような明るい声",
        "text": text
      },
      "voice": {
        "languageCode": AppConstants.ttsLanguageCode,
        "modelName": AppConstants.ttsModelName,
        "name": AppConstants.ttsVoiceName
      }
    };
  }
}
