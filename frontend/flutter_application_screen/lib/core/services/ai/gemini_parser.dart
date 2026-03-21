import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/gemini_analysis_result.dart';
import '../../errors/exceptions.dart';

/// Gemini API からのレスポンス (JSON) をパースするユーティリティ
class GeminiParser {
  /// AI による画像解析結果をパースします。
  static GeminiAnalysisResult parseAnalysisResponse(String text) {
    try {
      final jsonText = _cleanJsonResponse(text);
      final Map<String, dynamic> decoded = jsonDecode(jsonText);
      
      final targetName = decoded["名前"]?.toString() ?? "指定位置の対象物";
      final guideDesc = decoded["解説"]?.toString() ?? "解説を取得できませんでした。";
      
      final List<dynamic> polygon = decoded["polygon"] is List ? decoded["polygon"] : [0, 0, 1000, 1000];
      final segData = [ {"polygon": polygon} ];
      
      final double? latitude = decoded["latitude"] is num ? (decoded["latitude"] as num).toDouble() : null;
      final double? longitude = decoded["longitude"] is num ? (decoded["longitude"] as num).toDouble() : null;
      
      return GeminiAnalysisResult(targetName, guideDesc, segData, latitude: latitude, longitude: longitude);
    } catch (e) {
      debugPrint("JSON Parse Error (Analysis): $e\nRaw: $text");
      throw DataParsingException("AIの解析結果の読み取りに失敗しました");
    }
  }

  /// 音声インテント解析結果をパースします。
  static bool parseVoiceIntentResponse(String text) {
    try {
      final jsonText = _cleanJsonResponse(text);
      final Map<String, dynamic> decoded = jsonDecode(jsonText);
      return decoded["positive"] == true;
    } catch (e) {
      debugPrint("JSON Parse Error (Intent): $e\nRaw: $text");
      return false;
    }
  }

  static String _cleanJsonResponse(String text) {
    String cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      final lines = cleaned.split('\n');
      if (lines.length > 2) {
        cleaned = lines.sublist(1, lines.length - 1).join('\n');
      }
    }
    return cleaned;
  }
}
