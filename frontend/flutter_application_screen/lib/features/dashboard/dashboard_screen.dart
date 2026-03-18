import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../common_widgets/glowing_orb.dart';
import '../../common_widgets/primary_button.dart';
import '../analysis/analysis_screen.dart';
import '../analysis/analysis_model.dart';
import '../camera/models/face_vector.dart';
import '../camera/services/camera_service.dart';
import '../camera/services/face_tracker_service.dart';
import '../camera/services/gemini_service.dart';
import '../camera/services/mediapipe_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<GlowingOrbState> _orbKey = GlobalKey<GlowingOrbState>();

  final CameraService _cameraService = CameraService();
  final FaceTrackerService _faceTracker = FaceTrackerService();
  final GeminiService _geminiService = GeminiService();
  final MediapipeService _mediapipeService = MediapipeService();
  
  StreamSubscription? _faceSubscription;

  bool _isProcessing = false;
  bool _skipFaceDetection = false;
  String _statusMessage = "初期化しています...";
  
  // ユーザーガイド・解析用
  bool _isAnalyzing = false;
  DateTime _lastAnalysisTime = DateTime.now();
  DateTime _lastFaceDetectedTime = DateTime.now();
  bool _hasFaceInFrame = false;
  Rect? _detectedFaceRect;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _cameraService.initialize();
    await _mediapipeService.initialize();

    // APIキーの読み込み (.env ファイルから取得)
    _geminiService.initialize(dotenv.env['GEMINI_API_KEY'] ?? ''); 
    _skipFaceDetection = dotenv.env['SKIP_FACE_DETECTION']?.toLowerCase() == 'true';
    
    if (_skipFaceDetection) {
      setState(() => _statusMessage = "自動撮影テスト中...");
      _autoTriggerCapture();
    } else {
      setState(() => _statusMessage = "インカメラでこちらを見てください");
      _startFaceTracking();
      _startGuidanceTimer();
    }
  }

  void _startGuidanceTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || _isProcessing || _skipFaceDetection) return false;
      
      final now = DateTime.now();
      if (now.difference(_lastFaceDetectedTime).inSeconds > 5 && !_hasFaceInFrame) {
        setState(() {
          _statusMessage = "顔が検出されません。カメラに顔を向けてください";
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

  void _startFaceTracking() {
    if (_cameraService.inCameraController == null) return;
    if (_cameraService.inCameraController!.value.isStreamingImages) return;

    // MediaPipe からのストリームを購読
    _faceSubscription = _mediapipeService.faceStream.listen((data) {
      if (_isProcessing || !mounted) return;

      // ネストされた Map の型を安全にキャスト
      final rawLandmarks = data['landmarks'] as List?;
      final landmarks = rawLandmarks?.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (landmarks == null || landmarks.isEmpty) {
        // 顔ロスト時の猶予処理
        final now = DateTime.now();
        if (_hasFaceInFrame && now.difference(_lastFaceDetectedTime).inMilliseconds > 1000) {
          if (mounted) {
            setState(() {
              _hasFaceInFrame = false;
              _detectedFaceRect = null;
            });
            _orbKey.currentState?.setTracking(false);
            _orbKey.currentState?.setFaceOffset(null);
          }
        }
        return;
      }

      // 顔を検出
      _lastFaceDetectedTime = DateTime.now();
      if (!_hasFaceInFrame) {
        setState(() => _hasFaceInFrame = true);
        _orbKey.currentState?.setTracking(true);
      }

      // 478個のランドマークから Euler角 (Yaw/Pitch) を簡易推定
      // Point 4: Nose Tip, Point 152: Chin, Point 33: Left Eye, Point 263: Right Eye
      final nose = landmarks[4];
      final eyeLeft = landmarks[33];
      final eyeRight = landmarks[263];
      
      // 顔の幅を基準に水平位置を正規化
      final faceWidth = (eyeRight['x'] - eyeLeft['x']).abs();
      if (faceWidth < 0.05) return; // 小さすぎる（遠すぎる）場合はスキップ

      final eyeCenterX = (eyeLeft['x'] + eyeRight['x']) / 2;
      final yaw = (nose['x'] - eyeCenterX) / faceWidth * 30.0; // 顔の幅で割って正規化

      // 垂直方向も同様。目の高さと鼻の距離
      final eyeCenterY = (eyeLeft['y'] + eyeRight['y']) / 2;
      final pitch = (nose['y'] - eyeCenterY) / faceWidth * 30.0;

      final currentFaceVector = FaceVector(yaw, pitch);
      final stableProgress = _faceTracker.getStableProgress([currentFaceVector]);

      // Orbの状態更新
      final faceOffset = Offset(
        (yaw / 25.0).clamp(-1.0, 1.0),
        (pitch / 20.0).clamp(-1.0, 1.0)
      );
      _orbKey.currentState?.setFaceOffset(faceOffset);

      // 表情の反映
      final rawBlendshapes = data['blendshapes'] as List?;
      if (rawBlendshapes != null) {
        final blendshapes = rawBlendshapes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final scores = { for (var e in blendshapes) e['category'] as String : (e['score'] as num).toDouble() };
        _orbKey.currentState?.setBlendshapes(scores);
      }

      if (stableProgress >= 0.8) {
        _isProcessing = true;
        _orbKey.currentState?.setStable(true);
        
        setState(() {
          _statusMessage = "目線が固定されました。撮影・解析を開始します...";
        });

        // 撮影と遷移
        _captureAndHandleTransition(currentFaceVector);
      } else if (stableProgress > 0) {
        setState(() {
          // 表示上は 80% を上限とするため、現在の進捗を 0.8 で正規化して表示
          final percent = (stableProgress / 0.8 * 100).clamp(0, 100).toInt();
          _statusMessage = "視点を固定中... $percent%";
        });
      }
    });

    // カメラストリームの開始と MediaPipe への送信
    _cameraService.inCameraController?.startImageStream((CameraImage image) {
      if (_isProcessing || _isAnalyzing) return;
      
      final now = DateTime.now();
      // CPU負荷軽減のため、100ms (秒間最大10回相当) は間隔を空ける
      if (now.difference(_lastAnalysisTime).inMilliseconds < 100) return;

      _isAnalyzing = true;
      _lastAnalysisTime = now;

      // MediaPipe (Native) へ送信
      final rotation = _cameraService.inCameraController?.description.sensorOrientation ?? 0;
      _mediapipeService.detect(image, rotation: rotation).then((_) {
        _isAnalyzing = false;
      });
    });
  }

  Future<void> _captureAndHandleTransition(FaceVector targetVector) async {
    // 1. まずインカメラのストリームを止める
    try {
      if (_cameraService.inCameraController?.value.isStreamingImages ?? false) {
        await _cameraService.inCameraController?.stopImageStream();
      }
    } catch (e) {
      debugPrint("Error stopping image stream: $e");
    }
    
    // 2. アウトカメラで撮影
    final capturedImage = await _cameraService.captureOutCameraImage();
    
    if (mounted) {
      _navigateToGeneratingAndAnalyze(targetVector, capturedImage: capturedImage);
    }
  }


  void _navigateToGeneratingAndAnalyze(FaceVector targetVector, {XFile? capturedImage}) {
    final analysisFuture = _captureAndAnalyze(targetVector, preCapturedImage: capturedImage);

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => AnalysisScreen(analysisFuture: analysisFuture),
        transitionDuration: const Duration(milliseconds: 600),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut), child: child);
        },
      ),
    ).then((_) {
      if (mounted) {
        _isProcessing = false;
        if (_skipFaceDetection) {
          setState(() => _statusMessage = "自動解析モード: 次の解析を待機中...");
          _autoTriggerCapture();
        } else {
          _orbKey.currentState?.setStable(false);
          _orbKey.currentState?.setFaceOffset(null);
          setState(() => _statusMessage = "インカメラでこちらを見てください");
          _startFaceTracking();
        }
      }
    });
  }

  Future<AnalysisData> _captureAndAnalyze(FaceVector targetVector, {XFile? preCapturedImage}) async {
    final outImage = preCapturedImage ?? await _cameraService.captureOutCameraImage();
    
    if (outImage != null) {
      final result = await _geminiService.analyzeAndMask(File(outImage.path), targetVector.x, targetVector.y);
      
      return AnalysisData(
        tag: "AI RECOGNITION",
        title: result.targetName,
        subtitle: "Analyzed by Gemini",
        description: result.guideDesc,
        imagePath: outImage.path,
      );
    } else {
      throw Exception("撮影に失敗しました。");
    }
  }

  @override
  void dispose() {
    _faceSubscription?.cancel();
    _mediapipeService.close();
    _cameraService.dispose();
    super.dispose();
  }

  void _navigateToGenerating() {
    // Navigate to the generating screen when asked manually
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const AnalysisScreen(),
        transitionDuration: const Duration(milliseconds: 600),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
    );
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
            SafeArea(
              child: _buildDashboardBody(),
            ),
            if (!_skipFaceDetection && _hasFaceInFrame && _detectedFaceRect != null)
              _buildFaceGuidanceOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildFaceGuidanceOverlay() {
    return Positioned(
      top: 40,
      right: 40,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.face, color: Color(0xFFE2F063), size: 40),
              SizedBox(height: 8),
              Text(
                "DETECTED",
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardBody() {
    return Row(
      children: [
        // Left side: Glowing Orb
        Expanded(
          flex: 1,
          child: Center(
            child: GlowingOrb(key: _orbKey, size: 180),
          ),
        ),
        
        // Right side: Info and Action button
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Google AI Concierge",
                style: TextStyle(
                  color: Color(0xFF002022),
                  fontSize: 28, // Increased for AAOS
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _statusMessage,
                style: const TextStyle(
                  color: Color(0xFF44474E),
                  fontSize: 16, // Increased for AAOS
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              PrimaryButton(
                label: _skipFaceDetection ? "Capture (Manual)" : "Ask me",
                icon: Icons.mic_none_outlined,
                onPressed: _skipFaceDetection 
                    ? () => _navigateToGeneratingAndAnalyze(const FaceVector(0, 0))
                    : _navigateToGenerating,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
