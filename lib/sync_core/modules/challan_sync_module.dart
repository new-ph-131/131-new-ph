// FILE: lib/sync_core/modules/challan_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// ChallanSyncModule: Isolated Synchronization & Conflict Resolution Engine for Challans.
/// Supports both Sale Challan (Dispatch) and Purchase Challan (GRN).
/// Strictly decoupled from Sales, Purchases, Returns, and Vouchers (File Separation Rule).
class ChallanSyncModule {
  static const String docTypeSaleChallan = "SALE_CHALLAN";
  static const String docTypePurchaseChallan = "PURCHASE_CHALLAN";

  // --- SALE CHALLAN ---
  static void onChallanSaved(SaleChallan challan, String storeToken) {
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

  static void onChallanDeleted(SaleChallan challan, String storeToken) {
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

  static bool mergeIncomingChallanEnvelope(List<SaleChallan> currentChallans, SyncEnvelope envelope) {
    if (envelope.documentType != docTypeSaleChallan && envelope.documentType != "CHALLAN") return false;
    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;
    final incomingChallan = SaleChallan.fromMap(envelope.billData);
    incomingChallan.id = targetId;
    incomingChallan.version = envelope.version;
    incomingChallan.updatedAt = envelope.updatedAt;
    incomingChallan.isDeleted = envelope.isDeleted;
    return applyChallanMutation(currentChallans, incomingChallan);
  }

  static bool applyChallanMutation(List<SaleChallan> currentChallans, SaleChallan incoming) {
    final idx = currentChallans.indexWhere((c) => c.id == incoming.id);
    if (incoming.isDeleted == 1) {
      if (idx != -1) {
        final local = currentChallans[idx];
        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
          currentChallans.removeAt(idx);
          debugPrint("🗑️ [ChallanSyncModule] Evicted deleted sale challan: ${incoming.billNo}");
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

  // --- PURCHASE CHALLAN ---
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

  static bool mergeIncomingPurchaseChallanEnvelope(List<PurchaseChallan> currentList, SyncEnvelope envelope) {
    if (envelope.documentType != docTypePurchaseChallan) return false;
    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;
    final incoming = PurchaseChallan.fromMap(envelope.billData);
    incoming.id = targetId;
    incoming.version = envelope.version;
    incoming.updatedAt = envelope.updatedAt;
    incoming.isDeleted = envelope.isDeleted;

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
        currentList.removeAt(idx);
        return true;
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
