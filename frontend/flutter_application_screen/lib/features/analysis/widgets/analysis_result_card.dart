import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../analysis_model.dart';
import '../../../core/theme/app_colors.dart';

class AnalysisResultCard extends StatelessWidget {
  final AnalysisData data;
  final Animation<double> contentFade;
  final Animation<Offset> titleSlideIn;
  final ScrollController scrollController;
  final VoidCallback onManualScroll;
  final VoidCallback onNavigate;
  final bool isLandscape;

  const AnalysisResultCard({
    super.key,
    required this.data,
    required this.contentFade,
    required this.titleSlideIn,
    required this.scrollController,
    required this.onManualScroll,
    required this.onNavigate,
    required this.isLandscape,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: contentFade,
      child: Padding(
        padding: EdgeInsets.only(
          left: isLandscape ? 0 : 24.0,
          right: isLandscape ? 0 : 24.0,
          bottom: isLandscape ? 0 : 24.0,
        ),
        child: Container(
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
                if (notification.direction != ScrollDirection.idle) {
                  onManualScroll();
                }
              }
              return false;
            },
            child: SingleChildScrollView(
              controller: scrollController,
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
                      data.tag,
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
                    position: titleSlideIn,
                    child: Text(
                      data.title,
                      style: TextStyle(
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
                      const Icon(Icons.calendar_today, size: 16, color: Color(0xFF52A574)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          data.subtitle,
                          style: const TextStyle(
                            color: Color(0xFF52A574),
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
                    data.description,
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
        ),
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
          onTap: onNavigate,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: (data.latitude != null && data.longitude != null) 
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
                      data.latitude != null ? "Navigate there" : "Location unknown",
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
