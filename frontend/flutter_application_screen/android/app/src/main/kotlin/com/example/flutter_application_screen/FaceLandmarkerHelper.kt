package com.example.flutter_application_screen

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.SystemClock
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult

class FaceLandmarkerHelper(
    private val context: Context,
    private val resultListener: (FaceLandmarkerResult?, MPImage) -> Unit,
    private val errorListener: (String) -> Unit
) {
    private val TAG = "FaceLandmarkerHelper"
    private var faceLandmarker: FaceLandmarker? = null

    init {
        setupFaceLandmarker()
    }

    fun setupFaceLandmarker() {
        val baseOptionsBuilder = BaseOptions.builder().setModelAssetPath("face_landmarker.task")

        try {
            val optionsBuilder =
                FaceLandmarker.FaceLandmarkerOptions.builder()
                    .setBaseOptions(baseOptionsBuilder.build())
                    .setMinFaceDetectionConfidence(0.2f)
                    .setMinTrackingConfidence(0.2f)
                    .setMinFacePresenceConfidence(0.2f)
                    .setResultListener(this::returnDetectionResult)
                    .setErrorListener(this::returnDetectionError)
                    .setRunningMode(RunningMode.LIVE_STREAM)

            faceLandmarker = FaceLandmarker.createFromOptions(context, optionsBuilder.build())
            android.util.Log.d(TAG, "FaceLandmarker initialized successfully")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Face Landmarker init failed", e)
            errorListener("Face Landmarker init failed: ${e.message}")
        }
    }

    fun detectLiveStream(bitmap: Bitmap, isFrontCamera: Boolean, rotation: Int) {
        if (faceLandmarker == null) {
            android.util.Log.e(TAG, "detectLiveStream called but faceLandmarker is null")
            return
        }
        val frameTime = SystemClock.uptimeMillis()

        // Rotate and Flip according to sensor orientation and camera type
        val matrix = Matrix().apply {
            // Android sensor orientation is typically 90 or 270.
            // Correct the rotation so the face is "upright" for MediaPipe.
            // For many front cameras, (360 - rotation) % 360 is common to get upright
            postRotate(rotation.toFloat())
            
            if (isFrontCamera) {
                // Mirror for front camera AFTER rotation to match selfie preview
                postScale(-1f, 1f)
            }
        }
        
        val rotatedBitmap = Bitmap.createBitmap(
            bitmap, 0, 0, bitmap.width, bitmap.height,
            matrix, true
        )

        val mpImage = BitmapImageBuilder(rotatedBitmap).build()
        faceLandmarker?.detectAsync(mpImage, frameTime)
    }

    private fun returnDetectionResult(
        result: FaceLandmarkerResult,
        input: MPImage
    ) {
        if (result.faceLandmarks().isNotEmpty()) {
            android.util.Log.d(TAG, "SUCCESS: Face detected!")
        } else {
            // android.util.Log.v(TAG, "No face in frame")
        }
        resultListener(result, input)
    }

    private fun returnDetectionError(error: RuntimeException) {
        errorListener(error.message ?: "An unknown error occurred")
    }

    fun close() {
        faceLandmarker?.close()
        faceLandmarker = null
    }
}
