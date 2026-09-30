// FILE: lib/web_live_sync/pharoah_auto_sync_service.dart
// Live Revision: #PH-REV-128

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'pharoah_web_manager.dart';

class PharoahAutoSyncService {
  final PharoahWebManager webManager;
  Timer? _debounceTimer;
  Timer? _heartbeatTimer;
  bool _isSyncing = false;

  PharoahAutoSyncService({required this.webManager}) {
    _startPeriodicHeartbeat();
  }

  /// 🔄 1. DEBOUNCED AUTO-PUSH (Triggered on any Transaction / Master update)
  /// Rapid clicks or multiple line items won't spam the network;
  /// it waits 2 seconds after the last action and silently syncs to Cloud.
  void triggerAutoSync() {
    if (!webManager.isAuthenticated || webManager.activeStoreToken.isEmpty) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () async {
      if (_isSyncing) return;
      _isSyncing = true;
      try {
        await webManager.pushUpdatedDataToCloud();
        debugPrint("⚡ [AutoSync] Background delta pushed to cloud successfully.");
      } catch (e) {
        debugPrint("⚠ [AutoSync] Background push error: $e");
      } finally {
        _isSyncing = false;
      }
    });
  }

  /// 💓 2. PERIODIC BACKGROUND HEARTBEAT (Silent Pull & Merge every 2 minutes)
  void _startPeriodicHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!webManager.isAuthenticated || webManager.activeStoreToken.isEmpty || _isSyncing) return;
      _isSyncing = true;
      try {
        await webManager.refreshStoreData();
        debugPrint("💓 [AutoSync] Periodic cloud heartbeat sync completed.");
      } catch (e) {
        debugPrint("⚠ [AutoSync] Heartbeat pull error: $e");
      } finally {
        _isSyncing = false;
      }
    });
  }

  void dispose() {
    _debounceTimer?.cancel();
    _heartbeatTimer?.cancel();
  }
}
