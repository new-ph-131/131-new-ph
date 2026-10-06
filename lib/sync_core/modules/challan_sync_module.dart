// FILE: lib/sync_core/modules/challan_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// ChallanSyncModule: Isolated Synchronization & Conflict Resolution Engine for Challans.
/// Strictly decoupled from Sales, Purchases, and Vouchers (File Separation Rule).
class ChallanSyncModule {
  static const String documentType = "CHALLAN";

  /// Dispatches a challan creation or modification to the Outbox queue
  static void onChallanSaved(SaleChallan challan, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(
      syncId: challan.id,
      storeToken: storeToken,
      docType: documentType,
      currentVersion: challan.version,
      isDelete: false,
      rawPayload: challan.toMap(),
    );
  }

  /// Dispatches a soft-delete operation to the Outbox queue
  static void onChallanDeleted(SaleChallan challan, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    challan.isDeleted = 1;
    challan.status = "Cancelled";
    challan.version += 1;
    challan.updatedAt = DateTime.now().millisecondsSinceEpoch;

    SyncQueueManager.enqueueMutation(
      syncId: challan.id,
      storeToken: storeToken,
      docType: documentType,
      currentVersion: challan.version,
      isDelete: true,
      rawPayload: challan.toMap(),
    );
  }

  /// handleIncomingSync conforming to Step 3 Frontend State Optimization
  static List<SaleChallan> handleIncomingSync(List<SaleChallan> currentUIStateList, SyncEnvelope incomingEvent) {
    mergeIncomingChallanEnvelope(currentUIStateList, incomingEvent);
    return currentUIStateList;
  }

  /// Merges an incoming SyncEnvelope into current Challans list
  static bool mergeIncomingChallanEnvelope(List<SaleChallan> currentChallans, SyncEnvelope envelope) {
    if (envelope.documentType != documentType) return false;

    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;

    final incomingChallan = SaleChallan.fromMap(envelope.billData);
    incomingChallan.id = targetId;
    incomingChallan.version = envelope.version;
    incomingChallan.updatedAt = envelope.updatedAt;
    incomingChallan.isDeleted = envelope.isDeleted;

    return applyChallanMutation(currentChallans, incomingChallan);
  }

  /// Core LWW State Machine for Challan Objects
  static bool applyChallanMutation(List<SaleChallan> currentChallans, SaleChallan incoming) {
    final idx = currentChallans.indexWhere((c) => c.id == incoming.id);

    // 1. Check if delete operation
    if (incoming.isDeleted == 1) {
      if (idx != -1) {
        final local = currentChallans[idx];
        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
          currentChallans.removeAt(idx);
          debugPrint("🗑️ [ChallanSyncModule] Soft-deleted challan evicted: ${incoming.billNo} (${incoming.id})");
          return true;
        }
      }
      return false;
    }

    // 2. Existing record check
    if (idx > -1) {
      final local = currentChallans[idx];
      if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) {
        return false;
      }
      currentChallans[idx] = incoming;
      debugPrint("🔄 [ChallanSyncModule] In-place updated challan: ${incoming.billNo} (v${incoming.version})");
      return true;
    } else {
      int billNoIdx = incoming.billNo.isNotEmpty
          ? currentChallans.indexWhere((c) => c.billNo.trim() == incoming.billNo.trim())
          : -1;

      if (billNoIdx != -1) {
        final existing = currentChallans[billNoIdx];
        if (incoming.updatedAt >= existing.updatedAt) {
          currentChallans[billNoIdx] = incoming;
          debugPrint("🔄 [ChallanSyncModule] Replaced challan by number: ${incoming.billNo}");
          return true;
        }
        return false;
      } else {
        currentChallans.insert(0, incoming);
        debugPrint("✨ [ChallanSyncModule] Added new remote challan: ${incoming.billNo} (${incoming.id})");
        return true;
      }
    }
  }
}
