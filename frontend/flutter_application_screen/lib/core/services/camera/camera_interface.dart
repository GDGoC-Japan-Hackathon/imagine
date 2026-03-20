import 'package:camera/camera.dart';

/// カメラ操作の抽象インターフェース
abstract class BaseCameraService {
  /// カメラの初期化
  Future<void> initialize({bool force = false});
  
  /// アウトカメラ（背面/外部）による画像キャプチャ
  Future<XFile?> captureOutCameraImage();
  
  /// リソースの解放
  Future<void> dispose();
  
  /// 現在の状態が初期化済みかどうか
  bool get isInitialized;
}
