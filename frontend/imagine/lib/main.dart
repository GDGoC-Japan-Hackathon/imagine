import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/dashboard_screen.dart';

/// Dashboard アプリのエントリーポイント（AAOS / スマートフォン向け Dashboard 専用）
///
/// Streamer モード（スマートフォンのカメラ映像を中継する機能）は
/// backend/streamer_app に分離されました。
/// 詳細は backend/streamer_app/README.md を参照してください。
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // アプリを横画面（Landscape）に固定
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await dotenv.load(fileName: ".env");
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IMAGINE',
      theme: AppTheme.lightTheme,
      home: const DashboardScreen(),
    );
  }
}
