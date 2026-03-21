import 'dart:io';
import 'dart:typed_data';
import '../../models/gemini_analysis_result.dart';
import 'gemini_client.dart';
import 'analysis_service.dart';
import 'tts_service.dart';
import 'voice_intent_service.dart';

/// Gemini AI に関する全ての機能を提供する総合サービス。
/// 既存のコードとの互換性を保ちつつ、内部的に機能別のサービスへ委譲します。
class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  final GeminiClient _client = GeminiClient();
  final AnalysisService _analysis = AnalysisService();
  final TtsService _tts = TtsService();
  final VoiceIntentService _intent = VoiceIntentService();

  /// サービスを初期化します。
  void initialize(String geminiKey, String? serviceAccountJson) {
    _client.initialize(geminiKey);
    _tts.initialize(serviceAccountJson);
  }

  /// 画像を解析して結果を返します。
  Future<GeminiAnalysisResult> analyzeAndMask(File imageFile, double pan, double tilt) {
    return _analysis.analyzeImage(imageFile, pan, tilt);
  }

  /// テキストを音声に変換します。
  Future<Uint8List?> synthesizeSpeech(String text) {
    return _tts.synthesize(text);
  }

  /// 音声インテントを分類します。
  Future<bool> classifyVoiceIntent(Uint8List audioBytes) {
    return _intent.classifyIntent(audioBytes);
  }
}
