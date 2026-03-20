import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants/app_constants.dart';

/// カメラの初期化、管理、およびキャプチャ機能を担当するサービス。
/// 通常のローカルカメラと、ネットワーク経由のリレーカメラの両方をサポートします。
class CameraService {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  static const MethodChannel _channel = MethodChannel('com.example.imagine/mediapipe');
  bool _isAutomotiveCache = false;
  bool get isAutomotive => _isAutomotiveCache;

  /// インカメラ（主に顔認識用）のコントローラー
  CameraController? inCameraController;
  /// アウトカメラ（主に景色撮影用）のコントローラー
  CameraController? outCameraController;
  List<CameraDescription> _cameras = [];

  /// 現在ネットワークモード（リレーサーバー経由）で動作しているかどうか
  bool isNetworkMode = false;
  WebSocketChannel? _networkChannel;
  StreamController<Uint8List>? _networkStreamController;
  
  /// ネットワークカメラからの画像ストリーム
  Stream<Uint8List>? get networkImageStream => _networkStreamController?.stream;

  /// カメラサービスを初期化します。
  /// [force] が true の場合、既存のコントローラーを破棄して再初期化を強制します。
  Future<void> initialize({bool force = false}) async {
    // 既に初期化されており、強制再起動でない場合はスキップ
    if (!force && 
        inCameraController != null && inCameraController!.value.isInitialized) {
      return;
    }

    // 既存のコントローラーがあれば確実に解放する
    await dispose();
    
    _cameras = await availableCameras();
    
    // USBカメラの認識に時間がかかる場合があるため、空なら一度だけリトライ
    if (_cameras.isEmpty) {
      debugPrint("No cameras found. Retrying in ${AppConstants.cameraRetryDelay.inSeconds}s...");
      await Future.delayed(AppConstants.cameraRetryDelay);
      _cameras = await availableCameras();
    }

    debugPrint("===== CAMERA INIT DEBUG =====");
    debugPrint("Found ${_cameras.length} cameras available.");
    for (var i = 0; i < _cameras.length; i++) {
        debugPrint("Index $i: name=${_cameras[i].name}, lens=${_cameras[i].lensDirection}, sensorOrientation=${_cameras[i].sensorOrientation}");
    }
    debugPrint("=============================");

    if (_cameras.isEmpty) {
      debugPrint("No cameras found after retry. Falling back to Network WebSocket Mode.");
      isNetworkMode = true;
      _networkStreamController = StreamController<Uint8List>.broadcast();
      _connectToRelay();
      return;
    }
    
    isNetworkMode = false;
    
    try {
      _isAutomotiveCache = await _channel.invokeMethod('isAutomotiveOS') ?? false;
    } catch (e) {
      debugPrint("Failed to check automotive os: $e");
    }

    CameraDescription selectedInCamera;
    
    // .envから手動インデックス設定を取得
    final int manualInIndex = int.tryParse(dotenv.env['IN_CAMERA_INDEX'] ?? '${AppConstants.defaultManualIndex}') ?? AppConstants.defaultManualIndex;
    
    if (manualInIndex != AppConstants.defaultManualIndex && manualInIndex < _cameras.length) {
      // 手動指定がある場合はそれを優先
      selectedInCamera = _cameras[manualInIndex];
    } else if (_cameras.length <= 1) {
      // カメラが1台しかない場合は、その唯一のカメラを使用
      selectedInCamera = _cameras.first;
    } else if (_isAutomotiveCache) {
      // Android Automotive (車載機) の場合のオートロジック: USBカメラ(external)を最優先
      selectedInCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.external,
        orElse: () => _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        ),
      );
    } else {
      // スマートフォン単体等の場合のロジック（フロント優先）
      selectedInCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
    }
    
    inCameraController = CameraController(
      selectedInCamera, 
      ResolutionPreset.medium, 
      enableAudio: false,
    );

    try {
      await inCameraController?.initialize();
    } catch (e) {
      debugPrint("Error initializing in-camera: $e");
    }

    // アウトカメラは初期化時（常時）起動せず、必要になった瞬間にのみ起動します。
  }

  /// アウトカメラ（またはネットワーク経由の背面カメラ）で静止画を撮影します。
  Future<XFile?> captureOutCameraImage() async {
    if (isNetworkMode) {
      return await _captureNetworkImage();
    }
    return await _captureLocalOutCameraImage();
  }

  /// ネットワークリレー経由で画像をキャプチャします。
  Future<XFile?> _captureNetworkImage() async {
    if (_networkChannel == null || _networkStreamController == null) return null;

    try {
      // 背面カメラに切り替え指示
      _networkChannel!.sink.add(jsonEncode({"command": "switch_camera", "lensDirection": "back"}));
      // カメラハードウェアの物理的な切り替えを待機
      await Future.delayed(AppConstants.networkCaptureSwitchDelay);
      
      // 前面のバッファ残りを避けるため、数フレームスキップして最新を取得
      final jpegBytes = await networkImageStream!
          .take(AppConstants.networkCaptureSkipFrames)
          .last
          .timeout(AppConstants.networkCaptureTimeout);
          
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/out_network_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(jpegBytes);
      
      // 顔変換用にフロントカメラに戻す
      _networkChannel!.sink.add(jsonEncode({"command": "switch_camera", "lensDirection": "front"}));
      
      return XFile(file.path);
    } catch (e) {
      debugPrint("Failed to capture network image: $e");
      // エラー時もフロントカメラへの復帰を試みる
      _networkChannel?.sink.add(jsonEncode({"command": "switch_camera", "lensDirection": "front"}));
      return null;
    }
  }

  /// ローカルのアウトカメラを使用して画像をキャプチャします。
  Future<XFile?> _captureLocalOutCameraImage() async {
    // 1. Androidデュアルカメラ仕様の問題（リアがフロントを上書きする現象）を防ぐため、
    // まず完全にフロントカメラ（インカメラ）を破棄し、ハードウェアロックを解除します。
    if (inCameraController != null) {
      try {
        await inCameraController!.dispose();
      } catch (e) {
        debugPrint("Error during in-camera dispose before capturing: $e");
      } finally {
        inCameraController = null;
      }
    }

    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
    }
    if (_cameras.isEmpty) return null;

    CameraDescription selectedOutCamera;
    
    // .envから手動インデックス設定を取得
    final int manualOutIndex = int.tryParse(dotenv.env['OUT_CAMERA_INDEX'] ?? '${AppConstants.defaultManualIndex}') ?? AppConstants.defaultManualIndex;

    if (manualOutIndex != AppConstants.defaultManualIndex && manualOutIndex < _cameras.length) {
      // 手動指定がある場合はそれを優先
      selectedOutCamera = _cameras[manualOutIndex];
    } else if (_cameras.length <= 1) {
      // カメラが1台しかない場合は同じカメラを使う
      selectedOutCamera = _cameras.first;
    } else if (_isAutomotiveCache) {
      // 車載機の場合は back よりも external を優先して探す
      selectedOutCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.external,
        orElse: () => _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras.first,
        ),
      );
    } else {
      // 一般デバイスの場合は back を優先
      selectedOutCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
    }
    
    outCameraController = CameraController(
      selectedOutCamera, 
      ResolutionPreset.high, 
      enableAudio: false,
    );
    
    try {
      await outCameraController?.initialize();
    } catch (e) {
      debugPrint("Error initializing out-camera for capture: $e");
      return null;
    }

    // 撮影を実行
    XFile? capturedImage;
    if (outCameraController != null && outCameraController!.value.isInitialized) {
      try {
        capturedImage = await outCameraController!.takePicture();
        // 撮影直後に即座にdisposeするとクラッシュする場合があるため、わずかなディレイを置く
        await Future.delayed(AppConstants.cameraCaptureDelay);
      } catch (e) {
        debugPrint("Error taking picture: $e");
      }
    }

    // 重複起動を防ぐため、撮影後は即座にアウトカメラを破棄します
    try {
      if (outCameraController != null) {
        await outCameraController!.dispose();
      }
    } catch (e) {
      debugPrint("Error disposing out-camera after capture: $e");
    } finally {
      outCameraController = null;
    }

    return capturedImage;
  }

  void _connectToRelay() {
    final url = dotenv.env['RELAY_WS_URL'] ?? AppConstants.defaultRelayWsUrl;
    try {
      _networkChannel = WebSocketChannel.connect(Uri.parse(url));
      // 初期状態として顔認識用のフロントカメラを要求
      _networkChannel!.sink.add(jsonEncode({"command": "switch_camera", "lensDirection": "front"}));
      
      _networkChannel!.stream.listen((message) {
        if (message is Uint8List) {
          _networkStreamController?.add(message);
        }
      }, onDone: () {
        debugPrint("Network camera disconnected.");
      }, onError: (e) {
        debugPrint("Network camera error: $e");
      });
    } catch (e) {
      debugPrint("Failed to connect to network relay: $e");
    }
  }

  /// 全てのカメラリソースとネットワーク接続を解放します。
  Future<void> dispose() async {
    try {
      if (inCameraController != null) {
        await inCameraController!.dispose();
      }
    } catch (e) {
      debugPrint("Error during in-camera dispose: $e");
    } finally {
      inCameraController = null;
    }

    try {
      if (outCameraController != null) {
        await outCameraController!.dispose();
      }
    } catch (e) {
      debugPrint("Error during out-camera dispose: $e");
    } finally {
      outCameraController = null;
    }

    _networkChannel?.sink.close();
    _networkChannel = null;
    await _networkStreamController?.close();
    _networkStreamController = null;
  }
}
