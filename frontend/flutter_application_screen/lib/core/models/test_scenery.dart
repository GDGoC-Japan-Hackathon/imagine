import 'face_vector.dart';

/// デバッグ用のテスト風景データ
class TestScenery {
  final String assetPath;
  final FaceVector targetVector;

  const TestScenery(this.assetPath, this.targetVector);

  static const List<TestScenery> items = [
    TestScenery('assets/test_tokyo_tower.jpg', FaceVector(5.0, -10.0)),
    TestScenery('assets/test_fuji.jpg', FaceVector(-15.0, 5.0)),
    TestScenery('assets/test_shrine.jpg', FaceVector(0.0, 0.0)),
  ];

  static TestScenery getRandom() {
    return items[(DateTime.now().millisecond) % items.length];
  }
}
