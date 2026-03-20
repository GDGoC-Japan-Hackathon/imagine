import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart' hide CameraException;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../constants/app_constants.dart';
import '../../errors/exceptions.dart';
import 'camera_interface.dart';

/// WebSocketを介したネットワークカメラと通信するサービスの実装
class NetworkCameraService implements BaseCameraService {
  WebSocketChannel? _channel;
  StreamController<Uint8List>? _streamController;
  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;

  Stream<Uint8List>? get imageStream => _streamController?.stream;

  @override
  Future<void> initialize({bool force = false}) async {
    if (!force && _isInitialized) return;

    await dispose();
    
    final url = dotenv.env['RELAY_WS_URL'] ?? AppConstants.defaultRelayWsUrl;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _streamController = StreamController<Uint8List>.broadcast();
      
      // フロントカメラ（顔認識用）への切替を要求
      _channel!.sink.add(jsonEncode({"command": "switch_camera", "lensDirection": "front"}));
      
      _channel!.stream.listen((message) {
        if (message is Uint8List) {
          _streamController?.add(message);
        }
      }, onDone: () {
        debugPrint("Network camera disconnected.");
        _isInitialized = false;
      }, onError: (e) {
        debugPrint("Network camera error: $e");
        _isInitialized = false;
      });
      
      _isInitialized = true;
    } catch (e) {
      throw CameraException("ネットワークカメラへの接続に失敗しました: $e");
    }
  }

  @override
  Future<XFile?> captureOutCameraImage() async {
    if (_channel == null || _streamController == null) return null;

    try {
      // 背面カメラに切り替え指示
      _channel!.sink.add(jsonEncode({"command": "switch_camera", "lensDirection": "back"}));
      await Future.delayed(AppConstants.networkCaptureSwitchDelay);
      
      // 最新のフレームを取得
      final jpegBytes = await imageStream!
          .take(AppConstants.networkCaptureSkipFrames)
          .last
          .timeout(AppConstants.networkCaptureTimeout);
          
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/out_network_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(jpegBytes);
      
      // 元に戻す
      _channel!.sink.add(jsonEncode({"command": "switch_camera", "lensDirection": "front"}));
      
      return XFile(file.path);
    } catch (e) {
      _channel?.sink.add(jsonEncode({"command": "switch_camera", "lensDirection": "front"}));
      throw CameraException("ネットワークカメラでの撮影に失敗しました: $e");
    }
  }

  @override
  Future<void> dispose() async {
    _channel?.sink.close();
    _channel = null;
    await _streamController?.close();
    _streamController = null;
    _isInitialized = false;
  }
}
