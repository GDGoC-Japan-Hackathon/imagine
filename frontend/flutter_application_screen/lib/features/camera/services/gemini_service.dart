import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../models/gemini_analysis_result.dart';
import 'gemini_parser.dart';

/// Gemini APIとのやり取りを担当するサービス。
/// 画像解析、テキスト読み上げ(TTS)、音声インテント分類
class GeminiService {
  GenerativeModel? _model;
  String? _serviceAccountJson;
  
  /// 使用するGeminiモデル名
  final String modelName = AppConstants.geminiModelName; 

  /// サービスを初期化
  /// [geminiKey] APIキー, [serviceAccountJson] Google Cloud サービスアカウントJSON
  void initialize(String geminiKey, String? serviceAccountJson) {
    _serviceAccountJson = serviceAccountJson;
    _model ??= GenerativeModel(
      model: modelName,
      apiKey: geminiKey,
    );
  }

  /// 画像を解析して対象物の特定と座標の推測を行う
  /// [imageFile] 解析対象の画像, [pan] カメラの水平角度, [tilt] カメラの垂直角度
  Future<GeminiAnalysisResult> analyzeAndMask(File imageFile, double pan, double tilt) async {
    // 座標のパーセント変換・正規化 
    double percentX = (pan / 60.0 + 0.5) * 100.0;
    double percentY = (tilt / 45.0 + 0.5) * 100.0;
    
    int normX = (percentX.clamp(0.0, 100.0) * 10).toInt();
    int normY = (percentY.clamp(0.0, 100.0) * 10).toInt();
    
    String locationDesc = "画像の左端から ${percentX.clamp(0.0, 100.0).toStringAsFixed(1)}%、上端から ${percentY.clamp(0.0, 100.0).toStringAsFixed(1)}% の位置（正規化座標で [y, x] = [$normY, $normX] 付近）";

    final prompt = _buildAnalysisPrompt(locationDesc);

    try {
      final bytes = await imageFile.readAsBytes();
      final content = [Content.multi([TextPart(prompt), DataPart('image/jpeg', bytes)])];

      final response = await _model!.generateContent(
        content,
        generationConfig: GenerationConfig(responseMimeType: "application/json"),
      );

      final responseText = response.text;
      if (responseText == null || responseText.isEmpty) {
        throw GeminiException("AIからの空の回答が返されました");
      }

      return GeminiParser.parseAnalysisResponse(responseText);
    } catch (e) {
      debugPrint("Gemini analysis failed: $e");
      if (e is AppException) rethrow;
      throw GeminiException("画像キャプションの生成中にエラーが発生しました: $e");
    }
  }

  String _buildAnalysisPrompt(String locationDesc) {
    return '''
あなたは優秀で知識豊富なコンシェルジュ（パーソナルアシスタント）です。
提供された画像を注意深く観察し、指定された位置にある【単一の対象物】を見つけ、ユーザーへ丁寧に説明する魅力的で専門的な解説を作成してください。

【注目するべき位置】
$locationDesc

以下の条件を厳守してください：
1. 指定された位置から最も近い「1つの物体のみ」に焦点を当て、その物体のバウンディングボックス座標も推測してください。
2. 指定された位置に著名なランドマークがある場合は、そのランドマークを優先して説明してください。
3. 優秀なアシスタントのように、丁寧なトーンで説明する。
4. 解説に座標を含めない。
5. 出力は以下のJSON形式のみとし、Markdown(` ```json `など)は一切含めない。

{
    "名前": "対象物の具体的な名称",
    "解説": "こちらに写っておりますのは…から始まるような、丁寧で詳細な解説文",
    "polygon": [ymin, xmin, ymax, xmax],
    "latitude": 付近の緯度 (数値、不明な場合は null),
    "longitude": 付近の経度 (数値、不明な場合は null)
}
※ polygon は対象物を実際に囲む 0 から 1000 までの正規化座標 [y_min, x_min, y_max, x_max] の4つの数値の配列です。
''';
  }

  /// テキストを音声に変換(TTS)します。
  Future<Uint8List?> synthesizeSpeech(String text) async {
    String? jsonStr = _serviceAccountJson;
    if (jsonStr == null || jsonStr.isEmpty) {
      debugPrint("TTS OAuth Error: Service Account JSON is null or empty");
      return null;
    }

    // .env でクォート（' や "）で囲まれている場合を考慮
    jsonStr = jsonStr.trim();
    final firstBrace = jsonStr.indexOf('{');
    final lastBrace = jsonStr.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      jsonStr = jsonStr.substring(firstBrace, lastBrace + 1);
    } else {
      debugPrint("TTS OAuth Error: Valid JSON part not found.");
      return null;
    }

    try {
      final accountCredentials = auth.ServiceAccountCredentials.fromJson(jsonStr);
      final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
      final authClient = await auth.clientViaServiceAccount(accountCredentials, scopes);

      final url = Uri.parse('https://texttospeech.googleapis.com/v1beta1/text:synthesize');
      final Map<String, dynamic> requestBody = _buildTtsRequestBody(text);

      try {
        final response = await authClient.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final audioContent = data['audioContent'];
          if (audioContent != null) {
            return base64Decode(audioContent);
          }
        } else {
          debugPrint("TTS API Error: ${response.statusCode} - ${response.body}");
        }
      } finally {
        authClient.close();
      }
    } catch (e) {
      debugPrint("TTS Request failed or Auth failed: $e");
      if (e is AppException) rethrow;
      throw GeminiException("音声合成のリクエスト中にエラーが発生しました: $e");
    }
    return null;
  }

  Map<String, dynamic> _buildTtsRequestBody(String text) {
    return {
      "audioConfig": {
        "audioEncoding": "MP3",
        "pitch": 0,
        "speakingRate": 1
      },
      "input": {
        "prompt": "バスの添乗員のような明るくハキハキした声",
        "text": text
      },
      "voice": {
        "languageCode": AppConstants.ttsLanguageCode,
        "modelName": AppConstants.ttsModelName,
        "name": AppConstants.ttsVoiceName
      }
    };
  }

  /// ユーザーの音声入力から目的地の追加の意思を分類
  Future<bool> classifyVoiceIntent(Uint8List audioBytes) async {
    final prompt = _buildVoiceIntentPrompt();
    final content = [Content.multi([TextPart(prompt), DataPart('audio/aac', audioBytes)])];

    try {
      final response = await _model!.generateContent(
        content,
        generationConfig: GenerationConfig(responseMimeType: "application/json"),
      );

      final responseText = response.text;
      if (responseText == null || responseText.isEmpty) {
        return false;
      }

      return GeminiParser.parseVoiceIntentResponse(responseText);
    } catch (e) {
      debugPrint("Voice intent classification failed: $e");
      return false;
    }
  }

  String _buildVoiceIntentPrompt() {
    return '''
あなたは優秀なアシスタントです。
提供された音声を聞き、ユーザーが目的地へ「行きたい（肯定・承諾）」と考えているか、「行きたくない（否定・拒否）」と考えているかを判定してください。

判定基準：
- 肯定的 -> "positive": true
- 否定的 -> "positive": false
- 判断不能 -> "positive": false

出力は以下のJSON形式のみとし、Markdownは含めないでください。
{
  "positive": boolean
}
''';
  }
}
