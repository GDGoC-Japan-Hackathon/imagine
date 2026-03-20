import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../../core/models/analysis_model.dart';

class NavigationHandler {
  static Future<void> startNavigation({
    required BuildContext context,
    required AnalysisData data,
    required VoidCallback onStarted,
  }) async {
    onStarted();

    if (data.latitude == null || data.longitude == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ナビゲーション用の座標が取得できていません。')),
        );
      }
      return;
    }

    final intentUrl = 'geo:${data.latitude},${data.longitude}?q=${data.latitude},${data.longitude}';
    final googleNavUrl = 'google.navigation:q=${data.latitude},${data.longitude}';
    final httpsUrl = 'https://www.google.com/maps/dir/?api=1&destination=${data.latitude},${data.longitude}&travelmode=driving';
    
    try {
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
        if (!status.isGranted) {
          if (context.mounted) {
            await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
          }
          return;
        }
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

      if (context.mounted) {
        // ナビゲーション画面を表示（SDKモード）
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text('${data.title} への案内')),
              body: GoogleMapsNavigationView(
                onViewCreated: (controller) async {
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
        
        // ナビゲーション画面が閉じられた後、画面が生きていればポップする
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint("SDK Error: $e. Fallback to Intent.");
      if (context.mounted) {
        await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
      }
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
