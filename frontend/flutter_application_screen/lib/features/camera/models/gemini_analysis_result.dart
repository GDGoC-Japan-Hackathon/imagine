/// Gemini APIによる画像解析結果を保持するクラス。
class GeminiAnalysisResult {
  /// 対象物の名前
  final String targetName;
  /// 対象物の詳細な解説
  final String guideDesc;
  /// セグメンテーション用データ（ポリゴン情報など）
  final List<dynamic> segData;
  /// 付近の緯度
  final double? latitude;
  /// 付近の経度
  final double? longitude;

  GeminiAnalysisResult(this.targetName, this.guideDesc, this.segData, {this.latitude, this.longitude});
}
