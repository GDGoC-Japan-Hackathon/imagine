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
  late final GenerativeModel _model;
  // 最新安定版の Flash モデル 'gemini-2.5-flash' を指定
  final String modelName = 'gemini-2.5-flash'; 

  void initialize(String apiKey) {
    _model = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
    );
  }

  Future<Map<String, String>> analyzeImageAtLocation(File imageFile, double pan, double tilt) async {
    // 座標のパーセント変換・正規化 
    double percentX = (pan + 90) / 180.0 * 100;
    double percentY = (50 - tilt) / 100.0 * 100;
    int normX = (percentX * 10).toInt();
    int normY = (percentY * 10).toInt();
    
    String locationDesc = "画像の左端から ${percentX.toStringAsFixed(1)}%、上端から ${percentY.toStringAsFixed(1)}% の位置（正規化座標で [y, x] = [$normY, $normX] 付近）";

    final prompt = '''
あなたは優秀で知識豊富なコンシェルジュ（パーソナルアシスタント）です。
提供された画像を注意深く観察し、指定された位置にある【単一の対象物】を見つけ、ユーザーへ丁寧に説明する魅力的で専門的な解説を作成してください。

【注目するべき位置】
$locationDesc

以下の条件を厳守してください：
1. 指定された位置から最も近い「1つの物体のみ」に焦点を当てる。
2. 優秀なアシスタントのように、丁寧なトーンで説明する。
3. 出力は以下のJSON形式のみとし、Markdown(` ```json `など)は一切含めない。

{
    "名前": "対象物の具体的な名称",
    "解説": "こちらに写っておりますのは…から始まるような、丁寧で詳細な解説文"
}
''';

    final bytes = await imageFile.readAsBytes();
    final content = [Content.multi([TextPart(prompt), DataPart('image/jpeg', bytes)])];

    final response = await _model.generateContent(
      content,
      generationConfig: GenerationConfig(responseMimeType: "application/json"),
    );

    try {
      final jsonText = _cleanJsonResponse(response.text ?? "{}");
      final decoded = jsonDecode(jsonText);
      return {
        "名前": decoded["名前"] ?? "指定位置の対象物",
        "解説": decoded["解説"] ?? "解説を取得できませんでした。",
        "normX": normX.toString(),
        "normY": normY.toString(),
        "locationDesc": locationDesc,
      };
    } catch (e) {
      return {"名前": "Null", "解説": "解説取得に失敗しました。"};
    }
  }

  Future<List<dynamic>> createMaskForTarget(File imageFile, String targetName, String locationDesc, int normX, int normY) async {
    final prompt = '''
Please perform instance segmentation ONLY on the single object identified as '$targetName' located near $locationDesc in this image.
Provide the following in structured JSON format:
1. 'label': '$targetName'
2. 'polygon': Precise coordinates [y1, x1, y2, x2, ... yN, xN] between 0 and 1000.
Return ONLY valid JSON array. No markdown.
''';

    final bytes = await imageFile.readAsBytes();
    final content = [Content.multi([TextPart(prompt), DataPart('image/jpeg', bytes)])];

    final response = await _model.generateContent(
      content,
      generationConfig: GenerationConfig(responseMimeType: "application/json"),
    );

    try {
      final jsonText = _cleanJsonResponse(response.text ?? "[]");
      final decoded = jsonDecode(jsonText);
      if (decoded is List) return decoded;
    } catch (_) {}
    return [];
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

  Future<GeminiAnalysisResult> analyzeAndMask(File imageFile, double pan, double tilt) async {
    final analysisInfo = await analyzeImageAtLocation(imageFile, pan, tilt);
    
    final targetName = analysisInfo["名前"]!;
    final guideDesc = analysisInfo["解説"]!;
    final normX = int.tryParse(analysisInfo["normX"] ?? "0") ?? 0;
    final normY = int.tryParse(analysisInfo["normY"] ?? "0") ?? 0;
    final locationDesc = analysisInfo["locationDesc"]!;

    final segData = await createMaskForTarget(imageFile, targetName, locationDesc, normX, normY);

    return GeminiAnalysisResult(targetName, guideDesc, segData);
  }
}
