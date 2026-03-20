import 'face_vector.dart';

/// デバッグ用のテスト風景データ
class TestScenery {
  final String assetPath;
  final FaceVector targetVector;

  const TestScenery(this.assetPath, this.targetVector);

  static const List<TestScenery> items = [
    TestScenery('assets/tokyo_place.png', FaceVector(0, 0)),
    // TestScenery('assets/tokyo_place.png', FaceVector(-15, -15)),
  ];

  static TestScenery getRandom() {
    return items[(DateTime.now().millisecond) % items.length];
  }
}
