// FILE: lib/sync_core/modules/purchase_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// PurchaseSyncModule: Isolated Synchronization & Conflict Resolution Engine for Purchases.
/// Strictly decoupled from Sales, Challans, and Vouchers (Enterprise File Separation Rule).
/// Uses Composite Keys (PartyId + BillNo / InternalNo) to guarantee zero collisions across suppliers.
class PurchaseSyncModule {
  static const String documentType = "PURCHASE";

  /// 🛡️ Generates a deterministic Composite Unique Key for Purchases
  /// Supplier invoices are only unique per supplier, never globally!
  static String getCompositeKey(Purchase p) {
    if (p.internalNo.trim().isNotEmpty) {
      return p.internalNo.trim().toUpperCase();
    }
    final cleanParty = p.partyId.trim().toUpperCase();
    final cleanBill = p.billNo.trim().toUpperCase();
    if (cleanParty.isNotEmpty && cleanBill.isNotEmpty) {
      return "${cleanParty}_$cleanBill";
    }
    return p.id.trim();
  }

  /// 🛡️ Static factory to construct Composite Key from components
  static String makeCompositeKey(String partyId, String billNo, [String internalNo = ""]) {
    final cleanInt = internalNo.trim().toUpperCase();
    if (cleanInt.isNotEmpty) return cleanInt;
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    if (cleanParty.isNotEmpty && cleanBill.isNotEmpty) {
      return "${cleanParty}_$cleanBill";
    }
    return cleanBill.isNotEmpty ? cleanBill : "UNKNOWN_PURCHASE";
  }

  /// Dispatches a purchase creation or modification to the Outbox queue
  static void onPurchaseSaved(Purchase purchase, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(
      syncId: purchase.id,
      storeToken: storeToken,
      docType: documentType,
      currentVersion: purchase.version,
      isDelete: false,
      rawPayload: purchase.toMap(),
    );
  }

  /// Dispatches a soft-delete operation to the Outbox queue
  static void onPurchaseDeleted(Purchase purchase, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    purchase.isDeleted = 1;
    purchase.version += 1;
    purchase.updatedAt = DateTime.now().millisecondsSinceEpoch;
    SyncQueueManager.enqueueMutation(
      syncId: purchase.id,
      storeToken: storeToken,
      docType: documentType,
      currentVersion: purchase.version,
      isDelete: true,
      rawPayload: purchase.toMap(),
    );
  }

  /// handleIncomingSync conforming to Step 3 Frontend State Optimization
  static List<Purchase> handleIncomingSync(List<Purchase> currentUIStateList, SyncEnvelope incomingEvent) {
    mergeIncomingPurchaseEnvelope(currentUIStateList, incomingEvent);
    return currentUIStateList;
  }

  /// Merges an incoming SyncEnvelope into current Purchases list
  static bool mergeIncomingPurchaseEnvelope(List<Purchase> currentPurchases, SyncEnvelope envelope) {
    if (envelope.documentType != documentType) return false;
    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;
    final incomingPurchase = Purchase.fromMap(envelope.billData);
    incomingPurchase.id = targetId;
    incomingPurchase.version = envelope.version;
    incomingPurchase.updatedAt = envelope.updatedAt;
    incomingPurchase.isDeleted = envelope.isDeleted;
    return applyPurchaseMutation(currentPurchases, incomingPurchase);
  }

  /// Core LWW State Machine for Purchase Objects with Composite Key isolation
  static bool applyPurchaseMutation(List<Purchase> currentPurchases, Purchase incoming) {
    final cleanIntNo = incoming.internalNo.trim().toUpperCase();
    final cleanBillNo = incoming.billNo.trim().toUpperCase();
    final cleanPartyId = incoming.partyId.trim().toUpperCase();

    // 1. Search existing index using strict 3-tier identity (never naked billNo alone!)
    int idx = currentPurchases.indexWhere((p) {
      if (incoming.id.isNotEmpty && p.id.trim() == incoming.id.trim()) return true;
      if (cleanIntNo.isNotEmpty && p.internalNo.trim().toUpperCase() == cleanIntNo) return true;
      if (cleanBillNo.isNotEmpty && cleanPartyId.isNotEmpty &&
          p.billNo.trim().toUpperCase() == cleanBillNo &&
          p.partyId.trim().toUpperCase() == cleanPartyId) {
        return true;
      }
      return false;
    });

    // 2. Handle Soft Deletion (is_deleted == 1)
    if (incoming.isDeleted == 1) {
      if (idx != -1) {
        final local = currentPurchases[idx];
        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version || incoming.updatedAt == 0) {
          currentPurchases.removeAt(idx);
          debugPrint("🗑️ [PurchaseSyncModule] Soft-deleted purchase evicted safely: ${incoming.billNo} (${incoming.id})");
          return true;
        }
      }
      return false;
    }

    // 3. Handle Active Mutation (is_deleted == 0)
    if (idx != -1) {
      final local = currentPurchases[idx];
      // If incoming version is less or equal AND updated_at is older, ignore stale data
      if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) {
        return false;
      }
      currentPurchases[idx] = incoming;
      debugPrint("🔄 [PurchaseSyncModule] In-place updated purchase: ${incoming.billNo} (v${incoming.version})");
      return true;
    } else {
      currentPurchases.insert(0, incoming);
      debugPrint("✨ [PurchaseSyncModule] Added new remote purchase: ${incoming.billNo} (${incoming.id})");
      return true;
    }
  }
}
