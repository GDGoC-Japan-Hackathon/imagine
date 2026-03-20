import 'dart:math' as math;
import 'package:flutter/material.dart';

class VoiceWaveform extends StatefulWidget {
  final double amplitude; // -160.0 to 0.0 (dB)
  final bool isListening;

  const VoiceWaveform({
    super.key,
    required this.amplitude,
    required this.isListening,
  });

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  
  double get _normAmp {
    if (!widget.isListening) return 0.0;
    final val = (widget.amplitude + 50) / 40;
    return val.clamp(0.05, 0.8);
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(double.infinity, 80),
          painter: WavePainter(
            phase: _animController.value * 2 * math.pi,
            amplitude: _normAmp,
            isListening: widget.isListening,
          ),
        );
      },
    );
  }
}

class WavePainter extends CustomPainter {
  final double phase;
  final double amplitude;
  final bool isListening;

  WavePainter({
    required this.phase,
    required this.amplitude,
    required this.isListening,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isListening) return;

    // 青色の階調
    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFF64B5F6),
      const Color(0xFF2196F3),
      const Color(0xFF1976D2),
    ];

    final centerY = size.height / 2;
    
    for (int i = 0; i < colors.length; i++) {
      final paint = Paint()
        ..color = colors[i].withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);

      final path = Path();
      final wavePhase = phase + (i * math.pi / 2);
      final waveAmplitude = amplitude * size.height * (0.3 + (i * 0.1));

      path.moveTo(0, centerY);
      
      for (double x = 0; x <= size.width; x += 3) {
        final dy = math.sin(x * 0.015 + wavePhase) * waveAmplitude + 
                   math.sin(x * 0.03 - wavePhase * 0.8) * (waveAmplitude * 0.2);
        
        final edgeFade = math.sin(x / size.width * math.pi);
        path.lineTo(x, centerY + dy * edgeFade);
      }
      
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.amplitude != amplitude || oldDelegate.isListening != isListening;
  }
}
