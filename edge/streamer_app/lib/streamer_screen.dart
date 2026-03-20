import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Streamer スクリーン
/// スマートフォンのカメラ映像をキャプチャし、WebSocket 経由でリレーサーバーへ送信します。
/// Dashboard 側 (AAOS) からのコマンドを受け取り、使用カメラの切り替えも行います。
class StreamerScreen extends StatefulWidget {
  const StreamerScreen({super.key});

  @override
  State<StreamerScreen> createState() => _StreamerScreenState();
}

class _StreamerScreenState extends State<StreamerScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _isStreaming = false;
  bool _isProcessingFrame = false;
  String _statusMessage = "初期化中...";

  /// YUV → JPEG 変換用の MethodChannel
  /// ネイティブ側 (MainActivity.kt) の compressYuvToJpeg メソッドを呼び出します。
  static const MethodChannel _channelNative =
      MethodChannel('com.example.imagine/mediapipe');

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  /// アプリ初期化処理
  /// カメラ一覧の取得 → WebSocket 接続 → カメラ初期化の順に行います。
  Future<void> _initApp() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _statusMessage = "カメラが見つかりませんでした。");
        return;
      }

      // .env から WebSocket URL を読み込み
      final url = dotenv.env['RELAY_WS_URL'] ?? 'ws://127.0.0.1:8080';
      _connectWebSocket(url);

      // デフォルトはフロントカメラで初期化（顔検出用）
      await _initCamera(_cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      ));
    } catch (e) {
      if (mounted) setState(() => _statusMessage = "エラー: $e");
    }
  }

  /// WebSocket 接続処理
  /// 接続後は Dashboard 側からの JSON コマンド（カメラ切り替えなど）を待ち受けます。
  void _connectWebSocket(String url) {
    _reconnectTimer?.cancel();
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      if (mounted) setState(() => _statusMessage = "接続済み: $url");

      _channel?.stream.listen(
        (message) {
          if (message is String) {
            debugPrint("Received command: $message");
            _handleCommand(message);
          } else if (message is Uint8List || message is List<int>) {
            // リレーサーバー経由でバイナリ (Buffer) として届いた場合を考慮
            try {
              final decoded = utf8.decode(message as List<int>);
              debugPrint("Received binary command (decoded): $decoded");
              _handleCommand(decoded);
            } catch (e) {
              // 映像データなどの純粋なバイナリの場合は無視
            }
          }
        },
        onDone: () {
          if (mounted) {
            setState(() => _statusMessage = "WebSocket 切断 - 5秒後に再接続します");
            _scheduleReconnect(url);
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() => _statusMessage = "WebSocket エラー: $e - 5秒後に再接続します");
            _scheduleReconnect(url);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = "WS 接続エラー: $e - 5秒後に再接続します");
        _scheduleReconnect(url);
      }
    }
  }

  /// 再接続をスケジュール
  void _scheduleReconnect(String url) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        debugPrint("Attempting to reconnect to $url...");
        _connectWebSocket(url);
      }
    });
  }

  /// Dashboard 側から受信したコマンドを処理
  /// 現在対応しているコマンド: switch_camera
  Future<void> _handleCommand(String message) async {
    try {
      final data = jsonDecode(message);
      if (data['command'] == 'switch_camera') {
        final lensRaw = data['lensDirection'];
        final targetLens = lensRaw == 'back'
            ? CameraLensDirection.back
            : CameraLensDirection.front;

        final targetCamera = _cameras.firstWhere(
          (c) => c.lensDirection == targetLens,
          orElse: () => _cameras.first,
        );
        await _initCamera(targetCamera);
      }
    } catch (e) {
      debugPrint("無効なコマンド: $message");
    }
  }

  /// 指定されたカメラの初期化と映像ストリーミング開始
  Future<void> _initCamera(CameraDescription description) async {
    // 既存のコントローラーを解放
    if (_controller != null) {
      final oldController = _controller!;
      _controller = null; 
      if (mounted) setState(() {});

      if (oldController.value.isStreamingImages) {
        try {
          await oldController.stopImageStream();
        } catch (e) {
          debugPrint("Error stopping image stream: $e");
        }
      }
      try {
        await oldController.dispose();
      } catch (e) {
        debugPrint("Error disposing controller: $e");
      }
    }

    final newController = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller = newController;

    try {
      await newController.initialize();
      if (mounted) setState(() {});
      _startStreaming();
    } catch (e) {
      if (mounted) setState(() => _statusMessage = "カメラエラー: $e");
    }
  }

  /// カメライメージストリームの開始
  /// 各フレームを YUV → JPEG に変換してリレーサーバーへ送信します。
  /// 約 15fps (66ms) に制限して負荷を抑えます。
  void _startStreaming() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isStreamingImages) return;

    _controller!.startImageStream((CameraImage image) async {
      if (_isProcessingFrame || _channel == null) return;
      _isProcessingFrame = true;

      try {
        final yPlane = image.planes[0];
        final uPlane = image.planes[1];
        final vPlane = image.planes[2];

        // ネイティブ側で YUV → JPEG 変換
        final jpegBytes = await _channelNative.invokeMethod<Uint8List>(
            'compressYuvToJpeg', {
          'y': yPlane.bytes,
          'u': uPlane.bytes,
          'v': vPlane.bytes,
          'yRowStride': yPlane.bytesPerRow,
          'uvRowStride': uPlane.bytesPerRow,
          'uvPixelStride': uPlane.bytesPerPixel,
          'width': image.width,
          'height': image.height,
        });

        if (jpegBytes != null && _channel != null) {
          _channel!.sink.add(jpegBytes);
        }
      } catch (e) {
        debugPrint("JPEG 変換エラー: $e");
      } finally {
        // ~15fps に制限
        await Future.delayed(const Duration(milliseconds: 66));
        _isProcessingFrame = false;
      }
    });

    if (mounted) setState(() => _isStreaming = true);
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    if (_isStreaming && _controller != null) {
      _controller!.stopImageStream();
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // カメラプレビュー
          if (_controller != null && _controller!.value.isInitialized)
            CameraPreview(_controller!)
          else
            Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white24),
                    SizedBox(height: 16),
                    Text(
                      "カメラ切り替え中...",
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ステータスバー
                Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        "STREAMER MODE",
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Imagine — カメラ中継アプリ",
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusMessage,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // ストリーミング中インジケーター
                if (_isStreaming)
                  const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.red),
                          SizedBox(height: 12),
                          Text(
                            "配信中",
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
