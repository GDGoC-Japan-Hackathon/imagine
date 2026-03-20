import 'dart:io';
import 'package:flutter/material.dart';
import 'analysis_model.dart';
import 'widgets/analysis_static_image.dart';
import 'widgets/analysis_generating_card.dart';
import 'widgets/analysis_result_card.dart';
import 'services/navigation_handler.dart';
import '../../core/theme/app_colors.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;
import '../../core/errors/exceptions.dart';
import '../../common_widgets/voice_waveform.dart';
import '../camera/services/gemini_service.dart';
import '../../core/services/sound_service.dart';

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
  double _currentAmplitude = -60.0;
  final AudioRecorder _recorder = AudioRecorder();
  final GeminiService _geminiService = GeminiService(); 
  StreamSubscription? _amplitudeSub;
  Timer? _listeningTimeoutTimer;

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
          String errorMsg;
          if (e is AppException) {
            errorMsg = 'error:${e.message}';
          } else {
            errorMsg = isDebug ? 'error:$e' : 'error:解析に失敗しました。しばらく待ってからやり直してください。';
          }
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
        
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }

        setState(() {
          _isListening = true;
          _currentAmplitude = -60.0;
        });
        
        // 録音開始 (AAC/m4a)
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);

        // 録音開始の合図としてシステム通知音を再生
        SoundService.playVoiceStart();

        // VAD (Voice Activity Detection): 声が途切れたら自動停止
        DateTime lastSoundTime = DateTime.now();
        _amplitudeSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 50)).listen((amp) {
          if (mounted) {
            setState(() {
              _currentAmplitude = amp.current;
            });
            
            // しきい値 -40dB 以上の入力があれば「声」とみなす
            if (amp.current > -40) {
              lastSoundTime = DateTime.now();
            } else {
              // 1.5秒以上沈黙が続いたら、発話終了とみなして停止
              if (DateTime.now().difference(lastSoundTime).inMilliseconds > 1500) {
                 _stopAndProcessVoiceIntent();
              }
            }
          }
        });

        // 最大10秒のタイムアウトを設定（誰も話さない場合など）
        _listeningTimeoutTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && _isListening) {
             _stopAndProcessVoiceIntent();
          }
        });

      } else {
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

  Future<void> _stopAndProcessVoiceIntent() async {
    if (!_isListening) return;

    _amplitudeSub?.cancel();
    _listeningTimeoutTimer?.cancel();

    // 録音停止
    final recordPath = await _recorder.stop();
    if (!mounted) return;
    
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
      _navigateToDashboard();
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
    _recorder.dispose();
    _amplitudeSub?.cancel();
    _listeningTimeoutTimer?.cancel();
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
      await _recorder.stop();
      _isListening = false;
      _amplitudeSub?.cancel();
      _listeningTimeoutTimer?.cancel();
    }

    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _startNavigation() async {
    await NavigationHandler.startNavigation(
      context: context,
      data: _data,
      onStarted: () async {
        await _audioPlayer.stop();
        _autoExitTimer?.cancel();
        if (_isListening) {
          await _recorder.stop();
          if (mounted) {
            setState(() {
              _isListening = false;
            });
          }
          _amplitudeSub?.cancel();
          _listeningTimeoutTimer?.cancel();
        }
      },
    );
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
          
          if (_isListening)
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: FadeTransition(
                opacity: _contentFade,
                child: VoiceWaveform(
                  amplitude: _currentAmplitude,
                  isListening: _isListening,
                ),
              ),
            ),

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
          AnalysisStaticImage(data: _data, imageDissolve: _imageDissolve),
          Expanded(
            child: Stack(
              children: [
                if (_transitionController.value < 1.0)
                  AnalysisGeneratingCard(
                    titleFadeOut: _titleFadeOut,
                    titleSlideOut: _titleSlideOut,
                    skeletonFade: _skeletonFade,
                    isLandscape: false,
                  ),
                if (_transitionController.value > 0.0 || _phase == AnalysisPhase.complete)
                  AnalysisResultCard(
                    data: _data,
                    contentFade: _contentFade,
                    titleSlideIn: _titleSlideIn,
                    scrollController: _infoScrollController,
                    onManualScroll: () => _isUserScrolling = true,
                    onNavigate: _startNavigation,
                    isLandscape: false,
                  ),
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
          Expanded(
            flex: 2,
            child: AnalysisStaticImage(data: _data, imageDissolve: _imageDissolve),
          ),
          
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 24.0, bottom: 24.0, top: 24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_transitionController.value < 1.0)
                    SingleChildScrollView(
                      child: AnalysisGeneratingCard(
                        titleFadeOut: _titleFadeOut,
                        titleSlideOut: _titleSlideOut,
                        skeletonFade: _skeletonFade,
                        isLandscape: true,
                      ),
                    ),
                  if (_transitionController.value > 0.0 || _phase == AnalysisPhase.complete)
                    AnalysisResultCard(
                      data: _data,
                      contentFade: _contentFade,
                      titleSlideIn: _titleSlideIn,
                      scrollController: _infoScrollController,
                      onManualScroll: () => _isUserScrolling = true,
                      onNavigate: _startNavigation,
                      isLandscape: true,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
