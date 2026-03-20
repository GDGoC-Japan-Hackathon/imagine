import 'package:flutter/foundation.dart';
import '../models/face_vector.dart';

class FaceTrackerService {
  static const int nextCheckIntervalMs = 2000;

  final Map<int, FaceVector> _lastFaceVectors = {};
  final Map<int, bool> _faceSuccesses = {};
  int _nextTimestampMs = 0;

  FaceTrackerService() {
    _resetNextCheck();
  }

  void _resetNextCheck() {
    _nextTimestampMs = DateTime.now().millisecondsSinceEpoch + nextCheckIntervalMs;
  }

  // 顔の向きが動いていないか判定
  bool _isGazeNotMoving(FaceVector? current, FaceVector? previous, {double ratioThreshold = 8.0}) {
    if (current == null || previous == null) return false;
    final delta = current - previous;
    if (delta.x == 0 || delta.y == 0) return true;
    return (delta.x / delta.y).abs() <= ratioThreshold;
  }

  // フレームごとの顔データを入力し、安定状態を返却する
  List<FaceVector>? processFaces(List<FaceVector> anglesList) {
    int timestampMs = DateTime.now().millisecondsSinceEpoch;

    // 各顔のベクトル更新
    for (int i = 0; i < anglesList.length; i++) {
      final currentAngles = anglesList[i];
      final prevAngles = _lastFaceVectors[i];

      if (_isGazeNotMoving(currentAngles, prevAngles)) {
        _faceSuccesses[i] = true;
      } else {
        if (kDebugMode) print("顔 $i の目線が動いています");
        _faceSuccesses[i] = false;
        _resetNextCheck();
      }
      _lastFaceVectors[i] = currentAngles;
    }

    // フレームから消えた顔ステータス削除
    _lastFaceVectors.removeWhere((key, _) => key >= anglesList.length);
    _faceSuccesses.removeWhere((key, _) => key >= anglesList.length);

    // 一定時間経過後に安定状態をチェック
    if (timestampMs >= _nextTimestampMs) {
      final stableVectors = <FaceVector>[];
      for (int i = 0; i < anglesList.length; i++) {
        if (_faceSuccesses[i] == true && _lastFaceVectors[i] != null) {
          stableVectors.add(_lastFaceVectors[i]!);
        }
      }

      if (stableVectors.isNotEmpty) {
        if (kDebugMode) print("目線が動いていない状態を検出しました。");
        _resetNextCheck();
        return stableVectors;
      }
      _resetNextCheck();
    }
    return null;
  }
}
