import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/theme/app_colors.dart';

class AnalysisGeneratingCard extends StatelessWidget {
  final Animation<double> titleFadeOut;
  final Animation<Offset> titleSlideOut;
  final Animation<double> skeletonFade;
  final bool isLandscape;

  const AnalysisGeneratingCard({
    super.key,
    required this.titleFadeOut,
    required this.titleSlideOut,
    required this.skeletonFade,
    required this.isLandscape,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: titleFadeOut,
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
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTagRow("AI ANALYSIS IN PROGRESS"),
              const SizedBox(height: 12),
              
              SlideTransition(
                position: titleSlideOut,
                child: Text(
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
                opacity: skeletonFade,
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
    );
  }

  Widget _buildTagRow(String text) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
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
}
