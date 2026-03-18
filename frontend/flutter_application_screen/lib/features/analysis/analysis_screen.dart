import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../camera/services/mediapipe_service.dart';
import '../../core/theme/app_colors.dart';
import '../camera/services/camera_service.dart';
import '../camera/services/face_tracker_service.dart';
import '../camera/models/face_vector.dart';
import '../dashboard/dashboard_screen.dart';
import 'analysis_model.dart';
import 'dart:async';

enum AnalysisPhase { generating, peakPulse, convergence, reveal, complete }

class AnalysisScreen extends StatefulWidget {
  final Future<AnalysisData>? analysisFuture;
  final AnalysisData? fallbackData;

  const AnalysisScreen({
    super.key,
    this.analysisFuture,
    this.fallbackData,
  });

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> with TickerProviderStateMixin {
  AnalysisPhase _phase = AnalysisPhase.generating;
  late AnimationController _transitionController;
  late AnalysisData _data;
  late DateTime _screenStartTime;
  DateTime? _resultShowTime;

  // Face tracking for auto-return
  final CameraService _cameraService = CameraService();
  final FaceTrackerService _faceTracker = FaceTrackerService();
  final MediapipeService _mediapipeService = MediapipeService();
  StreamSubscription? _faceSubscription;
  bool _isAutoReturning = false;
  bool _isAnalyzing = false;

  // Animation values
  late Animation<double> _imageDissolve;
  late Animation<double> _titleFadeOut;
  late Animation<Offset> _titleSlideOut;
  late Animation<Offset> _titleSlideIn;
  late Animation<double> _skeletonFade;
  late Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();
    _screenStartTime = DateTime.now();
    _data = widget.fallbackData ?? AnalysisData.defaultData;
    _initAutoReturnTracking();
    
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500), // Motion Specs: 500ms
    );

    _imageDissolve = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeInOut),
      ),
    );

    _titleFadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    _titleSlideOut = Tween<Offset>(begin: Offset.zero, end: const Offset(0.0, -0.2)).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );

    _titleSlideIn = Tween<Offset>(begin: const Offset(0.0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeInOut),
      ),
    );

    _skeletonFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    _contentFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    _transitionController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _phase = AnalysisPhase.complete;
          _resultShowTime = DateTime.now();
        });
      }
    });

    if (widget.analysisFuture != null) {
      widget.analysisFuture!.then((result) {
        if (mounted) {
          setState(() {
            _data = result;
          });
          _startTransition();
        }
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _data = AnalysisData(
              tag: "ERROR",
              title: "Analysis Failed",
              subtitle: "Oops, something went wrong.",
              description: e.toString(),
              imagePath: _data.imagePath,
            );
          });
          _startTransition();
        }
      });
    }

  }

  Future<void> _initAutoReturnTracking() async {
    await _cameraService.initialize();
    await _mediapipeService.initialize();
    _startFaceTracking();
  }

  void _startFaceTracking() {
    _faceSubscription = _mediapipeService.faceStream.listen((data) {
      if (_isAutoReturning || !mounted) return;

      final rawLandmarks = data['landmarks'] as List?;
      final landmarks = rawLandmarks?.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (landmarks == null || landmarks.isEmpty) return;

      // 478個のランドマークから Euler角 (Yaw/Pitch) を簡易推定
      // DashboardScreen と同じロジック
      final nose = landmarks[4];
      final eyeLeft = landmarks[33];
      final eyeRight = landmarks[263];
      
      final faceWidth = (eyeRight['x'] - eyeLeft['x']).abs();
      if (faceWidth < 0.05) return;

      final eyeCenterX = (eyeLeft['x'] + eyeRight['x']) / 2;
      final yaw = (nose['x'] - eyeCenterX) / faceWidth * 30.0;
      final eyeCenterY = (eyeLeft['y'] + eyeRight['y']) / 2;
      final pitch = (nose['y'] - eyeCenterY) / faceWidth * 30.0;

      final currentFaceVector = FaceVector(yaw, pitch);
      final stableProgress = _faceTracker.getStableProgress([currentFaceVector]);
      
      final elapsed = _resultShowTime != null 
          ? DateTime.now().difference(_resultShowTime!).inSeconds 
          : 0;

      if (stableProgress >= 0.8 && elapsed >= 5) {
        _isAutoReturning = true;
        _navigateToDashboard();
      }
    });

    _cameraService.inCameraController?.startImageStream((CameraImage image) {
      if (_isAutoReturning || _isAnalyzing || !mounted) return;
      
      _isAnalyzing = true;
      final rotation = _cameraService.inCameraController?.description.sensorOrientation ?? 0;
      _mediapipeService.detect(image, rotation: rotation).then((_) {
        _isAnalyzing = false;
      });
    });
  }

  @override
  void dispose() {
    _faceSubscription?.cancel();
    _transitionController.dispose();
    _cameraService.dispose();
    _mediapipeService.close();
    super.dispose();
  }

  void _startTransition() {
    setState(() => _phase = AnalysisPhase.reveal);
    _transitionController.forward();
  }

  void _navigateToDashboard() {
    if (_isAutoReturning == false) {
       _isAutoReturning = true;
    }
    
    // Stop stream before popping
    try {
      if (_cameraService.inCameraController?.value.isStreamingImages ?? false) {
        _cameraService.inCameraController?.stopImageStream();
      }
    } catch (e) {
      debugPrint("Error stopping stream in AnalysisScreen: $e");
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const DashboardScreen(),
        transitionDuration: const Duration(milliseconds: 700),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // 全体の経過時間（念のためのセーフガード）
        final screenElapsed = DateTime.now().difference(_screenStartTime).inSeconds;
        // 結果表示からの経過時間
        final resultElapsed = _resultShowTime != null 
            ? DateTime.now().difference(_resultShowTime!).inSeconds 
            : 0;

        if (screenElapsed >= 15 || resultElapsed >= 5) {
          _navigateToDashboard();
          return;
        }

        if (_phase == AnalysisPhase.generating && widget.analysisFuture == null) {
          _startTransition();
        } else if (_phase == AnalysisPhase.complete) {
          _navigateToDashboard();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: AnimatedBuilder(
          animation: _transitionController,
          builder: (context, child) {
            return OrientationBuilder(
              builder: (context, orientation) {
                if (orientation == Orientation.landscape) {
                  return _buildLandscapeLayout();
                } else {
                  return _buildPortraitLayout();
                }
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return SafeArea(
      child: Column(
        children: [
          _buildStaticImageArea(),
          Expanded(
            child: Stack(
              children: [
                if (_transitionController.value < 1.0)
                  _buildGeneratingCard(false),
                if (_transitionController.value > 0.0 || _phase == AnalysisPhase.complete)
                  _buildResultCard(false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout() {
    return SafeArea(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Image bounded
          Expanded(
            flex: 2,
            child: _buildStaticImageArea(),
          ),
          
          // Right: Content Card or Reveal layout
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 24.0, bottom: 24.0, top: 24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_transitionController.value < 1.0)
                    SingleChildScrollView(
                      child: _buildGeneratingCard(true),
                    ),
                  if (_transitionController.value > 0.0 || _phase == AnalysisPhase.complete)
                    _buildResultCard(true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildStaticImageArea() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 30,
                spreadRadius: 5,
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Loading Image Area / Shimmer (Dissolves OUT)
                Opacity(
                  opacity: 1.0 - _imageDissolve.value,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Shimmer.fromColors(
                        baseColor: Colors.grey.shade200,
                        highlightColor: Colors.grey.shade50,
                        child: Container(
                          color: Colors.white,
                          child: Center(
                            child: Icon(Icons.map_outlined, size: 48, color: Colors.grey.shade400),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 16,
                        left: 16,
                        child: _buildBadge("● ANALYZING...", Colors.black.withValues(alpha: 0.6), const Color(0xFFE2F063)),
                      ),
                    ],
                  ),
                ),

                // 2. Result Image area (Dissolves IN)
                Opacity(
                  opacity: _imageDissolve.value,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImageWithFallback(),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.black.withValues(alpha: 0.4), Colors.transparent],
                              begin: Alignment.bottomCenter,
                              end: Alignment.center,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 16,
                        left: 16,
                        child: _buildBadge("● LIVE RECOGNITION", Colors.transparent, const Color(0xFFE2F063)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color bgColor, Color dotColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratingCard(bool isLandscape) {
    return FadeTransition(
      opacity: _titleFadeOut,
      child: Padding(
        padding: EdgeInsets.only(
          left: isLandscape ? 0 : 24.0,
          right: isLandscape ? 0 : 24.0,
          bottom: isLandscape ? 0 : 24.0,
        ),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: const Color(0xFFF9F7EC), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 40,
                spreadRadius: 8,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTagRow("AI ANALYSIS IN PROGRESS"),
              const SizedBox(height: 12),
              
              SlideTransition(
                position: _titleSlideOut,
                child: const Text(
                  "Generating...",
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              FadeTransition(
                opacity: _skeletonFade,
                child: Shimmer.fromColors(
                  baseColor: Colors.grey.shade200,
                  highlightColor: Colors.grey.shade50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildShimmerContainer(width: 180, height: 16, circular: true),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade300),
                          const SizedBox(width: 8),
                          _buildShimmerContainer(width: 120, height: 14, circular: true),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildShimmerContainer(width: double.infinity, height: 12, circular: true),
                      const SizedBox(height: 8),
                      _buildShimmerContainer(width: double.infinity, height: 12, circular: true),
                      const SizedBox(height: 8),
                      _buildShimmerContainer(width: double.infinity, height: 12, circular: true),
                      const SizedBox(height: 8),
                      _buildShimmerContainer(width: 180, height: 12, circular: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (!isLandscape) const Spacer() else const SizedBox(height: 48),

              _buildOutlineButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagRow(String text) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: AppColors.dot2,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 12),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary.withValues(alpha: 0.8),
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildOutlineButtons() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.grey.shade300, width: 1.5),
          ),
          child: const Center(
            child: Text(
              "Tell me more",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.grey.shade300, width: 1.5),
          ),
          child: const Center(
            child: Text(
              "Navigate there",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }





  Widget _buildShimmerContainer({required double width, required double height, bool circular = false}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(circular ? height / 2 : 8),
      ),
    );
  }


  Widget _buildImageWithFallback() {
    final imagePath = _data.imagePath;
    final ImageProvider imageProvider;
    if (imagePath.startsWith('assets/')) {
      imageProvider = AssetImage(imagePath);
    } else {
      imageProvider = FileImage(File(imagePath));
    }

    return Image(
      image: imageProvider,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey.shade300,
          child: const Center(
            child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(32.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 40,
            spreadRadius: 5,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFAD6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _data.tag,
                style: const TextStyle(
                  color: Color(0xFFAC8B18),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 24),
      
            // Title
            SlideTransition(
              position: _titleSlideIn,
              child: Text(
                _data.title,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 12),
      
            // Subtitle
            Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: const Color(0xFF52A574)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _data.subtitle,
                  style: const TextStyle(
                    color: Color(0xFF52A574), // Greenish
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
            const SizedBox(height: 24),
      
            // Description
            Text(
              _data.description,
              style: const TextStyle(
                color: Color(0xFF5C626C),
                fontSize: 15,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
      
            // Buttons
            _buildInfoButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(bool isLandscape) {
    return FadeTransition(
      opacity: _contentFade,
      child: Padding(
        padding: EdgeInsets.only(
          left: isLandscape ? 0 : 24.0,
          right: isLandscape ? 0 : 24.0,
          bottom: isLandscape ? 0 : 24.0,
        ),
        child: _buildInfoCard(),
      ),
    );
  }

  Widget _buildInfoButtons() {
    return Column(
      children: [
        // Tell me more
        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFF52A574), width: 1.5),
          ),
          child: const Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF52A574)),
                  SizedBox(width: 12),
                  Text(
                    "Tell me more",
                    style: TextStyle(
                      color: Color(0xFF52A574),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        
        // Navigate there
        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFFF895D), // Salmon color from screen.png
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.navigation_outlined, color: Colors.white),
                  SizedBox(width: 12),
                  Text(
                    "Navigate there",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }


}
