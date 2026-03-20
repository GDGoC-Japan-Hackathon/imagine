package com.example.flutter_application_screen

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.SystemClock
import android.view.Surface
import android.view.WindowManager
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
                    .setMinFaceDetectionConfidence(0.3f)
                    .setMinTrackingConfidence(0.3f)
                    .setMinFacePresenceConfidence(0.3f)
                    .setResultListener(this::returnDetectionResult)
                    .setErrorListener(this::returnDetectionError)
                    .setOutputFaceBlendshapes(true)
                    .setRunningMode(RunningMode.LIVE_STREAM)

            faceLandmarker = FaceLandmarker.createFromOptions(context, optionsBuilder.build())
            android.util.Log.d(TAG, "FaceLandmarker initialized successfully")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Face Landmarker init failed", e)
            errorListener("Face Landmarker init failed: ${e.message}")
        }
    }

    private var lastTimestamp: Long = -1

    // 顔検出部分のコード
    fun detectLiveStream(bitmap: Bitmap, isFrontCamera: Boolean, rotation: Int) {
        if (faceLandmarker == null) return
        
        // Timestamps must be strictly increasing for LIVE_STREAM mode
        var frameTime = SystemClock.uptimeMillis()
        if (frameTime <= lastTimestamp) {
            frameTime = lastTimestamp + 1
        }
        lastTimestamp = frameTime

        // デバイスの現在の画面の回転角度を取得する
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val displayRotation = windowManager.defaultDisplay.rotation
        
        val degrees = when(displayRotation) {
            Surface.ROTATION_0 -> 0
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
        
        // センサーの物理的な固定回転（rotation）からデバイスの傾き（degrees）を考慮し、
        // 常に顔が上を向くようにターゲットの回転角度を計算する
        val targetRotation = if (isFrontCamera) {
            (rotation + degrees) % 360
        } else {
            (rotation - degrees + 360) % 360
        }

        // Rotate and Flip according to calculated target rotation
        val matrix = Matrix().apply {
            postRotate(targetRotation.toFloat())
            /*
            if (isFrontCamera) {
                // Mirror for front camera AFTER rotation to match selfie preview
                val newWidth = if (rotation % 180 == 0) bitmap.width else bitmap.height
                val newHeight = if (rotation % 180 == 0) bitmap.height else bitmap.width
                postScale(-1f, 1f, newWidth.toFloat() / 2f, newHeight.toFloat() / 2f)
            }
            */
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
