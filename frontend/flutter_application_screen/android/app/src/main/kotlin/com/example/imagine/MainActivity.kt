package com.example.imagine

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.MediaActionSound
import android.media.RingtoneManager
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
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.ConnectionResult

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.imagine/mediapipe"
    private val EVENT_CHANNEL = "com.example.imagine/mediapipe_events"

    private var faceLandmarkerHelper: FaceLandmarkerHelper? = null
    private var eventSink: EventChannel.EventSink? = null
    private var debugShowFaceImage: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d("MainActivity", "onCreate started")
        try {
            // 繧ｹ繝ｪ繝ｼ繝暦ｼ育判髱｢縺ｮ閾ｪ蜍墓ｶ育・・峨ｒ髦ｲ豁｢
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            Log.d("MainActivity", "Keep screen on flag added")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error in onCreate: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("MainActivity", "configureFlutterEngine started")

        try {
            // Event Channel Setup
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                        Log.d("MainActivity", "EventChannel onListen")
                        eventSink = sink
                    }

                    override fun onCancel(arguments: Any?) {
                        Log.d("MainActivity", "EventChannel onCancel")
                        eventSink = null
                    }
                }
            )

            // Flutter縺九ｉ蜻ｼ縺ｳ蜃ｺ縺輔ｌ繧九Γ繧ｽ繝・ラ
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
                Log.d("MainActivity", "MethodChannel call: ${call.method}")
                // 繝｡繧ｽ繝・ラ縺斐→縺ｫ蜃ｦ逅・ｒ蛻・ｲ・
                when (call.method) {
                    // 蛻晄悄蛹門・逅・
                    "init" -> {
                        try {
                            debugShowFaceImage = call.argument<Boolean>("debugShowFaceImage") ?: false
                            val delegate = call.argument<Int>("delegate") ?: 1 // Default to GPU
                            
                            if (faceLandmarkerHelper == null) {
                                faceLandmarkerHelper = FaceLandmarkerHelper(
                                    context = this,
                                    delegate = delegate,
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

                                            // 繝・ヰ繝・げ逕ｨ逕ｻ蜒上・霆｢騾・
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
                    // 鬘疲､懷・
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
                            // Native蛛ｴ縺ｧYUV縺九ｉRGB(Bitmap)縺ｫ螟画鋤
                            val originalBitmap = yuvToBitmap(y, u, v, yRowStride, uvRowStride, uvPixelStride, width, height)
                            if (originalBitmap != null) {
                                // 1. 繝ｪ繧ｵ繧､繧ｺ
                                var processedBitmap = resizeBitmap(originalBitmap, 640)
                                
                                // 2. 譏弱ｋ縺戊｣懈ｭ｣ (萓・ +20)
                                processedBitmap = adjustBrightness(processedBitmap, 25)
                                
                                // 3. 繧ｬ繝ｳ繝櫁｣懈ｭ｣ (萓・ 1.2)
                                processedBitmap = applyGammaCorrection(processedBitmap, 1.2f)

                                // 鬘疲､懷・
                                faceLandmarkerHelper?.detectLiveStream(processedBitmap, isFront, rotation)
                                result.success(true)
                            } else {
                                result.error("DECODE_ERROR", "Failed to process YUV", null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "Missing data", null)
                        }
                    }
                    "detectJpeg" -> {
                        val jpegBytes = call.argument<ByteArray>("jpeg")
                        val isFront = call.argument<Boolean>("isFront") ?: true
                        val rotation = call.argument<Int>("rotation") ?: 0
                        
                        if (jpegBytes != null && faceLandmarkerHelper != null) {
                            val originalBitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
                            if (originalBitmap != null) {
                                var processedBitmap = resizeBitmap(originalBitmap, 640)
                                processedBitmap = adjustBrightness(processedBitmap, 25)
                                processedBitmap = applyGammaCorrection(processedBitmap, 1.2f)
                                faceLandmarkerHelper?.detectLiveStream(processedBitmap, isFront, rotation)
                                result.success(true)
                            } else {
                                result.error("DECODE_ERROR", "Failed to decode JPEG", null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "Missing data", null)
                        }
                    }
                    "compressYuvToJpeg" -> {
                        val y = call.argument<ByteArray>("y")
                        val u = call.argument<ByteArray>("u")
                        val v = call.argument<ByteArray>("v")
                        val yRowStride = call.argument<Int>("yRowStride") ?: 0
                        val uvRowStride = call.argument<Int>("uvRowStride") ?: 0
                        val uvPixelStride = call.argument<Int>("uvPixelStride") ?: 1
                        val width = call.argument<Int>("width") ?: 0
                        val height = call.argument<Int>("height") ?: 0
                        
                        if (y != null && u != null && v != null) {
                            try {
                                val nv21 = yuv420ThreePlanesToNV21(y, u, v, width, height, yRowStride, uvRowStride, uvPixelStride)
                                val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
                                val stream = ByteArrayOutputStream()
                                yuvImage.compressToJpeg(Rect(0, 0, width, height), 60, stream)
                                result.success(stream.toByteArray())
                            } catch (e: Exception) {
                                result.error("COMPRESS_ERROR", e.message, null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "Missing YUV data", null)
                        }
                    }
                    "close" -> {
                        faceLandmarkerHelper?.close()
                        faceLandmarkerHelper = null
                        result.success(true)
                    }
                    "isAutomotiveOS" -> {
                        val isAutomotive = packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_AUTOMOTIVE)
                        result.success(isAutomotive)
                    }
                    // GMS・・oogle Mobile Services・峨・蛻ｩ逕ｨ蜿ｯ蜷ｦ繝√ぉ繝・け
                    "isGmsAvailable" -> {
                        try {
                            val availability = GoogleApiAvailability.getInstance()
                            val resultCode = availability.isGooglePlayServicesAvailable(this)
                            result.success(resultCode == ConnectionResult.SUCCESS)
                        } catch (e: Exception) {
                            Log.w("GMS", "isGmsAvailable check failed: ${e.message}")
                            result.success(false)
                        }
                    }
                    // 菴咲ｽｮ諠・ｱ縺悟叙蠕怜庄閭ｽ縺具ｼ医・繝ｭ繝舌う繝繝ｼ縺悟ｭ伜惠縺吶ｋ縺具ｼ峨・繝√ぉ繝・け
                    "canGetLocation" -> {
                        try {
                            val locationManager = getSystemService(android.content.Context.LOCATION_SERVICE) as android.location.LocationManager
                            val providers = locationManager.getProviders(true)
                            // GPS 縺ｾ縺溘・ Network 繝励Ο繝舌う繝繝ｼ縺梧怏蜉ｹ縺九メ繧ｧ繝・け
                            val isAvailable = providers.contains(android.location.LocationManager.GPS_PROVIDER) || 
                                              providers.contains(android.location.LocationManager.NETWORK_PROVIDER)
                            result.success(isAvailable)
                        } catch (e: Exception) {
                            Log.w("Location", "canGetLocation check failed: ${e.message}")
                            result.success(false)
                        }
                    }
                    // 鬘碑ｪ崎ｭ俶・蜉滓凾縺ｮ繧ｷ繧ｹ繝・Β繧ｵ繧ｦ繝ｳ繝会ｼ医き繝｡繝ｩ縺ｮAF繝ｭ繝・け髻ｳ・・
                    "playFaceDetected" -> {
                        try {
                            val sound = MediaActionSound()
                            sound.play(MediaActionSound.FOCUS_COMPLETE)
                        } catch (e: Exception) {
                            Log.w("Sound", "playFaceDetected failed: ${e.message}")
                        }
                        result.success(null)
                    }
                    // 髻ｳ螢ｰ骭ｲ髻ｳ髢句ｧ区凾縺ｮ繧ｷ繧ｹ繝・Β繧ｵ繧ｦ繝ｳ繝会ｼ磯夂衍髻ｳ・・
                    "playVoiceStart" -> {
                        try {
                            val sound = MediaActionSound()
                            sound.play(MediaActionSound.FOCUS_COMPLETE)
                        } catch (e: Exception) {
                            Log.w("Sound", "playVoiceStart failed: ${e.message}")
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error in configureFlutterEngine: ${e.message}")
        }
    }

    // YUV蠖｢蠑上°繧隠itmap縺ｫ螟画鋤
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
                    
                    // YUV to RGB 螟画鋤
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

    private fun yuv420ThreePlanesToNV21(
        yPlane: ByteArray, uPlane: ByteArray, vPlane: ByteArray,
        width: Int, height: Int,
        yRowStride: Int, uvRowStride: Int, uvPixelStride: Int
    ): ByteArray {
        val nv21 = ByteArray(width * height * 3 / 2)
        var pos = 0
        
        // Copy Y
        for (row in 0 until height) {
            val length = minOf(width, yPlane.size - row * yRowStride)
            System.arraycopy(yPlane, row * yRowStride, nv21, pos, length)
            pos += width
        }
        
        // Copy V and U
        for (row in 0 until height / 2) {
            for (col in 0 until width / 2) {
                val vuPos = (row * uvRowStride) + (col * uvPixelStride)
                if (vuPos < vPlane.size && pos < nv21.size) {
                    nv21[pos++] = vPlane[vuPos]
                } else { pos++ }
                if (vuPos < uPlane.size && pos < nv21.size) {
                    nv21[pos++] = uPlane[vuPos]
                } else { pos++ }
            }
        }
        return nv21
    }

    // 繝薙ャ繝医・繝・・繧呈欠螳壹＆繧後◆譛螟ｧ繧ｵ繧､繧ｺ縺ｫ繝ｪ繧ｵ繧､繧ｺ
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

    // 繝薙ャ繝医・繝・・縺ｮ譏弱ｋ縺輔ｒ隱ｿ謨ｴ縺吶ｋ
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
     * 繝薙ャ繝医・繝・・縺ｫ繧ｬ繝ｳ繝櫁｣懈ｭ｣繧帝←逕ｨ縺吶ｋ
     */
    private fun applyGammaCorrection(original: Bitmap, gamma: Float): Bitmap {
        val width = original.width
        val height = original.height
        val pixels = IntArray(width * height)
        original.getPixels(pixels, 0, width, 0, 0, width, height)

        // 繝ｫ繝・け繧｢繝・・繝・・繝悶Ν縺ｮ菴懈・
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
