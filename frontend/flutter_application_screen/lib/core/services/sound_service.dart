import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Androidのシステムサウンドを再生するサービス。
/// 既存の MediaPipe チャンネルを共有して通信する。
class SoundService {
  static const _channel = MethodChannel('com.example.imagine/mediapipe');

  /// 顔認識が成功し、解析が始まるタイミングで呼び出す。
  /// Android の MediaActionSound.FOCUS_COMPLETE（カメラAFロック音）を再生する。
  static Future<void> playFaceDetected() async {
    try {
      await _channel.invokeMethod('playFaceDetected');
    } on PlatformException catch (e) {
      // 音声再生の失敗はアプリ動作に影響しないため、ログのみ出力
      debugPrint('SoundService.playFaceDetected error: $e');
    }
  }

  /// 音声録音（音声認識）が始まるタイミングで呼び出す。
  /// Android のデフォルト通知音を再生する。
  static Future<void> playVoiceStart() async {
    try {
      await _channel.invokeMethod('playVoiceStart');
    } on PlatformException catch (e) {
      // 音声再生の失敗はアプリ動作に影響しないため、ログのみ出力
      debugPrint('SoundService.playVoiceStart error: $e');
    }
  }
}
