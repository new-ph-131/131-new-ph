import 'package:flutter/foundation.dart';
import '../pharoah_manager.dart';
import 'engines/app_auto_sync_daemon.dart';

/// SyncBridgeBootstrapper: Binds the 2-Way Live Sync Daemon to PharoahManager
/// lifecycle without touching or modifying any original core files.
class SyncBridgeBootstrapper {
  /// Binds background synchronization to active company session
  static void bind(PharoahManager ph) {
    if (ph.activeCompany != null && ph.currentFY.isNotEmpty) {
      AppAutoSyncDaemon.instance.triggerSilentPush(ph);
      AppAutoSyncDaemon.instance.startHeartbeat(ph);
      debugPrint("🛡️ [SyncBridge] 2-Way Live Sync bounded to ${ph.activeCompany!.name} (${ph.currentFY})");
    }
  }

  /// Stops background timers on session logout
  static void unbind() {
    AppAutoSyncDaemon.instance.stop();
  }
}
