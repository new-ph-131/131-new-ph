import '../../web_live_sync/sync_protocol/tombstone_engine.dart';
import '../../sync_core/orchestrator/master_sync_orchestrator.dart';
// FILE: lib/realtime_signaling/coordinators/app_realtime_coordinator.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../pharoah_manager.dart';
import '../../web_live_sync/weblivetoken.dart';
import '../../web_live_sync/app_sync_engine.dart';
import '../models/sync_signal_event.dart';
import '../transport/cloud_signal_channel.dart';
import '../engines/fast_pull_engine.dart';

/// AppRealtimeCoordinator: Coordinates real-time signaling & sync for Native App.
class AppRealtimeCoordinator {
  static final AppRealtimeCoordinator instance = AppRealtimeCoordinator._internal();
  AppRealtimeCoordinator._internal();

  Timer? _safetyHeartbeatTimer;
  Timer? _pushDebounceTimer;
  bool _isPushing = false;

  /// Starts listening to real-time events from Web
  Future<void> start(PharoahManager ph) async {
    stop();
    if (ph.activeCompany == null || ph.currentFY.isEmpty) return;

    final token = await WebLiveToken.getOrCreateToken(ph.activeCompany!.id);

    // 1. Initial Quick Pull
    FastPullEngine.pullAndMerge(ph);

    // 2. Connect to Real-time Signal Channel
    CloudSignalChannel.instance.listenToSignals(
      storeToken: token,
      mySource: 'app',
      interval: const Duration(milliseconds: 4000),
      onBatchReceived: (batchOps) {
        MasterSyncOrchestrator.dispatchBatchOperations(operations: batchOps, phApp: ph);
      },
      onSignal: (event) async {
        debugPrint("🔔 [AppRealtimeCoordinator] Web activity detected (${event.action}). Pulling immediately...");
        if (event.unmarkedIds.isNotEmpty && ph.activeCompany != null) {
          for (final u in event.unmarkedIds) {
            await TombstoneEngine.unmarkTombstoneWithTimestamp(ph.activeCompany!.id, id: u);
          }
        }
        await FastPullEngine.pullAndMerge(ph);
      },
    );

    // 3. Fallback Safety Net (pulls every 10s if signal missed)
    _safetyHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (ph.activeCompany != null && ph.currentFY.isNotEmpty) {
        await FastPullEngine.pullAndMerge(ph);
      }
    });
  }

  /// Triggers a push to cloud and sends instant wake-up signal to Web
  void notifyAppMutation(PharoahManager ph, {String action = 'DATA_MUTATED', String entityId = '', List<String> unmarkedIds = const []}) {
    if (ph.activeCompany == null || ph.currentFY.isEmpty) return;

    _pushDebounceTimer?.cancel();
    _pushDebounceTimer = Timer(const Duration(milliseconds: 800), () async {
      if (_isPushing) return;
      _isPushing = true;
      try {
        final token = await WebLiveToken.getOrCreateToken(ph.activeCompany!.id);
        final success = await AppSyncEngine.pushStoreData(ph);
        if (success) {
          // Broadcast signal to Web immediately
          await CloudSignalChannel.instance.broadcastSignal(
            SyncSignalEvent(
              storeToken: token,
              source: 'app',
              action: action,
              entityId: entityId,
              unmarkedIds: unmarkedIds,
              companyId: ph.activeCompany!.id,
            ),
          );
          debugPrint("⚡ [AppRealtimeCoordinator] Pushed to cloud and broadcast signal to Web!");
        }
      } catch (e) {
        debugPrint("⚠ [AppRealtimeCoordinator] Push error: $e");
      } finally {
        _isPushing = false;
      }
    });
  }

  void stop() {
    _pushDebounceTimer?.cancel();
    _safetyHeartbeatTimer?.cancel();
    CloudSignalChannel.instance.stopListening();
    _isPushing = false;
  }
}
