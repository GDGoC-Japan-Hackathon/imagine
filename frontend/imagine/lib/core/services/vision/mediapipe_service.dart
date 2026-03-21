import 'dart:async';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart' hide CameraException;
import '../../errors/exceptions.dart';

/// MediaPipe による顔検出（ネイティブ連携）を担当するサービス
class MediapipeService {
  static final MediapipeService _instance = MediapipeService._internal();
  factory MediapipeService() => _instance;
  MediapipeService._internal();

  static const _methodChannel = MethodChannel('com.example.imagine/mediapipe');
  static const _eventChannel = EventChannel('com.example.imagine/mediapipe_events');

  /// 顔認識結果のストリーム
  Stream<Map<String, dynamic>> get faceStream =>
      _eventChannel.receiveBroadcastStream().map((event) {
        final data = event as Map;
        return data.map((key, value) => MapEntry(key.toString(), value));
      });

  /// MediaPipe を初期化します。
  Future<void> initialize({bool debugShowFaceImage = false, int delegate = 1}) async {
    try {
      await _methodChannel.invokeMethod('init', {
        'debugShowFaceImage': debugShowFaceImage,
        'delegate': delegate,
      });
    } on PlatformException catch (e) {
      throw CameraException("MediaPipeの初期化に失敗しました: ${e.message}", e.code);
    } catch (e) {
      throw CameraException("MediaPipeの初期化中に予期せぬエラーが発生しました");
    }
  }

  /// カメラ画像（YUV）から顔を検出します。
  Future<void> detect(CameraImage image, {bool isFront = true, int rotation = 0}) async {
    try {
      await _methodChannel.invokeMethod('detect', {
        'y': image.planes[0].bytes,
        'u': image.planes[1].bytes,
        'v': image.planes[2].bytes,
        'yRowStride': image.planes[0].bytesPerRow,
        'uvRowStride': image.planes[1].bytesPerRow,
        'uvPixelStride': image.planes[1].bytesPerPixel,
        'width': image.width,
        'height': image.height,
        'isFront': isFront,
        'rotation': rotation,
      });
    } on PlatformException catch (e) {
      throw CameraException("顔検出処理に失敗しました: ${e.message}", e.code);
    }
  }

  /// JPEG データから顔を検出します。
  Future<void> detectJpeg(Uint8List jpegBytes, {bool isFront = true, int rotation = 0}) async {
    try {
      await _methodChannel.invokeMethod('detectJpeg', {
        'jpeg': jpegBytes,
        'isFront': isFront,
        'rotation': rotation,
      });
    } on PlatformException catch (e) {
      throw CameraException("JPEGからの顔検出処理に失敗しました: ${e.message}", e.code);
    }
  }

  /// MediaPipe 機能を終了します。
  Future<void> close() async {
    await _methodChannel.invokeMethod('close');
  }
}
