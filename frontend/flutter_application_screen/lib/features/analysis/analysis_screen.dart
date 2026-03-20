import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'analysis_model.dart';
import '../../core/theme/app_colors.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/rendering.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;
import '../camera/services/gemini_service.dart';

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

  // Result tracking
  bool _isNavigatingBack = false;
  bool _isListening = false;
  final AudioRecorder _recorder = AudioRecorder();
  final GeminiService _geminiService = GeminiService(); // すでにDashboardで初期化されているがServiceクラスなので再初期化でもステートは保持される前提か、またはプロバイダ経由が望ましいが現状に合わせる

  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription? _playerCompleteSubscription;
  Timer? _autoExitTimer;
  final ScrollController _infoScrollController = ScrollController();
  bool _isUserScrolling = false;

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
    _data = widget.fallbackData ?? AnalysisData.defaultData;
    
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

    // .env から GeminiService を再初期化 (Dashboardで初期化済みだが、画面遷移後も使えるように)
    _geminiService.initialize(
      dotenv.env['GEMINI_API_KEY'] ?? '',
      dotenv.env['GOOGLE_SERVICE_ACCOUNT_JSON'] ?? '',
    );

    _transitionController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _phase = AnalysisPhase.complete;
        });
        _playAudio();
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
          final isDebug = dotenv.env['DEBUG_MODE']?.toLowerCase() == 'true';
          final errorMsg = isDebug ? 'error:$e' : 'error:解析に失敗しました。しばらく待ってからやり直してください。';
          // エラー時はメッセージを添えてダッシュボードに戻る
          _navigateToDashboard(result: errorMsg);
        }
      });
    }

    _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (_data.latitude != null && _data.longitude != null) {
        _startVoiceIntentDetection();
      } else {
        _startAutoExitTimer(const Duration(seconds: 3));
      }
    });
  }

  Future<void> _playAudio() async {
    if (_data.audioBytes != null) {
      try {
        await _audioPlayer.play(BytesSource(_data.audioBytes!));
        _startAutoScrolling();
      } catch (e) {
        debugPrint("Error playing audio: $e");
        // 再生エラー時はフォールバックとして3秒後に戻る
        _startAutoExitTimer(const Duration(seconds: 3));
      }
    } else {
      // TTSがない場合は、表示完了から3秒後に戻る
      _startAutoExitTimer(const Duration(seconds: 3));
    }
  }

  Future<void> _startAutoScrolling() async {
    // ユーザー操作をリセット
    _isUserScrolling = false;

    // レイアウトが確定して音声情報が取得できるまで少し待機
    await Future.delayed(const Duration(milliseconds: 1000));
    
    if (!mounted || !_infoScrollController.hasClients) return;
    if (_isUserScrolling) return;

    final maxScroll = _infoScrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final duration = await _audioPlayer.getDuration();
    if (duration != null && duration.inSeconds > 0) {
      // 音声の長さに合わせて等速で最後までスクロール
      _infoScrollController.animateTo(
        maxScroll,
        duration: duration,
        curve: Curves.linear,
      );
    }
  }

  void _startAutoExitTimer(Duration delay) {
    _autoExitTimer?.cancel();
    _autoExitTimer = Timer(delay, () {
      if (mounted && !_isListening) {
        _navigateToDashboard();
      }
    });
  }

  Future<void> _startVoiceIntentDetection() async {
    if (_isListening) return;

    try {
      if (await _recorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = p.join(tempDir.path, 'intent_record.m4a');
        
        // 以前のファイルがあれば削除
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }

        setState(() => _isListening = true);
        
        // 録音開始 (AAC/m4a)
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);

        // 3秒間待機
        await Future.delayed(const Duration(seconds: 3));

        if (!mounted || !_isListening) return;

        // 録音停止
        final recordPath = await _recorder.stop();
        setState(() => _isListening = false);

        if (recordPath != null) {
          final audioBytes = await File(recordPath).readAsBytes();
          
          // Geminiで意図判定
          final isPositive = await _geminiService.classifyVoiceIntent(audioBytes);
          
          if (mounted) {
            if (isPositive) {
              debugPrint("Voice Intent: Positive -> Starting Navigation");
              _startNavigation();
            } else {
              debugPrint("Voice Intent: Negative or Neutral -> Returning to Dashboard");
              _navigateToDashboard();
            }
          }
        } else {
          // 録音データがない場合はダッシュボードに戻る
          _navigateToDashboard();
        }
      } else {
        // 権限がない場合は通常通り3秒待って戻る
        _startAutoExitTimer(const Duration(seconds: 3));
      }
    } catch (e) {
      debugPrint("Error in voice intent detection: $e");
      if (mounted) {
        setState(() => _isListening = false);
        _navigateToDashboard();
      }
    }
  }

  // Removed _initAutoReturnTracking and _startFaceTracking functionality

  @override
  void dispose() {
    _transitionController.dispose();
    _playerCompleteSubscription?.cancel();
    _autoExitTimer?.cancel();
    _audioPlayer.dispose();
    _infoScrollController.dispose();
    _recorder.dispose(); // Recorderの破棄
    super.dispose();
  }

  void _startTransition() {
    setState(() => _phase = AnalysisPhase.reveal);
    _transitionController.forward();
  }

  Future<void> _navigateToDashboard({dynamic result}) async {
    if (_isNavigatingBack) return;
    _isNavigatingBack = true;
    _autoExitTimer?.cancel();

    if (_isListening) {
      _recorder.stop();
      _isListening = false;
    }

    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _startNavigation() async {
    // TTS再生中の場合は停止
    await _audioPlayer.stop();
    _autoExitTimer?.cancel(); // 安全のためここでもキャンセル

    if (_isListening) {
      _recorder.stop();
      _isListening = false;
    }

    if (_data.latitude == null || _data.longitude == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ナビゲーション用の座標が取得できていません。')),
        );
      }
      return;
    }

    // GASが使えない場合などでマップアプリを直接呼び出すための geo スキームを優先
    final intentUrl = 'geo:${_data.latitude},${_data.longitude}?q=${_data.latitude},${_data.longitude}';
    final googleNavUrl = 'google.navigation:q=${_data.latitude},${_data.longitude}';
    
    // SDK方式を試みる
    try {
      // 0. 位置情報パーミッションの確認
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
        if (!status.isGranted) {
          // パーミッション拒否時はIntent方式へフォールバック
          await _launchIntent(intentUrl, googleNavUrl);
          return;
        }
      }

      // 1. 利用規約の確認と表示
      if (!await GoogleMapsNavigator.areTermsAccepted()) {
        final accepted = await GoogleMapsNavigator.showTermsAndConditionsDialog(
          'Google Maps Navigation SDK 利用規約',
          'ナビゲーション機能を利用するには、Google Maps Platform の利用規約に同意する必要があります。',
        );
        if (!accepted) {
          // 利用規約に同意しない場合は、Intent方式へフォールバック
          await _launchIntent(intentUrl, googleNavUrl);
          return;
        }
      }

      // 2. ナビゲーションセッションの初期化
      // タイムアウトを設定して、応答がない場合にIntentへフォールバック
      await GoogleMapsNavigator.initializeNavigationSession().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Navigation initialization timed out'),
      );
      
      final waypoint = NavigationWaypoint.withLatLngTarget(
        title: _data.title,
        target: LatLng(latitude: _data.latitude!, longitude: _data.longitude!),
      );

      final destinations = Destinations(
        waypoints: [waypoint],
        displayOptions: NavigationDisplayOptions(),
      );

      // 3. ナビゲーション画面を表示するための画面遷移
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text('${_data.title} への案内')),
              body: GoogleMapsNavigationView(
                onViewCreated: (controller) async {
                  final navigator = Navigator.of(context);
                  try {
                    // ルート計算の状態を確認
                    final status = await GoogleMapsNavigator.setDestinations(destinations).timeout(
                      const Duration(seconds: 15),
                      onTimeout: () => throw TimeoutException('Routing timed out'),
                    );

                    if (status == NavigationRouteStatus.statusOk) {
                      await GoogleMapsNavigator.startGuidance();
                    } else {
                      debugPrint("Routing failed with status: $status. Fallback to Intent.");
                      if (navigator.mounted) navigator.pop();
                      await _launchIntent(intentUrl, googleNavUrl);
                    }
                  } catch (e) {
                    debugPrint("SDK View Error: $e. Fallback to Intent.");
                    if (navigator.mounted) navigator.pop();
                    await _launchIntent(intentUrl, googleNavUrl);
                  }
                },
              ),
            ),
          ),
        );
      }
    } catch (e) {
      // 400エラーやタイムアウトなどの例外をキャッチ
      debugPrint("SDK Error: $e. Fallback to Intent.");
      await _launchIntent(intentUrl, googleNavUrl);
    }
  }

  Future<void> _launchIntent(String url, String fallbackUrl) async {
    try {
      // LaunchMode.externalNonBrowserApplication を指定して強制的にブラウザ以外（マップアプリ）で開く
      if (await canLaunchUrlString(url)) {
        await launchUrlString(
          url,
          mode: LaunchMode.externalNonBrowserApplication,
        );
        // Intent開始後は解析画面を閉じてダッシュボードに戻る
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else if (await canLaunchUrlString(fallbackUrl)) {
        await launchUrlString(
          fallbackUrl,
          mode: LaunchMode.externalNonBrowserApplication,
        );
        if (mounted) Navigator.of(context).pop();
      } else {
        // 最後の手段: https URL
        final httpsUrl = 'https://www.google.com/maps/dir/?api=1&destination=${_data.latitude},${_data.longitude}&travelmode=driving';
        if (await canLaunchUrlString(httpsUrl)) {
          await launchUrlString(httpsUrl);
          if (mounted) Navigator.of(context).pop();
        } else {
          throw 'Could not launch navigation';
        }
      }
    } catch (e) {
      debugPrint("Intent Error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ナビゲーションの開始に失敗しました: $e')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          AnimatedBuilder(
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
          // 右上の「×」ボタン（結果表示またはエラー表示以降に出現）
          if (_phase == AnalysisPhase.complete || _phase == AnalysisPhase.reveal)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 24,
              child: FadeTransition(
                opacity: _contentFade,
                child: GestureDetector(
                  onTap: () => _navigateToDashboard(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: const Icon(Icons.close, color: AppColors.textPrimary, size: 24),
                  ),
                ),
              ),
            ),
        ],
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
    final polygon = _data.polygon;
    double aspectRatio = 16 / 9;
    if (polygon != null && polygon.length >= 4) {
      double minX = 1000, minY = 1000, maxX = 0, maxY = 0;
      for (int i = 0; i < polygon.length - 1; i += 2) {
        final y = polygon[i];
        final x = polygon[i + 1];
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      
      final w = (maxX - minX).clamp(1.0, 1000.0);
      final h = (maxY - minY).clamp(1.0, 1000.0);
      
      if (h > w * 1.2) {
        aspectRatio = 3 / 4; // 縦長
      } else if (w > h * 1.2) {
        aspectRatio = 16 / 9; // 横長
      } else {
        aspectRatio = 1.0; // 正方形に近い
      }
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: AspectRatio(
        aspectRatio: aspectRatio,
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
                      _buildImageWithCrop(),
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
          child: SingleChildScrollView(
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
  
                const SizedBox(height: 48),
  
                _buildOutlineButtons(),
              ],
            ),
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


  Widget _buildImageWithCrop() {
    final polygon = _data.polygon;
    final imagePath = _data.imagePath;
    final ImageProvider imageProvider = imagePath.startsWith('assets/') ? AssetImage(imagePath) : FileImage(File(imagePath));

    if (polygon == null || polygon.length < 4) {
      return Image(image: imageProvider, fit: BoxFit.cover);
    }

    // 境界矩形の計算 (Geminiの座標は 0~1000 の範囲 [ymin, xmin, ymax, xmax] など)
    double minX = 1000, minY = 1000, maxX = 0, maxY = 0;
    for (int i = 0; i < polygon.length - 1; i += 2) {
      final y = polygon[i];
      final x = polygon[i + 1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    // 対象物の中心座標(0.0〜1.0)
    final cx = (minX + maxX) / 2 / 1000;
    final cy = (minY + maxY) / 2 / 1000;

    // 対象物の幅と高さ(0.0〜1.0)
    final w = (maxX - minX) / 1000;
    final h = (maxY - minY) / 1000;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 対象物が画面の約75%を占めるようにズーム率を計算（大きすぎ・小さすぎを防ぐため 1.0〜4.0 倍に制限）
        final zoomScale = (0.75 / math.max(0.1, math.max(w, h))).clamp(1.0, 4.0);

        // FractionalOffset を使うことで、BoxFit.cover でどれだけ切り取られても、
        // 対象物の中心 (cx, cy) がコンテナの (cx, cy) 位置に確実に配置されます。
        // Transform.scale により、その (cx, cy) を中心としてズームされるため、画面から見切れることがありません。
        final alignment = FractionalOffset(cx, cy);

        return ClipRect(
          child: Transform.scale(
            scale: zoomScale,
            alignment: alignment,
            child: Image(
              image: imageProvider,
              fit: BoxFit.cover,
              alignment: alignment,
            ),
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
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is UserScrollNotification) {
            // ユーザーが手動スクロールを開始した場合は自動スクロールを停止
            if (notification.direction != ScrollDirection.idle) {
              _isUserScrolling = true;
            }
          }
          return false;
        },
        child: SingleChildScrollView(
          controller: _infoScrollController,
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
        GestureDetector(
          onTap: () {
            _autoExitTimer?.cancel(); // 自動戻りをキャンセル
            _startNavigation();
          },
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: (_data.latitude != null && _data.longitude != null) 
                  ? const Color(0xFFFF895D) 
                  : Colors.grey.shade400,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.navigation_outlined, color: Colors.white),
                    const SizedBox(width: 12),
                    Text(
                      _data.latitude != null ? "Navigate there" : "Location unknown",
                      style: const TextStyle(
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
        ),
      ],
    );
  }


}
