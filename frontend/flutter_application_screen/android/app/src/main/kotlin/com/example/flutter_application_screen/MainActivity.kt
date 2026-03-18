package com.example.flutter_application_screen

import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import com.google.mediapipe.tasks.components.containers.Category
import com.google.mediapipe.tasks.components.containers.Classifications
import java.io.ByteArrayOutputStream
import java.io.IOException

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.imagine/mediapipe"
    private val EVENT_CHANNEL = "com.example.imagine/mediapipe_events"

    private var faceLandmarkerHelper: FaceLandmarkerHelper? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        flutterEngine?.let { engine ->
            // Event Channel Setup
            EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                        eventSink = sink
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                }
            )

            // Method Channel Setup
            MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "init" -> {
                        try {
                            if (faceLandmarkerHelper == null) {
                                faceLandmarkerHelper = FaceLandmarkerHelper(
                                    context = this,
                                    resultListener = { faceResult, _ ->
                                        if (faceResult != null) {
                                            val faceLandmarks = faceResult.faceLandmarks()
                                            val landmarkList = if (faceLandmarks.isNotEmpty()) {
                                                faceLandmarks[0].map {
                                                    mapOf("x" to it.x(), "y" to it.y(), "z" to it.z())
                                                }
                                            } else {
                                                emptyList()
                                            }
                                            
                                            val blendshapeList = mutableListOf<Map<String, Any>>()
                                            val blendshapesOptional = faceResult.faceBlendshapes()
                                            
                                            if (blendshapesOptional.isPresent()) {
                                                val results = blendshapesOptional.get()
                                                if (results.isNotEmpty()) {
                                                    val firstResult = results[0]
                                                    val categories = if (firstResult is List<*>) {
                                                        firstResult
                                                    } else {
                                                        (firstResult as? Classifications)?.categories()
                                                    }

                                                    categories?.forEach { item ->
                                                        if (item is Category) {
                                                            blendshapeList.add(
                                                                mapOf(
                                                                    "category" to item.categoryName(),
                                                                    "score" to item.score()
                                                                )
                                                            )
                                                        }
                                                    }
                                                }
                                            }

                                            val faceData = mapOf(
                                                "landmarks" to landmarkList,
                                                "blendshapes" to blendshapeList
                                            )

                                            runOnUiThread {
                                                eventSink?.success(faceData)
                                            }
                                        }
                                    },
                                    errorListener = { error ->
                                        Log.e("MediaPipe", "Detection error: $error")
                                        runOnUiThread {
                                            eventSink?.error("MEDIAPIPE_ERROR", error, null)
                                        }
                                    }
                                )
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INIT_FAILED", e.message, null)
                        }
                    }
                    "detect" -> {
                        val y = call.argument<ByteArray>("y")
                        val u = call.argument<ByteArray>("u")
                        val v = call.argument<ByteArray>("v")
                        val yRowStride = call.argument<Int>("yRowStride") ?: 0
                        val uvRowStride = call.argument<Int>("uvRowStride") ?: 0
                        val uvPixelStride = call.argument<Int>("uvPixelStride") ?: 1
                        val width = call.argument<Int>("width") ?: 0
                        val height = call.argument<Int>("height") ?: 0
                        val isFront = call.argument<Boolean>("isFront") ?: true
                        val rotation = call.argument<Int>("rotation") ?: 0
                        
                        if (y != null && u != null && v != null && faceLandmarkerHelper != null) {
                            val bitmap = yuvToBitmap(y, u, v, yRowStride, uvRowStride, uvPixelStride, width, height)
                            if (bitmap != null) {
                                faceLandmarkerHelper?.detectLiveStream(bitmap, isFront, rotation)
                                result.success(true)
                            } else {
                                result.error("DECODE_ERROR", "Failed to process YUV", null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "Missing data", null)
                        }
                    }
                    "close" -> {
                        faceLandmarkerHelper?.close()
                        faceLandmarkerHelper = null
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun yuvToBitmap(
        y: ByteArray,
        u: ByteArray,
        v: ByteArray,
        yRowStride: Int,
        uvRowStride: Int,
        uvPixelStride: Int,
        width: Int,
        height: Int
    ): android.graphics.Bitmap? {
        return try {
            val argb = IntArray(width * height)
            
            for (row in 0 until height) {
                for (col in 0 until width) {
                    val yIdx = row * yRowStride + col
                    val uvRow = row / 2
                    val uvCol = col / 2
                    val uvIdx = uvRow * uvRowStride + uvCol * uvPixelStride
                    
                    // Note: u and v are separate buffers in Flutter CameraImage
                    // but they might point to the same storage. indexing relatively is safe.
                    val yVal = if (yIdx < y.size) y[yIdx].toInt() and 0xFF else 0
                    val uVal = (if (uvIdx < u.size) u[uvIdx].toInt() and 0xFF else 128) - 128
                    val vVal = (if (uvIdx < v.size) v[uvIdx].toInt() and 0xFF else 128) - 128
                    
                    // YUV to RGB (Standard formula)
                    var r = (yVal + 1.370705f * vVal).toInt()
                    var g = (yVal - 0.337633f * uVal - 0.698001f * vVal).toInt()
                    var b = (yVal + 1.732446f * uVal).toInt()
                    
                    r = r.coerceIn(0, 255)
                    g = g.coerceIn(0, 255)
                    b = b.coerceIn(0, 255)
                    
                    argb[row * width + col] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
                }
            }
            
            val originalBitmap = android.graphics.Bitmap.createBitmap(argb, width, height, android.graphics.Bitmap.Config.ARGB_8888)
            
            // Resize to max 320 for performance and better face detection
            val maxSide = 320
            if (width > maxSide || height > maxSide) {
                val scale = maxSide.toFloat() / maxOf(width, height)
                val newWidth = (width * scale).toInt()
                val newHeight = (height * scale).toInt()
                android.graphics.Bitmap.createScaledBitmap(originalBitmap, newWidth, newHeight, true)
            } else {
                originalBitmap
            }
        } catch (e: Exception) {
            Log.e("MediaPipe", "YUV Conversion failed: ${e.message}")
            null
        }
    }

    override fun onDestroy() {
        faceLandmarkerHelper?.close()
        super.onDestroy()
    }
}
