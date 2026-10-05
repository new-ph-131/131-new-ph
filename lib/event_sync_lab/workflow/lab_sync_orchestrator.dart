// FILE: lib/event_sync_lab/workflow/lab_sync_orchestrator.dart
import 'package:flutter/foundation.dart';
import '../../pharoah_manager.dart';
import '../../web_live_sync/pharoah_web_manager.dart';
import '../../web_live_sync/weblivetoken.dart';
import '../models/lab_sync_event.dart';
import '../method/lab_event_transport.dart';
import '../logic/lab_delta_processor.dart';

/// Workflow Orchestrator: Connects local mutations to outgoing signals
/// and incoming signals to atomic delta merges.
class LabSyncOrchestrator {
  static final LabSyncOrchestrator instance = LabSyncOrchestrator._internal();
  LabSyncOrchestrator._internal();

  final List<String> eventLog = [];
  void Function()? onLogUpdated;

  void _addLog(String msg) {
    final entry = "[${DateTime.now().toIso8601String().substring(11, 19)}] $msg";
    eventLog.insert(0, entry);
    if (eventLog.length > 50) eventLog.removeLast();
    onLogUpdated?.call();
    debugPrint(entry);
  }

  /// Binds the orchestrator to Native App
  Future<void> bindApp(PharoahManager ph) async {
    if (ph.activeCompany == null) return;
    final token = await WebLiveToken.getOrCreateToken(ph.activeCompany!.id);
    
    _addLog("🟢 Binding App Orchestrator to Store Token: $token");

    LabEventTransport.instance.startListening(
      storeToken: token,
      mySource: 'APP',
      onSignal: (event) async {
        _addLog("📥 Incoming Remote Signal from ${event.source}: ${event.action} (${event.entityId})");
        final ok = await LabDeltaProcessor.instance.processEventForApp(ph, event);
        _addLog(ok ? "✅ App Auto-Merged latest cloud delta!" : "❌ App Merge Failed!");
      },
    );
  }

  /// Binds the orchestrator to Web Workstation
  void bindWeb(PharoahWebManager webPh) {
    if (!webPh.isAuthenticated || webPh.activeStoreToken.isEmpty) return;
    final token = webPh.activeStoreToken;

    _addLog("🟢 Binding Web Orchestrator to Store Token: $token");

    LabEventTransport.instance.startListening(
      storeToken: token,
      mySource: 'WEB',
      onSignal: (event) async {
        _addLog("📥 Incoming Remote Signal from ${event.source}: ${event.action} (${event.entityId})");
        final ok = await LabDeltaProcessor.instance.processEventForWeb(webPh, event);
        _addLog(ok ? "✅ Web Auto-Merged latest cloud delta!" : "❌ Web Merge Failed!");
      },
    );
  }

  /// Unbinds listener
  void unbind() {
    LabEventTransport.instance.stopListening();
    _addLog("🛑 Lab Orchestrator Unbound");
  }

  /// Triggers outgoing mutation signal from App to Web
  Future<bool> dispatchAppMutation(
    PharoahManager ph, {
    required String action,
    required String entityId,
    Map<String, dynamic> payload = const {},
  }) async {
    if (ph.activeCompany == null) return false;
    final token = await WebLiveToken.getOrCreateToken(ph.activeCompany!.id);

    final event = LabSyncEvent(
      id: "evt_${DateTime.now().millisecondsSinceEpoch}",
      storeToken: token,
      source: 'APP',
      action: action,
      entityId: entityId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: payload,
    );

    _addLog("📤 Dispatching Event from APP: $action ($entityId)...");
    final emitted = await LabEventTransport.instance.emitSignal(event);
    _addLog(emitted ? "⚡ Signal Broadcasted to Web in ${LabEventTransport.instance.lastLatencyMs}ms" : "❌ Signal Broadcast Failed!");
    return emitted;
  }

  /// Triggers outgoing mutation signal from Web to App
  Future<bool> dispatchWebMutation(
    PharoahWebManager webPh, {
    required String action,
    required String entityId,
    Map<String, dynamic> payload = const {},
  }) async {
    if (!webPh.isAuthenticated || webPh.activeStoreToken.isEmpty) return false;

    final event = LabSyncEvent(
      id: "evt_${DateTime.now().millisecondsSinceEpoch}",
      storeToken: webPh.activeStoreToken,
      source: 'WEB',
      action: action,
      entityId: entityId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: payload,
    );

    _addLog("📤 Dispatching Event from WEB: $action ($entityId)...");
    final emitted = await LabEventTransport.instance.emitSignal(event);
    _addLog(emitted ? "⚡ Signal Broadcasted to App in ${LabEventTransport.instance.lastLatencyMs}ms" : "❌ Signal Broadcast Failed!");
    return emitted;
  }
}
