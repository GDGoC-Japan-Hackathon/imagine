/// アプリケーション全体で使用される定数クラス
class AppConstants {
  // --- カメラ関連 (CameraConfig) ---
  static const int defaultManualIndex = -1;
  static const Duration cameraRetryDelay = Duration(seconds: 1);
  static const Duration cameraRetryDelayAaos = Duration(seconds: 3);
  static const int cameraRetryCount = 3;
  static const Duration cameraCaptureDelay = Duration(milliseconds: 200);
  static const Duration networkCaptureSwitchDelay = Duration(milliseconds: 1500);
  static const int networkCaptureSkipFrames = 5;
  static const Duration networkCaptureTimeout = Duration(seconds: 4);
  
  // --- 初期化リトライ関連 ---
  static const int maxInitRetryCount = 2;
  static const Duration initRetryDelay = Duration(seconds: 3);

  // --- ビジョン/トラチE��ング関連 (VisionConfig) ---
  static const int requiredStableFrames = 20; 
  static const double yawThreshold = 1.0;
  static const double pitchThreshold = 1.0;
  static const double faceWidthMinThreshold = 0.02;
  static const Duration faceLostGracePeriod = Duration(milliseconds: 2000);
  static const Duration mediapipeProcessingInterval = Duration(milliseconds: 30);

  // --- Gemini設宁E(GeminiService) ---
  static const String geminiModelName = 'gemini-2.5-flash';
  static const String ttsModelName = 'gemini-2.5-pro-tts';
  static const String ttsVoiceName = 'Achernar';
  static const String ttsLanguageCode = 'ja-jp';

  // --- ネットワーク/リレー関連 (NetworkConfig) ---
  static const String defaultRelayWsUrl = 'ws://127.0.0.1:8080';
  
  // --- UI/ナビゲーション関連 (UiConfig) ---
  static const Duration guidanceTimerInterval = Duration(seconds: 1);
  static const int guidanceNoFaceThresholdSeconds = 5;
  static const Duration screenTransitionDuration = Duration(milliseconds: 600);
  static const Duration reverseTransitionDuration = Duration(milliseconds: 400);
}
