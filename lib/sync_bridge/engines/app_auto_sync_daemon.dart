import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:pharoah_erp/web_live_sync/app_sync_engine.dart';

/// AppAutoSyncDaemon: Background daemon for the native App (iPad/Mobile).
/// Provides 2-second debounced silent pushes whenever any record is created,
/// edited, or deleted, plus an automated background heartbeat.
class AppAutoSyncDaemon {
  static final AppAutoSyncDaemon instance = AppAutoSyncDaemon._internal();
  AppAutoSyncDaemon._internal();

  Timer? _debounceTimer;
  Timer? _heartbeatTimer;
  bool _isSyncing = false;

  /// Triggers a debounced (2 seconds) background push to Cloud Relay.
  void triggerSilentPush(PharoahManager ph) {
    if (ph.activeCompany == null || ph.currentFY.isEmpty) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () async {
      if (_isSyncing) return;
      _isSyncing = true;
      try {
        final bool success = await AppSyncEngine.pushStoreData(ph);
        if (success) {
          debugPrint("⚡ [AppAutoSyncDaemon] Background delta push successful.");
        } else {
          debugPrint("⚠ [AppAutoSyncDaemon] Background delta push failed or skipped.");
        }
      } catch (e) {
        debugPrint("⚠ [AppAutoSyncDaemon] Push exception: $e");
      } finally {
        _isSyncing = false;
      }
    });
  }

  /// Starts a periodic background heartbeat to pull & merge cloud changes (every 2 minutes)
  void startHeartbeat(PharoahManager ph) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (_isSyncing || ph.activeCompany == null || ph.currentFY.isEmpty) return;
      _isSyncing = true;
      try {
        await AppSyncEngine.pushStoreData(ph);
        debugPrint("💓 [AppAutoSyncDaemon] Periodic cloud heartbeat sync completed.");
      } catch (e) {
        debugPrint("⚠ [AppAutoSyncDaemon] Heartbeat error: $e");
      } finally {
        _isSyncing = false;
      }
    });
  }

  /// Cancels active background timers on logout/session clear
  void stop() {
    _debounceTimer?.cancel();
    _heartbeatTimer?.cancel();
    _isSyncing = false;
  }
}
