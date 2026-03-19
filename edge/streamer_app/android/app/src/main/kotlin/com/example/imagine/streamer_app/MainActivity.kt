package com.example.imagine.streamer_app

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/// Streamer アプリの MainActivity
/// Flutter 側からの MethodChannel 呼び出しを受け取り、YUV → JPEG 変換を行います。
/// この変換は Dashboard 側の flutter_application_screen と同じロジックを使用しています。
class MainActivity : FlutterActivity() {
    /// Flutter とのブリッジに使用するチャンネル名
    /// streamer_screen.dart 側の MethodChannel 名と一致させる必要があります。
    private val METHOD_CHANNEL = "com.example.imagine/mediapipe"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 配信中は画面を点灯し続ける（スリープ防止）
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        flutterEngine?.let { engine ->
            MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        // YUV フレームを JPEG バイト列に変換してリレーサーバーへ送信するためのメソッド
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
                                    // YUV420 (3-plane) → NV21 (2-plane) に変換してから JPEG 圧縮
                                    val nv21 = yuv420ThreePlanesToNV21(
                                        y, u, v, width, height,
                                        yRowStride, uvRowStride, uvPixelStride
                                    )
                                    val yuvImage =
                                        YuvImage(nv21, ImageFormat.NV21, width, height, null)
                                    val stream = ByteArrayOutputStream()
                                    yuvImage.compressToJpeg(Rect(0, 0, width, height), 60, stream)
                                    result.success(stream.toByteArray())
                                } catch (e: Exception) {
                                    result.error("COMPRESS_ERROR", e.message, null)
                                }
                            } else {
                                result.error("INVALID_ARGS", "YUV データが不足しています", null)
                            }
                        }

                        else -> result.notImplemented()
                    }
                }
        }
    }

    /// YUV420 3-plane 形式を NV21 2-plane 形式に変換するヘルパー関数
    /// Android カメラの YUV_420_888 フォーマットを YuvImage クラスが扱える NV21 に変換します。
    private fun yuv420ThreePlanesToNV21(
        yPlane: ByteArray, uPlane: ByteArray, vPlane: ByteArray,
        width: Int, height: Int,
        yRowStride: Int, uvRowStride: Int, uvPixelStride: Int
    ): ByteArray {
        val nv21 = ByteArray(width * height * 3 / 2)
        var pos = 0

        // Y プレーン（輝度成分）をコピー
        for (row in 0 until height) {
            val length = minOf(width, yPlane.size - row * yRowStride)
            System.arraycopy(yPlane, row * yRowStride, nv21, pos, length)
            pos += width
        }

        // V・U プレーン（色差成分）を交互にコピーして NV21 形式に整列
        for (row in 0 until height / 2) {
            for (col in 0 until width / 2) {
                val vuPos = (row * uvRowStride) + (col * uvPixelStride)
                if (vuPos < vPlane.size && pos < nv21.size) {
                    nv21[pos++] = vPlane[vuPos]
                } else {
                    pos++
                }
                if (vuPos < uPlane.size && pos < nv21.size) {
                    nv21[pos++] = uPlane[vuPos]
                } else {
                    pos++
                }
            }
        }
        return nv21
    }
}
