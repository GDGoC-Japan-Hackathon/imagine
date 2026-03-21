/// アプリケーション全体で使用される基本例外クラス
abstract class AppException implements Exception {
  final String message;
  final String? code;

  AppException(this.message, [this.code]);

  @override
  String toString() => "[$code] $message";
}

/// カメラ操作に関連する例外
class CameraException extends AppException {
  CameraException(String message, [String? code]) : super(message, code ?? 'CAMERA_ERROR');
}

/// AI (Gemini) 関連の処理で発生する例外
class GeminiException extends AppException {
  GeminiException(String message, [String? code]) : super(message, code ?? 'GEMINI_ERROR');
}

/// ネットワーク通信に関連する例外
class NetworkException extends AppException {
  NetworkException(String message, [String? code]) : super(message, code ?? 'NETWORK_ERROR');
}

/// 権限不足により発生する例外
class PermissionException extends AppException {
  PermissionException(String message, [String? code]) : super(message, code ?? 'PERMISSION_ERROR');
}

/// データの解析や変換に失敗した際の例外
class DataParsingException extends AppException {
  DataParsingException(String message, [String? code]) : super(message, code ?? 'DATA_PARSING_ERROR');
}
