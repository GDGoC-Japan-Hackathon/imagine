import 'dart:async';
import 'package:camera/camera.dart' hide CameraException;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../constants/app_constants.dart';
import '../../errors/exceptions.dart';
import 'camera_interface.dart';

/// デバイスの物理カメラを制御するサービスの実装
class LocalCameraService implements BaseCameraService {
  static const MethodChannel _channel = MethodChannel('com.example.imagine/mediapipe');
  
  CameraController? frontCameraController;
  CameraController? backCameraController;
  List<CameraDescription> _cameras = [];
  bool _isAutomotive = false;

  @override
  bool get isInitialized => frontCameraController != null && frontCameraController!.value.isInitialized;

  bool get isAutomotive => _isAutomotive;

  @override
  Future<void> initialize({bool force = false}) async {
    if (!force && isInitialized) return;

    await dispose();
    _cameras = await availableCameras();
    
    if (_cameras.isEmpty) {
      await Future.delayed(AppConstants.cameraRetryDelay);
      _cameras = await availableCameras();
    }

    if (_cameras.isEmpty) {
      throw CameraException("利用可能なカメラが見つかりません");
    }

    try {
      _isAutomotive = await _channel.invokeMethod('isAutomotiveOS') ?? false;
    } catch (e) {
      debugPrint("Failed to check automotive os: $e");
    }

    final selectedInCamera = _selectFrontCamera();
    
    try {
      frontCameraController = CameraController(
        selectedInCamera, 
        ResolutionPreset.medium, 
        enableAudio: false,
      );
      await frontCameraController?.initialize();
    } on PlatformException catch (e) {
      throw CameraException("カメラデバイスの属性取得に失敗しました", e.code);
    } catch (e) {
      throw CameraException("カメラの初期化中にエラーが発生しました: $e");
    }
  }

  CameraDescription _selectFrontCamera() {
    final int manualInIndex = int.tryParse(dotenv.env['IN_CAMERA_INDEX'] ?? '${AppConstants.defaultManualIndex}') ?? AppConstants.defaultManualIndex;
    
    if (manualInIndex != AppConstants.defaultManualIndex && manualInIndex < _cameras.length) {
      return _cameras[manualInIndex];
    } else if (_cameras.length <= 1) {
      return _cameras.first;
    } else if (_isAutomotive) {
      return _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.external,
        orElse: () => _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        ),
      );
    } else {
      return _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
    }
  }

  @override
  Future<XFile?> captureOutCameraImage() async {
    // フロントカメラが起動している場合は一旦停止（リソース競合回避）
    if (frontCameraController != null) {
      await frontCameraController!.dispose();
      frontCameraController = null;
    }

    if (_cameras.isEmpty) _cameras = await availableCameras();
    if (_cameras.isEmpty) return null;

    final selectedOutCamera = _selectBackCamera();
    
    backCameraController = CameraController(
      selectedOutCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await backCameraController!.initialize();
      final image = await backCameraController!.takePicture();
      await Future.delayed(AppConstants.cameraCaptureDelay);
      return image;
    } catch (e) {
      throw CameraException("写真の撮影中にエラーが発生しました: $e");
    } finally {
      await backCameraController?.dispose();
      backCameraController = null;
    }
  }

  CameraDescription _selectBackCamera() {
    final int manualOutIndex = int.tryParse(dotenv.env['OUT_CAMERA_INDEX'] ?? '${AppConstants.defaultManualIndex}') ?? AppConstants.defaultManualIndex;

    if (manualOutIndex != AppConstants.defaultManualIndex && manualOutIndex < _cameras.length) {
      return _cameras[manualOutIndex];
    } else if (_cameras.length <= 1) {
      return _cameras.first;
    } else if (_isAutomotive) {
      return _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.external,
        orElse: () => _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras.first,
        ),
      );
    } else {
      return _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
    }
  }

  @override
  Future<void> dispose() async {
    await frontCameraController?.dispose();
    frontCameraController = null;
    await backCameraController?.dispose();
    backCameraController = null;
  }
}
