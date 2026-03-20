import 'package:google_generative_ai/google_generative_ai.dart';
import '../../constants/app_constants.dart';

/// Gemini API との低レベルな通信を担当するクライアント
class GeminiClient {
  static final GeminiClient _instance = GeminiClient._internal();
  factory GeminiClient() => _instance;
  GeminiClient._internal();

  GenerativeModel? _model;
  String? _apiKey;

  /// クライアントの初期化
  void initialize(String apiKey) {
    if (_apiKey == apiKey && _model != null) return;
    _apiKey = apiKey;
    _model = GenerativeModel(
      model: AppConstants.geminiModelName,
      apiKey: apiKey,
    );
  }

  GenerativeModel get model {
    if (_model == null) {
      throw StateError("GeminiClient is not initialized. Call initialize() first.");
    }
    return _model!;
  }
}
