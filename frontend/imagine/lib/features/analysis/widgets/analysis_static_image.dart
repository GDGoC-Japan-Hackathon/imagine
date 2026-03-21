import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/models/analysis_model.dart';
import 'dart:math' as math;

class AnalysisStaticImage extends StatelessWidget {
  final AnalysisData data;
  final Animation<double> imageDissolve;

  const AnalysisStaticImage({
    super.key,
    required this.data,
    required this.imageDissolve,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: imageDissolve,
      builder: (context, child) {
        return _buildStaticImageArea();
      },
    );
  }

  Widget _buildStaticImageArea() {
    final polygon = data.polygon;
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
                  opacity: 1.0 - imageDissolve.value,
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
                  opacity: imageDissolve.value,
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

  Widget _buildImageWithCrop() {
    final polygon = data.polygon;
    final imagePath = data.imagePath;
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
        final viewW = constraints.maxWidth;
        final viewH = constraints.maxHeight;

        // 対象物が画面の約70%を占めるようにズーム率を計算（1.0〜4.0 倍に制限）
        final zoomScale = (0.70 / math.max(0.1, math.max(w, h))).clamp(1.0, 4.0);

        // 対象物の中心を表示領域の中心に移動するためのオフセットを計算
        // cx, cy は画像全体に対する対象物中心の割合（0.0〜1.0）
        // 画像が BoxFit.cover で表示されるため、表示領域サイズ基準で計算
        final offsetX = (0.5 - cx) * viewW * zoomScale;
        final offsetY = (0.5 - cy) * viewH * zoomScale;

        return ClipRect(
          child: Transform.translate(
            offset: Offset(offsetX, offsetY),
            child: Transform.scale(
              scale: zoomScale,
              alignment: Alignment.center,
              child: Image(
                image: imageProvider,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    );
  }
}
