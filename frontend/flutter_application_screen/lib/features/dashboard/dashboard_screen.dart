import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart' hide CameraException;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common_widgets/glowing_orb.dart';
import '../analysis/analysis_screen.dart';
import '../../core/models/face_vector.dart';
import '../../core/services/camera/camera_service.dart';
import '../../core/services/vision/face_tracker_service.dart';
import '../../core/services/ai/gemini_service.dart';
import '../../core/services/vision/mediapipe_service.dart';
import '../../core/models/test_scenery.dart';
import '../../core/models/analysis_model.dart';
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
  String _statusMessage = "襍ｷ蜍穂ｸｭ";
  
  // 繝ｦ繝ｼ繧ｶ繝ｼ繧ｬ繧､繝峨・隗｣譫千畑
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

    // 繧｢繝励Μ縺後ヰ繝・け繧ｰ繝ｩ繧ｦ繝ｳ繝峨↓蝗槭▲縺溘√∪縺溘・繧ｹ繝ｪ繝ｼ繝励＠縺滄圀縺ｮ蜃ｦ逅・
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopAllServices(); // 髱槫酔譛溘〒蛛懈ｭ｢蜃ｦ逅・ｒ髢句ｧ・
    } 
    // 繧｢繝励Μ縺悟ｾｩ蟶ｰ縺励◆髫帙・蜃ｦ逅・
    else if (state == AppLifecycleState.resumed) {
      if (!_isProcessing && !_isCameraInitialized) {
        // 繧ｹ繝ｪ繝ｼ繝励ｄ繝舌ャ繧ｯ繧ｰ繝ｩ繧ｦ繝ｳ繝峨°繧牙ｾｩ蟶ｰ縺励◆髫帙・縲∫｢ｺ螳溘↓繧ｫ繝｡繝ｩ繧貞ｼ輔″逶ｴ縺吶◆繧√↓蠑ｷ蛻ｶ繝ｪ繧ｻ繝・ヨ
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

  Future<void> _initApp({bool force = false, int retryCount = 0}) async {
    // 譌｢縺ｫ蛻晄悄蛹門・逅・′騾ｲ陦御ｸｭ縺ｮ蝣ｴ蜷医・縲∝ｼｷ蛻ｶ螳溯｡・force)縺ｧ縺ｪ縺・剞繧翫せ繧ｭ繝・・
    if (_isProcessing && !force) return;
    _isProcessing = true;
    
    try {
      // AAOS蛻､螳壹ｒ繧ｫ繝｡繝ｩ蛻晄悄蛹門燕縺ｫ陦後≧・医ヱ繝ｼ繝溘ャ繧ｷ繝ｧ繝ｳ蛻ｶ蠕｡縺ｫ蠢・ｦ・ｼ・
      final isAaos = await _cameraService.checkIsAutomotive();
      
      // AAOS迺ｰ蠅・〒縺ｯ繧ｷ繧ｹ繝・Β繝ｬ繝吶Ν縺ｧ繝代・繝溘ャ繧ｷ繝ｧ繝ｳ縺御ｻ倅ｸ弱＆繧後ｋ縺溘ａ縲・
      // permission_handler 縺ｫ繧医ｋ蜍慕噪隕∵ｱゅｒ繧ｹ繧ｭ繝・・縺吶ｋ・医け繝ｩ繝・す繝･髦ｲ豁｢・・
      if (!isAaos) {
        Map<Permission, PermissionStatus> statuses = {};
        try {
          statuses = await [
            Permission.camera,
            Permission.microphone,
          ].request();
        } catch (e) {
          debugPrint("Permission request failed: $e");
        }

        if (statuses.isNotEmpty && statuses[Permission.camera]?.isDenied == true) {
          setState(() {
            _statusMessage = "繧ｫ繝｡繝ｩ縺ｮ讓ｩ髯舌′蠢・ｦ√〒縺・;
            _isProcessing = false;
          });
          _showErrorSnackBar("繧ｫ繝｡繝ｩ縺ｮ蛻ｩ逕ｨ縺瑚ｨｱ蜿ｯ縺輔ｌ縺ｦ縺・∪縺帙ｓ・域ｨｩ髯占ｨｭ螳壹ｒ遒ｺ隱阪＠縺ｦ縺上□縺輔＞・・);
          return;
        }
      }

      await _cameraService.initialize(force: force);
      _isCameraInitialized = true;

      // 繝阪ャ繝医Ρ繝ｼ繧ｯ繝｢繝ｼ繝峨∈縺ｮ繝輔か繝ｼ繝ｫ繝舌ャ繧ｯ繧帝夂衍
      if (_cameraService.isNetworkMode) {
        _showInfoSnackBar("繝ｭ繝ｼ繧ｫ繝ｫ繧ｫ繝｡繝ｩ縺瑚ｦ九▽縺九ｊ縺ｾ縺帙ｓ縲ゅロ繝・ヨ繝ｯ繝ｼ繧ｯ繝｢繝ｼ繝峨〒襍ｷ蜍輔＠縺ｾ縺励◆縲・, title: "騾夂衍");
      }

      // API繧ｭ繝ｼ縺ｮ隱ｭ縺ｿ霎ｼ縺ｿ (.env 繝輔ぃ繧､繝ｫ縺九ｉ蜿門ｾ・
      _geminiService.initialize(
        dotenv.env['GEMINI_API_KEY'] ?? '',
        dotenv.env['GOOGLE_SERVICE_ACCOUNT_JSON'] ?? '',
      ); 
      _skipFaceDetection = dotenv.env['SKIP_FACE_DETECTION']?.toLowerCase() == 'true';
      _debugMode = dotenv.env['DEBUG_MODE']?.toLowerCase() == 'true';
      _showDebugCamera = dotenv.env['DEBUG_SHOW_CAMERA']?.toLowerCase() == 'true';
      _showDebugFaceImage = dotenv.env['DEBUG_SHOW_FACE_IMAGE']?.toLowerCase() == 'true';
      
      // AAOS迺ｰ蠅・ｼ・aspberry Pi遲会ｼ峨ｄ繝阪ャ繝医Ρ繝ｼ繧ｯ繝｢繝ｼ繝峨〒縺ｯ GPU 縺御ｸ榊ｮ牙ｮ壹↑蝣ｴ蜷医′縺ゅｋ縺溘ａ縲，PU繝・Μ繧ｲ繝ｼ繝・0) 繧呈､懆ｨ・
      final String? envDelegate = dotenv.env['MEDIAPIPE_DELEGATE'];
      final int defaultDelegate = (_cameraService.isAutomotive || _cameraService.isNetworkMode) ? 0 : 1;
      final int delegate = envDelegate != null ? (int.tryParse(envDelegate) ?? defaultDelegate) : defaultDelegate;

      await _mediapipeService.initialize(
        debugShowFaceImage: _showDebugFaceImage,
        delegate: delegate,
      );
      
      if (_skipFaceDetection) {
        setState(() => _statusMessage = "閾ｪ蜍墓聴蠖ｱ繝・せ繝井ｸｭ...");
        _autoTriggerCapture();
      } else {
        setState(() => _statusMessage = "譎ｯ濶ｲ縺ｫ豕ｨ逶ｮ縺励※縺上□縺輔＞");
        _startFaceTracking();
        _startGuidanceTimer();
      }
      _isProcessing = false; // 蛻晄悄蛹門ｮ御ｺ・
    } catch (e) {
      _isProcessing = false;
      debugPrint("Initialization error (attempt ${retryCount + 1}): $e");
      
      // AAOS迺ｰ蠅・〒縺ｯUSB繧ｫ繝｡繝ｩ縺ｮ貅門ｙ縺ｫ譎る俣縺後°縺九ｋ縺溘ａ縲∬・蜍輔Μ繝医Λ繧､
      if (retryCount < AppConstants.maxInitRetryCount) {
        setState(() => _statusMessage = "繧ｫ繝｡繝ｩ縺ｫ蜀肴磁邯壻ｸｭ... (${retryCount + 1}/${AppConstants.maxInitRetryCount})");
        await Future.delayed(AppConstants.initRetryDelay);
        if (mounted) {
          _initApp(force: true, retryCount: retryCount + 1);
        }
        return;
      }
      
      setState(() => _statusMessage = "繧ｫ繝｡繝ｩ縺ｮ蛻晄悄蛹悶↓螟ｱ謨励＠縺ｾ縺励◆");
      
      final String message = e is AppException ? e.message : "繧ｫ繝｡繝ｩ縺ｮ蛻晄悄蛹悶↓螟ｱ謨励＠縺ｾ縺励◆: $e";
      _showErrorSnackBar(message);
    }
  }

  /// 繝ｦ繝ｼ繧ｶ繝ｼ繧定ｪ伜ｰ弱☆繧九◆繧√・繧ｿ繧､繝槭・繧帝幕蟋九＠縺ｾ縺吶・
  void _startGuidanceTimer() {
    Future.doWhile(() async {
      await Future.delayed(AppConstants.guidanceTimerInterval);
      if (!mounted || _isProcessing || _skipFaceDetection) return false;
      
      final now = DateTime.now();
      if (now.difference(_lastFaceDetectedTime).inSeconds > AppConstants.guidanceNoFaceThresholdSeconds && !_hasFaceInFrame) {
        setState(() {
          _statusMessage = "螟悶・譎ｯ濶ｲ繧堤惻繧√※縺上□縺輔＞";
        });
      }
      return true;
    });
  }

  void _autoTriggerCapture() {
    // 繧ｫ繝｡繝ｩ縺ｮ貅門ｙ縺ｨ繝輔か繝ｼ繧ｫ繧ｹ螳牙ｮ壹・縺溘ａ縺ｫ2遘貞ｾ・▲縺ｦ閾ｪ蜍墓聴蠖ｱ
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted && _isProcessing == false) {
        _navigateToGeneratingAndAnalyze(const FaceVector(0, 0));
      }
    });
  }

  /// 鬘碑ｪ崎ｭ倥→繝医Λ繝・く繝ｳ繧ｰ繝ｭ繧ｸ繝・け繧帝幕蟋九＠縺ｾ縺吶・
  void _startFaceTracking() {
    if (_cameraService.isNetworkMode) {
      if (_cameraService.networkImageStream == null) return;
    } else {
      if (_cameraService.inCameraController == null) return;
      if (_cameraService.inCameraController!.value.isStreamingImages) return;
    }

    // MediaPipe 縺九ｉ縺ｮ繧ｹ繝医Μ繝ｼ繝繧定ｳｼ隱ｭ
    _faceSubscription = _mediapipeService.faceStream.listen((data) {
      if (_isProcessing || !mounted) return;
      _handleFaceStreamData(data);
    });

    _startImageStreamDetection();
  }

  /// MediaPipe縺九ｉ縺ｮ繧ｹ繝医Μ繝ｼ繝繝・・繧ｿ繧貞・逅・＠縺ｾ縺吶・
  void _handleFaceStreamData(Map<String, dynamic> data) {
    // 繝阪せ繝医＆繧後◆ Map 縺ｮ蝙九ｒ螳牙・縺ｫ繧ｭ繝｣繧ｹ繝・
    final rawLandmarks = data['landmarks'] as List?;
    final landmarks = rawLandmarks?.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    // 繝・ヰ繝・げ逕ｨ逕ｻ蜒上・譖ｴ譁ｰ
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

  /// 鬘斐ｒ繝ｭ繧ｹ繝医＠縺滄圀縺ｮ迪ｶ莠亥・逅・ｒ陦後＞縺ｾ縺吶・
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

  /// 讀懷・縺輔ｌ縺滄｡斐・繝ｩ繝ｳ繝峨・繝ｼ繧ｯ繧貞・縺ｫ繝医Λ繝・く繝ｳ繧ｰ迥ｶ諷九ｒ譖ｴ譁ｰ縺励∪縺吶・
  void _handleFaceDetected(List<Map<String, dynamic>> landmarks, Map<String, dynamic> data) {
    _lastFaceDetectedTime = DateTime.now();
    if (!_hasFaceInFrame) {
      setState(() => _hasFaceInFrame = true);
      _orbKey.currentState?.setTracking(true);
    }

    // 478蛟九・繝ｩ繝ｳ繝峨・繝ｼ繧ｯ縺九ｉ Euler隗・(Yaw/Pitch) 繧堤ｰ｡譏捺耳螳・
    final currentFaceVector = _estimateFaceVector(landmarks);
    if (currentFaceVector == null) return;

    final stableProgress = _faceTracker.getStableProgress([currentFaceVector]);

    // 繝ｭ繧ｹ繝亥ｾｩ蟶ｰ繧・眠隕剰ｪ崎ｭ俶凾縺ｫ繧ｵ繧ｦ繝ｳ繝峨ヵ繝ｩ繧ｰ繧偵Μ繧ｻ繝・ヨ
    if (stableProgress < 0.1) {
      _didPlayStableSound = false;
    }
    
    // Orb縺ｮ迥ｶ諷区峩譁ｰ
    final faceOffset = Offset(
      (currentFaceVector.x / 25.0).clamp(-1.0, 1.0),
      (currentFaceVector.y / 20.0).clamp(-1.0, 1.0)
    );
    _orbKey.currentState?.setFaceOffset(faceOffset);
    _orbKey.currentState?.setProgress(stableProgress);

    // 陦ｨ諠・・蜿肴丐
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

  /// 繝ｩ繝ｳ繝峨・繝ｼ繧ｯ縺九ｉ鬘斐・蜷代″・・aceVector・峨ｒ謗ｨ螳壹＠縺ｾ縺吶・
  FaceVector? _estimateFaceVector(List<Map<String, dynamic>> landmarks) {
    // Point 4: Nose Tip, Point 33: Left Eye, Point 263: Right Eye
    final nose = landmarks[4];
    final eyeLeft = landmarks[33];
    final eyeRight = landmarks[263];
    
    // 鬘斐・蟷・ｒ繝ｦ繝ｼ繧ｯ繝ｪ繝・ラ霍晞屬縺ｧ險育ｮ・
    final dx = eyeRight['x'] - eyeLeft['x'];
    final dy = eyeRight['y'] - eyeLeft['y'];
    final faceWidth = math.sqrt(dx * dx + dy * dy);
    
    if (faceWidth < AppConstants.faceWidthMinThreshold) return null;

    final eyeCenterX = (eyeLeft['x'] + eyeRight['x']) / 2;
    final yaw = (eyeCenterX - nose['x']) / faceWidth * 30.0;

    final eyeCenterY = (eyeLeft['y'] + eyeRight['y']) / 2;
    final pitch = (nose['y'] - eyeCenterY) / faceWidth * 30.0;

    return FaceVector(yaw, pitch);
  }

  /// 螳牙ｮ壹＠縺滄｡疲､懷・縺悟ｮ御ｺ・＠縺滄圀縺ｮ蜃ｦ逅・ｒ陦後＞縺ｾ縺吶・
  void _triggerSuccessfulDetection(FaceVector vector) {
    if (!_didPlayStableSound) {
      _playSuccessFeedback();
      _didPlayStableSound = true;
    }

    _isProcessing = true;
    _orbKey.currentState?.setStable(true);
    _orbKey.currentState?.setProgress(1.0);
    
    setState(() {
      _statusMessage = "豌励▼縺阪ｒ繧ｭ繝｣繝・メ縺励∪縺励◆";
    });

    _captureAndHandleTransition(vector);
  }

  /// 騾ｲ謐励↓蠢懊§縺溘せ繝・・繧ｿ繧ｹ繝｡繝・そ繝ｼ繧ｸ縺ｮ譖ｴ譁ｰ
  void _updateStatusByProgress(double progress) {
    if (progress > 0) {
      final clampedProgress = progress.clamp(0.0, 1.0);
      _orbKey.currentState?.setProgress(clampedProgress);
      setState(() {
        _statusMessage = "縺ゅ↑縺溘・隕也ｷ壹↓蟇・ｊ豺ｻ縺｣縺ｦ縺・∪縺・..";
      });
    } else {
      _orbKey.currentState?.setProgress(0.0);
      setState(() {
        _statusMessage = "蠢・・蜍輔″繧定ｧ｣譫舌＠縺ｦ縺・∪縺・;
      });
    }
  }

  /// 繧ｫ繝｡繝ｩ繧ｹ繝医Μ繝ｼ繝縺ｮ髢句ｧ九→MediaPipe縺ｸ縺ｮ邯咏ｶ夂噪縺ｪ騾∽ｿ｡繧帝幕蟋九＠縺ｾ縺吶・
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
    // 謌仙粥譎ゅ・繧ｵ繧ｦ繝ｳ繝峨→謖ｯ蜍・
    HapticFeedback.heavyImpact();
    // Android 繧ｷ繧ｹ繝・Β繧ｵ繧ｦ繝ｳ繝・ 繧ｫ繝｡繝ｩAF繝ｭ繝・け髻ｳ・・OCUS_COMPLETE・・
    SoundService.playFaceDetected();
  }

  Future<void> _captureAndHandleTransition(FaceVector targetVector) async {
    // 1. 縺ｾ縺壹う繝ｳ繧ｫ繝｡繝ｩ縺ｮ繧ｹ繝医Μ繝ｼ繝繧呈ｭ｢繧√ｋ
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
        // 蛻・梵逕ｻ髱｢縺ｸ遘ｻ繧矩圀縲・｡疲､懷・讖溯・繧呈・遉ｺ逧・↓荳譎ょ●豁｢・医け繝ｭ繝ｼ繧ｺ・峨☆繧・
        await _mediapipeService.close();
      }
    } catch (e) {
      debugPrint("Error stopping image stream: $e");
    }
    
    try {
      // 2. 繧｢繧ｦ繝医き繝｡繝ｩ縺ｧ謦ｮ蠖ｱ
      final capturedImage = await _cameraService.captureOutCameraImage();
      
      if (mounted) {
        _navigateToGeneratingAndAnalyze(targetVector, capturedImage: capturedImage);
      }
    } catch (e) {
      debugPrint("Error during capture and transition: $e");
      if (mounted) {
        final String message = e is AppException ? e.message : "鬚ｨ譎ｯ縺ｮ謦ｮ蠖ｱ縺ｫ螟ｱ謨励＠縺ｾ縺励◆: $e";
        _showErrorSnackBar(message);
        // 螟ｱ謨励＠縺溷ｴ蜷医・繝医Λ繝・く繝ｳ繧ｰ迥ｶ諷九ｒ繝ｪ繧ｻ繝・ヨ縺励※騾壼ｸｸ繝｢繝ｼ繝峨↓謌ｻ繧・
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
        // 蜈ｨ縺ｦ縺ｮ迥ｶ諷九ｒ繝ｪ繝輔Ξ繝・す繝･
        _resetTrackingState();
        
        // 隗｣譫舌お繝ｩ繝ｼ縺瑚ｿ斐▲縺ｦ縺阪◆蝣ｴ蜷医√せ繝翫ャ繧ｯ繝舌・縺ｧ陦ｨ遉ｺ
        if (result is String && result.startsWith('error:')) {
          final errorMessage = result.replaceFirst('error:', '');
          _showErrorSnackBar(errorMessage);
        }
        
        // Android迚ｹ譛峨・ "Dead Thread" 蝠城｡後ｒ蝗樣∩縺吶ｋ縺溘ａ縲・
        // 謌ｻ縺｣縺ｦ縺阪◆譎ゅ・蠑ｷ蛻ｶ逧・↓繧ｫ繝｡繝ｩ繧ｳ繝ｳ繝医Ο繝ｼ繝ｩ繝ｼ繧堤ｴ譽・＠縺ｦ蜀堺ｽ懈・縺吶ｋ
        try {
          _initApp(force: true);
        } catch (e) {
          debugPrint("Error re-initializing app: $e");
          _showErrorSnackBar("繧｢繝励Μ縺ｮ蜀榊・譛溷喧縺ｫ螟ｱ謨励＠縺ｾ縺励◆: $e");
        }
      }
    });
  }

  void _resetTrackingState() {
    setState(() {
      _isProcessing = false;
      _didPlayStableSound = false;
      _hasFaceInFrame = false;
      _statusMessage = "譎ｯ濶ｲ縺ｫ豕ｨ逶ｮ縺励※縺上□縺輔＞"; // 繧ｹ繝・・繧ｿ繧ｹ繧ょ・譛溽憾諷九↓繝ｪ繧ｻ繝・ヨ
    });
    _faceTracker.reset();
    _orbKey.currentState?.setTracking(false);
    _orbKey.currentState?.setProgress(0.0);
    _orbKey.currentState?.setStable(false);
  }

  void _showErrorSnackBar(String message) {
    _showSnackBar(message, isError: true);
  }

  void _showInfoSnackBar(String message, {String title = "諠・ｱ"}) {
    _showSnackBar(message, isError: false, title: title);
  }

  void _showSnackBar(String message, {bool isError = false, String? title}) {
    final Color bgColor = isError 
        ? const Color(0xFF2C3E50).withValues(alpha: 0.9)
        : const Color(0xFF1ABC9C).withValues(alpha: 0.9);
    final Color iconColor = isError ? const Color(0xFFFF8B8B) : const Color(0xFFE2F063);
    final IconData icon = isError ? Icons.error_outline : Icons.info_outline;
    final String displayTitle = title ?? (isError ? (_debugMode ? "DEBUG ERROR" : "繧ｨ繝ｩ繝ｼ") : "諠・ｱ");

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
      // 繝・せ繝医Δ繝ｼ繝・ 繧｢繧ｻ繝・ヨ縺九ｉ逕ｻ蜒上ｒ蜿門ｾ励＠縲∵ｭ｣隕丞喧蠎ｧ讓吶ｒ繧ｻ繝・ヨ
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
      
      // Gemini縺ｮ邨先棡縺九ｉ繝昴Μ繧ｴ繝ｳ諠・ｱ繧呈歓蜃ｺ
      final segArray = result.segData;
      List<double>? polygon;
      if (segArray.isNotEmpty && segArray[0] is Map && segArray[0]['polygon'] is List) {
        final rawPolygon = segArray[0]['polygon'] as List;
        polygon = rawPolygon.map((e) => (e as num).toDouble()).toList();
      }

      // 髻ｳ螢ｰ繝・・繧ｿ縺ｮ蜿門ｾ・(TTS)
      String ttsText = result.guideDesc;
      if (result.latitude != null && result.longitude != null) {
        ttsText += " 縲ゅゅ・縺薙・蝣ｴ謇縺ｫ陦後″縺溘＞縺ｧ縺吶°・・;
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
      throw CameraException("謦ｮ蠖ｱ縺ｫ螟ｱ謨励＠縺ｾ縺励◆縲・);
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
                    "AI 繧ｳ繝ｳ繧ｷ繧ｧ繝ｫ繧ｸ繝･",
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
                          _isProcessing ? "" : (_hasFaceInFrame ? "縺昴・縺ｾ縺ｾ謨ｰ遘帝俣縲∬ｦ也ｷ壹ｒ蝗ｺ螳壹＠縺ｦ縺上□縺輔＞" : "豌励↓縺ｪ繧九ｂ縺ｮ繧定ｦ九▽繧√ｋ縺ｨAI縺瑚ｧ｣隱ｬ縺励∪縺・), // 隱崎ｭ俶・蜉滓凾縺ｮ縺ｿ髱櫁｡ｨ遉ｺ
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
