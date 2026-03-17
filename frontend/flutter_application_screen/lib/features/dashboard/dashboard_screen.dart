import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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
  late final FaceDetector _mlkitDetector;

  bool _isProcessing = false;
  bool _skipFaceDetection = false;
  String _statusMessage = "初期化しています...";
  
  // ユーザーガイド用
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
    
    // Google ML Kit FaceDetectorの初期化 (Euler角取得のため classification 有効)
    _mlkitDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    
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
    _cameraService.inCameraController?.startImageStream((CameraImage image) async {
      if (_isProcessing) return;

      // CameraImage から ML Kit の InputImage への変換
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final faces = await _mlkitDetector.processImage(inputImage);
      
      if (faces.isEmpty) {
        // 500msの猶予（グレイスピリオド）を設けて、一瞬の検出失敗によるチラつきを防ぐ
        final now = DateTime.now();
        if (_hasFaceInFrame && now.difference(_lastFaceDetectedTime).inMilliseconds > 500) {
          if (mounted) {
            setState(() {
              _hasFaceInFrame = false;
              _detectedFaceRect = null;
            });
          }
        }
      } else {
        _lastFaceDetectedTime = DateTime.now();
        if (mounted) {
          if (!_hasFaceInFrame) {
            setState(() => _hasFaceInFrame = true);
          }
          final face = faces.first;
          _detectedFaceRect = face.boundingBox;
        }
      }

      List<FaceVector> currentFaceAngles = faces.map((face) {
        // ML Kit は Euler角を直接返してくれる (度単位)
        // headEulerAngleY: 左右の向き (Yaw相当)
        // headEulerAngleX: 上下の向き (Pitch相当)
        final yaw = face.headEulerAngleY ?? 0.0;
        final pitch = face.headEulerAngleX ?? 0.0;

        return FaceVector(yaw, pitch);
      }).toList();

      final stableProgress = _faceTracker.getStableProgress(currentFaceAngles);
      
      if (currentFaceAngles.isNotEmpty) {
        final mainFace = currentFaceAngles.first;
        // 向きをOrbに伝える (Yawは左右、Pitchは上下。ML Kitの値を適度にスケーリング)
        _orbKey.currentState?.setFaceOffset(Offset(mainFace.x / 40, mainFace.y / 40));
      } else {
        _orbKey.currentState?.setFaceOffset(null);
      }

      if (stableProgress >= 1.0) {
        _isProcessing = true;
        _orbKey.currentState?.setStable(true);
        await _cameraService.inCameraController?.stopImageStream();
        
        setState(() {
           _statusMessage = "目線が固定されました。撮影・解析を開始します...";
        });
        
        await Future.delayed(const Duration(milliseconds: 500)); // 安定状態を少し見せる
        _navigateToGeneratingAndAnalyze(currentFaceAngles.first);
      } else if (stableProgress > 0) {
        setState(() {
          final percent = (stableProgress * 100).toInt();
          _statusMessage = "視点を固定中... $percent%";
        });
      }
    });
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_cameraService.inCameraController == null) return null;

    final sensorOrientation = _cameraService.inCameraController!.description.sensorOrientation;
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // Google ML Kit for Android expects NV21 format when using fromBytes
    // We need to concatenate the YUV planes correctly.
    final Uint8List bytes = _concatenatePlanes(image.planes);

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  void _navigateToGeneratingAndAnalyze(FaceVector targetVector) {
    final analysisFuture = _captureAndAnalyze(targetVector);

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

  Future<AnalysisData> _captureAndAnalyze(FaceVector targetVector) async {
    final outImage = await _cameraService.captureOutCameraImage();
    
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
    _cameraService.dispose();
    _mlkitDetector.close();
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
