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
    if (ph.activeCompany == null) return;

    final token = await WebLiveToken.getOrCreateToken(ph.activeCompany!.id);

    // 1. Initial Quick Pull
    FastPullEngine.pullAndMerge(ph);

    // 2. Connect to Real-time Signal Channel (fast 2s poll)
    CloudSignalChannel.instance.listenToSignals(
      storeToken: token,
      mySource: 'app',
      interval: const Duration(milliseconds: 2000),
      onBatchReceived: (batchOps) async {
        if (ph.currentFY.isEmpty) return false;
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
            await File('$workingDir/s_return.json').writeAsString(
              jsonEncode(ph.saleReturns.map((e) => e.toMap()).toList()),
            );
            await File('$workingDir/p_return.json').writeAsString(
              jsonEncode(ph.purchaseReturns.map((e) => e.toMap()).toList()),
            );
            await File('$workingDir/parts.json').writeAsString(
              jsonEncode(ph.parties.map((e) => e.toMap()).toList()),
            );
            await File('$workingDir/meds.json').writeAsString(
              jsonEncode(ph.medicines.map((e) => e.toMap()).toList()),
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
        final String eventFy = event.fy.trim();
        final String activeFy = ph.currentFY.trim();
        final bool isTargetSameFy = eventFy.isEmpty || eventFy == activeFy;
        debugPrint("🔔 [AppRealtimeCoordinator] Web activity detected (${event.action}, FY: $eventFy, activeFY: $activeFy). Pulling...");

        if (event.unmarkedIds.isNotEmpty && ph.activeCompany != null) {
          final targetFy = eventFy.isNotEmpty ? eventFy : activeFy;
          for (final u in event.unmarkedIds) {
            D1SalesLedgerService.unmarkPermanentlyDeleted(u, "", "", targetFy);
            D1SalesLedgerService.unmarkPermanentlyDeleted(u.toUpperCase(), "", "", targetFy);
            await TombstoneEngine.unmarkTombstoneWithTimestamp(ph.activeCompany!.id, id: u, fy: targetFy);
          }
        }
        if (event.deletedIds.isNotEmpty && ph.activeCompany != null) {
          final companyId = ph.activeCompany!.id;
          final targetFy = eventFy.isNotEmpty ? eventFy : activeFy;
          for (final d in event.deletedIds) {
            D1SalesLedgerService.markPermanentlyDeleted(d, "", "", targetFy);
          }
          await TombstoneEngine.recordBatchTombstones(companyId, event.deletedIds, fy: targetFy);

          // 🛡️ STRICT CROSS-FY ISOLATION GUARD (#PH-REV-808):
          // If the deletion event happened in another FY (e.g. New FY 2027-28),
          // NEVER purge or mutate records from the currently active session (e.g. Back FY 2026-27)!
          if (isTargetSameFy) {
            final reg = await TombstoneEngine.getTombstoneRegistry(companyId);
            final tombstones = await TombstoneEngine.getLocalTombstones(companyId);
            TombstoneEngine.purgeDeletedRecordsWithRegistry(ph, reg);
            TombstoneEngine.purgeDeletedRecords(ph, tombstones, reg);
            ph.notifyListeners();
          }
        }
        await FastPullEngine.pullAndMerge(ph);
        // 🏛️ REAL-TIME SILENT MULTI-YEAR AUTO-CASCADE (#PH-REV-809):
        // If mutation/deletion happened in a back financial year, automatically cascade forward into active year!
        if (eventFy.isNotEmpty && eventFy != activeFy && ph.activeCompany != null) {
          debugPrint("🏛️ [AppRealtimeCoordinator] Cross-FY mutation detected from $eventFy. Silently cascading balances & stock into active year $activeFy...");
          await ph.silentAutoCascadeFromBackYear(eventFy);
        }
      },
    );

    // 3. Fallback Safety Net (pulls every 12s if signal missed, including on Control Panel for FY discovery)
    _safetyHeartbeatTimer = Timer.periodic(const Duration(seconds: 12), (_) async {
      if (ph.activeCompany != null) {
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
    String? fy,
  }) {
    if (ph.activeCompany == null) return;
    if (ph.currentFY.isEmpty && action != 'NEW_FY_CREATED') return;
    final String effFy = (fy != null && fy.trim().isNotEmpty) ? fy.trim() : ph.currentFY.trim();

    if (deletedIds.isNotEmpty) {
      for (final d in deletedIds) {
        final rawD = d.trim();
        if (rawD.isNotEmpty) {
          final bool keepCase = rawD.contains('_');
          final clean = keepCase ? rawD : rawD.toUpperCase();
          final scoped = D1SalesLedgerService.isUnscopedSeriesKey(clean)
              ? D1SalesLedgerService.scopeSecondaryKey(clean, effFy, keepCase)
              : clean;
          _pendingDeletedIds.add(scoped);
          _pendingUnmarkedIds.remove(scoped);
          _pendingUnmarkedIds.remove(clean);
          _pendingUnmarkedIds.remove(rawD);
        }
      }
    }
    if (unmarkedIds.isNotEmpty) {
      for (final u in unmarkedIds) {
        final rawU = u.trim();
        if (rawU.isNotEmpty) {
          final bool keepCase = rawU.contains('_');
          final clean = keepCase ? rawU : rawU.toUpperCase();
          final scoped = D1SalesLedgerService.isUnscopedSeriesKey(clean)
              ? D1SalesLedgerService.scopeSecondaryKey(clean, effFy, keepCase)
              : clean;
          _pendingUnmarkedIds.add(scoped);
          _pendingDeletedIds.remove(scoped);
          _pendingDeletedIds.remove(clean);
          _pendingDeletedIds.remove(rawU);
        }
      }
    }
    if (entityId.isNotEmpty && (action.contains('DELETE') || action.contains('REMOVE'))) {
      final rawE = entityId.trim();
      final bool keepCase = rawE.contains('_');
      final clean = keepCase ? rawE : rawE.toUpperCase();
      final scoped = D1SalesLedgerService.isUnscopedSeriesKey(clean)
          ? D1SalesLedgerService.scopeSecondaryKey(clean, effFy, keepCase)
          : clean;
      _pendingDeletedIds.add(scoped);
      _pendingUnmarkedIds.remove(scoped);
      _pendingUnmarkedIds.remove(rawE);
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
                financialYear: effFy,
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
                  financialYear: effFy,
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

  /// Immediately flushes any pending debounced outbox/cloud push before switching Financial Year
  Future<void> flushPendingPushBeforeSwitch(PharoahManager ph) async {
    final bool hadPending = (_pushDebounceTimer?.isActive ?? false) ||
        _hasPendingPush ||
        _pendingDeletedIds.isNotEmpty ||
        _pendingUnmarkedIds.isNotEmpty;
    _pushDebounceTimer?.cancel();
    if (!hadPending && !_isPushing) return;
    if (ph.activeCompany == null) return;
    try {
      await SyncQueueManager.flushOutboxAsJSONBatch();
      await AppSyncEngine.pushStoreData(ph, ph.currentFY);
    } catch (_) {}
  }

  void stop({PharoahManager? ph}) {
    _pushDebounceTimer?.cancel();
    _safetyHeartbeatTimer?.cancel();
    CloudSignalChannel.instance.stopListening();
    _isPushing = false;
    _hasPendingPush = false;
    _pendingDeletedIds.clear();
    _pendingUnmarkedIds.clear();
  }
}
