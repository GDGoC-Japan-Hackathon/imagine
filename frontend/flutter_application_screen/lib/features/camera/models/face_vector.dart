/// 顔認識のベクトルクラス
class FaceVector {
  final double x; // Yaw（横方向）
  final double y; // Pitch（縦方向）

  const FaceVector(this.x, this.y);

  FaceVector operator -(FaceVector other) {
    return FaceVector(x - other.x, y - other.y);
  }

  @override
  String toString() => 'x: ${x.toStringAsFixed(2)}, y: ${y.toStringAsFixed(2)}';
}
