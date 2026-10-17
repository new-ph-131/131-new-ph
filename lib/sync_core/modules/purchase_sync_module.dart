// FILE: lib/sync_core/modules/purchase_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// Purchase synchronization with Dual-Series (PUR- & WPUR-) & internalNo-isolated identity (#PH-REV-711).
class PurchaseSyncModule {
  static const String documentType = "PURCHASE";

  /// Every Purchase inward entry is uniquely identified by its series number (internalNo: PUR-* or WPUR-*)
  /// combined with supplier/party + supplier invoice number so separate entries never overwrite each other.
  static String getCompositeKey(Purchase p) =>
      makeCompositeKey(p.partyId, p.billNo, p.internalNo);

  static String makeCompositeKey(String partyId, String billNo, [String internalNo = ""]) {
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final cleanInt = internalNo.trim().toUpperCase();
    if (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty) {
      return "${cleanParty}_${cleanBill}_$cleanInt";
    }
    if (cleanInt.isNotEmpty) return cleanInt;
    if (cleanParty.isNotEmpty && cleanBill.isNotEmpty) {
      return "${cleanParty}_$cleanBill";
    }
    return cleanBill.isNotEmpty ? cleanBill : "UNKNOWN_PURCHASE";
  }

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

  static List<Purchase> handleIncomingSync(List<Purchase> currentUIStateList, SyncEnvelope incomingEvent) {
    mergeIncomingPurchaseEnvelope(currentUIStateList, incomingEvent);
    return currentUIStateList;
  }

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

  static bool _sameSupplierInvoice(Purchase a, Purchase b) {
    final aParty = a.partyId.trim().toUpperCase();
    final bParty = b.partyId.trim().toUpperCase();
    final aBill = a.billNo.trim().toUpperCase();
    final bBill = b.billNo.trim().toUpperCase();
    return aParty.isNotEmpty && bParty.isNotEmpty &&
        aBill.isNotEmpty && bBill.isNotEmpty &&
        aParty == bParty && aBill == bBill;
  }

  static bool applyPurchaseMutation(List<Purchase> currentPurchases, Purchase incoming) {
    final cleanIntNo = incoming.internalNo.trim().toUpperCase();
    final hasSupplierInvoice = incoming.partyId.trim().isNotEmpty && incoming.billNo.trim().isNotEmpty;

    // Match by immutable ID first, then by series internalNo (e.g. PUR-1 vs WPUR-1).
    // Only fallback to supplier+billNo when internalNo is absent.
    int idx = currentPurchases.indexWhere((p) {
      if (incoming.id.trim().isNotEmpty && p.id.trim() == incoming.id.trim()) return true;
      if (cleanIntNo.isNotEmpty && p.internalNo.trim().toUpperCase() == cleanIntNo) return true;
      if (cleanIntNo.isEmpty && p.internalNo.trim().isEmpty && hasSupplierInvoice && _sameSupplierInvoice(p, incoming)) {
        return true;
      }
      return false;
    });

    if (incoming.isDeleted == 1) {
      if (idx == -1) return false;
      final local = currentPurchases[idx];
      if (incoming.updatedAt < local.updatedAt &&
          incoming.version <= local.version && incoming.updatedAt != 0) {
        return false;
      }
      currentPurchases.removeAt(idx);
      debugPrint("🗑️ [PurchaseSyncModule] Deleted purchase: ${incoming.internalNo} / ${incoming.billNo} (${incoming.id})");
      return true;
    }

    if (idx != -1) {
      final local = currentPurchases[idx];
      if (incoming.version < local.version && incoming.updatedAt < local.updatedAt) return false;
      currentPurchases[idx] = incoming;
    } else {
      currentPurchases.insert(0, incoming);
    }

    // Deduplicate only records that share the exact same ID or exact same non-empty internalNo
    currentPurchases.removeWhere((p) =>
        !identical(p, incoming) &&
        ((incoming.id.isNotEmpty && p.id == incoming.id) ||
         (cleanIntNo.isNotEmpty && p.internalNo.trim().toUpperCase() == cleanIntNo)));
    return true;
  }
}
