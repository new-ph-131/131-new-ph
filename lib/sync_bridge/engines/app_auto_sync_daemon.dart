// FILE: lib/sync_bridge/engines/app_auto_sync_daemon.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../pharoah_manager.dart';
import '../../web_live_sync/app_sync_engine.dart';
import '../../web_live_sync/weblivetoken.dart';
import '../../web_live_sync/sync_protocol/tombstone_engine.dart';
import '../../realtime_signaling/engines/fast_pull_engine.dart';
import '../../realtime_signaling/transport/cloud_signal_channel.dart';
import '../../realtime_signaling/models/sync_signal_event.dart';

/// AppAutoSyncDaemon: Background daemon for the native App (iPad/Mobile/Desktop).
/// Provides non-dropping queue execution for high-speed deletions, Cloudflare Edge
/// signaling (<30ms), and 2-way real-time heartbeat.
class AppAutoSyncDaemon {
  static final AppAutoSyncDaemon instance = AppAutoSyncDaemon._internal();
  AppAutoSyncDaemon._internal();

  Timer? _debounceTimer;
  Timer? _heartbeatTimer;
  bool _isSyncing = false;
  bool _hasPendingPush = false;
  final List<String> _pendingDeletedIds = [];

  /// Triggers a non-dropping background push with Cloudflare Edge signal
  void triggerSilentPush(
    PharoahManager ph, {
    String action = 'DATA_SAVED',
    String entityId = '',
    List<String> deletedIds = const [],
  }) {
    if (ph.activeCompany == null || ph.currentFY.isEmpty) return;

    if (deletedIds.isNotEmpty) {
      _pendingDeletedIds.addAll(deletedIds);
    }
    if (entityId.isNotEmpty && (action.contains('DELETE') || action.contains('REMOVE'))) {
      _pendingDeletedIds.add(entityId);
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      if (_isSyncing) {
        _hasPendingPush = true;
        return;
      }
      _isSyncing = true;
      try {
        do {
          _hasPendingPush = false;
          final batchDeleted = List<String>.from(_pendingDeletedIds);
          _pendingDeletedIds.clear();

          final companyId = ph.activeCompany!.id;
          final storeToken = await WebLiveToken.getOrCreateToken(companyId);

          // 1. Send ultra-fast Cloudflare Edge mutation event (<30ms)
          if (storeToken.isNotEmpty) {
            await CloudSignalChannel.instance.broadcastSignal(
              SyncSignalEvent(
                storeToken: storeToken,
                source: 'app',
                action: action,
                entityId: entityId,
                deletedIds: batchDeleted,
                companyId: companyId,
              ),
            );
          }

          // 2. Push full snapshot to Cloud Relay (Google Drive)
          final bool success = await AppSyncEngine.pushStoreData(ph);
          if (success) {
            debugPrint("⚡ [AppAutoSyncDaemon] Background push successful with ${batchDeleted.length} batch tombstones.");
          }
        } while (_hasPendingPush);
      } catch (e) {
        debugPrint("⚠ [AppAutoSyncDaemon] Push exception: $e");
      } finally {
        _isSyncing = false;
      }
    });
  }

  /// Starts real-time listening & background heartbeat to pull & merge cloud changes
  void startHeartbeat(PharoahManager ph) async {
    _heartbeatTimer?.cancel();

    if (ph.activeCompany != null && ph.currentFY.isNotEmpty) {
      final storeToken = await WebLiveToken.getOrCreateToken(ph.activeCompany!.id);
      if (storeToken.isNotEmpty) {
        // Connect to Cloudflare Edge Signal Bus
        CloudSignalChannel.instance.listenToSignals(
          storeToken: storeToken,
          mySource: 'app',
          interval: const Duration(milliseconds: 1200),
          onSignal: (event) async {
            debugPrint("🔔 [AppAutoSyncDaemon] Remote Web Mutation Received: ${event.action}");
            if (event.deletedIds.isNotEmpty) {
              TombstoneEngine.purgeDeletedRecords(ph, event.deletedIds.toSet());
              ph.notifyListeners();
            }
            await FastPullEngine.pullAndMerge(ph);
          },
        );
      }
    }

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (_isSyncing || ph.activeCompany == null || ph.currentFY.isEmpty) return;
      _isSyncing = true;
      try {
        await FastPullEngine.pullAndMerge(ph);
        debugPrint("💓 [AppAutoSyncDaemon] Periodic cloud pull heartbeat completed.");
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
    CloudSignalChannel.instance.stopListening();
    _isSyncing = false;
    _hasPendingPush = false;
    _pendingDeletedIds.clear();
  }
}
