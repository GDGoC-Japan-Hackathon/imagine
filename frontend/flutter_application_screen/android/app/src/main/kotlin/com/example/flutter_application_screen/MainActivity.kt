package com.example.flutter_application_screen

import android.graphics.Bitmap
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
import android.view.WindowManager
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.framework.image.BitmapExtractor

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.imagine/mediapipe"
    private val EVENT_CHANNEL = "com.example.imagine/mediapipe_events"

    private var faceLandmarkerHelper: FaceLandmarkerHelper? = null
    private var eventSink: EventChannel.EventSink? = null
    private var debugShowFaceImage: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // スリープ（画面の自動消灯）を防止
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

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

            // Flutterから呼び出されるメソッド
            MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
                // メソッドごとに処理を分岐
                when (call.method) {
                    // 初期化処理
                    "init" -> {
                        try {
                            debugShowFaceImage = call.argument<Boolean>("debugShowFaceImage") ?: false
                            if (faceLandmarkerHelper == null) {
                                faceLandmarkerHelper = FaceLandmarkerHelper(
                                    context = this,
                                    resultListener = { faceResult, input ->
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

                                            val faceData = mutableMapOf<String, Any?>(
                                                "landmarks" to landmarkList,
                                                "blendshapes" to blendshapeList
                                            )

                                            // デバッグ用画像の転送
                                            if (debugShowFaceImage) {
                                                try {
                                                    val bitmap = BitmapExtractor.extract(input)
                                                    val stream = ByteArrayOutputStream()
                                                    bitmap.compress(Bitmap.CompressFormat.JPEG, 60, stream)
                                                    faceData["faceImage"] = stream.toByteArray()
                                                } catch (e: Exception) {
                                                    Log.e("MediaPipe", "Failed to compress face image", e)
                                                }
                                            }

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
                    // 顔検出
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
                            // Native側でYUVからRGB(Bitmap)に変換
                            val originalBitmap = yuvToBitmap(y, u, v, yRowStride, uvRowStride, uvPixelStride, width, height)
                            if (originalBitmap != null) {
                                // 1. リサイズ
                                var processedBitmap = resizeBitmap(originalBitmap, 640)
                                
                                // 2. 明るさ補正 (例: +20)
                                processedBitmap = adjustBrightness(processedBitmap, 25)
                                
                                // 3. ガンマ補正 (例: 1.2)
                                processedBitmap = applyGammaCorrection(processedBitmap, 1.2f)

                                // 顔検出
                                faceLandmarkerHelper?.detectLiveStream(processedBitmap, isFront, rotation)
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

    // YUV形式からBitmapに変換
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
                    
                    val yVal = if (yIdx < y.size) y[yIdx].toInt() and 0xFF else 0
                    val uVal = (if (uvIdx < u.size) u[uvIdx].toInt() and 0xFF else 128) - 128
                    val vVal = (if (uvIdx < v.size) v[uvIdx].toInt() and 0xFF else 128) - 128
                    
                    // YUV to RGB 変換
                    var r = (yVal + 1.370705f * vVal).toInt()
                    var g = (yVal - 0.337633f * uVal - 0.698001f * vVal).toInt()
                    var b = (yVal + 1.732446f * uVal).toInt()
                    
                    r = r.coerceIn(0, 255)
                    g = g.coerceIn(0, 255)
                    b = b.coerceIn(0, 255)
                    
                    argb[row * width + col] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
                }
            }
            android.graphics.Bitmap.createBitmap(argb, width, height, android.graphics.Bitmap.Config.ARGB_8888)
        } catch (e: Exception) {
            Log.e("MediaPipe", "YUV Conversion failed: ${e.message}")
            null
        }
    }

    // ビットマップを指定された最大サイズにリサイズ
    private fun resizeBitmap(bitmap: android.graphics.Bitmap, maxSide: Int): android.graphics.Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        return if (width > maxSide || height > maxSide) {
            val scale = maxSide.toFloat() / maxOf(width, height)
            val newWidth = (width * scale).toInt()
            val newHeight = (height * scale).toInt()
            android.graphics.Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
        } else {
            bitmap
        }
    }

    // ビットマップの明るさを調整する
    private fun adjustBrightness(original: Bitmap, value: Int): Bitmap {
        val width = original.width
        val height = original.height
        val pixels = IntArray(width * height)
        original.getPixels(pixels, 0, width, 0, 0, width, height)

        for (i in pixels.indices) {
            val a = pixels[i] shr 24 and 0xff
            var r = (pixels[i] shr 16 and 0xff) + value
            var g = (pixels[i] shr 8 and 0xff) + value
            var b = (pixels[i] and 0xff) + value

            r = r.coerceIn(0, 255)
            g = g.coerceIn(0, 255)
            b = b.coerceIn(0, 255)

            pixels[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }

    /**
     * ビットマップにガンマ補正を適用する
     */
    private fun applyGammaCorrection(original: Bitmap, gamma: Float): Bitmap {
        val width = original.width
        val height = original.height
        val pixels = IntArray(width * height)
        original.getPixels(pixels, 0, width, 0, 0, width, height)

        // ルックアップテーブルの作成
        val lut = IntArray(256)
        for (i in 0..255) {
            lut[i] = (Math.pow(i / 255.0, 1.0 / gamma) * 255.0).toInt().coerceIn(0, 255)
        }

        for (i in pixels.indices) {
            val a = pixels[i] shr 24 and 0xff
            val r = pixels[i] shr 16 and 0xff
            val g = pixels[i] shr 8 and 0xff
            val b = pixels[i] and 0xff

            pixels[i] = (a shl 24) or (lut[r] shl 16) or (lut[g] shl 8) or lut[b]
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }

    override fun onDestroy() {
        faceLandmarkerHelper?.close()
        super.onDestroy()
    }
}
