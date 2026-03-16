import 'package:flutter/material.dart';
import '../../common_widgets/glowing_orb.dart';
import '../../common_widgets/primary_button.dart';
import '../analysis/analysis_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<GlowingOrbState> _orbKey = GlobalKey<GlowingOrbState>();

  void _navigateToGenerating() {
    // Navigate to the generating screen when asked
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
              const Text(
                "Built-in Gemini 3 Flash",
                style: TextStyle(
                  color: Color(0xFF44474E),
                  fontSize: 16, // Increased for AAOS
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              PrimaryButton(
                label: "Ask me",
                icon: Icons.mic_none_outlined,
                onPressed: _navigateToGenerating,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
