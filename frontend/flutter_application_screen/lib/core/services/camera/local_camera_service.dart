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

  /// AAOS環境かどうかをカメラ初期化前に事前チェックするメソッド。
  /// カメラ初期化に依存しないため、起動直後に呼び出すことができる。
  Future<bool> checkIsAutomotive() async {
    try {
      _isAutomotive = await _channel.invokeMethod('isAutomotiveOS') ?? false;
    } catch (e) {
      debugPrint("Failed to check automotive OS: $e");
      _isAutomotive = false;
    }
    return _isAutomotive;
  }

  @override
  Future<void> initialize({bool force = false}) async {
    if (!force && isInitialized) return;

    await dispose();
    
    // AAOS判定（まだ取得していない場合のみ）
    if (!_isAutomotive) {
      await checkIsAutomotive();
    }
    
    // AAOS環境ではUSBカメラの認識に時間がかかるため、リトライ回数を増やす
    _cameras = await _safeAvailableCameras();
    
    if (_cameras.isEmpty) {
      final retryCount = _isAutomotive ? AppConstants.cameraRetryCount : 1;
      final retryDelay = _isAutomotive ? AppConstants.cameraRetryDelayAaos : AppConstants.cameraRetryDelay;
      
      for (int i = 0; i < retryCount && _cameras.isEmpty; i++) {
        debugPrint("カメラ検出リトライ (${i + 1}/$retryCount)...");
        await Future.delayed(retryDelay);
        _cameras = await _safeAvailableCameras();
      }
    }

    if (_cameras.isEmpty) {
      throw CameraException("利用可能なカメラが見つかりません");
    }

    final selectedInCamera = _selectFrontCamera();
    
    // 解像度フォールバック: medium → low
    await _initializeFrontCamera(selectedInCamera);
  }

  /// `availableCameras()` を安全に呼び出すラッパー。
  /// AAOS環境ではカメラサービスが無効化されている場合に
  /// PlatformException が発生するため、空リストを返すようにする。
  Future<List<CameraDescription>> _safeAvailableCameras() async {
    try {
      return await availableCameras();
    } on PlatformException catch (e) {
      debugPrint("availableCameras() PlatformException: ${e.message}");
      return [];
    } catch (e) {
      debugPrint("availableCameras() error: $e");
      return [];
    }
  }

  /// フロントカメラコントローラーの初期化。
  /// 解像度がサポートされない場合のフォールバックを含む。
  Future<void> _initializeFrontCamera(CameraDescription camera) async {
    // まず medium で試行
    try {
      frontCameraController = CameraController(
        camera, 
        ResolutionPreset.medium, 
        enableAudio: false,
      );
      await frontCameraController?.initialize();
      return;
    } on PlatformException catch (e) {
      debugPrint("カメラ初期化(medium)失敗: ${e.message}、低解像度でリトライします");
      await frontCameraController?.dispose();
      frontCameraController = null;
    } catch (e) {
      debugPrint("カメラ初期化(medium)エラー: $e、低解像度でリトライします");
      await frontCameraController?.dispose();
      frontCameraController = null;
    }
    
    // medium が失敗した場合、low でフォールバック
    try {
      frontCameraController = CameraController(
        camera, 
        ResolutionPreset.low, 
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

    if (_cameras.isEmpty) _cameras = await _safeAvailableCameras();
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
