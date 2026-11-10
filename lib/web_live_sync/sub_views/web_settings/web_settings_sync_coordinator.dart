// FILE: lib/web_live_sync/sub_views/web_settings/web_settings_sync_coordinator.dart
// Revision: #PH-REV-793 (ENTERPRISE-FY-ISOLATED-BRANDING-AND-BASE64-LOGO-SYNC)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../pharoah_web_manager.dart';
import '../../../logic/app_settings_model.dart';

class WebSettingsSyncCoordinator {
  /// Centrally saves AppConfig from Web, ensures monotonic versioning,
  /// saves specifically into the active FY snapshot in fyVault, and pushes to D1 Edge & Cloud.
  static Future<bool> saveAndBroadcastConfig({
    required PharoahWebManager webPh,
    required AppConfig updatedConfig,
  }) async {
    try {
      updatedConfig.version += 1;
      updatedConfig.updatedAt = DateTime.now().millisecondsSinceEpoch;
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

      // 2. Dispatch via Manager which enqueues to SyncQueue and D1 Edge
      webPh.updateAppConfig(updatedConfig);

      // 3. Trigger immediate cloud push to update Cloud storage
      final bool cloudSynced = await webPh.pushUpdatedDataToCloud();
      return cloudSynced;
    } catch (e) {
      debugPrint("WebSettingsSyncCoordinator error: $e");
      return false;
    }
  }
}
