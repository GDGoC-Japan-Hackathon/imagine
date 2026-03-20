import 'dart:math' as math;
import '../models/face_vector.dart';
import '../../../core/constants/app_constants.dart';

/// 顔の向きの安定性を追跡し、一定時間（フレーム数）安定しているかを判定するサービス。
class FaceTrackerService {
  static final FaceTrackerService _instance = FaceTrackerService._internal();
  factory FaceTrackerService() => _instance;
  FaceTrackerService._internal();

  static const int _requiredStableFrames = AppConstants.requiredStableFrames; 
  static const double _yawThreshold = AppConstants.yawThreshold;
  static const double _pitchThreshold = AppConstants.pitchThreshold;

  // 安定判定の基準となる位置（アンカー）を保持。複数の顔を識別可能。
  final Map<int, FaceVector> _anchorFaceVectors = {};
  final Map<int, int> _stableCounts = {};

  /// 顔の向きが基準位置の範囲内にあるかどうかを判定します。
  bool _isWithinStaringRange(FaceVector? currentAngles, FaceVector? anchorAngles) {
    if (currentAngles == null || anchorAngles == null) return false;

    final dx = (currentAngles.x - anchorAngles.x).abs();
    final dy = (currentAngles.y - anchorAngles.y).abs();
    
    // Euler角（相当）の基準点からの差分が閾値以内の場合のみ安定とみなす。
    // フレーム間比較ではなく、注視開始点との比較にすることでドリフトを防止しています。
    return dx <= _yawThreshold && dy <= _pitchThreshold;
  }

  /// 現在の安定度合いを 0.0 ~ 1.0 で返します。
  /// [anglesList] 検出された顔の向き（FaceVector）のリスト。
  double getStableProgress(List<FaceVector> anglesList) {
    if (anglesList.isEmpty) {
      _anchorFaceVectors.clear();
      _stableCounts.clear();
      return 0.0;
    }

    double maxProgress = 0.0;
    // 検出された全ての顔に対して判定を行う
    for (int i = 0; i < anglesList.length; i++) {
      final currentAngles = anglesList[i];
      final anchorAngles = _anchorFaceVectors[i];

      // 顔の向きが安定開始時の位置から大きく動いていないかを判定
      if (_isWithinStaringRange(currentAngles, anchorAngles)) {
        _stableCounts[i] = (_stableCounts[i] ?? 0) + 1;
      } else {
        // 閾値を超えた瞬間にカウントをリセットし、現在地を新しいアンカーに設定
        _stableCounts[i] = 0;
        _anchorFaceVectors[i] = currentAngles;
      }

      final count = _stableCounts[i] ?? 0;
      // 連続フレーム数を進捗として計算（UI表示用）
      final progress = (count / _requiredStableFrames).clamp(0.0, 1.0);
      maxProgress = math.max(maxProgress, progress);
    }

    // フレームから消えた顔のステートを削除する
    _anchorFaceVectors.removeWhere((key, _) => key >= anglesList.length);
    _stableCounts.removeWhere((key, _) => key >= anglesList.length);

    return maxProgress;
  }

  /// 進捗状態を更新せずに、現在の最大進捗を取得します（UI表示用）。
  double get currentProgress {
    double maxProgress = 0.0;
    for (final count in _stableCounts.values) {
      final progress = (count / _requiredStableFrames).clamp(0.0, 1.0);
      maxProgress = math.max(maxProgress, progress);
    }
    return maxProgress;
  }

  /// 追跡状態をリセットします。
  void reset() {
    _anchorFaceVectors.clear();
    _stableCounts.clear();
  }
}

