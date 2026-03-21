import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'camera_interface.dart';
import 'local_camera_service.dart';
import 'network_camera_service.dart';

/// アプリケーション内でカメラ操作を行うメインのエントリポイント。
/// デバイスの状態に応じて Local または Network の適切な実装を選択します。
class CameraService implements BaseCameraService {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  final LocalCameraService _local = LocalCameraService();
  final NetworkCameraService _network = NetworkCameraService();
  
  bool _isNetworkMode = false;

  bool get isNetworkMode => _isNetworkMode;
  BaseCameraService get _activeService => _isNetworkMode ? _network : _local;

  /// カメラ初期化前に AAOS 環境かどうかを判定します。
  /// パーミッション要求の制御や MediaPipe デリゲート選択に使用。
  Future<bool> checkIsAutomotive() async {
    return await _local.checkIsAutomotive();
  }

  /// ローカルカメラが見つからない場合に自動的にネットワークモードへフォールバックします。
  @override
  Future<void> initialize({bool force = false}) async {
    try {
      await _local.initialize(force: force);
      _isNetworkMode = false;
    } catch (e) {
      // ローカルカメラ失敗時にネットワークモードを試行
      try {
        await _network.initialize(force: force);
        _isNetworkMode = true;
      } catch (networkError) {
        // 両方失敗した場合はローカル側のエラーを再スロー（根本原因を伝えるため）
        rethrow;
      }
    }
  }

  @override
  Future<XFile?> captureOutCameraImage() => _activeService.captureOutCameraImage();

  @override
  Future<void> dispose() async {
    await _local.dispose();
    await _network.dispose();
  }

  @override
  bool get isInitialized => _activeService.isInitialized;

  // 既存のコードとの互換性のためのゲッター
  CameraController? get inCameraController => _local.frontCameraController;
  CameraController? get outCameraController => _local.backCameraController;
  
  /// ネットワークカメラからの画像ストリーム。型安全性のために Uint8List を明示します。
  Stream<Uint8List>? get networkImageStream => _network.imageStream;
  
  bool get isAutomotive => _local.isAutomotive;
}
