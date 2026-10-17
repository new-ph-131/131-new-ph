// FILE: lib/web_live_sync/pharoah_auto_sync_service.dart
// Live Revision: #PH-REV-710 (PURCHASE-LIFECYCLE-ATOMIC-SYNC-PRO)
import pharoah_web_manager.dart;
import ../realtime_signaling/coordinators/web_realtime_coordinator.dart;
import ../event_sync_lab/workflow/lab_sync_orchestrator.dart;

/// PharoahAutoSyncService: Delegates to WebRealtimeCoordinator for ultra-fast
/// Cloudflare Edge event signaling (<30ms) + non-dropping sequential sync queue.
class PharoahAutoSyncService {
  final PharoahWebManager webManager;
  late final WebRealtimeCoordinator _coordinator;

  PharoahAutoSyncService({required this.webManager}) {
    _coordinator = WebRealtimeCoordinator(webManager: webManager);
  }

  /// Starts the real-time event listener and fallback safety polling
  void startAutoPull() {
    _coordinator.start();
    LabSyncOrchestrator.instance.addLog("🟢 Web Unified Realtime Listener Active (#PH-REV-710)");
  }

  /// Triggers an immediate Edge signal broadcast + queued Cloud push
  void triggerInstantPush({
    String action = DATA_MUTATED,
    String entityId = ,
    List<String> deletedIds = const [],
    List<String> unmarkedIds = const [],
  }) {
    _coordinator.notifyWebMutation(
      action: action,
      entityId: entityId,
      deletedIds: deletedIds,
      unmarkedIds: unmarkedIds,
    );
    LabSyncOrchestrator.instance.addLog("📤 [WEB] Queued unified mutation ($action: $entityId)");
  }

  void dispose() {
    _coordinator.stop();
  }
}
