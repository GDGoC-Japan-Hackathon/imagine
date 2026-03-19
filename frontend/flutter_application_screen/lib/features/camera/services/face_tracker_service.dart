import 'dart:math' as math;
import '../models/face_vector.dart';

class FaceTrackerService {
  static final FaceTrackerService _instance = FaceTrackerService._internal();
  factory FaceTrackerService() => _instance;
  FaceTrackerService._internal();

  // Python実装（10fps換算で6フレーム = 約600ms）を、Dart側（約33fps）に換算して20フレームとして設定
  static const int _requiredStableFrames = 20; 
  static const double _yawThreshold = 3.0;
  static const double _pitchThreshold = 3.0;

  final Map<int, FaceVector> _lastFaceVectors = {};
  final Map<int, int> _stableCounts = {};

  bool _isGazeNotMoving(FaceVector? currentAngles, FaceVector? previousAngles) {
    if (currentAngles == null || previousAngles == null) return false;

    final dx = (currentAngles.x - previousAngles.x).abs();
    final dy = (currentAngles.y - previousAngles.y).abs();
    
    // Euler角の差分が両方とも3.0度以内の場合のみ安定とみなす
    return dx <= _yawThreshold && dy <= _pitchThreshold;
  }

  /// 現在の安定度合いを 0.0 ~ 1.0 で返す
  double getStableProgress(List<FaceVector> anglesList) {
    if (anglesList.isEmpty) {
      _lastFaceVectors.clear();
      _stableCounts.clear();
      return 0.0;
    }

    double maxProgress = 0.0;
  // 人の顔の数だけ判定する
    for (int i = 0; i < anglesList.length; i++) {
      final currentAngles = anglesList[i];
      final prevAngles = _lastFaceVectors[i];

      // 顔の向きが前フレームから動いていないかを判定
      if (_isGazeNotMoving(currentAngles, prevAngles)) {
        _stableCounts[i] = (_stableCounts[i] ?? 0) + 1;
      } else {
        // 動いた瞬間にカウントをリセット（厳格化）
        _stableCounts[i] = 0;
      }

      // 次回判定用に更新
      _lastFaceVectors[i] = currentAngles;

      final count = _stableCounts[i] ?? 0;
      // 連続フレーム数を進捗としてプロット（UI表示用）
      final progress = (count / _requiredStableFrames).clamp(0.0, 1.0);
      maxProgress = math.max(maxProgress, progress);
    }

    // フレームから消えた顔のステートを削除する
    _lastFaceVectors.removeWhere((key, _) => key >= anglesList.length);
    _stableCounts.removeWhere((key, _) => key >= anglesList.length);

    return maxProgress;
  }

  /// 進捗状態を更新せずに取得する（UI表示用）
  double get currentProgress {
    double maxProgress = 0.0;
    for (final count in _stableCounts.values) {
      final progress = (count / _requiredStableFrames).clamp(0.0, 1.0);
      maxProgress = math.max(maxProgress, progress);
    }
    return maxProgress;
  }

  void reset() {
    _lastFaceVectors.clear();
    _stableCounts.clear();
  }
}
