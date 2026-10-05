// FILE: lib/event_sync_lab/workflow/lab_sync_orchestrator.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../pharoah_manager.dart';
import '../../web_live_sync/pharoah_web_manager.dart';
import '../../web_live_sync/weblivetoken.dart';
import '../../web_live_sync/app_sync_engine.dart';
import '../models/lab_sync_event.dart';
import '../method/lab_event_transport.dart';
import '../logic/lab_delta_processor.dart';

/// Workflow Orchestrator: Connects REAL-TIME App & Web mutations
/// (Bill Create, Edit, Cancel, Delete, Purchase, Voucher)
/// to the instant Event Bus and atomic Google Drive cloud push/pull.
class LabSyncOrchestrator {
  static final LabSyncOrchestrator instance = LabSyncOrchestrator._internal();
  LabSyncOrchestrator._internal();

  final List<String> eventLog = [];
  void Function()? onLogUpdated;

  Timer? _appDebounceTimer;
  bool _isAppPushing = false;

  Timer? _webDebounceTimer;
  bool _isWebPushing = false;

  void addLog(String msg) {
    final entry = "[${DateTime.now().toIso8601String().substring(11, 19)}] $msg";
    eventLog.insert(0, entry);
    if (eventLog.length > 50) eventLog.removeLast();
    onLogUpdated?.call();
    debugPrint(entry);
  }

  /// 🟢 Binds Native App to live event listener
  Future<void> bindApp(PharoahManager ph) async {
    if (ph.activeCompany == null) return;
    final token = await WebLiveToken.getOrCreateToken(ph.activeCompany!.id);
    
    addLog("🟢 App Event Listener Active for Store: $token");

    LabEventTransport.instance.startListening(
      storeToken: token,
      mySource: 'APP',
      onSignal: (event) async {
        addLog("📥 [APP RECEIVED SIGNAL] Peer ${event.source} performed ${event.action} (${event.entityId})");
        final ok = await LabDeltaProcessor.instance.processEventForApp(ph, event);
        if (ok) {
          addLog("✅ Real Data Auto-Synced from Cloud to App! Screen Updated.");
        } else {
          addLog("❌ Cloud Delta Pull Failed on App.");
        }
      },
    );
  }

  /// 🟢 Binds Web Workstation to live event listener
  void bindWeb(PharoahWebManager webPh) {
    if (!webPh.isAuthenticated || webPh.activeStoreToken.isEmpty) return;
    final token = webPh.activeStoreToken;

    addLog("🟢 Web Event Listener Active for Store: $token");

    LabEventTransport.instance.startListening(
      storeToken: token,
      mySource: 'WEB',
      onSignal: (event) async {
        addLog("📥 [WEB RECEIVED SIGNAL] Peer ${event.source} performed ${event.action} (${event.entityId})");
        final ok = await LabDeltaProcessor.instance.processEventForWeb(webPh, event);
        if (ok) {
          addLog("✅ Real Data Auto-Synced from Cloud to Web! Screen Updated.");
        } else {
          addLog("❌ Cloud Delta Pull Failed on Web.");
        }
      },
    );
  }

  /// ⚡ REAL MUTATION HOOK (APP SIDE):
  /// Triggered whenever user creates, modifies, cancels, or deletes a Bill/Purchase in the App!
  void notifyAppRealMutation(PharoahManager ph, {String action = 'DATA_SAVED', String entityId = ''}) {
    if (ph.activeCompany == null) return;

    _appDebounceTimer?.cancel();
    _appDebounceTimer = Timer(const Duration(milliseconds: 700), () async {
      if (_isAppPushing) return;
      _isAppPushing = true;
      try {
        final token = await WebLiveToken.getOrCreateToken(ph.activeCompany!.id);
        addLog("📤 [APP MUTATION] Pushing real change to Google Drive Cloud Relay...");

        // 1. Silent background push to Google Drive (Zero UI freezing)
        final success = await AppSyncEngine.pushStoreData(ph);

        if (success) {
          // 2. Broadcast high-speed wake-up signal to Web (<50ms)
          final event = LabSyncEvent(
            id: "evt_${DateTime.now().millisecondsSinceEpoch}",
            storeToken: token,
            source: 'APP',
            action: action,
            entityId: entityId,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
          await LabEventTransport.instance.emitSignal(event);
          addLog("⚡ [APP MUTATION COMPLETED] Pushed to Cloud & Signaled Web in ${LabEventTransport.instance.lastLatencyMs}ms!");
        } else {
          addLog("⚠ [APP MUTATION] Cloud Push failed. Check internet.");
        }
      } catch (e) {
        addLog("❌ [APP MUTATION ERROR] $e");
      } finally {
        _isAppPushing = false;
      }
    });
  }

  /// ⚡ REAL MUTATION HOOK (WEB SIDE):
  /// Triggered whenever user creates, modifies, or deletes a Bill/Purchase on Web Workstation!
  void notifyWebRealMutation(PharoahWebManager webPh, {String action = 'DATA_SAVED', String entityId = ''}) {
    if (!webPh.isAuthenticated || webPh.activeStoreToken.isEmpty) return;

    _webDebounceTimer?.cancel();
    _webDebounceTimer = Timer(const Duration(milliseconds: 700), () async {
      if (_isWebPushing) return;
      _isWebPushing = true;
      try {
        addLog("📤 [WEB MUTATION] Pushing real change to Google Drive Cloud Relay...");

        // 1. Silent background push to Google Drive
        final success = await webPh.pushUpdatedDataToCloud();

        if (success) {
          // 2. Broadcast high-speed wake-up signal to App (<50ms)
          final event = LabSyncEvent(
            id: "evt_${DateTime.now().millisecondsSinceEpoch}",
            storeToken: webPh.activeStoreToken,
            source: 'WEB',
            action: action,
            entityId: entityId,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
          await LabEventTransport.instance.emitSignal(event);
          addLog("⚡ [WEB MUTATION COMPLETED] Pushed to Cloud & Signaled App in ${LabEventTransport.instance.lastLatencyMs}ms!");
        } else {
          addLog("⚠ [WEB MUTATION] Cloud Push failed. Check internet.");
        }
      } catch (e) {
        addLog("❌ [WEB MUTATION ERROR] $e");
      } finally {
        _isWebPushing = false;
      }
    });
  }

  void unbind() {
    _appDebounceTimer?.cancel();
    _webDebounceTimer?.cancel();
    LabEventTransport.instance.stopListening();
    addLog("🛑 Lab Orchestrator Unbound");
  }
}
