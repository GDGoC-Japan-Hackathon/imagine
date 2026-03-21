import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_screen/core/services/vision/face_tracker_service.dart';
import 'package:flutter_application_screen/core/models/face_vector.dart';
import 'package:flutter_application_screen/core/constants/app_constants.dart';

void main() {
  group('FaceTrackerService Tests', () {
    late FaceTrackerService faceTracker;
    const int requiredStableFrames = AppConstants.requiredStableFrames;

    setUp(() {
      faceTracker = FaceTrackerService();
      faceTracker.reset();
    });

    test('Initial progress should be 0.0', () {
      expect(faceTracker.currentProgress, 0.0);
    });

    test('Progress should increase when face is stable within threshold', () {
      faceTracker.getStableProgress([const FaceVector(0.0, 0.0)]);
      final progress = faceTracker.getStableProgress([const FaceVector(0.1, 0.1)]);
      expect(progress, 1 / requiredStableFrames);
    });

    test('Progress should reach 1.0 after required stable frames', () {
      faceTracker.getStableProgress([const FaceVector(0.0, 0.0)]);
      double lastProgress = 0.0;
      for (int i = 0; i < requiredStableFrames; i++) {
        lastProgress = faceTracker.getStableProgress([const FaceVector(0.2, 0.2)]);
      }
      expect(lastProgress, 1.0);
    });

    test('Progress should reset when face moves out of threshold', () {
      faceTracker.getStableProgress([const FaceVector(0.0, 0.0)]);
      for (int i = 0; i < 10; i++) {
        faceTracker.getStableProgress([const FaceVector(0.1, 0.1)]);
      }
      final progress = faceTracker.getStableProgress([const FaceVector(5.0, 5.0)]);
      expect(progress, 0.0);
    });
  });
}
