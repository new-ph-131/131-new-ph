// FILE: lib/web_live_sync/sub_views/web_settings/web_settings_sync_coordinator.dart
// Revision: #PH-REV-797 (ENTERPRISE-WEB-SETTINGS-D1-FAST-PATH)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../pharoah_web_manager.dart';
import '../../../models.dart';
import '../../../logic/app_settings_model.dart';
import 'services/web_settings_d1_sync_service.dart';

class WebSettingsSyncCoordinator {
  /// Centrally saves AppConfig from Web, ensures monotonic versioning,
  /// saves specifically into the active FY snapshot in fyVault, and pushes to D1 Edge with fast ~200ms confirmation.
  static Future<bool> saveAndBroadcastConfig({
    required PharoahWebManager webPh,
    required AppConfig updatedConfig,
  }) async {
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      updatedConfig.version = nowMs;
      updatedConfig.updatedAt = nowMs;
      webPh.appConfig = updatedConfig;

      // 1. Save config.json specifically for the active Financial Year in fyVault
      final activeFy = webPh.financialYear;
      final configJsonStr = jsonEncode(updatedConfig.toMap());
      if (webPh.fyVault.containsKey(activeFy) && webPh.fyVault[activeFy] != null) {
        webPh.fyVault[activeFy]!['config.json'] = configJsonStr;
      } else {
        webPh.fyVault[activeFy] = {
          'config.json': configJsonStr,
        };
      }

      // 2. Fast-Path D1 Edge Sync (~200ms roundtrip)
      final bool d1Success = await WebSettingsD1SyncService.syncConfigToD1(
        config: updatedConfig,
        storeToken: webPh.activeStoreToken,
        financialYear: activeFy,
        clientSource: "WEB_PORTAL",
      );

      // 3. Dispatch to local manager outbox & notify listeners
      webPh.updateAppConfigWithoutBlockingCloud(updatedConfig);

      // 4. Trigger background full-store cloud vault backup silently (unawaited so UI is not blocked)
      unawaited(webPh.pushUpdatedDataToCloud().catchError((e) {
        debugPrint("Background cloud push: $e");
        return false;
      }));

      return d1Success;
    } catch (e) {
      debugPrint("WebSettingsSyncCoordinator error: $e");
      return false;
    }
  }

  /// Centrally saves NumberingSeries from Web, saves into active FY snapshot in fyVault, and pushes to D1 Edge.
  static Future<bool> saveAndBroadcastSeries({
    required PharoahWebManager webPh,
    required List<NumberingSeries> updatedSeries,
  }) async {
    try {
      webPh.numberingSeries = updatedSeries;

      // 1. Save series.json specifically for the active Financial Year in fyVault
      final activeFy = webPh.financialYear;
      final seriesJsonStr = jsonEncode(updatedSeries.map((e) => e.toMap()).toList());
      if (webPh.fyVault.containsKey(activeFy) && webPh.fyVault[activeFy] != null) {
        webPh.fyVault[activeFy]!['series.json'] = seriesJsonStr;
      } else {
        webPh.fyVault[activeFy] = {
          'series.json': seriesJsonStr,
        };
      }

      // 2. Fast-Path D1 Edge Sync (~200ms)
      final bool d1Success = await WebSettingsD1SyncService.syncSeriesToD1(
        seriesList: updatedSeries,
        storeToken: webPh.activeStoreToken,
        financialYear: activeFy,
        clientSource: "WEB_PORTAL",
      );

      webPh.notifyListeners();

      // 3. Trigger background full-store backup silently
      unawaited(webPh.pushUpdatedDataToCloud().catchError((e) {
        debugPrint("Background series cloud push: $e");
        return false;
      }));

      return d1Success;
    } catch (e) {
      debugPrint("WebSettingsSyncCoordinator series error: $e");
      return false;
    }
  }
}
