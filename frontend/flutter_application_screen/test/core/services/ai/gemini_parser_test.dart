import 'package:flutter_test/flutter_test.dart';
import 'package:imagine/core/services/ai/gemini_parser.dart';
import 'package:imagine/core/errors/exceptions.dart';

void main() {
  group('GeminiParser Tests', () {
    test('parseAnalysisResponse should correctly parse valid JSON', () {
      const jsonText = '```json\n{\n  "名前": "東京タワー",\n  "解説": "日本のシンボルです。",\n  "polygon": [100, 200, 300, 400],\n  "latitude": 35.6586,\n  "longitude": 139.7454\n}\n```';
      
      final result = GeminiParser.parseAnalysisResponse(jsonText);
      
      expect(result.targetName, '東京タワー');
      expect(result.guideDesc, '日本のシンボルです。');
      expect(result.segData[0]['polygon'], [100, 200, 300, 400]);
      expect(result.latitude, 35.6586);
      expect(result.longitude, 139.7454);
    });

    test('parseAnalysisResponse should throw DataParsingException on invalid JSON', () {
      const invalidJson = '{"invalid": "format"'; 
      expect(() => GeminiParser.parseAnalysisResponse(invalidJson), throwsA(isA<DataParsingException>()));
    });

    test('parseVoiceIntentResponse should correctly parse positive intent', () {
      const jsonText = '{"positive": true}';
      final result = GeminiParser.parseVoiceIntentResponse(jsonText);
      expect(result, isTrue);
    });

    test('parseVoiceIntentResponse should return false on invalid JSON', () {
      const invalidJson = 'invalid';
      final result = GeminiParser.parseVoiceIntentResponse(invalidJson);
      expect(result, isFalse);
    });
  });
}
