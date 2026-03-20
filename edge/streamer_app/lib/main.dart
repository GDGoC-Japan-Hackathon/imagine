import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'streamer_screen.dart';

/// Streamer アプリのエントリーポイント
/// このアプリはスマートフォンのカメラ映像をリレーサーバーへ WebSocket で中継する専用アプリです。
/// Dashboard (AAOS 側) はフロントエンドの flutter_application_screen を参照してください。
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // アプリを横画面（Landscape）に固定
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await dotenv.load(fileName: ".env");
  runApp(const StreamerApp());
}

class StreamerApp extends StatelessWidget {
  const StreamerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Imagine Streamer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.greenAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const StreamerScreen(),
    );
  }
}
