import 'package:camera/camera.dart';

class CameraService {
  CameraController? inCameraController;
  CameraController? outCameraController;
  List<CameraDescription> _cameras = [];

  Future<void> initialize() async {
    _cameras = await availableCameras();
    
    // InCamera (インカメラ: 初期化してプレビュー表示・顔認識に使用)
    final frontCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );
    inCameraController = CameraController(frontCamera, ResolutionPreset.medium);
    await inCameraController?.initialize();

    // OutCamera (アウトカメラ: 撮影用)
    // ※Android仕様上、一部端末では2つのカメラ同時プレビューができないため、利用時のみ有効化する設計が安全です。
    final backCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.last,
    );
    outCameraController = CameraController(backCamera, ResolutionPreset.high);
    await outCameraController?.initialize();
  }

  /// アウトカメラで静止画を撮影
  Future<XFile?> captureOutCameraImage() async {
    if (outCameraController != null && outCameraController!.value.isInitialized) {
      return await outCameraController!.takePicture();
    }
    return null;
  }

  void dispose() {
    inCameraController?.dispose();
    outCameraController?.dispose();
  }
}
