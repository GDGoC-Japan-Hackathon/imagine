import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class GlowingOrb extends StatefulWidget {
  final double size;
  const GlowingOrb({super.key, this.size = 180.0});

  @override
  State<GlowingOrb> createState() => GlowingOrbState();
}

class GlowingOrbState extends State<GlowingOrb> with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late AnimationController _floatingController;
  late AnimationController _lookingController;
  late AnimationController _pullController;

  late Animation<double> _breathingAnimation;
  
  // Floating animation variables
  late Animation<double> _floatingYAnimation;
  late Animation<double> _floatingXAnimation;

  // Looking around and blinking animation variables
  Offset _currentEyeOffset = Offset.zero;
  Offset _targetEyeOffset = Offset.zero;
  bool _isBlinking = false;
  bool _isStable = false;
  bool _isTracking = false;
  
  // Interactive Pull variables
  Offset _currentPullOffset = Offset.zero;

  // MediaPipe Blendshapes
  double _smileScore = 0.0;
  double _leftBlinkScore = 0.0;
  double _rightBlinkScore = 0.0;
  double _squintScore = 0.0;

  // Face stabilization progress (0.0 to 1.0)
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();

    // 1. Breathing Animation (Glow intensity)
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _breathingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOutSine),
    );

    // 2. Floating Animation (Figure-8 motion)
    _floatingController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 8),
    )..repeat();

    _floatingYAnimation = Tween<double>(begin: -10.0, end: 10.0).animate(
      CurvedAnimation(parent: _floatingController, curve: _SineCurve()),
    );
    
    _floatingXAnimation = Tween<double>(begin: -5.0, end: 5.0).animate(
      CurvedAnimation(parent: _floatingController, curve: _CosineCurve()),
    );

    // 3. Pull Interaction Animation
    _pullController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400), // Default duration
    );

    _pullController.addListener(() {
      setState(() {});
    });

    // 3. Looking Around Animation (Random eye movement)
    _lookingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _lookingController.addListener(() {
      setState(() {
         // Interpolate between current and target
        _currentEyeOffset = Offset.lerp(_currentEyeOffset, _targetEyeOffset, _lookingController.value) ?? _currentEyeOffset;
      });
    });

    _startRandomLooking();
    _startRandomBlinking();
  }

  void setStable(bool stable) {
    if (_isStable == stable) return;
    setState(() {
      _isStable = stable;
      if (stable) {
        _isBlinking = false;
        _progress = 1.0;
        // 螳牙ｮ壽凾縺ｯ鬮倬溘〒蠑ｷ辜医↑繝代Ν繧ｹ
        _breathingController.duration = const Duration(milliseconds: 600);
        _breathingController.repeat(reverse: true);
      } else {
        // 騾壼ｸｸ譎ゅ√∪縺溘・繝医Λ繝・く繝ｳ繧ｰ荳ｭ縺ｮ縺ｿ縺ｮ蝣ｴ蜷医・蜈・・騾溷ｺｦ縺ｸ
        _breathingController.duration = _isTracking ? const Duration(seconds: 2) : const Duration(seconds: 4);
        _breathingController.repeat(reverse: true);
      }
    });
  }

  void setProgress(double progress) {
    if (!mounted) return;
    setState(() {
      _progress = progress.clamp(0.0, 1.0);
    });
  }

  void setTracking(bool tracking) {
    if (_isTracking == tracking) return;
    setState(() {
      _isTracking = tracking;
      if (tracking) {
        _breathingController.duration = const Duration(seconds: 2);
      } else {
        _breathingController.duration = const Duration(seconds: 4);
        _smileScore = 0;
        _leftBlinkScore = 0;
        _rightBlinkScore = 0;
        _squintScore = 0;
      }
      _breathingController.repeat(reverse: true);
    });
  }

  void setBlendshapes(Map<String, double> scores) {
    if (!mounted) return;
    setState(() {
      // MediaPipe Blendshape categories
      _smileScore = (scores['mouthSmileLeft'] ?? 0) + (scores['mouthSmileRight'] ?? 0) / 2;
      _leftBlinkScore = scores['eyeBlinkLeft'] ?? 0;
      _rightBlinkScore = scores['eyeBlinkRight'] ?? 0;
      _squintScore = (scores['eyeSquintLeft'] ?? 0) + (scores['eyeSquintRight'] ?? 0) / 2;
    });
  }

  void setFaceOffset(Offset? offset) {
    if (offset == null) {
      if (_isTracking) {
        setState(() {
          _isTracking = false;
        });
        _startRandomLooking();
      }
      return;
    }

    _isTracking = true;
    // Map camera normalized coordinates to orb displacement
    // Let's assume input offset is roughly -30 to 30 for meaningful range
    final dx = offset.dx.clamp(-1.0, 1.0) * (widget.size * 0.2);
    final dy = offset.dy.clamp(-1.0, 1.0) * (widget.size * 0.2);
    
    // Only visually follow the face if we have meaningful progress
    if (_progress >= 0.5) {
      setState(() {
        _targetEyeOffset = Offset(dx, dy);
        _currentEyeOffset = Offset.lerp(_currentEyeOffset, _targetEyeOffset, 0.4) ?? _targetEyeOffset;
      });
    } else {
      // Keep target at zero or let random looking handle it
      _targetEyeOffset = Offset.zero;
    }
  }

  void pullTowards(Offset tapDelta) async {
    final distance = tapDelta.distance;
    final maxPull = widget.size * 0.3; // Pull up to 30% of size
    final direction = distance > 0 ? (tapDelta / distance) : Offset.zero;
    
    _currentPullOffset = direction * maxPull;
    
    // Move towards tap
    if (mounted) {
      await _pullController.animateTo(1.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
    
    // Return to center slowly with elastic effect
    if (mounted) {
      await _pullController.animateTo(0.0, duration: const Duration(milliseconds: 1500), curve: Curves.elasticOut);
    }
  }

  void _startRandomBlinking() async {
    final random = math.Random();
    while (mounted) {
      // Wait before blink
      await Future.delayed(Duration(milliseconds: 2000 + random.nextInt(4000)));
      if (!mounted) break;
      
      setState(() { _isBlinking = true; });
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) break;
      setState(() { _isBlinking = false; });
      
      // 30% chance for a double blink
      if (random.nextDouble() > 0.7) {
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted) break;
        setState(() { _isBlinking = true; });
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted) break;
        setState(() { _isBlinking = false; });
      }
    }
  }

  void _startRandomLooking() async {
    final random = math.Random();
    while (mounted) {
      if (_isTracking && _progress >= 0.5) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }
      // 1. Wait a random amount of time (the "tame" or pause)
      final pauseDuration = Duration(milliseconds: 500 + random.nextInt(2000));
      await Future.delayed(pauseDuration);
      if (!mounted) break;

      // 2. Pick a new random target offset for the eyes
      // Max displacement is about 15% of the orb size
      final maxDisplacement = widget.size * 0.15;
      final angle = random.nextDouble() * 2 * math.pi;
      final distance = random.nextDouble() * maxDisplacement;
      
      final dx = math.cos(angle) * distance;
      final dy = math.sin(angle) * distance;
      
      _targetEyeOffset = Offset(dx, dy);

      // 3. Animate to the new offset
      _lookingController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _floatingController.dispose();
    _lookingController.dispose();
    _pullController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_breathingController, _floatingController]),
      builder: (context, child) {
        final interactiveOffset = _currentPullOffset * _pullController.value;
        final totalOffset = Offset(_floatingXAnimation.value, _floatingYAnimation.value) + interactiveOffset;
        
        return Center(
          child: SizedBox(
            width: widget.size * 1.4,
            height: widget.size * 1.4,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // outer progress ring
                if ((_isTracking || _progress > 0) && _progress >= 0.5)
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: _progress),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, value, child) {
                      return SizedBox(
                        width: widget.size * 1.25,
                        height: widget.size * 1.25,
                        child: CircularProgressIndicator(
                          value: value,
                          strokeWidth: 4,
                          backgroundColor: Colors.white10,
                          color: _isStable ? const Color(0xFFE2F063) : const Color(0xFFBCCB3D).withValues(alpha: 0.8),
                        ),
                      );
                    },
                  ),
                
                // Shadow for the ring
                if ((_isTracking || _progress > 0) && _progress >= 0.5)
                  Container(
                    width: widget.size * 1.25,
                    height: widget.size * 1.25,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isStable ? const Color(0xFFE2F063) : const Color(0xFFBCCB3D)).withValues(alpha: 0.2),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),

                Transform.translate(
                  offset: totalOffset,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isStable 
                        ? const Color(0xFFE2F063) 
                        : ((_isTracking && _progress >= 0.5) ? const Color(0xFFD4E157) : AppColors.orbBackground),
                      boxShadow: [
                        // Inner glow (Breathing)
                        BoxShadow(
                          color: (_isStable ? Colors.white : ((_isTracking && _progress >= 0.5) ? const Color(0xFFE2F063) : AppColors.orbGlowYellow))
                              .withValues(alpha: 0.5 + (_breathingAnimation.value * 0.3)),
                          blurRadius: (_isStable ? 45 : ((_isTracking && _progress >= 0.5) ? 35 : 30)) + (_breathingAnimation.value * 15),
                          spreadRadius: (_isStable ? 18 : ((_isTracking && _progress >= 0.5) ? 12 : 10)) + (_breathingAnimation.value * 8),
                        ),
                        // Outer glow (Breathing)
                        BoxShadow(
                          color: ((_isTracking && _progress >= 0.5) ? const Color(0xFFBCCB3D).withValues(alpha: 0.4) : AppColors.orbGlowOuter.withValues(alpha: 0.3))
                              .withValues(alpha: 0.3 + (_breathingAnimation.value * 0.2)),
                          blurRadius: 60 + (_breathingAnimation.value * 20),
                          spreadRadius: 20 + (_breathingAnimation.value * 10),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Central subtle yellow gradient base
                        Container(
                          width: widget.size * 0.8,
                          height: widget.size * 0.8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.orbGlowYellow.withValues(alpha: 0.8),
                                Colors.transparent,
                              ],
                              stops: const [0.1, 0.8],
                            ),
                          ),
                        ),
                        // Eyes (Translates based on looking animation)
                        Transform.translate(
                          offset: _currentEyeOffset,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildEye(isLeft: true),
                              SizedBox(width: widget.size * (_isStable ? 0.2 : 0.15)),
                              _buildEye(isLeft: false),
                            ],
                          ),
                        ),
                         // Central subtle yellow gradient base
                        if (_isTracking && _progress >= 0.5)
                          Transform.translate(
                             offset: _currentEyeOffset,
                             child: Container(
                                width: widget.size * 0.8,
                                height: widget.size * 0.2,
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    colors: [
                                      const Color(0xFFE2F063).withValues(alpha: 0.3),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                             ),
                          ),
                        if (_isStable)
                           Center(
                             child: Container(
                               width: widget.size * 0.4,
                               height: 2,
                               decoration: BoxDecoration(
                                 color: Colors.black.withValues(alpha: 0.5 * _breathingAnimation.value),
                                 boxShadow: [
                                   BoxShadow(color: Colors.white, blurRadius: 4 * _breathingAnimation.value),
                                 ],
                               ),
                             ),
                           ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEye({required bool isLeft}) {
    final blinkScore = isLeft ? _leftBlinkScore : _rightBlinkScore;
    
    final bool visuallyTracking = _isTracking && _progress >= 0.5;
    
    // 繝励Ο繧ｰ繝ｬ繧ｹ縺ｫ蜷医ｏ縺帙※讓ｪ蟷・ｒ蠎・￡縲・ｫ倥＆繧堤ｵ槭ｋ・医ヵ繧ｩ繝ｼ繧ｫ繧ｹ蜉ｹ譫懶ｼ・
    final double focusWidthFactor = visuallyTracking ? (0.06 + _progress * 0.04) : 0.06;
    final double focusHeightFactor = visuallyTracking ? (0.06 - _progress * 0.04) : 0.06;

    final eyeWidth = _isStable 
        ? widget.size * 0.12 
        : (visuallyTracking ? (widget.size * (focusWidthFactor + _smileScore * 0.02)) : widget.size * 0.06);
    
    // 繧ｹ繝槭う繝ｫ繧・せ繧ｯ繧､繝ｳ繝医〒鬮倥＆縺梧ｸ帙ｋ縲√∪縺ｰ縺溘″縺ｧ髢峨§繧・
    double eyeHeight = _isStable ? 2.0 : (visuallyTracking ? widget.size * focusHeightFactor : widget.size * 0.06);
    
    if (_isBlinking || blinkScore > 0.5) {
      eyeHeight = 0.0;
    } else if (visuallyTracking && !_isStable) {
      // 隨鷹｡斐Ξ繝吶Ν縺ｫ蜷医ｏ縺帙※縺輔ｉ縺ｫ逶ｮ繧堤ｴｰ繧√ｋ
      eyeHeight = eyeHeight * (1.0 - (_smileScore * 0.5 + _squintScore * 0.3)).clamp(0.1, 1.0);
    }

    // 繝励Ο繧ｰ繝ｬ繧ｹ縺碁ｫ倥＞縺ｻ縺ｩ迸ｳ縺梧・繧九￥霈昴￥
    final eyeColor = _isStable 
        ? Colors.black 
        : (visuallyTracking ? (Color.lerp(Colors.white, const Color(0xFFE2F063), _progress) ?? Colors.white) : Colors.white);

    return Flexible(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        width: eyeWidth,
        height: eyeHeight,
        decoration: BoxDecoration(
          color: eyeColor,
          borderRadius: BorderRadius.circular(_isStable ? 1 : widget.size),
          shape: BoxShape.rectangle,
          boxShadow: [
            BoxShadow(
              color: _isStable 
                  ? Colors.black26 
                  : (visuallyTracking ? (Color.lerp(Colors.white54, const Color(0xFFE2F063), _progress) ?? Colors.white54) : Colors.transparent),
              blurRadius: 5 + (_progress * 5),
              spreadRadius: 2 + (_progress * 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _SineCurve extends Curve {
  @override
  double transformInternal(double t) {
    return math.sin(t * 2 * math.pi);
  }
}

class _CosineCurve extends Curve {
  @override
  double transformInternal(double t) {
    // Multiplied by 2 for a figure-8 like motion on X relative to sine on Y
    return math.cos(t * 4 * math.pi);
  }
}
