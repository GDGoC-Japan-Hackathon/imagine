import '../models/face_vector.dart';

class TestScenery {
  final String assetPath;
  final FaceVector targetVector;
  final String label;

  const TestScenery({
    required this.assetPath,
    required this.targetVector,
    required this.label,
  });

  static const List<TestScenery> samples = [
    TestScenery(
      assetPath: 'assets/tokyo_place.png',
      targetVector: FaceVector(0, 0), // 画像中央を注視
      label: 'TokyoPlace (Test)',
    ),    
    TestScenery(
      assetPath: 'assets/tokyo_place.png',
      targetVector: FaceVector(-15, -15), // 画像中央を注視
      label: 'Car (Test)',
    )
    // 必要に応じて追加
  ];

  static TestScenery getRandom() {
    return samples[DateTime.now().millisecond % samples.length];
  }
}
