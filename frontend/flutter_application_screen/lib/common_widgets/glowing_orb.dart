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
        _breathingController.duration = const Duration(milliseconds: 1000);
        _breathingController.repeat(reverse: true);
      } else {
        _breathingController.duration = const Duration(seconds: 4);
        _breathingController.repeat(reverse: true);
      }
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
    
    setState(() {
      _targetEyeOffset = Offset(dx, dy);
      _currentEyeOffset = Offset.lerp(_currentEyeOffset, _targetEyeOffset, 0.4) ?? _targetEyeOffset;
    });
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
      if (_isTracking) {
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
        
        return Transform.translate(
          offset: totalOffset,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isStable ? const Color(0xFFE2F063) : AppColors.orbBackground,
              boxShadow: [
                // Inner glow (Breathing)
                BoxShadow(
                  color: (_isStable ? Colors.white : AppColors.orbGlowYellow).withValues(alpha: 0.5 + (_breathingAnimation.value * 0.3)),
                  blurRadius: (_isStable ? 40 : 30) + (_breathingAnimation.value * 15),
                  spreadRadius: (_isStable ? 15 : 10) + (_breathingAnimation.value * 8),
                ),
                // Outer glow (Breathing)
                BoxShadow(
                  color: AppColors.orbGlowOuter.withValues(alpha: 0.3 + (_breathingAnimation.value * 0.2)),
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
                      _buildEye(),
                      SizedBox(width: widget.size * (_isStable ? 0.2 : 0.15)),
                      _buildEye(),
                    ],
                  ),
                ),
                if (_isStable)
                   Center(
                     child: Container(
                       width: widget.size * 0.4,
                       height: 2,
                       decoration: BoxDecoration(
                         color: Colors.white.withValues(alpha: 0.5 * _breathingAnimation.value),
                         boxShadow: [
                           BoxShadow(color: Colors.white, blurRadius: 4 * _breathingAnimation.value),
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

  Widget _buildEye() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: _isStable ? widget.size * 0.08 : widget.size * 0.06,
      height: _isBlinking ? 0.0 : (_isStable ? 2.0 : widget.size * 0.06),
      decoration: BoxDecoration(
        color: _isStable ? Colors.black : Colors.white,
        shape: _isStable ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: _isStable ? BorderRadius.circular(1) : null,
        boxShadow: [
          BoxShadow(
            color: _isStable ? Colors.black26 : Colors.white54,
            blurRadius: 5,
            spreadRadius: 2,
          ),
        ],
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
