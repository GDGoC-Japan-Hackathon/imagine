import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/face_vector.dart';

class _FaceSample {
  final int timestamp;
  final bool isGazeStable;

  _FaceSample(this.timestamp, this.isGazeStable);
}

class FaceTrackerService {
  static const int trackingWindowMs = 2000; // 2秒間のウィンドウ
  static const double stabilityThreshold = 0.1; // 10%以上のフレームが安定していればOK

  final Map<int, FaceVector> _baseFaceVectors = {}; // ウィンドウ開始時の基準点
  final Map<int, List<_FaceSample>> _faceHistory = {};

  // 顔の向きが基準から「大きく」外れていないか判定
  bool _isGazeStableFromBase(FaceVector current, FaceVector base, {double angleThreshold = 25.0}) {
    final dx = current.x - base.x;
    final dy = current.y - base.y;
    final movement = dx * dx + dy * dy;
    return movement < (angleThreshold * angleThreshold); // 25度の範囲内ならOK
  }

  /// 現在の安定度合いを 0.0 ~ 1.0 で返す
  double getStableProgress(List<FaceVector> anglesList) {
    int now = DateTime.now().millisecondsSinceEpoch;

    // フレームから消えた顔のデータを削除
    _baseFaceVectors.removeWhere((key, _) => key >= anglesList.length);
    _faceHistory.removeWhere((key, _) => key >= anglesList.length);

    if (anglesList.isEmpty) {
      _baseFaceVectors.clear();
      return 0.0;
    }

    for (int i = 0; i < anglesList.length; i++) {
      final currentAngles = anglesList[i];
      
      if (_baseFaceVectors[i] == null) {
        _baseFaceVectors[i] = currentAngles;
        _faceHistory[i] = [];
      }

      final isStable = _isGazeStableFromBase(currentAngles, _baseFaceVectors[i]!);

      _faceHistory[i]!.add(_FaceSample(now, isStable));
      _faceHistory[i]!.removeWhere((sample) => now - sample.timestamp > trackingWindowMs);
      
      final history = _faceHistory[i]!;
      final stableCount = history.where((s) => s.isGazeStable).length;
      final stabilityRatio = stableCount / history.length;
      
      // 安定性が著しく低い場合のみリセット
      // ただし、進捗が戻るのを防ぐため、リセット時は進捗計算用のリストもクリアされる
      if (stabilityRatio < stabilityThreshold && history.length > 5) {
        _baseFaceVectors[i] = currentAngles;
        _faceHistory[i] = [];
      }
    }

    double maxProgress = 0.0;
    for (int i = 0; i < anglesList.length; i++) {
      final history = _faceHistory[i]!;
      if (history.isEmpty) continue;

      final startTime = history.first.timestamp;
      final elapsed = now - startTime;
      
      // trackingWindowMs(2000ms) に対しての経過時間を 0.0 ~ 1.0 で返す
      // これにより、履歴が古くなることによる「逆戻り」を防ぎ、2秒経てば必ず1.0になる
      final progress = (elapsed / trackingWindowMs).clamp(0.0, 1.0);
      maxProgress = math.max(maxProgress, progress);
    }

    return maxProgress;
  }
}
