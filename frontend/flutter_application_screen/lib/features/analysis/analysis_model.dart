class AnalysisData {
  final String tag;
  final String title;
  final String subtitle;
  final String description;
  final String imagePath;

  const AnalysisData({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.imagePath,
  });

  static const defaultData = AnalysisData(
    tag: "HISTORICAL SITE",
    title: "Traditional Soy Sauce Brew",
    subtitle: "Built 1920 • 0.2 miles away",
    description: "A preserved historical brewery showcasing traditional fermentation methods and architectural heritage from the early 20th century. Experience the authentic brewing process of artisanal soy sauce.",
    imagePath: 'assets/brewery.png',
  );
}
