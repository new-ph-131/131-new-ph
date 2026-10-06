// FILE: lib/sync_core/modules/purchase_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// PurchaseSyncModule: Isolated Synchronization & Conflict Resolution Engine for Purchases.
/// Strictly decoupled from Sales, Challans, and Vouchers (File Separation Rule).
class PurchaseSyncModule {
  static const String documentType = "PURCHASE";

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

  /// Core LWW State Machine for Purchase Objects
  static bool applyPurchaseMutation(List<Purchase> currentPurchases, Purchase incoming) {
    final idx = currentPurchases.indexWhere((p) => p.id == incoming.id);

    // 1. Check if delete operation (is_deleted == 1)
    if (incoming.isDeleted == 1) {
      if (idx != -1) {
        final local = currentPurchases[idx];
        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
          currentPurchases.removeAt(idx);
          debugPrint("🗑️ [PurchaseSyncModule] Soft-deleted purchase evicted: ${incoming.billNo} (${incoming.id})");
          return true;
        }
      }
      return false;
    }

    // 2. Existing record check
    if (idx > -1) {
      final local = currentPurchases[idx];
      // If incoming version is less or equal AND updated_at is older, ignore stale data
      if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) {
        return false;
      }
      currentPurchases[idx] = incoming;
      debugPrint("🔄 [PurchaseSyncModule] In-place updated purchase: ${incoming.billNo} (v${incoming.version})");
      return true;
    } else {
      // Secondary check by internalNo or billNo to prevent duplicates
      int numIdx = -1;
      if (incoming.internalNo.isNotEmpty) {
        numIdx = currentPurchases.indexWhere((p) => p.internalNo.trim() == incoming.internalNo.trim());
      }
      if (numIdx == -1 && incoming.billNo.isNotEmpty && incoming.partyId.isNotEmpty) {
        numIdx = currentPurchases.indexWhere((p) => p.billNo.trim() == incoming.billNo.trim() && p.partyId.trim() == incoming.partyId.trim());
      }

      if (numIdx != -1) {
        final existing = currentPurchases[numIdx];
        if (incoming.updatedAt >= existing.updatedAt) {
          currentPurchases[numIdx] = incoming;
          debugPrint("🔄 [PurchaseSyncModule] Replaced purchase by number: ${incoming.billNo}");
          return true;
        }
        return false;
      } else {
        currentPurchases.insert(0, incoming);
        debugPrint("✨ [PurchaseSyncModule] Added new remote purchase: ${incoming.billNo} (${incoming.id})");
        return true;
      }
    }
  }
}
