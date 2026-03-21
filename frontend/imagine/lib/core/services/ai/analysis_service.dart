import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../models/gemini_analysis_result.dart';
import '../../errors/exceptions.dart';
import 'gemini_client.dart';
import 'gemini_parser.dart';

/// 画像解析（Vision）に特化した AI サービス
class AnalysisService {
  final GeminiClient _client = GeminiClient();

  /// 指定された座標付近の物体を詳しく解析します。
  Future<GeminiAnalysisResult> analyzeImage(File imageFile, double pan, double tilt) async {
    // 座標の正規化 (0-100%)
    double percentX = (pan / 60.0 + 0.5) * 100.0;
    double percentY = (tilt / 45.0 + 0.5) * 100.0;
    
    int normX = (percentX.clamp(0.0, 100.0) * 10).toInt();
    int normY = (percentY.clamp(0.0, 100.0) * 10).toInt();
    
    final locationDesc = "画像の左端から ${percentX.clamp(0.0, 100.0).toStringAsFixed(1)}%、上端から ${percentY.clamp(0.0, 100.0).toStringAsFixed(1)}% の位置（正規化座標で [y, x] = [$normY, $normX] 付近）";

    final prompt = _buildPrompt(locationDesc);

    try {
      final bytes = await imageFile.readAsBytes();
      final content = [Content.multi([TextPart(prompt), DataPart('image/jpeg', bytes)])];

      final response = await _client.model.generateContent(
        content,
        generationConfig: GenerationConfig(responseMimeType: "application/json"),
      );

      final responseText = response.text;
      if (responseText == null || responseText.isEmpty) {
        throw GeminiException("AIからの空の回答が返されました");
      }

      return GeminiParser.parseAnalysisResponse(responseText);
    } catch (e) {
      if (e is AppException) rethrow;
      throw GeminiException("画像解析中にエラーが発生しました: $e");
    }
  }

  String _buildPrompt(String locationDesc) {
    return '''
あなたは優秀なコンシェルジュです。
指定された位置にある【単一の対象物】を見つけ、ユーザーへ丁寧に説明する詳細な解説を作成してください。

【注目位置】
$locationDesc

条件：
1. 指定位置の最も近い「1つの建物か車」に焦点を当てる。
2. 著名なランドマークがあれば優先する。
3. 丁寧なトーンで解説し、座標は文中に含めない。
4. 出力は以下のJSON形式のみ（Markdown不可）。

{
    "名前": "具体的な名称",
    "解説": "丁寧で詳細な解説文",
    "polygon": [ymin, xmin, ymax, xmax],
    "latitude": 緯度 (数値 or null),
    "longitude": 経度 (数値 or null)
}
※ polygon は対象物を囲むバウンディングボックスの 0-1000 の正規化座標です。必ず [ymin, xmin, ymax, xmax] の順番で4つの数値を含む配列にしてください。
''';
  }
}
