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
        inCameraController != null && inCameraController!.value.isInitialized) {
      return;
    }

    // 既存のコントローラーがあれば確実に解放する
    await dispose();
    
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    
    // 1. InCamera (運転手側: 顔認識・プレビュー用)
    // フロントカメラを探し、なければリストの2番目（多くのAndroidでフロントはindex 1）をフォールバックに
    final frontCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.length > 1 ? _cameras[1] : _cameras.first,
    );
    
    inCameraController = CameraController(
      frontCamera, 
      ResolutionPreset.medium, 
      enableAudio: false,
    );

    try {
      await inCameraController?.initialize();
    } catch (e) {
      print("Error initializing in-camera: $e");
    }

    // アウトカメラは初期化時（常時）起動せず、必要になった瞬間にのみ起動します。
  }

  /// アウトカメラで静止画を撮影
  Future<XFile?> captureOutCameraImage() async {
    // 1. Androidデュアルカメラ仕様の問題（リアがフロントを上書きする現象）を防ぐため、
    // まず完全にフロントカメラ（インカメラ）を破棄し、ハードウェアロックを解除します。
    if (inCameraController != null) {
      try {
        await inCameraController!.dispose();
      } catch (e) {
        print("Error during in-camera dispose before capturing: $e");
      } finally {
        inCameraController = null;
      }
    }

    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
    }
    if (_cameras.isEmpty) return null;

    // 2. 風景保存用のアウトカメラを探して初期化します
    final backCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );
    
    outCameraController = CameraController(
      backCamera, 
      ResolutionPreset.high, 
      enableAudio: false,
    );
    
    try {
      await outCameraController?.initialize();
    } catch (e) {
      print("Error initializing out-camera for capture: $e");
      return null;
    }

    // 3. 撮影を実行
    XFile? capturedImage;
    if (outCameraController != null && outCameraController!.value.isInitialized) {
      try {
        capturedImage = await outCameraController!.takePicture();
        // 撮影直後に即座にdisposeすると、ネイティブ側（特にオートフォーカス解除時など）で
        // "CameraDevice was already closed" エラーが発生してクラッシュする場合があるため、
        // わずかなディレイを置いて後処理を待機します。（特にPixelなどの端末で有効）
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        print("Error taking picture: $e");
      }
    }

    // 4. 重複起動を防ぐため、撮影後は即座にアウトカメラを破棄します
    try {
      if (outCameraController != null) {
        await outCameraController!.dispose();
      }
    } catch (e) {
      print("Error disposing out-camera after capture: $e");
    } finally {
      outCameraController = null;
    }

    return capturedImage;
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
