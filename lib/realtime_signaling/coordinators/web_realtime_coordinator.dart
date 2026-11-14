import '../../sync_core/d1_sales_ledger_service.dart';
// FILE: lib/realtime_signaling/coordinators/web_realtime_coordinator.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../sync_core/orchestrator/master_sync_orchestrator.dart';
import '../../sync_core/outbox/sync_queue_manager.dart';
import '../../web_live_sync/pharoah_web_manager.dart';
import '../models/sync_signal_event.dart';
import '../transport/cloud_signal_channel.dart';

/// WebRealtimeCoordinator: Coordinates real-time signaling & sync for Web Portal (#PH-REV-711).
/// Flushes Outbox to D1 BEFORE broadcasting signal, then pushes snapshot to Cloud Relay and confirms.
class WebRealtimeCoordinator {
  final PharoahWebManager webManager;

  Timer? _safetyHeartbeatTimer;
  Timer? _pushDebounceTimer;
  bool _isPushing = false;
  bool _hasPendingPush = false;
  final List<String> _pendingDeletedIds = [];
  final List<String> _pendingUnmarkedIds = [];

  WebRealtimeCoordinator({required this.webManager});

  /// Starts listening to real-time events from Native App
  void start() {
    stop();
    if (!webManager.isAuthenticated || webManager.activeStoreToken.isEmpty) return;

    final token = webManager.activeStoreToken;

    // 1. Connect to Real-time Signal Channel (fast 2s poll)
    CloudSignalChannel.instance.listenToSignals(
      storeToken: token,
      mySource: 'web',
      interval: const Duration(milliseconds: 2000),
      onTombstonesReceived: (edgeTombstones) {
        webManager.purgeDeletedIds(edgeTombstones);
      },
      onBatchReceived: (batchOps) {
        MasterSyncOrchestrator.dispatchBatchOperations(operations: batchOps, phWeb: webManager);
      },
      onSignal: (event) async {
        final String eventFy = event.financialYear?.trim() ?? '';
        final String activeFy = webManager.financialYear.trim();
        final bool isSameFy = eventFy.isEmpty || activeFy.isEmpty || eventFy == activeFy;
        debugPrint("🔔 [WebRealtimeCoordinator] App activity detected (${event.action}, FY: $eventFy, activeFY: $activeFy). Processing...");

        final String targetFy = eventFy.isNotEmpty ? eventFy : activeFy;
        if (event.unmarkedIds.isNotEmpty) {
          for (final u in event.unmarkedIds) {
            final cleanU = u.trim();
            if (cleanU.isEmpty) continue;
            webManager.unmarkDeletedId(cleanU, preserveCase: cleanU.contains('_'), fy: targetFy);
            D1SalesLedgerService.unmarkPermanentlyDeleted(cleanU, "", "", targetFy, cleanU.contains('_'));
            if (!cleanU.contains('_')) {
              D1SalesLedgerService.unmarkPermanentlyDeleted(cleanU.toUpperCase(), "", "", targetFy);
            }
          }
        }
        // 🛡️ STRICT CROSS-FY ISOLATION GUARD (#PH-REV-800 & #PH-REV-809):
        // Only purge local in-memory active year if mutation occurred in active year!
        if (isSameFy) {
          final List<String> allDel = [...event.deletedIds];
          if (event.entityId.isNotEmpty && (event.action.contains('DELETE') || event.action.contains('REMOVE'))) {
            allDel.add(event.entityId);
          }
          if (allDel.isNotEmpty) {
            webManager.purgeDeletedIds(allDel);
          }
        }
        if (!_isPushing && !webManager.isCloudPushInProgress) {
          await webManager.refreshStoreData(isSilent: true);
          // 🏛️ REAL-TIME SILENT MULTI-YEAR AUTO-CASCADE (#PH-REV-809):
          // If mutation/deletion happened in a back financial year, automatically cascade forward into active year!
          if (eventFy.isNotEmpty && eventFy != activeFy) {
            debugPrint("🏛️ [WebRealtimeCoordinator] Cross-FY mutation detected from $eventFy. Silently cascading into active year $activeFy...");
            webManager.silentAutoCascadeMultiYear(eventFy);
          }
        }
      },
    );

    // 2. Fallback Safety Net (refreshes silently every 12s if signal missed)
    _safetyHeartbeatTimer = Timer.periodic(const Duration(seconds: 12), (_) async {
      if (webManager.isAuthenticated && webManager.activeStoreToken.isNotEmpty && !_isPushing) {
        await webManager.refreshStoreData(isSilent: true);
      }
    });
  }

  /// Triggers a non-dropping queued push with atomic Outbox flush + post-upload signal confirmation
  void notifyWebMutation({
    String action = 'DATA_MUTATED',
    String entityId = '',
    List<String> deletedIds = const [],
    List<String> unmarkedIds = const [],
    String? fy,
  }) {
    if (!webManager.isAuthenticated || webManager.activeStoreToken.isEmpty) return;
    final String effFy = (fy != null && fy.trim().isNotEmpty) ? fy.trim() : webManager.financialYear.trim();

    if (deletedIds.isNotEmpty) {
      for (final d in deletedIds) {
        final rawD = d.trim();
        if (rawD.isEmpty) continue;
        final bool keepCase = rawD.contains('_');
        final clean = keepCase ? rawD : rawD.toUpperCase();
        final scoped = D1SalesLedgerService.isUnscopedSeriesKey(clean)
            ? D1SalesLedgerService.scopeSecondaryKey(clean, effFy, keepCase)
            : clean;
        _pendingDeletedIds.add(scoped);
        _pendingUnmarkedIds.remove(scoped);
        _pendingUnmarkedIds.remove(rawD);
        if (!keepCase) _pendingUnmarkedIds.remove(rawD.toUpperCase());
      }
    }
    if (unmarkedIds.isNotEmpty) {
      for (final u in unmarkedIds) {
        final rawU = u.trim();
        if (rawU.isEmpty) continue;
        final bool keepCase = rawU.contains('_');
        final clean = keepCase ? rawU : rawU.toUpperCase();
        final scoped = D1SalesLedgerService.isUnscopedSeriesKey(clean)
            ? D1SalesLedgerService.scopeSecondaryKey(clean, effFy, keepCase)
            : clean;
        _pendingUnmarkedIds.add(scoped);
        _pendingDeletedIds.remove(scoped);
        _pendingDeletedIds.remove(rawU);
        if (!keepCase) _pendingDeletedIds.remove(rawU.toUpperCase());
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
    _pushDebounceTimer = Timer(const Duration(milliseconds: 250), () async {
      if (_isPushing) {
        _hasPendingPush = true;
        return;
      }
      _isPushing = true;
      try {
        do {
          _hasPendingPush = false;
          final batchDeleted = List<String>.from(_pendingDeletedIds.where((k) => k.trim().isNotEmpty));
          final batchUnmarked = List<String>.from(_pendingUnmarkedIds);

          // 0. Ensure any in-flight D1 direct writes/deletes settle before signaling App & uploading snapshot
          await webManager.awaitPendingD1Writes();

          // 1. Flush Outbox immediately so D1 erp_master_sync has the WPUR-/W- record BEFORE App polls
          await SyncQueueManager.flushOutboxAsJSONBatch();

          // 2. Broadcast instant D1 wake-up event (<30ms) so App gets D1 batch_operations immediately
          await CloudSignalChannel.instance.broadcastSignal(
            SyncSignalEvent(
              storeToken: webManager.activeStoreToken,
              source: 'web',
              action: action,
              entityId: entityId,
              financialYear: effFy,
              deletedIds: batchDeleted,
              unmarkedIds: batchUnmarked,
              companyId: webManager.companyProfile['id']?.toString() ?? '',
            ),
          );

          // 3. Push full snapshot to Cloud Relay (Google Drive)
          final bool relayOk = await webManager.pushUpdatedDataToCloud();

          // 4. Broadcast post-upload confirmation signal so App's FastPullEngine pulls the fresh purc.json/sales.json
          if (relayOk) {
            await CloudSignalChannel.instance.broadcastSignal(
              SyncSignalEvent(
                storeToken: webManager.activeStoreToken,
                source: 'web',
                action: '${action}_COMMITTED',
                entityId: entityId,
                financialYear: effFy,
                deletedIds: batchDeleted,
                unmarkedIds: batchUnmarked,
                companyId: webManager.companyProfile['id']?.toString() ?? '',
              ),
            );
          }

          // Remove processed IDs safely
          _pendingDeletedIds.removeWhere((id) => batchDeleted.contains(id));
          _pendingUnmarkedIds.removeWhere((id) => batchUnmarked.contains(id));

          debugPrint("⚡ [WebRealtimeCoordinator] Batch mutation synchronized & confirmed (#PH-REV-711).");
        } while (_hasPendingPush);
      } catch (e) {
        debugPrint("⚠ [WebRealtimeCoordinator] Push error: $e");
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
