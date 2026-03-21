import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../../core/models/analysis_model.dart';

/// ナビゲーション機能を管理するハンドラ。
/// GMS（Google Mobile Services）が利用可能な場合は Navigation SDK を使用し、
/// 利用不可の場合は Intent ベースのフォールバックを自動的に行う。
class NavigationHandler {
  static const MethodChannel _channel = MethodChannel('com.example.imagine/mediapipe');

  /// GMS が利用可能かどうかをネイティブ側で確認する。
  /// AAOS（Raspberry Pi 等）では GMS が無いため false を返す。
  static Future<bool> _isGmsAvailable() async {
    try {
      final result = await _channel.invokeMethod('isGmsAvailable');
      return result == true;
    } catch (e) {
      debugPrint("GMS availability check failed: $e");
      return false;
    }
  }

  /// 位置情報がハードウェア的に取得可能かどうかをネイティブ側で確認する。
  /// GPS や Network のプロバイダーが有効でない場合に false を返す。
  static Future<bool> _canGetLocation() async {
    try {
      final result = await _channel.invokeMethod('canGetLocation');
      return result == true;
    } catch (e) {
      debugPrint("Location availability check failed: $e");
      return false;
    }
  }

  static bool _isNavigating = false;

  static Future<void> startNavigation({
    required BuildContext context,
    required AnalysisData data,
    required VoidCallback onStarted,
  }) async {
    if (_isNavigating) {
      debugPrint("Navigation already starting. Ignoring concurrent request.");
      return;
    }
    _isNavigating = true;

    final encodedTitle = Uri.encodeComponent(data.title);
    final intentUrl = 'geo:${data.latitude},${data.longitude}?q=$encodedTitle';
    final googleNavUrl = 'google.navigation:q=$encodedTitle';
    final httpsUrl = 'https://www.google.com/maps/search/?api=1&query=$encodedTitle';

    try {
      onStarted();

      if (data.latitude == null || data.longitude == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ナビゲーション用の座標が取得できていません。')),
          );
        }
        return;
      }
      
      // GMS が利用不可の場合は、SDK ルートを完全にスキップして Intent にフォールバック
      final gmsAvailable = await _isGmsAvailable();
      if (!gmsAvailable) {
        debugPrint("GMS not available. Skipping Navigation SDK, falling back to Intent.");
        if (context.mounted) {
          await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
        }
        return;
      }

      // GMS が利用可能な場合は、位置情報サービスと権限を確認
      // 1. まず権限チェック（Android 12+では権限がないとGPS有効判定機能が正常動作しないことがあるため）
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
        if (!status.isGranted) {
          debugPrint("Location permission denied. Falling back to Intent.");
          if (context.mounted) {
            await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
          }
          return;
        }
      }

      // 2. 位置情報サービス（GPS）自体が有効かチェック
      final serviceStatus = await Permission.location.serviceStatus;
      if (!serviceStatus.isEnabled) {
        debugPrint("Location services are disabled. Falling back to Intent.");
        if (context.mounted) {
          await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
        }
        return;
      }

      // 3. 位置情報が取得可能か（ハードウェア/プロバイダー）をネィティブ側で詳細チェック
      final canGetLocation = await _canGetLocation();
      if (!canGetLocation) {
        debugPrint("Location cannot be obtained (No Providers). Falling back to Intent.");
        if (context.mounted) {
          await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
        }
        return;
      }

      if (!await GoogleMapsNavigator.areTermsAccepted()) {
        final accepted = await GoogleMapsNavigator.showTermsAndConditionsDialog(
          'Google Maps Navigation SDK 利用規約',
          'ナビゲーション機能を利用するには、Google Maps Platform の利用規約に同意する必要があります。',
        );
        if (!accepted) {
          if (context.mounted) {
            await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
          }
          return;
        }
      }

      await GoogleMapsNavigator.initializeNavigationSession().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Navigation initialization timed out'),
      );
      
      final waypoint = NavigationWaypoint.withLatLngTarget(
        title: data.title,
        target: LatLng(latitude: data.latitude!, longitude: data.longitude!),
      );

      final destinations = Destinations(
        waypoints: [waypoint],
        displayOptions: NavigationDisplayOptions(),
      );

      bool isViewCreated = false;

      if (context.mounted) {
        // ナビゲーション画面を表示（SDKモード）
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text('${data.title} への案内')),
              body: GoogleMapsNavigationView(
                onViewCreated: (controller) async {
                  if (isViewCreated) return;
                  isViewCreated = true;
                  
                  final navigator = Navigator.of(context);
                  try {
                    final status = await GoogleMapsNavigator.setDestinations(destinations).timeout(
                      const Duration(seconds: 15),
                      onTimeout: () => throw TimeoutException('Routing timed out'),
                    );

                    if (status == NavigationRouteStatus.statusOk) {
                      await GoogleMapsNavigator.startGuidance();
                    } else {
                      debugPrint("Routing failed with status: $status. Fallback to Intent.");
                      if (navigator.mounted) {
                        navigator.pop();
                      }
                      if (context.mounted) {
                        await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
                      }
                    }
                  } catch (e) {
                    debugPrint("SDK View Error: $e. Fallback to Intent.");
                    if (navigator.mounted) {
                      navigator.pop();
                    }
                    if (context.mounted) {
                      await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
                    }
                  }
                },
              ),
            ),
          ),
        );
        // ナビゲーション画面が閉じられた（戻るキー等でポップされた）後、ガイダンスを終了する
        try {
          await GoogleMapsNavigator.stopGuidance();
          // clearDestinations() は 400 Bad Request エラーの原因になるため呼び出さない
        } catch (e) {
          debugPrint("Failed to stop guidance: $e");
        }
      }
    } catch (e) {
      debugPrint("SDK Error: $e. Fallback to Intent.");
      if (context.mounted) {
        await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
      }
    } finally {
      _isNavigating = false;
    }
  }

  static Future<void> _launchIntent(BuildContext context, String url, String fallbackUrl, String httpsUrl) async {
    try {
      if (await canLaunchUrlString(url)) {
        await launchUrlString(url, mode: LaunchMode.externalNonBrowserApplication);
        if (context.mounted) Navigator.of(context).pop();
      } else if (await canLaunchUrlString(fallbackUrl)) {
        await launchUrlString(fallbackUrl, mode: LaunchMode.externalNonBrowserApplication);
        if (context.mounted) Navigator.of(context).pop();
      } else if (await canLaunchUrlString(httpsUrl)) {
        await launchUrlString(httpsUrl);
        if (context.mounted) Navigator.of(context).pop();
      } else {
        throw 'Could not launch navigation';
      }
    } catch (e) {
      debugPrint("Intent Error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ナビゲーションの開始に失敗しました: $e')),
        );
      }
    }
  }
}
