import 'package:camera/camera.dart';

class CameraService {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  CameraController? inCameraController;
  CameraController? outCameraController;
  List<CameraDescription> _cameras = [];

  Future<void> initialize({bool force = false}) async {
    // 既に初期化されており、強制再起動でない場合はスキップ
    if (!force && 
        inCameraController != null && inCameraController!.value.isInitialized &&
        outCameraController != null && outCameraController!.value.isInitialized) {
      return;
    }

    // 既存のコントローラーがあれば確実に解放する
    await dispose();
    
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    
    // InCamera (インカメラ: 初期化してプレビュー表示・顔認識に使用)
    final frontCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );
    
    inCameraController = CameraController(
      frontCamera, 
      ResolutionPreset.medium, 
      enableAudio: false, // 顔認識にオーディオは不要なのでオフにして負荷軽減
    );

    try {
      await inCameraController?.initialize();
    } catch (e) {
      print("Error initializing in-camera: $e");
    }

    // OutCamera (アウトカメラ: 撮影用)
    // ※Android仕様上、一部端末では2つのカメラ同時プレビューができないため、利用時のみ有効化する設計が安全です。
    final backCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.last,
    );
    outCameraController = CameraController(
      backCamera, 
      ResolutionPreset.high, 
      enableAudio: false,
    );
    
    try {
      await outCameraController?.initialize();
    } catch (e) {
      print("Error initializing out-camera: $e");
    }
  }

  /// アウトカメラで静止画を撮影
  Future<XFile?> captureOutCameraImage() async {
    if (outCameraController != null && outCameraController!.value.isInitialized) {
      try {
        return await outCameraController!.takePicture();
      } catch (e) {
        print("Error taking picture: $e");
      }
    }
    return null;
  }

  Future<void> dispose() async {
    try {
      if (inCameraController != null) {
        await inCameraController!.dispose();
      }
    } catch (e) {
      print("Error during in-camera dispose: $e");
    } finally {
      inCameraController = null;
    }

    try {
      if (outCameraController != null) {
        await outCameraController!.dispose();
      }
    } catch (e) {
      print("Error during out-camera dispose: $e");
    } finally {
      outCameraController = null;
    }
  }
}
