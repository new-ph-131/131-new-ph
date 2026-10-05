// FILE: lib/realtime_signaling/coordinators/web_realtime_coordinator.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../web_live_sync/pharoah_web_manager.dart';
import '../models/sync_signal_event.dart';
import '../transport/cloud_signal_channel.dart';

/// WebRealtimeCoordinator: Coordinates real-time signaling & sync for Web Portal.
class WebRealtimeCoordinator {
  final PharoahWebManager webManager;
  Timer? _safetyHeartbeatTimer;
  Timer? _pushDebounceTimer;
  bool _isPushing = false;

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
      interval: const Duration(seconds: 3),
      onSignal: (event) async {
        debugPrint("🔔 [WebRealtimeCoordinator] App activity detected (${event.action}). Refreshing immediately...");
        await webManager.refreshStoreData();
      },
    );

    // 2. Fallback Safety Net (refreshes every 10s if signal missed)
    _safetyHeartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (webManager.isAuthenticated && webManager.activeStoreToken.isNotEmpty) {
        await webManager.refreshStoreData();
      }
    });
  }

  /// Triggers a push to cloud and sends instant wake-up signal to App
  void notifyWebMutation({String action = 'DATA_MUTATED', String entityId = ''}) {
    if (!webManager.isAuthenticated || webManager.activeStoreToken.isEmpty) return;

    _pushDebounceTimer?.cancel();
    _pushDebounceTimer = Timer(const Duration(milliseconds: 800), () async {
      if (_isPushing) return;
      _isPushing = true;
      try {
        final success = await webManager.pushUpdatedDataToCloud();
        if (success) {
          // Broadcast signal to App immediately
          await CloudSignalChannel.instance.broadcastSignal(
            SyncSignalEvent(
              storeToken: webManager.activeStoreToken,
              source: 'web',
              action: action,
              entityId: entityId,
              companyId: webManager.currentCompanyId,
            ),
          );
          debugPrint("⚡ [WebRealtimeCoordinator] Pushed to cloud and broadcast signal to App!");
        }
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
  }
}
