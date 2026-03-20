import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart' hide CameraException;

import '../../../core/errors/exceptions.dart';

class MediapipeService {
  static final MediapipeService _instance = MediapipeService._internal();
  factory MediapipeService() => _instance;
  MediapipeService._internal();

  static const _methodChannel = MethodChannel('com.example.imagine/mediapipe');
  static const _eventChannel = EventChannel('com.example.imagine/mediapipe_events');

  Stream<Map<String, dynamic>> get faceStream =>
      _eventChannel.receiveBroadcastStream().map((event) {
        final data = event as Map;
        return data.map((key, value) => MapEntry(key.toString(), value));
      });

  Future<void> initialize({bool debugShowFaceImage = false, int delegate = 1}) async {
    try {
      await _methodChannel.invokeMethod('init', {
        'debugShowFaceImage': debugShowFaceImage,
        'delegate': delegate,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to initialize MediaPipe: ${e.message}");
      throw CameraException("MediaPipeの初期化に失敗しました: ${e.message}", e.code);
    } catch (e) {
      debugPrint("Unexpected error during MediaPipe initialization: $e");
      throw CameraException("MediaPipeの初期化中に予期せぬエラーが発生しました");
    }
  }

  Future<void> detect(CameraImage image, {bool isFront = true, int rotation = 0}) async {
    try {
      // YUV420 プレーンを転送。ストライド情報も付随させる
      final y = image.planes[0].bytes;
      final u = image.planes[1].bytes;
      final v = image.planes[2].bytes;
      
      // ネイティブ側のMediaPipeで処理する
      await _methodChannel.invokeMethod('detect', {
        'y': y,
        'u': u,
        'v': v,
        'yRowStride': image.planes[0].bytesPerRow,
        'uvRowStride': image.planes[1].bytesPerRow,
        'uvPixelStride': image.planes[1].bytesPerPixel,
        'width': image.width,
        'height': image.height,
        'isFront': isFront,
        'rotation': rotation,
      });
    } on PlatformException catch (e) {
      debugPrint("MediaPipe Detection error: ${e.message}");
      throw CameraException("顔検出処理に失敗しました: ${e.message}", e.code);
    }
  }

  Future<void> detectJpeg(Uint8List jpegBytes, {bool isFront = true, int rotation = 0}) async {
    try {
      await _methodChannel.invokeMethod('detectJpeg', {
        'jpeg': jpegBytes,
        'isFront': isFront,
        'rotation': rotation,
      });
    } on PlatformException catch (e) {
      debugPrint("MediaPipe Detection error: ${e.message}");
      throw CameraException("JPEGからの顔検出処理に失敗しました: ${e.message}", e.code);
    }
  }

  Future<void> close() async {
    await _methodChannel.invokeMethod('close');
  }
}
