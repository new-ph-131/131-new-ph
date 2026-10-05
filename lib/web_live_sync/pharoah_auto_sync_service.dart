// FILE: lib/web_live_sync/pharoah_auto_sync_service.dart
// Live Revision: #PH-REV-643 (REALTIME-SIGNALING-EVENT-BUS)
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'pharoah_web_manager.dart';
import '../realtime_signaling/coordinators/web_realtime_coordinator.dart';

class PharoahAutoSyncService {
  final PharoahWebManager webManager;
  late final WebRealtimeCoordinator _coordinator;

  PharoahAutoSyncService({required this.webManager}) {
    _coordinator = WebRealtimeCoordinator(webManager: webManager);
  }

  /// Starts real-time signaling listeners when web user logs in
  void startRealtimeSync() {
    _coordinator.start();
  }

  /// 🔄 1. AUTO-PUSH + INSTANT WAKE-UP SIGNAL DISPATCH
  /// Pushes changed data to cloud and immediately sends an ultra-fast event signal to the Native App
  void triggerAutoSync({String action = 'DATA_MUTATED', String entityId = ''}) {
    if (!webManager.isAuthenticated || webManager.activeStoreToken.isEmpty) return;
    _coordinator.notifyWebMutation(action: action, entityId: entityId);
  }

  void dispose() {
    _coordinator.stop();
  }
}
