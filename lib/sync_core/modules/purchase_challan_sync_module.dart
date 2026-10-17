// FILE: lib/sync_core/modules/purchase_challan_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// PurchaseChallanSyncModule: Isolated Synchronization & Conflict Resolution Engine for Purchase Challans (GRN / Inward).
/// Strictly decoupled from Sale Challan, Sales, and Purchases (File Separation Rule).
class PurchaseChallanSyncModule {
  static const String docTypePurchaseChallan = "PURCHASE_CHALLAN";

  /// Generate composite key: partyId_billNo_internalNo to prevent collisions across suppliers
  static String makeCompositeKey(String partyId, String billNo, String internalNo) {
    final p = partyId.trim().toUpperCase();
    final b = billNo.trim().toUpperCase();
    final i = internalNo.trim().toUpperCase();
    if (p.isNotEmpty && b.isNotEmpty && i.isNotEmpty) return "${p}_${b}_$i";
    if (p.isNotEmpty && b.isNotEmpty) return "${p}_$b";
    return i;
  }

  /// Enqueue an Outbox mutation when a Purchase Challan is created or modified
  static void onPurchaseChallanSaved(PurchaseChallan challan, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(
      syncId: challan.id,
      storeToken: storeToken,
      docType: docTypePurchaseChallan,
      currentVersion: challan.version,
      isDelete: false,
      rawPayload: challan.toMap(),
    );
  }

  /// Enqueue a deletion tombstone when a Purchase Challan is deleted
  static void onPurchaseChallanDeleted(PurchaseChallan challan, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    challan.isDeleted = 1;
    challan.status = "Cancelled";
    challan.version += 1;
    challan.updatedAt = DateTime.now().millisecondsSinceEpoch;
    SyncQueueManager.enqueueMutation(
      syncId: challan.id,
      storeToken: storeToken,
      docType: docTypePurchaseChallan,
      currentVersion: challan.version,
      isDelete: true,
      rawPayload: challan.toMap(),
    );
  }

  /// Merge incoming real-time SyncEnvelope into local Purchase Challan list
  static bool mergeIncomingPurchaseChallanEnvelope(List<PurchaseChallan> currentList, SyncEnvelope envelope) {
    if (envelope.documentType != docTypePurchaseChallan) return false;
    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;
    final incoming = PurchaseChallan.fromMap(envelope.billData);
    incoming.id = targetId;
    incoming.version = envelope.version;
    incoming.updatedAt = envelope.updatedAt;
    incoming.isDeleted = envelope.isDeleted;
    return applyPurchaseChallanMutation(currentList, incoming);
  }

  /// Apply mutation with Monotonic Versioning and LWW Clock Auditing
  static bool applyPurchaseChallanMutation(List<PurchaseChallan> currentList, PurchaseChallan incoming) {
    final cleanInt = incoming.internalNo.trim().toUpperCase();
    final cleanBill = incoming.billNo.trim().toUpperCase();
    final cleanParty = incoming.partyId.trim().toUpperCase();

    final idx = currentList.indexWhere((c) {
      if (c.id == incoming.id) return true;
      if (cleanInt.isNotEmpty && c.internalNo.trim().toUpperCase() == cleanInt) return true;
      if (cleanBill.isNotEmpty && cleanParty.isNotEmpty &&
          c.billNo.trim().toUpperCase() == cleanBill && c.partyId.trim().toUpperCase() == cleanParty) {
        return true;
      }
      return false;
    });

    if (incoming.isDeleted == 1) {
      if (idx != -1) {
        final local = currentList[idx];
        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
          currentList.removeAt(idx);
          debugPrint("🗑️ [PurchaseChallanSyncModule] Evicted deleted purchase challan: ${incoming.internalNo}");
          return true;
        }
      }
      return false;
    }

    if (idx != -1) {
      final local = currentList[idx];
      if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) return false;
      currentList[idx] = incoming;
      return true;
    } else {
      currentList.insert(0, incoming);
      return true;
    }
  }
}
