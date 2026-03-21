/// Gemini による解析結果のチE�EタモチE��
class GeminiAnalysisResult {
  final String targetName;
  final String guideDesc;
  final List<dynamic> segData;
  final double? latitude;
  final double? longitude;

  GeminiAnalysisResult(
    this.targetName, 
    this.guideDesc, 
    this.segData, 
    {this.latitude, this.longitude}
  );
}
