import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/face_vector.dart';

class _FaceSample {
  final int timestamp;
  final bool isGazeStable;

  _FaceSample(this.timestamp, this.isGazeStable);
}

class FaceTrackerService {
  static const int trackingWindowMs = 800; // 車内環境を想定し、判定時間を0.8秒へ短縮
  static const double stabilityThreshold = 0.05; // 振動によるフレーム損失を許容 (5%以上の安定フレームでOK)
  static const double smoothingAlpha = 0.10; // さらにスムージングを強くして車体の微振動をカット
  static const double driftFollowAlpha = 0.15; // 基準点を車の揺れや姿勢変化に素早く追従させる

  final Map<int, FaceVector> _baseFaceVectors = {};
  final Map<int, FaceVector> _smoothedFaceVectors = {};
  final Map<int, List<_FaceSample>> _faceHistory = {};

  FaceVector _smooth(int id, FaceVector raw) {
    final prev = _smoothedFaceVectors[id];
    if (prev == null) {
      _smoothedFaceVectors[id] = raw;
      return raw;
    }
    final smoothed = FaceVector(
      prev.x * (1 - smoothingAlpha) + raw.x * smoothingAlpha,
      prev.y * (1 - smoothingAlpha) + raw.y * smoothingAlpha,
    );
    _smoothedFaceVectors[id] = smoothed;
    return smoothed;
  }

  bool _isGazeStableFromBase(FaceVector current, FaceVector base, {double angleThreshold = 45.0}) {
    final dx = current.x - base.x;
    final dy = current.y - base.y;
    final distance = math.sqrt(dx * dx + dy * dy);
    return distance < angleThreshold; // ドライブレコーダー用に閾値を45.0へ緩和し、大きな振動も許容
  }

  /// 現在の安定度合いを 0.0 ~ 1.0 で返す
  double getStableProgress(List<FaceVector> anglesList) {
    int now = DateTime.now().millisecondsSinceEpoch;

    // フレームから消えた顔のデータを削除
    _baseFaceVectors.removeWhere((key, _) => key >= anglesList.length);
    _smoothedFaceVectors.removeWhere((key, _) => key >= anglesList.length);
    _faceHistory.removeWhere((key, _) => key >= anglesList.length);

    if (anglesList.isEmpty) {
      _baseFaceVectors.clear();
      return 0.0;
    }

    for (int i = 0; i < anglesList.length; i++) {
      // 1. まず入力をスムージング（手振れ補正）
      final smoothedAngles = _smooth(i, anglesList[i]);
      
      if (_baseFaceVectors[i] == null) {
        _baseFaceVectors[i] = smoothedAngles;
        _faceHistory[i] = [];
      }

      // 2. スムージングされた値で安定判定
      final isStable = _isGazeStableFromBase(smoothedAngles, _baseFaceVectors[i]!);

      // 3. 基準点を現在の値に極低速で追従させる (Drift Compensation)
      // これにより、ゆっくりとした姿勢の変化を「動き」とみなさず安定として継続できる
      if (isStable) {
        _baseFaceVectors[i] = FaceVector(
          _baseFaceVectors[i]!.x * (1 - driftFollowAlpha) + smoothedAngles.x * driftFollowAlpha,
          _baseFaceVectors[i]!.y * (1 - driftFollowAlpha) + smoothedAngles.y * driftFollowAlpha,
        );
      }

      _faceHistory[i]!.add(_FaceSample(now, isStable));
      _faceHistory[i]!.removeWhere((sample) => now - sample.timestamp > trackingWindowMs);
      
      final history = _faceHistory[i]!;
      final stableCount = history.where((s) => s.isGazeStable).length;
      final stabilityRatio = stableCount / history.length;
      
      // 安定性が著しく低い場合のみリセット
      if (stabilityRatio < stabilityThreshold && history.length > 10) {
        _baseFaceVectors[i] = smoothedAngles;
        _faceHistory[i] = [];
      }
    }

    double maxProgress = 0.0;
    for (int i = 0; i < anglesList.length; i++) {
      final history = _faceHistory[i]!;
      if (history.isEmpty) continue;

      final startTime = history.first.timestamp;
      final elapsed = now - startTime;
      
      // 時間経過による進捗をシンプルに計算 (1.0秒で100%に到達)
      final progress = (elapsed / trackingWindowMs).clamp(0.0, 1.0);
      maxProgress = math.max(maxProgress, progress);
    }

    return maxProgress > 0.95 ? 1.0 : maxProgress;
  }
}
