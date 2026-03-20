import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'models/face_vector.dart';
import 'services/camera_service.dart';
import 'services/face_tracker_service.dart';
import 'services/gemini_service.dart';

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final CameraService _cameraService = CameraService();
  final FaceTrackerService _faceTracker = FaceTrackerService();
  final GeminiService _geminiService = GeminiService();
  final FaceDetector _faceDetector = FaceDetector(options: FaceDetectorOptions(enableTracking: true));

  bool _isProcessing = false;
  String _statusMessage = "初期化しています...";

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _cameraService.initialize();
    
    // APIキーの読み込み（起動時に --dart-define=GEMINI_API_KEY=xxx を付与する前提）
    _geminiService.initialize(const String.fromEnvironment('GEMINI_API_KEY')); 
    
    setState(() => _statusMessage = "インカメラで目線を監視中です...");
    _startFaceTracking();
  }

  void _startFaceTracking() {
    _cameraService.inCameraController?.startImageStream((CameraImage image) async {
      if (_isProcessing) return;

      // CameraImage から ML Kit 形式へのコンバート
      final inputImage = _processCameraImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      
      // Face情報を FaceVector に変換
      List<FaceVector> currentFaceAngles = faces.map((f) {
        return FaceVector(f.headEulerAngleY ?? 0.0, f.headEulerAngleX ?? 0.0);
      }).toList();

      // 目線の安定性をチェック
      final stableVectors = _faceTracker.processFaces(currentFaceAngles);

      if (stableVectors != null && stableVectors.isNotEmpty) {
        _isProcessing = true;
        // ストリームを一時停止して処理へ
        await _cameraService.inCameraController?.stopImageStream();
        
        setState(() => _statusMessage = "目線が固定されました。撮影・解析を開始します...");
        await _captureAndAnalyze(stableVectors.first);
      }
    });
  }

  Future<void> _captureAndAnalyze(FaceVector targetVector) async {
    // 1. アウトカメラで撮影
    final outImage = await _cameraService.captureOutCameraImage();
    
    if (outImage != null) {
      // 2. 撮影した画像と目線ベクトルをGeminiに送信して解析
      final result = await _geminiService.analyzeAndMask(File(outImage.path), targetVector.x, targetVector.y);
      setState(() {
        _statusMessage = "【検出】: ${result.targetName}\n\n【解説】:\n${result.guideDesc}";
      });
      // 注意: result.segData にはポリゴンの点データが含まれます。
      // 必要に応じて CustomPaint() などに渡し、枠線(マスク)を描画できます。
    } else {
      setState(() => _statusMessage = "撮影に失敗しました。");
    }
    
    // 5秒待機したあとトラッキングを再開
    await Future.delayed(const Duration(seconds: 5));
    setState(() => _statusMessage = "インカメラで目線を監視中です...");
    _isProcessing = false;
    _startFaceTracking();
  }

  InputImage? _processCameraImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final imageRotation = InputImageRotationValue.fromRawValue(
          _cameraService.inCameraController!.description.sensorOrientation) ?? InputImageRotation.rotation0deg;
      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );
      
      return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
    } catch (e) {
      return null;
    }
  }

  @override
  void dispose() {
    _cameraService.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Tracker & AI Assistant')),
      body: Column(
        children: [
          // インカメラ映像のプレビュー
          Expanded(
            child: _cameraService.inCameraController?.value.isInitialized == true
                ? CameraPreview(_cameraService.inCameraController!)
                : const Center(child: CircularProgressIndicator()),
          ),
          // 結果・ステータス表示用領域
          Container(
            padding: const EdgeInsets.all(20.0),
            color: Colors.blueGrey.shade900,
            width: double.infinity,
            height: 200,
            child: SingleChildScrollView(
              child: Text(
                _statusMessage,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          )
        ],
      ),
    );
  }
}
