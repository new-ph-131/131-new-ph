// FILE: lib/sync_core/modules/purchase_challan_sync_module.dart
import 'dart:convert';
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
    final b = billNo.trim(); // Exact case preserved for supplier challan ref
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
    final cleanBill = incoming.billNo.trim();
    final cleanParty = incoming.partyId.trim().toUpperCase();

    final idx = currentList.indexWhere((c) {
      if (incoming.id.trim().isNotEmpty && c.id.trim().isNotEmpty) {
        return c.id.trim() == incoming.id.trim();
      }
      // 🛡️ PRIMARY ID RULE: Legacy fallback only if at least one ID is empty:
      if (incoming.id.trim().isEmpty || c.id.trim().isEmpty) {
        if (cleanInt.isNotEmpty && c.internalNo.trim().toUpperCase() == cleanInt &&
            c.effectiveOriginalFy == incoming.effectiveOriginalFy) {
          if (cleanBill.isNotEmpty && cleanParty.isNotEmpty &&
              c.billNo.trim().isNotEmpty && c.partyId.trim().isNotEmpty) {
            return c.billNo.trim() == cleanBill && c.partyId.trim().toUpperCase() == cleanParty;
          }
          return true;
        }
      }
      return false;
    });

    if (incoming.isDeleted == 1) {
      if (idx != -1) {
        final local = currentList[idx];
        if (local.status == "Billed") return false;
        if (incoming.version > local.version || (incoming.version == local.version && incoming.updatedAt >= local.updatedAt)) {
          currentList.removeAt(idx);
          debugPrint("🗑️ [PurchaseChallanSyncModule] Evicted deleted purchase challan: ${incoming.internalNo}");
          return true;
        }
      }
      return false;
    }

    if (idx != -1) {
      final local = currentList[idx];
      // 🛡️ Strict Monotonic Versioning + LWW Clock Auditing (#F-06 Deterministic Equal-Ver/Equal-Ts)
      if (incoming.version < local.version) return false;
      if (incoming.version == local.version) {
        if (incoming.updatedAt < local.updatedAt) return false;
        if (incoming.updatedAt == local.updatedAt) {
          final String localCanon = _canonicalDigest(local);
          final String incomingCanon = _canonicalDigest(incoming);
          if (localCanon == incomingCanon) return false;
          if (incomingCanon.compareTo(localCanon) <= 0) return false;
        }
      }
      currentList[idx] = incoming;
      return true;
    } else {
      currentList.insert(0, incoming);
      return true;
    }
  }

  static String _canonicalDigest(PurchaseChallan c) {
    return jsonEncode({
      'id': c.id.trim(),
      'internalNo': c.internalNo.trim(),
      'billNo': c.billNo.trim(),
      'partyId': c.partyId.trim(),
      'distributorName': c.distributorName.trim(),
      'status': c.status.trim(),
      'totalAmount': c.totalAmount,
      'date': c.date.toIso8601String(),
      'originalFy': c.effectiveOriginalFy,
      'remarks': c.remarks.trim(),
      'isDeleted': c.isDeleted,
      'items': c.items.map((i) => i.toMap()).toList(),
    });
  }
}
