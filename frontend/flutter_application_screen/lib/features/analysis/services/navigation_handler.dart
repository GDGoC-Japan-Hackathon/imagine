import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../../core/models/analysis_model.dart';

/// 繝翫ン繧ｲ繝ｼ繧ｷ繝ｧ繝ｳ讖溯・繧堤ｮ｡逅・☆繧九ワ繝ｳ繝峨Λ縲・/// GMS・・oogle Mobile Services・峨′蛻ｩ逕ｨ蜿ｯ閭ｽ縺ｪ蝣ｴ蜷医・ Navigation SDK 繧剃ｽｿ逕ｨ縺励・/// 蛻ｩ逕ｨ荳榊庄縺ｮ蝣ｴ蜷医・ Intent 繝吶・繧ｹ縺ｮ繝輔か繝ｼ繝ｫ繝舌ャ繧ｯ繧定・蜍慕噪縺ｫ陦後≧縲・class NavigationHandler {
  static const MethodChannel _channel = MethodChannel('com.example.imagine/mediapipe');

  /// GMS 縺悟茜逕ｨ蜿ｯ閭ｽ縺九←縺・°繧偵ロ繧､繝・ぅ繝門・縺ｧ遒ｺ隱阪☆繧九・  /// AAOS・・aspberry Pi 遲会ｼ峨〒縺ｯ GMS 縺檎┌縺・◆繧・false 繧定ｿ斐☆縲・  static Future<bool> _isGmsAvailable() async {
    try {
      final result = await _channel.invokeMethod('isGmsAvailable');
      return result == true;
    } catch (e) {
      debugPrint("GMS availability check failed: $e");
      return false;
    }
  }

  /// 菴咲ｽｮ諠・ｱ縺後ワ繝ｼ繝峨え繧ｧ繧｢逧・↓蜿門ｾ怜庄閭ｽ縺九←縺・°繧偵ロ繧､繝・ぅ繝門・縺ｧ遒ｺ隱阪☆繧九・  /// GPS 繧・Network 縺ｮ繝励Ο繝舌う繝繝ｼ縺梧怏蜉ｹ縺ｧ縺ｪ縺・ｴ蜷医↓ false 繧定ｿ斐☆縲・  static Future<bool> _canGetLocation() async {
    try {
      final result = await _channel.invokeMethod('canGetLocation');
      return result == true;
    } catch (e) {
      debugPrint("Location availability check failed: $e");
      return false;
    }
  }

  static Future<void> startNavigation({
    required BuildContext context,
    required AnalysisData data,
    required VoidCallback onStarted,
  }) async {
    onStarted();

    if (data.latitude == null || data.longitude == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('繝翫ン繧ｲ繝ｼ繧ｷ繝ｧ繝ｳ逕ｨ縺ｮ蠎ｧ讓吶′蜿門ｾ励〒縺阪※縺・∪縺帙ｓ縲・)),
        );
      }
      return;
    }

    final encodedTitle = Uri.encodeComponent(data.title);
    final intentUrl = 'geo:${data.latitude},${data.longitude}?q=$encodedTitle';
    final googleNavUrl = 'google.navigation:q=$encodedTitle';
    final httpsUrl = 'https://www.google.com/maps/search/?api=1&query=$encodedTitle';
    
    // GMS 縺悟茜逕ｨ荳榊庄縺ｮ蝣ｴ蜷医・縲ヾDK 繝ｫ繝ｼ繝医ｒ螳悟・縺ｫ繧ｹ繧ｭ繝・・縺励※ Intent 縺ｫ繝輔か繝ｼ繝ｫ繝舌ャ繧ｯ
    final gmsAvailable = await _isGmsAvailable();
    if (!gmsAvailable) {
      debugPrint("GMS not available. Skipping Navigation SDK, falling back to Intent.");
      if (context.mounted) {
        await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
      }
      return;
    }

    // GMS 縺悟茜逕ｨ蜿ｯ閭ｽ縺ｪ蝣ｴ蜷医・縲∽ｽ咲ｽｮ諠・ｱ繧ｵ繝ｼ繝薙せ縺ｨ讓ｩ髯舌ｒ遒ｺ隱・    try {
      // 1. 菴咲ｽｮ諠・ｱ縺悟叙蠕怜庄閭ｽ縺具ｼ医ワ繝ｼ繝峨え繧ｧ繧｢/繝励Ο繝舌う繝繝ｼ・峨ｒ繝阪ぅ繝・ぅ繝門・縺ｧ隧ｳ邏ｰ繝√ぉ繝・け
      final canGetLocation = await _canGetLocation();
      if (!canGetLocation) {
        debugPrint("Location cannot be obtained (No Providers). Falling back to Intent.");
        if (context.mounted) {
          await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
        }
        return;
      }

      // 2. 菴咲ｽｮ諠・ｱ繧ｵ繝ｼ繝薙せ・・PS・芽・菴薙′譛牙柑縺九メ繧ｧ繝・け
      final serviceStatus = await Permission.location.serviceStatus;
      if (!serviceStatus.isEnabled) {
        debugPrint("Location services are disabled. Falling back to Intent.");
        if (context.mounted) {
          await _launchIntent(context, intentUrl, googleNavUrl, httpsUrl);
        }
        return;
      }

      // 3. 讓ｩ髯舌メ繧ｧ繝・け
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

      if (!await GoogleMapsNavigator.areTermsAccepted()) {
        final accepted = await GoogleMapsNavigator.showTermsAndConditionsDialog(
          'Google Maps Navigation SDK 蛻ｩ逕ｨ隕冗ｴ・,
          '繝翫ン繧ｲ繝ｼ繧ｷ繝ｧ繝ｳ讖溯・繧貞茜逕ｨ縺吶ｋ縺ｫ縺ｯ縲；oogle Maps Platform 縺ｮ蛻ｩ逕ｨ隕冗ｴ・↓蜷梧э縺吶ｋ蠢・ｦ√′縺ゅｊ縺ｾ縺吶・,
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
        // 繝翫ン繧ｲ繝ｼ繧ｷ繝ｧ繝ｳ逕ｻ髱｢繧定｡ｨ遉ｺ・・DK繝｢繝ｼ繝会ｼ・        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text('${data.title} 縺ｸ縺ｮ譯亥・')),
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
        
        // 繝翫ン繧ｲ繝ｼ繧ｷ繝ｧ繝ｳ逕ｻ髱｢縺碁哩縺倥ｉ繧後◆蠕後∫判髱｢縺檎函縺阪※縺・ｌ縺ｰ繝昴ャ繝励☆繧・        if (context.mounted) {
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
          SnackBar(content: Text('繝翫ン繧ｲ繝ｼ繧ｷ繝ｧ繝ｳ縺ｮ髢句ｧ九↓螟ｱ謨励＠縺ｾ縺励◆: $e')),
        );
      }
    }
  }
}
