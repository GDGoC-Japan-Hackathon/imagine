import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiAnalysisResult {
  final String targetName;
  final String guideDesc;
  final List<dynamic> segData;

  GeminiAnalysisResult(this.targetName, this.guideDesc, this.segData);
}

class GeminiService {
  GenerativeModel? _model;
  // 最新安定版の Flash モデル 'gemini-2.5-flash' を指定
  final String modelName = 'gemini-2.5-flash'; 

  void initialize(String apiKey) {
    if (_model == null) {
      _model = GenerativeModel(
        model: modelName,
        apiKey: apiKey,
      );
    }
  }

  Future<GeminiAnalysisResult> analyzeAndMask(File imageFile, double pan, double tilt) async {
    // 座標のパーセント変換・正規化 
    // カメラの一般的な画角(FOV)を考慮してマッピング (例: 水平60度, 垂直45度)
    double percentX = (pan / 60.0 + 0.5) * 100.0;
    double percentY = (tilt / 45.0 + 0.5) * 100.0;
    
    int normX = (percentX.clamp(0.0, 100.0) * 10).toInt();
    int normY = (percentY.clamp(0.0, 100.0) * 10).toInt();
    
    String locationDesc = "画像の左端から ${percentX.clamp(0.0, 100.0).toStringAsFixed(1)}%、上端から ${percentY.clamp(0.0, 100.0).toStringAsFixed(1)}% の位置（正規化座標で [y, x] = [$normY, $normX] 付近）";

    final prompt = '''
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
    "polygon": [ymin, xmin, ymax, xmax]
}
※ polygon は対象物を実際に囲む 0 から 1000 までの正規化座標 [y_min, x_min, y_max, x_max] の4つの数値の配列です。
''';

    final bytes = await imageFile.readAsBytes();
    final content = [Content.multi([TextPart(prompt), DataPart('image/jpeg', bytes)])];

    final response = await _model!.generateContent(
      content,
      generationConfig: GenerationConfig(responseMimeType: "application/json"),
    );

    try {
      final jsonText = _cleanJsonResponse(response.text ?? "{}");
      final decoded = jsonDecode(jsonText);
      
      final targetName = decoded["名前"] ?? "指定位置の対象物";
      final guideDesc = decoded["解説"] ?? "解説を取得できませんでした。";
      // dashboard_screen が期待する形式に合わせるためラップする
      final List<dynamic> polygon = decoded["polygon"] ?? [0, 0, 1000, 1000];
      final segData = [ {"polygon": polygon} ];
      
      return GeminiAnalysisResult(targetName, guideDesc, segData);
    } catch (e) {
      return GeminiAnalysisResult(
        "認識エラー", 
        "解説の取得に失敗しました。", 
        [ {"polygon": [0, 0, 1000, 1000]} ]
      );
    }
  }

  /// Markdownのコードブロック(```json ... ```)などが含まれている場合に中身だけを取り出す
  String _cleanJsonResponse(String text) {
    String cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      final lines = cleaned.split('\n');
      if (lines.length > 2) {
        // 最初の行(```json)と最後の行(```)を除去
        cleaned = lines.sublist(1, lines.length - 1).join('\n');
      }
    }
    return cleaned;
  }
}
