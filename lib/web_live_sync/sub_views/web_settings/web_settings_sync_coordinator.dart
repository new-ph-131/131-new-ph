// FILE: lib/web_live_sync/sub_views/web_settings/web_settings_sync_coordinator.dart
// Revision: #PH-REV-792 (ENTERPRISE-WEB-SETTINGS-HUB-AND-D1-CONFIG-SYNC)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../pharoah_web_manager.dart';
import '../../../logic/app_settings_model.dart';
import '../../sync_protocol/sync_queue_manager.dart';
import '../../../gst/gst_diary/services/gst_diary_d1_sync_service.dart';

class WebSettingsSyncCoordinator {
  /// Centrally saves AppConfig from Web, ensures monotonic versioning,
  /// replicates across all Multi-FY snapshots, and pushes to D1 Edge & Cloud.
  static Future<bool> saveAndBroadcastConfig({
    required PharoahWebManager webPh,
    required AppConfig updatedConfig,
  }) async {
    try {
      updatedConfig.version += 1;
      updatedConfig.updatedAt = DateTime.now().millisecondsSinceEpoch;
      webPh.appConfig = updatedConfig;

      // 1. Mirror config.json across all FY snapshots in fyVault so FY switches never revert settings
      final configJsonStr = jsonEncode(updatedConfig.toMap());
      webPh.fyVault.forEach((fy, files) {
        files['config.json'] = configJsonStr;
      });

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
