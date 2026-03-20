import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart' hide CameraException;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common_widgets/glowing_orb.dart';
import '../analysis/analysis_screen.dart';
import '../analysis/analysis_model.dart';
import '../camera/models/face_vector.dart';
import '../camera/services/camera_service.dart';
import '../camera/services/face_tracker_service.dart';
import '../camera/services/gemini_service.dart';
import '../camera/services/mediapipe_service.dart';
import '../camera/models/test_scenery.dart';
import '../../core/services/sound_service.dart';
import '../../core/errors/exceptions.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_constants.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final GlobalKey<GlowingOrbState> _orbKey = GlobalKey<GlowingOrbState>();

  final CameraService _cameraService = CameraService();
  final FaceTrackerService _faceTracker = FaceTrackerService();
  final GeminiService _geminiService = GeminiService();
  final MediapipeService _mediapipeService = MediapipeService();
  
  StreamSubscription? _faceSubscription;
  StreamSubscription<Uint8List>? _networkImageSubscription;

  bool _isProcessing = false;
  bool _skipFaceDetection = false;
  bool _debugMode = false;
  bool _showDebugCamera = false;
  bool _showDebugFaceImage = false;
  Uint8List? _debugFaceImage;
  String _statusMessage = "起動中";
  
  // ユーザーガイド・解析用
  bool _isAnalyzing = false;
  DateTime _lastAnalysisTime = DateTime.now();
  DateTime _lastFaceDetectedTime = DateTime.now();
  bool _hasFaceInFrame = false;
  bool _isCameraStreaming = false;
  bool _isCameraInitialized = false;
  bool _didPlayStableSound = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {

    // アプリがバックグラウンドに回った、またはスリープした際の処理
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopAllServices(); // 非同期で停止処理を開始
    } 
    // アプリが復帰した際の処理
    else if (state == AppLifecycleState.resumed) {
      if (!_isProcessing && !_isCameraInitialized) {
        // スリープやバックグラウンドから復帰した際は、確実にカメラを引き直すために強制リセット
        _initApp(force: true);
      }
    }
  }

  Future<void> _stopAllServices() async {
    try {
      if (_isCameraStreaming) {
        _isCameraStreaming = false;
        if (!_cameraService.isNetworkMode) {
          await _cameraService.inCameraController?.stopImageStream();
        } else {
          await _networkImageSubscription?.cancel();
        }
      }
      await _cameraService.dispose();
      _isCameraInitialized = false;
      _faceSubscription?.cancel();
    } catch (e) {
      debugPrint("Error stopping services: $e");
    }
  }

  Future<void> _initApp({bool force = false}) async {
    // 既に初期化処理が進行中の場合は、強制実行(force)でない限りスキップ
    if (_isProcessing && !force) return;
    _isProcessing = true;
    
    try {
      // 権限をまとめてリクエスト
      Map<Permission, PermissionStatus> statuses = {};
      try {
        statuses = await [
          Permission.camera,
          Permission.microphone,
        ].request();
      } catch (e) {
        debugPrint("Permission request failed: $e");
      }

      if (statuses.isEmpty || statuses[Permission.camera]?.isDenied == true) {
        setState(() {
          _statusMessage = "カメラの権限が必要です";
          _isProcessing = false;
        });
        _showErrorSnackBar("カメラの利用が許可されていません（権限設定を確認してください）");
        return;
      }

      await _cameraService.initialize(force: force);
      _isCameraInitialized = true;

      // ネットワークモードへのフォールバックを通知
      if (_cameraService.isNetworkMode) {
        _showInfoSnackBar("ローカルカメラが見つかりません。ネットワークモードで起動しました。", title: "通知");
      }

      // APIキーの読み込み (.env ファイルから取得)
      _geminiService.initialize(
        dotenv.env['GEMINI_API_KEY'] ?? '',
        dotenv.env['GOOGLE_SERVICE_ACCOUNT_JSON'] ?? '',
      ); 
      _skipFaceDetection = dotenv.env['SKIP_FACE_DETECTION']?.toLowerCase() == 'true';
      _debugMode = dotenv.env['DEBUG_MODE']?.toLowerCase() == 'true';
      _showDebugCamera = dotenv.env['DEBUG_SHOW_CAMERA']?.toLowerCase() == 'true';
      _showDebugFaceImage = dotenv.env['DEBUG_SHOW_FACE_IMAGE']?.toLowerCase() == 'true';
      
      // AAOS環境（Raspberry Pi等）やネットワークモードでは GPU が不安定な場合があるため、CPUデリゲート(0) を検討
      final String? envDelegate = dotenv.env['MEDIAPIPE_DELEGATE'];
      final int defaultDelegate = (_cameraService.isAutomotive || _cameraService.isNetworkMode) ? 0 : 1;
      final int delegate = envDelegate != null ? (int.tryParse(envDelegate) ?? defaultDelegate) : defaultDelegate;

      await _mediapipeService.initialize(
        debugShowFaceImage: _showDebugFaceImage,
        delegate: delegate,
      );
      
      if (_skipFaceDetection) {
        setState(() => _statusMessage = "自動撮影テスト中...");
        _autoTriggerCapture();
      } else {
        setState(() => _statusMessage = "景色に注目してください");
        _startFaceTracking();
        _startGuidanceTimer();
      }
      _isProcessing = false; // 初期化完了
    } catch (e) {
      _isProcessing = false;
      debugPrint("Initialization error: $e");
      setState(() => _statusMessage = "カメラの初期化に失敗しました");
      
      final String message = e is AppException ? e.message : "カメラの初期化に失敗しました: $e";
      _showErrorSnackBar(message);
    }
  }

  /// ユーザーを誘導するためのタイマーを開始します。
  void _startGuidanceTimer() {
    Future.doWhile(() async {
      await Future.delayed(AppConstants.guidanceTimerInterval);
      if (!mounted || _isProcessing || _skipFaceDetection) return false;
      
      final now = DateTime.now();
      if (now.difference(_lastFaceDetectedTime).inSeconds > AppConstants.guidanceNoFaceThresholdSeconds && !_hasFaceInFrame) {
        setState(() {
          _statusMessage = "外の景色を眺めてください";
        });
      }
      return true;
    });
  }

  void _autoTriggerCapture() {
    // カメラの準備とフォーカス安定のために2秒待って自動撮影
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted && _isProcessing == false) {
        _navigateToGeneratingAndAnalyze(const FaceVector(0, 0));
      }
    });
  }

  /// 顔認識とトラッキングロジックを開始します。
  void _startFaceTracking() {
    if (_cameraService.isNetworkMode) {
      if (_cameraService.networkImageStream == null) return;
    } else {
      if (_cameraService.inCameraController == null) return;
      if (_cameraService.inCameraController!.value.isStreamingImages) return;
    }

    // MediaPipe からのストリームを購読
    _faceSubscription = _mediapipeService.faceStream.listen((data) {
      if (_isProcessing || !mounted) return;
      _handleFaceStreamData(data);
    });

    _startImageStreamDetection();
  }

  /// MediaPipeからのストリームデータを処理します。
  void _handleFaceStreamData(Map<String, dynamic> data) {
    // ネストされた Map の型を安全にキャスト
    final rawLandmarks = data['landmarks'] as List?;
    final landmarks = rawLandmarks?.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    // デバッグ用画像の更新
    if (_showDebugFaceImage && data.containsKey('faceImage')) {
      setState(() {
        _debugFaceImage = data['faceImage'] as Uint8List?;
      });
    }

    if (landmarks == null || landmarks.isEmpty) {
      _handleFaceLost();
      return;
    }

    _handleFaceDetected(landmarks, data);
  }

  /// 顔をロストした際の猶予処理を行います。
  void _handleFaceLost() {
    final now = DateTime.now();
    if (_hasFaceInFrame && now.difference(_lastFaceDetectedTime) > AppConstants.faceLostGracePeriod) {
      if (mounted) {
        setState(() {
          _hasFaceInFrame = false;
        });
        _orbKey.currentState?.setTracking(false);
        _orbKey.currentState?.setFaceOffset(null);
      }
    }
  }

  /// 検出された顔のランドマークを元にトラッキング状態を更新します。
  void _handleFaceDetected(List<Map<String, dynamic>> landmarks, Map<String, dynamic> data) {
    _lastFaceDetectedTime = DateTime.now();
    if (!_hasFaceInFrame) {
      setState(() => _hasFaceInFrame = true);
      _orbKey.currentState?.setTracking(true);
    }

    // 478個のランドマークから Euler角 (Yaw/Pitch) を簡易推定
    final currentFaceVector = _estimateFaceVector(landmarks);
    if (currentFaceVector == null) return;

    final stableProgress = _faceTracker.getStableProgress([currentFaceVector]);

    // ロスト復帰や新規認識時にサウンドフラグをリセット
    if (stableProgress < 0.1) {
      _didPlayStableSound = false;
    }
    
    // Orbの状態更新
    final faceOffset = Offset(
      (currentFaceVector.x / 25.0).clamp(-1.0, 1.0),
      (currentFaceVector.y / 20.0).clamp(-1.0, 1.0)
    );
    _orbKey.currentState?.setFaceOffset(faceOffset);
    _orbKey.currentState?.setProgress(stableProgress);

    // 表情の反映
    final rawBlendshapes = data['blendshapes'] as List?;
    if (rawBlendshapes != null) {
      final blendshapes = rawBlendshapes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final scores = { for (var e in blendshapes) e['category'] as String : (e['score'] as num).toDouble() };
      _orbKey.currentState?.setBlendshapes(scores);
    }

    if (stableProgress >= 1.0) {
      _triggerSuccessfulDetection(currentFaceVector);
    } else {
      _updateStatusByProgress(stableProgress);
    }
  }

  /// ランドマークから顔の向き（FaceVector）を推定します。
  FaceVector? _estimateFaceVector(List<Map<String, dynamic>> landmarks) {
    // Point 4: Nose Tip, Point 33: Left Eye, Point 263: Right Eye
    final nose = landmarks[4];
    final eyeLeft = landmarks[33];
    final eyeRight = landmarks[263];
    
    // 顔の幅をユークリッド距離で計算
    final dx = eyeRight['x'] - eyeLeft['x'];
    final dy = eyeRight['y'] - eyeLeft['y'];
    final faceWidth = math.sqrt(dx * dx + dy * dy);
    
    if (faceWidth < AppConstants.faceWidthMinThreshold) return null;

    final eyeCenterX = (eyeLeft['x'] + eyeRight['x']) / 2;
    final yaw = (nose['x'] - eyeCenterX) / faceWidth * 30.0;

    final eyeCenterY = (eyeLeft['y'] + eyeRight['y']) / 2;
    final pitch = (nose['y'] - eyeCenterY) / faceWidth * 30.0;

    return FaceVector(yaw, pitch);
  }

  /// 安定した顔検出が完了した際の処理を行います。
  void _triggerSuccessfulDetection(FaceVector vector) {
    if (!_didPlayStableSound) {
      _playSuccessFeedback();
      _didPlayStableSound = true;
    }

    _isProcessing = true;
    _orbKey.currentState?.setStable(true);
    _orbKey.currentState?.setProgress(1.0);
    
    setState(() {
      _statusMessage = "気づきをキャッチしました";
    });

    _captureAndHandleTransition(vector);
  }

  /// 進捗に応じたステータスメッセージの更新
  void _updateStatusByProgress(double progress) {
    if (progress > 0) {
      final clampedProgress = progress.clamp(0.0, 1.0);
      _orbKey.currentState?.setProgress(clampedProgress);
      setState(() {
        _statusMessage = "あなたの視線に寄り添っています...";
      });
    } else {
      _orbKey.currentState?.setProgress(0.0);
      setState(() {
        _statusMessage = "心の動きを解析しています";
      });
    }
  }

  /// カメラストリームの開始とMediaPipeへの継続的な送信を開始します。
  void _startImageStreamDetection() {
    try {
      if (_isCameraStreaming) return;
      _isCameraStreaming = true;
      
      if (_cameraService.isNetworkMode) {
        _networkImageSubscription = _cameraService.networkImageStream?.listen((Uint8List jpegBytes) {
          if (_isProcessing || _isAnalyzing || !mounted || !_isCameraStreaming) return;
          
          final now = DateTime.now();
          if (now.difference(_lastAnalysisTime) < AppConstants.mediapipeProcessingInterval) return;

          _isAnalyzing = true;
          _lastAnalysisTime = now;

          _mediapipeService.detectJpeg(jpegBytes, isFront: true, rotation: 0).then((_) {
            _isAnalyzing = false;
          }).catchError((e) {
            _isAnalyzing = false;
            debugPrint("MediaPipe network detection error: $e");
          });
        });
      } else {
        _cameraService.inCameraController?.startImageStream((CameraImage image) {
          if (_isProcessing || _isAnalyzing || !mounted || !_isCameraStreaming) return;
          
          final now = DateTime.now();
          if (now.difference(_lastAnalysisTime) < AppConstants.mediapipeProcessingInterval) return;

          _isAnalyzing = true;
          _lastAnalysisTime = now;

          final rotation = _cameraService.inCameraController?.description.sensorOrientation ?? 0;
          _mediapipeService.detect(image, isFront: true, rotation: rotation).then((_) {
            _isAnalyzing = false;
          }).catchError((e) {
            _isAnalyzing = false;
            debugPrint("MediaPipe detection error: $e");
          });
        });
      }
    } catch (e) {
      _isCameraStreaming = false;
      debugPrint("Error starting image stream: $e");
    }
  }

  void _playSuccessFeedback() {
    // 成功時のサウンドと振動
    HapticFeedback.heavyImpact();
    // Android システムサウンド: カメラAFロック音（FOCUS_COMPLETE）
    SoundService.playFaceDetected();
  }

  Future<void> _captureAndHandleTransition(FaceVector targetVector) async {
    // 1. まずインカメラのストリームを止める
    try {
      if (_isCameraStreaming) {
        _isCameraStreaming = false;
        if (!_cameraService.isNetworkMode && _cameraService.inCameraController != null) {
          if (_cameraService.inCameraController!.value.isStreamingImages) {
            await _cameraService.inCameraController?.stopImageStream();
          }
        } else if (_cameraService.isNetworkMode) {
          await _networkImageSubscription?.cancel();
        }
        // 分析画面へ移る際、顔検出機能を明示的に一時停止（クローズ）する
        await _mediapipeService.close();
      }
    } catch (e) {
      debugPrint("Error stopping image stream: $e");
    }
    
    try {
      // 2. アウトカメラで撮影
      final capturedImage = await _cameraService.captureOutCameraImage();
      
      if (mounted) {
        _navigateToGeneratingAndAnalyze(targetVector, capturedImage: capturedImage);
      }
    } catch (e) {
      debugPrint("Error during capture and transition: $e");
      if (mounted) {
        final String message = e is AppException ? e.message : "風景の撮影に失敗しました: $e";
        _showErrorSnackBar(message);
        // 失敗した場合はトラッキング状態をリセットして通常モードに戻る
        _resetTrackingState();
        _startFaceTracking();
      }
    }
  }


  void _navigateToGeneratingAndAnalyze(FaceVector targetVector, {XFile? capturedImage}) {
    final analysisFuture = _captureAndAnalyze(targetVector, preCapturedImage: capturedImage);

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => AnalysisScreen(
          analysisFuture: analysisFuture,
        ),
        transitionDuration: AppConstants.screenTransitionDuration,
        reverseTransitionDuration: AppConstants.reverseTransitionDuration,
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut), child: child);
        },
      ),
    ).then((result) {
      if (mounted) {
        // 全ての状態をリフレッシュ
        _resetTrackingState();
        
        // 解析エラーが返ってきた場合、スナックバーで表示
        if (result is String && result.startsWith('error:')) {
          final errorMessage = result.replaceFirst('error:', '');
          _showErrorSnackBar(errorMessage);
        }
        
        // Android特有の "Dead Thread" 問題を回避するため、
        // 戻ってきた時は強制的にカメラコントローラーを破棄して再作成する
        try {
          _initApp(force: true);
        } catch (e) {
          debugPrint("Error re-initializing app: $e");
          _showErrorSnackBar("アプリの再初期化に失敗しました: $e");
        }
      }
    });
  }

  void _resetTrackingState() {
    setState(() {
      _isProcessing = false;
      _didPlayStableSound = false;
      _hasFaceInFrame = false;
      _statusMessage = "景色に注目してください"; // ステータスも初期状態にリセット
    });
    _faceTracker.reset();
    _orbKey.currentState?.setTracking(false);
    _orbKey.currentState?.setProgress(0.0);
    _orbKey.currentState?.setStable(false);
  }

  void _showErrorSnackBar(String message) {
    _showSnackBar(message, isError: true);
  }

  void _showInfoSnackBar(String message, {String title = "情報"}) {
    _showSnackBar(message, isError: false, title: title);
  }

  void _showSnackBar(String message, {bool isError = false, String? title}) {
    final Color bgColor = isError 
        ? const Color(0xFF2C3E50).withValues(alpha: 0.9)
        : const Color(0xFF1ABC9C).withValues(alpha: 0.9);
    final Color iconColor = isError ? const Color(0xFFFF8B8B) : const Color(0xFFE2F063);
    final IconData icon = isError ? Icons.error_outline : Icons.info_outline;
    final String displayTitle = title ?? (isError ? (_debugMode ? "DEBUG ERROR" : "エラー") : "情報");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      message,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<AnalysisData> _captureAndAnalyze(FaceVector targetVector, {XFile? preCapturedImage}) async {
    XFile? outImage;
    FaceVector effectiveVector = targetVector;

    if (_debugMode) {
      // テストモード: アセットから画像を取得し、正規化座標をセット
      final testScenery = TestScenery.getRandom();
      final byteData = await rootBundle.load(testScenery.assetPath);
      final tempFile = File('${Directory.systemTemp.path}/test_scenery.png');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
      
      outImage = XFile(tempFile.path);
      effectiveVector = testScenery.targetVector;
      
      debugPrint("DEBUG_MODE: Using test asset ${testScenery.assetPath} at ${effectiveVector.x}, ${effectiveVector.y}");
    } else {
      outImage = preCapturedImage ?? await _cameraService.captureOutCameraImage();
    }
    
    if (outImage != null) {
      final result = await _geminiService.analyzeAndMask(File(outImage.path), effectiveVector.x, effectiveVector.y);
      
      // Geminiの結果からポリゴン情報を抽出
      final segArray = result.segData;
      List<double>? polygon;
      if (segArray.isNotEmpty && segArray[0] is Map && segArray[0]['polygon'] is List) {
        final rawPolygon = segArray[0]['polygon'] as List;
        polygon = rawPolygon.map((e) => (e as num).toDouble()).toList();
      }

      // 音声データの取得 (TTS)
      String ttsText = result.guideDesc;
      if (result.latitude != null && result.longitude != null) {
        ttsText += " 。。。 この場所に行きたいですか？";
      }
      final audioBytes = await _geminiService.synthesizeSpeech(ttsText);

      return AnalysisData(
        tag: "AI RECOGNITION",
        title: result.targetName,
        subtitle: "Analyzed by Gemini",
        description: result.guideDesc,
        imagePath: outImage.path,
        polygon: polygon,
        audioBytes: audioBytes,
        latitude: result.latitude,
        longitude: result.longitude,
      );
    } else {
      throw CameraException("撮影に失敗しました。");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _faceSubscription?.cancel();
    _mediapipeService.close();
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          final RenderBox? box = context.findRenderObject() as RenderBox?;
          if (box != null) {
            final size = box.size;
            final center = Offset(size.width / 2, size.height / 2);
            final tapDelta = event.localPosition - center;
            _orbKey.currentState?.pullTowards(tapDelta);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            SizedBox.expand(
              child: Image.asset(
                'assets/dashboard_bg.jpg',
                fit: BoxFit.cover,
              ),
            ),
            // Background overlay for car use (slightly darkens for contrast)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.1),
                    Colors.black.withValues(alpha: 0.4),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: _buildDashboardBody(),
            ),
            if (_showDebugCamera || _showDebugFaceImage) _buildDebugCameraOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugCameraOverlay() {
    final controller = _cameraService.inCameraController;
    if (controller == null || !controller.value.isInitialized) return const SizedBox.shrink();

    return Positioned(
      top: 20,
      left: 20,
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showDebugCamera) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: CameraPreview(controller),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              "FACE: ${_hasFaceInFrame ? 'DETECTED' : 'LOST'}",
              style: TextStyle(
                color: _hasFaceInFrame ? const Color(0xFFE2F063) : Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_hasFaceInFrame) ...[
              const SizedBox(height: 4),
              Text(
                "STABLE: ${(_faceTracker.currentProgress * 100).toStringAsFixed(1)}%",
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
              const SizedBox(height: 4),
              Text(
                "LAST: ${_lastFaceDetectedTime.toIso8601String().split('T').last}",
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
            if (_showDebugFaceImage && _debugFaceImage != null) ...[
              const SizedBox(height: 12),
              const Text(
                "PROCESSED AI IMAGE:",
                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(
                  _debugFaceImage!,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardBody() {
    return Row(
      children: [
        // Left side: Glowing Orb
        Expanded(
          flex: 12,
          child: Center(
            child: GlowingOrb(key: _orbKey, size: 240), // Slightly larger for car
          ),
        ),
        
        // Right side: Info and Action button
        Expanded(
          flex: 10,
          child: Padding(
            padding: const EdgeInsets.only(right: 60),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    "IMAGINE",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 48, 
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    "AI コンシェルジュ",
                    style: TextStyle(
                      color: Color(0xB3FFFFFF), // Colors.white.withValues(alpha: 0.7)
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4.0,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                
                // Status Glass Plate
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _hasFaceInFrame ? const Color(0xFFE2F063) : Colors.white24,
                              boxShadow: [
                                if (_hasFaceInFrame)
                                  const BoxShadow(color: Color(0xFFE2F063), blurRadius: 4, spreadRadius: 1),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 500),
                              layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                                return Stack(
                                  alignment: Alignment.centerLeft,
                                  children: <Widget>[
                                    ...previousChildren,
                                    ?currentChild,
                                  ],
                                );
                              },
                              transitionBuilder: (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.2),
                                      end: Offset.zero,
                                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                                    child: child,
                                  ),
                                );
                              },
                              child: Text(
                                _statusMessage.toUpperCase(),
                                key: ValueKey<String>(_statusMessage),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                                softWrap: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.2),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          _isProcessing ? "" : (_hasFaceInFrame ? "そのまま数秒間、視線を固定してください" : "気になるものを見つめるとAIが解説します"), // 認識成功時のみ非表示
                          key: ValueKey<bool>(_isProcessing || _hasFaceInFrame),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40), 
                

              ],
            ),
          ),
        ),
      ],
    );
  }
}
