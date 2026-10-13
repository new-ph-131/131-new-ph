// FILE: lib/sync_core/modules/returns_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// ReturnsSyncModule: Isolated Synchronization & Conflict Resolution Engine for Returns
/// (Sale Return / Credit Note & Purchase Return / Debit Note).
/// Conforms to Enterprise File Separation Architecture.
class ReturnsSyncModule {
  static const String docTypeSaleReturn = "SALE_RETURN";
  static const String docTypePurchaseReturn = "PURCHASE_RETURN";

  // --- SALE RETURN (CREDIT NOTE) ---
  static void onSaleReturnSaved(SaleReturn ret, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(
      syncId: ret.id,
      storeToken: storeToken,
      docType: docTypeSaleReturn,
      currentVersion: ret.version,
      isDelete: false,
      rawPayload: ret.toMap(),
    );
  }

  static void onSaleReturnDeleted(SaleReturn ret, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    ret.isDeleted = 1;
    ret.status = "Cancelled";
    ret.version += 1;
    ret.updatedAt = DateTime.now().millisecondsSinceEpoch;
    SyncQueueManager.enqueueMutation(
      syncId: ret.id,
      storeToken: storeToken,
      docType: docTypeSaleReturn,
      currentVersion: ret.version,
      isDelete: true,
      rawPayload: ret.toMap(),
    );
  }

  static bool mergeIncomingSaleReturn(List<SaleReturn> currentList, SyncEnvelope envelope) {
    if (envelope.documentType != docTypeSaleReturn && envelope.documentType != "CREDIT_NOTE") return false;
    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;
    final incoming = SaleReturn.fromMap(envelope.billData);
    incoming.id = targetId;
    incoming.version = envelope.version;
    incoming.updatedAt = envelope.updatedAt;
    incoming.isDeleted = envelope.isDeleted;

    final idx = currentList.indexWhere((r) => r.id == incoming.id || (incoming.billNo.isNotEmpty && r.billNo.trim().toUpperCase() == incoming.billNo.trim().toUpperCase()));
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

  // --- PURCHASE RETURN (DEBIT NOTE) ---
  static void onPurchaseReturnSaved(PurchaseReturn ret, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(
      syncId: ret.id,
      storeToken: storeToken,
      docType: docTypePurchaseReturn,
      currentVersion: ret.version,
      isDelete: false,
      rawPayload: ret.toMap(),
    );
  }

  static void onPurchaseReturnDeleted(PurchaseReturn ret, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    ret.isDeleted = 1;
    ret.status = "Cancelled";
    ret.version += 1;
    ret.updatedAt = DateTime.now().millisecondsSinceEpoch;
    SyncQueueManager.enqueueMutation(
      syncId: ret.id,
      storeToken: storeToken,
      docType: docTypePurchaseReturn,
      currentVersion: ret.version,
      isDelete: true,
      rawPayload: ret.toMap(),
    );
  }

  static bool mergeIncomingPurchaseReturn(List<PurchaseReturn> currentList, SyncEnvelope envelope) {
    if (envelope.documentType != docTypePurchaseReturn && envelope.documentType != "DEBIT_NOTE") return false;
    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;
    final incoming = PurchaseReturn.fromMap(envelope.billData);
    incoming.id = targetId;
    incoming.version = envelope.version;
    incoming.updatedAt = envelope.updatedAt;
    incoming.isDeleted = envelope.isDeleted;

    final idx = currentList.indexWhere((r) => r.id == incoming.id || (incoming.billNo.isNotEmpty && r.billNo.trim().toUpperCase() == incoming.billNo.trim().toUpperCase()));
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
