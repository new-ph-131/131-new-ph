// FILE: lib/sync_core/modules/sales_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// SalesSyncModule: Isolated Synchronization & Conflict Resolution Engine for Sales.
/// Strictly decoupled from Purchases, Challans, and Vouchers.
class SalesSyncModule {
  static const String documentType = "SALE";

  /// Dispatches a sale creation or modification to the Outbox queue
  static void onSaleSaved(Sale sale, String storeToken) {
    if (storeToken.trim().isEmpty) return;

    SyncQueueManager.enqueueMutation(
      syncId: sale.id,
      storeToken: storeToken,
      docType: documentType,
      currentVersion: sale.version,
      isDelete: false,
      rawPayload: sale.toMap(),
    );
  }

  /// Dispatches a soft-delete operation to the Outbox queue
  static void onSaleDeleted(Sale sale, String storeToken) {
    if (storeToken.trim().isEmpty) return;

    sale.isDeleted = 1;
    sale.status = "Deleted";
    sale.version += 1;
    sale.updatedAt = DateTime.now().millisecondsSinceEpoch;

    SyncQueueManager.enqueueMutation(
      syncId: sale.id,
      storeToken: storeToken,
      docType: documentType,
      currentVersion: sale.version,
      isDelete: true,
      rawPayload: sale.toMap(),
    );
  }

  /// Merges an incoming SyncEnvelope into the active in-memory Sales List.
  /// Enforces Last-Write-Wins (LWW) and Soft-Delete without destroying the series counter!
  static bool mergeIncomingSaleEnvelope(List<Sale> currentSales, SyncEnvelope envelope) {
    if (envelope.documentType != documentType) return false;

    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;

    final incomingSale = Sale.fromMap(envelope.billData);
    incomingSale.id = targetId;
    incomingSale.version = envelope.version;
    incomingSale.updatedAt = envelope.updatedAt;
    incomingSale.isDeleted = envelope.isDeleted;

    return applySaleMutation(currentSales, incomingSale);
  }

  /// Core LWW State Machine for Sale Objects
  static bool applySaleMutation(List<Sale> currentSales, Sale incoming) {
    final idx = currentSales.indexWhere((s) => s.id == incoming.id);

    // Case 1: Incoming is Soft-Deleted (isDeleted == 1)
    if (incoming.isDeleted == 1) {
      if (idx != -1) {
        final local = currentSales[idx];
        // Only accept delete if incoming is newer or equal
        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
          currentSales.removeAt(idx);
          debugPrint("🗑️ [SalesSyncModule] Soft-deleted sale evicted: ${incoming.billNo} (${incoming.id})");
          return true;
        }
      }
      return false;
    }

    // Case 2: Incoming is Active (isDeleted == 0)
    if (idx != -1) {
      final local = currentSales[idx];
      // LWW Concurrency Evaluation
      if (incoming.updatedAt > local.updatedAt || 
         (incoming.updatedAt == local.updatedAt && incoming.version >= local.version) ||
         local.updatedAt == 0) {
        currentSales[idx] = incoming;
        debugPrint("🔄 [SalesSyncModule] In-place updated sale: ${incoming.billNo} (v${incoming.version})");
        return true;
      }
      return false;
    } else {
      // Record does not exist locally -> Insert it!
      int billNoIdx = incoming.billNo.isNotEmpty 
          ? currentSales.indexWhere((s) => s.billNo.trim() == incoming.billNo.trim()) 
          : -1;
      
      if (billNoIdx != -1) {
        final existingWithBillNo = currentSales[billNoIdx];
        if (incoming.updatedAt >= existingWithBillNo.updatedAt) {
          currentSales[billNoIdx] = incoming;
          debugPrint("🔄 [SalesSyncModule] Replaced sale by billNo: ${incoming.billNo}");
          return true;
        }
      } else {
        currentSales.insert(0, incoming);
        debugPrint("✨ [SalesSyncModule] Added new remote sale: ${incoming.billNo} (${incoming.id})");
        return true;
      }
      return false;
    }
  }
}
