// FILE: lib/event_sync_lab/logic/lab_delta_processor.dart
import 'package:flutter/foundation.dart';
import '../../pharoah_manager.dart';
import '../../web_live_sync/pharoah_web_manager.dart';
import '../../realtime_signaling/engines/fast_pull_engine.dart';
import '../models/lab_sync_event.dart';

/// Delta Processing Logic: Executes fast atomic pull and in-memory merge
class LabDeltaProcessor {
  static final LabDeltaProcessor instance = LabDeltaProcessor._internal();
  LabDeltaProcessor._internal();

  bool isSyncing = false;
  int lastSyncDurationMs = 0;
  String lastSyncStatus = "None";

  /// Handles incoming remote event for App
  Future<bool> processEventForApp(PharoahManager ph, LabSyncEvent event) async {
    if (isSyncing) return false;
    isSyncing = true;
    final stopwatch = Stopwatch()..start();

    try {
      debugPrint("📥 [LabDeltaProcessor] Processing incoming event on App: ${event.action} (${event.entityId})");
      
      // Pull latest snapshot from Google Drive Cloud Relay using FastPullEngine
      final success = await FastPullEngine.pullAndMerge(ph);
      
      stopwatch.stop();
      lastSyncDurationMs = stopwatch.elapsedMilliseconds;
      lastSyncStatus = success ? "SUCCESS" : "NO_NEW_DATA";

      if (success) {
        debugPrint("✅ [LabDeltaProcessor] App memory updated & UI notified in ${lastSyncDurationMs}ms!");
      }
      return success;
    } catch (e) {
      stopwatch.stop();
      lastSyncDurationMs = stopwatch.elapsedMilliseconds;
      lastSyncStatus = "ERROR: $e";
      debugPrint("❌ [LabDeltaProcessor] Process error on App: $e");
      return false;
    } finally {
      isSyncing = false;
    }
  }

  /// Handles incoming remote event for Web Workstation
  Future<bool> processEventForWeb(PharoahWebManager webPh, LabSyncEvent event) async {
    if (isSyncing) return false;
    isSyncing = true;
    final stopwatch = Stopwatch()..start();

    try {
      debugPrint("📥 [LabDeltaProcessor] Processing incoming event on Web: ${event.action} (${event.entityId})");

      // Refresh Web Workstation data from Google Drive Cloud Relay
      await webPh.refreshStoreData();

      stopwatch.stop();
      lastSyncDurationMs = stopwatch.elapsedMilliseconds;
      lastSyncStatus = "SUCCESS";
      debugPrint("✅ [LabDeltaProcessor] Web workstation updated in ${lastSyncDurationMs}ms!");
      return true;
    } catch (e) {
      stopwatch.stop();
      lastSyncDurationMs = stopwatch.elapsedMilliseconds;
      lastSyncStatus = "ERROR: $e";
      debugPrint("❌ [LabDeltaProcessor] Process error on Web: $e");
      return false;
    } finally {
      isSyncing = false;
    }
  }
}
