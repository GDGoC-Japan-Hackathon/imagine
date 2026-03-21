import 'dart:typed_data';

/// 蛻・梵邨先棡縺ｮ陦ｨ遉ｺ縺ｫ菴ｿ逕ｨ縺吶ｋ繝・・繧ｿ繝｢繝・Ν
class AnalysisData {
  final String tag;
  final String title;
  final String subtitle;
  final String description;
  final String imagePath;
  final List<double>? polygon;
  final Uint8List? audioBytes;
  final double? latitude;
  final double? longitude;

  const AnalysisData({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.imagePath,
    this.polygon,
    this.audioBytes,
    this.latitude,
    this.longitude,
  });

  static const defaultData = AnalysisData(
    tag: "HISTORICAL SITE",
    title: "Traditional Soy Sauce Brew",
    subtitle: "Built 1920 窶｢ 0.2 miles away",
    description: "A preserved historical brewery showcasing traditional fermentation methods and architectural heritage from the early 20th century.",
    imagePath: 'assets/brewery.png',
  );
}
