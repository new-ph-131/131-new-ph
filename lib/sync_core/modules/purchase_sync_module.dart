// FILE: lib/sync_core/modules/purchase_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// Purchase synchronization with supplier-scoped invoice identity.
class PurchaseSyncModule {
  static const String documentType = "PURCHASE";

  /// Supplier invoice identity is supplier/party + supplier invoice number.
  /// internalNo is only a fallback when that pair is unavailable.
  static String getCompositeKey(Purchase p) => makeCompositeKey(p.partyId, p.billNo, p.internalNo);

  static String makeCompositeKey(String partyId, String billNo, [String internalNo = ""]) {
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    if (cleanParty.isNotEmpty && cleanBill.isNotEmpty) return "${cleanParty}_${cleanBill}";
    final cleanInt = internalNo.trim().toUpperCase();
    if (cleanInt.isNotEmpty) return cleanInt;
    return cleanBill.isNotEmpty ? cleanBill : "UNKNOWN_PURCHASE";
  }

  static void onPurchaseSaved(Purchase purchase, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(syncId: purchase.id, storeToken: storeToken,
      docType: documentType, currentVersion: purchase.version, isDelete: false,
      rawPayload: purchase.toMap());
  }

  static void onPurchaseDeleted(Purchase purchase, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    purchase.isDeleted = 1;
    purchase.version += 1;
    purchase.updatedAt = DateTime.now().millisecondsSinceEpoch;
    SyncQueueManager.enqueueMutation(syncId: purchase.id, storeToken: storeToken,
      docType: documentType, currentVersion: purchase.version, isDelete: true,
      rawPayload: purchase.toMap());
  }

  static List<Purchase> handleIncomingSync(List<Purchase> currentUIStateList, SyncEnvelope incomingEvent) {
    mergeIncomingPurchaseEnvelope(currentUIStateList, incomingEvent);
    return currentUIStateList;
  }

  static bool mergeIncomingPurchaseEnvelope(List<Purchase> currentPurchases, SyncEnvelope envelope) {
    if (envelope.documentType != documentType) return false;
    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;
    final incoming = Purchase.fromMap(envelope.billData);
    incoming.id = targetId;
    incoming.version = envelope.version;
    incoming.updatedAt = envelope.updatedAt;
    incoming.isDeleted = envelope.isDeleted;
    return applyPurchaseMutation(currentPurchases, incoming);
  }

  static bool _sameSupplierInvoice(Purchase a, Purchase b) {
    final ap = a.partyId.trim().toUpperCase(), bp = b.partyId.trim().toUpperCase();
    final ab = a.billNo.trim().toUpperCase(), bb = b.billNo.trim().toUpperCase();
    return ap.isNotEmpty && bp.isNotEmpty && ab.isNotEmpty && bb.isNotEmpty && ap == bp && ab == bb;
  }

  static bool applyPurchaseMutation(List<Purchase> currentPurchases, Purchase incoming) {
    final intNo = incoming.internalNo.trim().toUpperCase();
    final hasComposite = incoming.partyId.trim().isNotEmpty && incoming.billNo.trim().isNotEmpty;
    final idx = currentPurchases.indexWhere((p) {
      if (incoming.id.trim().isNotEmpty && p.id.trim() == incoming.id.trim()) return true;
      if (hasComposite && _sameSupplierInvoice(p, incoming)) return true;
      return !hasComposite && intNo.isNotEmpty &&
          p.internalNo.trim().toUpperCase() == intNo &&
          (incoming.partyId.trim().isEmpty || p.partyId.trim().isEmpty ||
           p.partyId.trim().toUpperCase() == incoming.partyId.trim().toUpperCase());
    });

    if (incoming.isDeleted == 1) {
      if (idx == -1) return false;
      final local = currentPurchases[idx];
      if (incoming.updatedAt < local.updatedAt && incoming.version <= local.version && incoming.updatedAt != 0) return false;
      currentPurchases.removeAt(idx);
      debugPrint("🗑️ [PurchaseSyncModule] Deleted purchase: ${incoming.billNo} (${incoming.id})");
      return true;
    }

    if (idx != -1) {
      final local = currentPurchases[idx];
      if (incoming.version < local.version && incoming.updatedAt < local.updatedAt) return false;
      currentPurchases[idx] = incoming;
    } else {
      currentPurchases.insert(0, incoming);
    }
    currentPurchases.removeWhere((p) => !identical(p, incoming) &&
      ((incoming.id.isNotEmpty && p.id == incoming.id) || (hasComposite && _sameSupplierInvoice(p, incoming))));
    return true;
  }
}