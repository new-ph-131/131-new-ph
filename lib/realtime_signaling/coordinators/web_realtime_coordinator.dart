import '../../sync_core/orchestrator/master_sync_orchestrator.dart';
// FILE: lib/realtime_signaling/coordinators/web_realtime_coordinator.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../web_live_sync/pharoah_web_manager.dart';
import '../models/sync_signal_event.dart';
import '../transport/cloud_signal_channel.dart';

/// WebRealtimeCoordinator: Coordinates real-time signaling & sync for Web Portal.
/// Features non-dropping Sequential Execution Queue & Batch Deletion Accumulator.
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

    // 1. Connect to Real-time Signal Channel
    CloudSignalChannel.instance.listenToSignals(
      storeToken: token,
      mySource: 'web',
      interval: const Duration(milliseconds: 3500),
      onBatchReceived: (batchOps) {
        MasterSyncOrchestrator.dispatchBatchOperations(operations: batchOps, phWeb: webManager);
      },
      onSignal: (event) async {
        debugPrint("🔔 [WebRealtimeCoordinator] App activity detected (${event.action}). Processing...");
        if (event.unmarkedIds.isNotEmpty) {
          for (final u in event.unmarkedIds) {
            webManager.unmarkDeletedId(u);
          }
        }
        if (event.deletedIds.isNotEmpty) {
          webManager.purgeDeletedIds(event.deletedIds);
        }
        await webManager.refreshStoreData();
      },
    );

    // 2. Fallback Safety Net (refreshes every 15s if signal missed)
    _safetyHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (webManager.isAuthenticated && webManager.activeStoreToken.isNotEmpty && !_isPushing) {
        await webManager.refreshStoreData();
      }
    });
  }

  /// Triggers a non-dropping queued push with atomic batch deletion support
  void notifyWebMutation({
    String action = 'DATA_MUTATED',
    String entityId = '',
    List<String> deletedIds = const [],
    List<String> unmarkedIds = const [],
  }) {
    if (!webManager.isAuthenticated || webManager.activeStoreToken.isEmpty) return;

    if (deletedIds.isNotEmpty) {
      _pendingDeletedIds.addAll(deletedIds);
    }
    if (unmarkedIds.isNotEmpty) {
      _pendingUnmarkedIds.addAll(unmarkedIds);
    }
    if (entityId.isNotEmpty && (action.contains('DELETE') || action.contains('REMOVE'))) {
      _pendingDeletedIds.add(entityId);
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
          final batchDeleted = List<String>.from(_pendingDeletedIds.where((k) => !k.contains('/')));
          final batchUnmarked = List<String>.from(_pendingUnmarkedIds);
          _pendingDeletedIds.clear();
          _pendingUnmarkedIds.clear();

          // 1. Broadcast instant event to Cloudflare Edge (<30ms)
          await CloudSignalChannel.instance.broadcastSignal(
            SyncSignalEvent(
              storeToken: webManager.activeStoreToken,
              source: 'web',
              action: action,
              entityId: entityId,
              deletedIds: batchDeleted,
              unmarkedIds: batchUnmarked,
              companyId: webManager.companyProfile['id']?.toString() ?? '',
            ),
          );

          // 2. Push full snapshot to Cloud Relay (Google Drive)
          await webManager.pushUpdatedDataToCloud();
          debugPrint("⚡ [WebRealtimeCoordinator] Batch mutation synchronized successfully.");
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
