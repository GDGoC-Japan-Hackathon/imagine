import 'dart:math' as math;
import '../../models/face_vector.dart';
import '../../constants/app_constants.dart';

/// 顔の向きの安定性を追跡・判定するサービス。
class FaceTrackerService {
  static final FaceTrackerService _instance = FaceTrackerService._internal();
  factory FaceTrackerService() => _instance;
  FaceTrackerService._internal();

  final Map<int, FaceVector> _anchorFaceVectors = {};
  final Map<int, int> _stableCounts = {};

  /// 顔の向きの安定進捗 (0.0 ~ 1.0) を取得し、内部状態を更新します。
  double getStableProgress(List<FaceVector> anglesList) {
    if (anglesList.isEmpty) {
      reset();
      return 0.0;
    }

    double maxProgress = 0.0;
    for (int i = 0; i < anglesList.length; i++) {
      final currentAngles = anglesList[i];
      final anchorAngles = _anchorFaceVectors[i];

      if (_isWithinStaringRange(currentAngles, anchorAngles)) {
        _stableCounts[i] = (_stableCounts[i] ?? 0) + 1;
      } else {
        _stableCounts[i] = 0;
        _anchorFaceVectors[i] = currentAngles;
      }

      final count = _stableCounts[i] ?? 0;
      final progress = (count / AppConstants.requiredStableFrames).clamp(0.0, 1.0);
      maxProgress = math.max(maxProgress, progress);
    }

    _anchorFaceVectors.removeWhere((key, _) => key >= anglesList.length);
    _stableCounts.removeWhere((key, _) => key >= anglesList.length);

    return maxProgress;
  }

  /// 進捗を更新せずに、現在の最大進捗を確認します。
  double get currentProgress {
    double maxProgress = 0.0;
    for (final count in _stableCounts.values) {
      final progress = (count / AppConstants.requiredStableFrames).clamp(0.0, 1.0);
      maxProgress = math.max(maxProgress, progress);
    }
    return maxProgress;
  }

  /// 追跡状態をリセットします。
  void reset() {
    _anchorFaceVectors.clear();
    _stableCounts.clear();
  }

  bool _isWithinStaringRange(FaceVector? current, FaceVector? anchor) {
    if (current == null || anchor == null) return false;
    final dx = (current.x - anchor.x).abs();
    final dy = (current.y - anchor.y).abs();
    return dx <= AppConstants.yawThreshold && dy <= AppConstants.pitchThreshold;
  }
}
