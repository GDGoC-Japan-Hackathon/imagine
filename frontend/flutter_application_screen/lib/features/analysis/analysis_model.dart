class AnalysisData {
  final String tag;
  final String title;
  final String subtitle;
  final String description;
  final String imagePath;
  final List<double>? polygon; // Gemini returns [y, x, y, x, ...]

  const AnalysisData({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.imagePath,
    this.polygon,
  });

  static const defaultData = AnalysisData(
    tag: "HISTORICAL SITE",
    title: "Traditional Soy Sauce Brew",
    subtitle: "Built 1920 • 0.2 miles away",
    description: "A preserved historical brewery showcasing traditional fermentation methods and architectural heritage from the early 20th century.",
    imagePath: 'assets/brewery.png',
  );
}
