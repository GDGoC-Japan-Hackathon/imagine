import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_screen/features/camera/services/face_tracker_service.dart';
import 'package:flutter_application_screen/features/camera/models/face_vector.dart';
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

    test('Single detection should return 0.0 progress and initialize anchor', () {
      final progress = faceTracker.getStableProgress([const FaceVector(0.0, 0.0)]);
      expect(progress, 0.0);
      expect(faceTracker.currentProgress, 0.0);
    });

    test('Progress should increase when face is stable within threshold', () {
      // First frame sets the anchor (progress: 0/20)
      faceTracker.getStableProgress([const FaceVector(0.0, 0.0)]);
      
      // Second frame within range (progress: 1/20)
      final progress = faceTracker.getStableProgress([const FaceVector(0.1, 0.1)]);
      expect(progress, 1 / requiredStableFrames);
      expect(faceTracker.currentProgress, 1 / requiredStableFrames);
    });

    test('Progress should reach 1.0 after required stable frames', () {
      // First frame (anchor)
      faceTracker.getStableProgress([const FaceVector(0.0, 0.0)]);

      // 20 more frames within threshold (total 21 frames)
      double lastProgress = 0.0;
      for (int i = 0; i < requiredStableFrames; i++) {
        lastProgress = faceTracker.getStableProgress([const FaceVector(0.2, 0.2)]);
      }

      expect(lastProgress, 1.0);
      expect(faceTracker.currentProgress, 1.0);
    });

    test('Progress should reset when face moves out of threshold', () {
      // Stabilize for 10 frames
      faceTracker.getStableProgress([const FaceVector(0.0, 0.0)]);
      for (int i = 0; i < 10; i++) {
        faceTracker.getStableProgress([const FaceVector(0.1, 0.1)]);
      }
      expect(faceTracker.currentProgress, 10 / requiredStableFrames);

      // Move out of threshold (threshold is around 1.0)
      final progress = faceTracker.getStableProgress([const FaceVector(2.0, 0.0)]);
      expect(progress, 0.0);
      expect(faceTracker.currentProgress, 0.0);
    });

    test('Multiple faces should take the max progress', () {
      // Face 0 is stable for 5 frames
      for (int i = 0; i < 6; i++) {
        faceTracker.getStableProgress([
          const FaceVector(0.0, 0.0), // Face 0
          const FaceVector(10.0, 10.0), // Face 1 (moving or new)
        ]);
      }
      expect(faceTracker.currentProgress, 5 / requiredStableFrames);
    });

    test('Reset should clear all states', () {
      faceTracker.getStableProgress([const FaceVector(0.0, 0.0)]);
      faceTracker.getStableProgress([const FaceVector(0.1, 0.1)]);
      expect(faceTracker.currentProgress, 1 / requiredStableFrames);

      faceTracker.reset();
      expect(faceTracker.currentProgress, 0.0);
    });
  });
}
