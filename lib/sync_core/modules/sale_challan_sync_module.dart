// FILE: lib/sync_core/modules/sale_challan_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// SaleChallanSyncModule: Isolated Synchronization & Conflict Resolution Engine for Sale Challans (Dispatch Notes).
/// Strictly decoupled from Purchase Challan, Sales, and Purchases (File Separation Rule).
class SaleChallanSyncModule {
  static const String docTypeSaleChallan = "SALE_CHALLAN";

  /// Enqueue an Outbox mutation when a Sale Challan is created or modified
  static void onSaleChallanSaved(SaleChallan challan, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(
      syncId: challan.id,
      storeToken: storeToken,
      docType: docTypeSaleChallan,
      currentVersion: challan.version,
      isDelete: false,
      rawPayload: challan.toMap(),
    );
  }

  /// Enqueue a deletion tombstone when a Sale Challan is deleted
  static void onSaleChallanDeleted(SaleChallan challan, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    challan.isDeleted = 1;
    challan.status = "Cancelled";
    challan.version += 1;
    challan.updatedAt = DateTime.now().millisecondsSinceEpoch;
    SyncQueueManager.enqueueMutation(
      syncId: challan.id,
      storeToken: storeToken,
      docType: docTypeSaleChallan,
      currentVersion: challan.version,
      isDelete: true,
      rawPayload: challan.toMap(),
    );
  }

  /// Merge incoming real-time SyncEnvelope into local Sale Challan list
  static bool mergeIncomingSaleChallanEnvelope(List<SaleChallan> currentChallans, SyncEnvelope envelope) {
    if (envelope.documentType != docTypeSaleChallan && envelope.documentType != "CHALLAN") return false;
    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;
    final incomingChallan = SaleChallan.fromMap(envelope.billData);
    incomingChallan.id = targetId;
    incomingChallan.version = envelope.version;
    incomingChallan.updatedAt = envelope.updatedAt;
    incomingChallan.isDeleted = envelope.isDeleted;
    return applySaleChallanMutation(currentChallans, incomingChallan);
  }

  /// Apply mutation with Monotonic Versioning and LWW Clock Auditing
  static bool applySaleChallanMutation(List<SaleChallan> currentChallans, SaleChallan incoming) {
    final idx = currentChallans.indexWhere((c) => c.id == incoming.id);
    if (incoming.isDeleted == 1) {
      if (idx != -1) {
        final local = currentChallans[idx];
        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
          currentChallans.removeAt(idx);
          debugPrint("🗑️ [SaleChallanSyncModule] Evicted deleted sale challan: ${incoming.billNo}");
          return true;
        }
      }
      return false;
    }
    if (idx > -1) {
      final local = currentChallans[idx];
      if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) {
        return false;
      }
      currentChallans[idx] = incoming;
      return true;
    } else {
      int billNoIdx = incoming.billNo.isNotEmpty
          ? currentChallans.indexWhere((c) => c.billNo.trim() == incoming.billNo.trim())
          : -1;
      if (billNoIdx != -1) {
        final existing = currentChallans[billNoIdx];
        if (incoming.updatedAt >= existing.updatedAt) {
          currentChallans[billNoIdx] = incoming;
          return true;
        }
        return false;
      } else {
        currentChallans.insert(0, incoming);
        return true;
      }
    }
  }
}
