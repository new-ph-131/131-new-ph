import "../../logic/master_cascade_service.dart";
// FILE: lib/realtime_signaling/coordinators/app_realtime_coordinator.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../pharoah_manager.dart';
import '../../sync_core/d1_sales_ledger_service.dart';
import '../../sync_core/orchestrator/master_sync_orchestrator.dart';
import '../../sync_core/outbox/sync_queue_manager.dart';
import '../../web_live_sync/app_sync_engine.dart';
import '../../web_live_sync/sync_protocol/tombstone_engine.dart';
import '../../web_live_sync/weblivetoken.dart';
import '../engines/fast_pull_engine.dart';
import '../models/sync_signal_event.dart';
import '../transport/cloud_signal_channel.dart';

/// AppRealtimeCoordinator: Coordinates real-time signaling & sync for Native App (#PH-REV-711).
class AppRealtimeCoordinator {
  static final AppRealtimeCoordinator instance = AppRealtimeCoordinator._internal();
  AppRealtimeCoordinator._internal();

  Timer? _safetyHeartbeatTimer;
  Timer? _pushDebounceTimer;
  bool _isPushing = false;
  bool _hasPendingPush = false;
  final List<String> _pendingDeletedIds = [];
  final List<String> _pendingUnmarkedIds = [];

  /// Starts listening to real-time events from Web
  Future<void> start(PharoahManager ph) async {
    stop();
    if (ph.activeCompany == null || ph.currentFY.isEmpty) return;

    final token = await WebLiveToken.getOrCreateToken(ph.activeCompany!.id);

    // 1. Initial Quick Pull
    FastPullEngine.pullAndMerge(ph);

    // 2. Connect to Real-time Signal Channel (fast 2s poll)
    CloudSignalChannel.instance.listenToSignals(
      storeToken: token,
      mySource: 'app',
      interval: const Duration(milliseconds: 2000),
      onBatchReceived: (batchOps) async {
        MasterSyncOrchestrator.dispatchBatchOperations(operations: batchOps, phApp: ph);
        try {
          final workingDir = await ph.getWorkingPath();
          if (workingDir.isNotEmpty) {
            await File('$workingDir/sales.json').writeAsString(
              jsonEncode(ph.sales.map((e) => e.toMap()).toList()),
            );
            await File('$workingDir/purc.json').writeAsString(
              jsonEncode(ph.purchases.map((e) => e.toMap()).toList()),
            );
            await File('$workingDir/vouc.json').writeAsString(
              jsonEncode(ph.vouchers.map((e) => e.toMap()).toList()),
            );
            await File('$workingDir/s_challan.json').writeAsString(
              jsonEncode(ph.saleChallans.map((e) => e.toMap()).toList()),
            );
            await File('$workingDir/p_challan.json').writeAsString(
              jsonEncode(ph.purchaseChallans.map((e) => e.toMap()).toList()),
            );
            await File('$workingDir/bats.json').writeAsString(
              jsonEncode(ph.batchHistory.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList()))),
            );
            await File('$workingDir/gst_sessions.json').writeAsString(
              jsonEncode(ph.gstDiarySessions.map((e) => e.toMap()).toList()),
            );
            await File('$workingDir/config.json').writeAsString(
              jsonEncode(ph.config.toMap()),
            );
          }
        } catch (_) {}
        ph.notifyListeners();
      },
      onSignal: (event) async {
        debugPrint("🔔 [AppRealtimeCoordinator] Web activity detected (${event.action}). Pulling immediately...");
        if (event.unmarkedIds.isNotEmpty && ph.activeCompany != null) {
          for (final u in event.unmarkedIds) {
            D1SalesLedgerService.unmarkPermanentlyDeleted(u);
            D1SalesLedgerService.unmarkPermanentlyDeleted(u.toUpperCase());
            await TombstoneEngine.unmarkTombstoneWithTimestamp(ph.activeCompany!.id, id: u);
          }
        }
        if (event.deletedIds.isNotEmpty && ph.activeCompany != null) {
          final companyId = ph.activeCompany!.id;
          for (final d in event.deletedIds) {
            D1SalesLedgerService.markPermanentlyDeleted(d);
          }
          await TombstoneEngine.recordBatchTombstones(companyId, event.deletedIds);
          final reg = await TombstoneEngine.getTombstoneRegistry(companyId);
          final tombstones = await TombstoneEngine.getLocalTombstones(companyId);
          TombstoneEngine.purgeDeletedRecordsWithRegistry(ph, reg);
          TombstoneEngine.purgeDeletedRecords(ph, tombstones, reg);
          ph.notifyListeners();
        }
        await FastPullEngine.pullAndMerge(ph);
      },
    );

    // 3. Fallback Safety Net (pulls every 12s if signal missed)
    _safetyHeartbeatTimer = Timer.periodic(const Duration(seconds: 12), (_) async {
      if (ph.activeCompany != null && ph.currentFY.isNotEmpty) {
        await FastPullEngine.pullAndMerge(ph);
      }
    });
  }

  /// Triggers a non-dropping queued push to cloud and sends instant wake-up signal to Web
  void notifyAppMutation(
    PharoahManager ph, {
    String action = 'DATA_MUTATED',
    String entityId = '',
    List<String> unmarkedIds = const [],
    List<String> deletedIds = const [],
  }) {
    if (ph.activeCompany == null || ph.currentFY.isEmpty) return;

    if (deletedIds.isNotEmpty) {
      for (final d in deletedIds) {
        if (d.trim().isNotEmpty) {
          _pendingDeletedIds.add(d.trim());
          _pendingUnmarkedIds.remove(d.trim());
          _pendingUnmarkedIds.remove(d.trim().toUpperCase());
        }
      }
    }
    if (unmarkedIds.isNotEmpty) {
      for (final u in unmarkedIds) {
        if (u.trim().isNotEmpty) {
          _pendingUnmarkedIds.add(u.trim());
          _pendingDeletedIds.remove(u.trim());
          _pendingDeletedIds.remove(u.trim().toUpperCase());
        }
      }
    }
    if (entityId.isNotEmpty && (action.contains('DELETE') || action.contains('REMOVE'))) {
      _pendingDeletedIds.add(entityId.trim());
    }

    _pushDebounceTimer?.cancel();
    _pushDebounceTimer = Timer(const Duration(milliseconds: 350), () async {
      if (_isPushing) {
        _hasPendingPush = true;
        return;
      }
      _isPushing = true;
      try {
        do {
          _hasPendingPush = false;
          final batchDeleted = List<String>.from(_pendingDeletedIds.toSet());
          final batchUnmarked = List<String>.from(_pendingUnmarkedIds.toSet());
          final token = await WebLiveToken.getOrCreateToken(ph.activeCompany!.id);

          // 1. Flush Outbox first so D1 erp_master_sync has the latest App records immediately
          await SyncQueueManager.flushOutboxAsJSONBatch();

          // 2. Broadcast instant signal to Cloudflare Edge (<30ms)
          if (token.isNotEmpty) {
            await CloudSignalChannel.instance.broadcastSignal(
              SyncSignalEvent(
                storeToken: token,
                source: 'app',
                action: action,
                entityId: entityId,
                deletedIds: batchDeleted,
                unmarkedIds: batchUnmarked,
                companyId: ph.activeCompany!.id,
              ),
            );
          }

          // 3. Push full snapshot to Cloud Relay (Google Drive) + Flush Outbox
          final success = await AppSyncEngine.pushStoreData(ph);
          if (success) {
            // 4. Broadcast post-upload signal so Web refreshes the freshly uploaded snapshot
            if (token.isNotEmpty) {
              await CloudSignalChannel.instance.broadcastSignal(
                SyncSignalEvent(
                  storeToken: token,
                  source: 'app',
                  action: '${action}_COMMITTED',
                  entityId: entityId,
                  deletedIds: batchDeleted,
                  unmarkedIds: batchUnmarked,
                  companyId: ph.activeCompany!.id,
                ),
              );
            }
            _pendingDeletedIds.removeWhere((id) => batchDeleted.contains(id));
            _pendingUnmarkedIds.removeWhere((id) => batchUnmarked.contains(id));
            debugPrint("⚡ [AppRealtimeCoordinator] Pushed to cloud and broadcast signal to Web (#PH-REV-711)!");
          }
        } while (_hasPendingPush);
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
    _hasPendingPush = false;
    _pendingDeletedIds.clear();
    _pendingUnmarkedIds.clear();
  }
}
