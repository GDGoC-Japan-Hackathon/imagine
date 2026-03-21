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

/// WebSocket繧剃ｻ九＠縺溘ロ繝・ヨ繝ｯ繝ｼ繧ｯ繧ｫ繝｡繝ｩ縺ｨ騾壻ｿ｡縺吶ｋ繧ｵ繝ｼ繝薙せ縺ｮ螳溯｣・class NetworkCameraService implements BaseCameraService {
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
      
      // 繝輔Ο繝ｳ繝医き繝｡繝ｩ・磯｡碑ｪ崎ｭ倡畑・峨∈縺ｮ蛻・崛繧定ｦ∵ｱ・      _channel!.sink.add(jsonEncode({"command": "switch_camera", "lensDirection": "front"}));
      
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
      throw CameraException("繝阪ャ繝医Ρ繝ｼ繧ｯ繧ｫ繝｡繝ｩ縺ｸ縺ｮ謗･邯壹↓螟ｱ謨励＠縺ｾ縺励◆: $e");
    }
  }

  @override
  Future<XFile?> captureOutCameraImage() async {
    if (_channel == null || _streamController == null) return null;

    try {
      // 閭碁擇繧ｫ繝｡繝ｩ縺ｫ蛻・ｊ譖ｿ縺域欠遉ｺ
      _channel!.sink.add(jsonEncode({"command": "switch_camera", "lensDirection": "back"}));
      await Future.delayed(AppConstants.networkCaptureSwitchDelay);
      
      // 譛譁ｰ縺ｮ繝輔Ξ繝ｼ繝繧貞叙蠕・      final jpegBytes = await imageStream!
          .take(AppConstants.networkCaptureSkipFrames)
          .last
          .timeout(AppConstants.networkCaptureTimeout);
          
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/out_network_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(jpegBytes);
      
      // 蜈・↓謌ｻ縺・      _channel!.sink.add(jsonEncode({"command": "switch_camera", "lensDirection": "front"}));
      
      return XFile(file.path);
    } catch (e) {
      _channel?.sink.add(jsonEncode({"command": "switch_camera", "lensDirection": "front"}));
      throw CameraException("繝阪ャ繝医Ρ繝ｼ繧ｯ繧ｫ繝｡繝ｩ縺ｧ縺ｮ謦ｮ蠖ｱ縺ｫ螟ｱ謨励＠縺ｾ縺励◆: $e");
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
