// FILE: lib/sync_core/modules/voucher_sync_module.dart
// Revision: #PH-REV-755 (ENTERPRISE-VOUCHER-2WAY-REALTIME-SYNC)
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../d1_sales_ledger_service.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// VoucherSyncModule: Isolated Synchronization & Conflict Resolution Engine for Vouchers/Payments.
/// Strictly decoupled from Sales, Purchases, and Challans (File Separation Rule).
class VoucherSyncModule {
  static const String documentType = "VOUCHER";

  /// Dispatches a voucher creation, modification, or cancellation to the Outbox queue
  static void onVoucherSaved(Voucher voucher, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    voucher.isDeleted = 0;
    if (voucher.updatedAt <= 0) {
      voucher.updatedAt = DateTime.now().millisecondsSinceEpoch;
    }
    SyncQueueManager.enqueueMutation(
      syncId: voucher.id,
      storeToken: storeToken,
      docType: documentType,
      currentVersion: voucher.version,
      isDelete: false,
      rawPayload: voucher.toMap(),
    );
  }

  /// Dispatches a voucher cancellation (status = Cancelled, isDeleted = 0) to the Outbox queue
  static void onVoucherCancelled(Voucher voucher, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    voucher.isDeleted = 0;
    voucher.status = "Cancelled";
    if (!voucher.narration.startsWith("[CANCELLED]")) {
      voucher.narration = "[CANCELLED] ${voucher.narration}".trim();
    }
    if (voucher.updatedAt <= 0) {
      voucher.updatedAt = DateTime.now().millisecondsSinceEpoch;
    }
    SyncQueueManager.enqueueMutation(
      syncId: voucher.id,
      storeToken: storeToken,
      docType: documentType,
      currentVersion: voucher.version,
      isDelete: false,
      rawPayload: voucher.toMap(),
    );
  }

  /// Dispatches a permanent delete operation to the Outbox queue
  static void onVoucherDeleted(Voucher voucher, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    voucher.isDeleted = 1;
    voucher.status = "Deleted";
    voucher.version += 1;
    voucher.updatedAt = DateTime.now().millisecondsSinceEpoch;

    SyncQueueManager.enqueueMutation(
      syncId: voucher.id,
      storeToken: storeToken,
      docType: documentType,
      currentVersion: voucher.version,
      isDelete: true,
      rawPayload: voucher.toMap(),
    );
  }

  /// handleIncomingSync conforming to Step 3 Frontend State Optimization
  static List<Voucher> handleIncomingSync(List<Voucher> currentUIStateList, SyncEnvelope incomingEvent) {
    mergeIncomingVoucherEnvelope(currentUIStateList, incomingEvent);
    return currentUIStateList;
  }

  /// Merges an incoming SyncEnvelope into current Vouchers list
  static bool mergeIncomingVoucherEnvelope(List<Voucher> currentVouchers, SyncEnvelope envelope) {
    if (envelope.documentType != documentType) return false;

    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;

    final incomingVoucher = Voucher.fromMap(envelope.billData);
    incomingVoucher.id = targetId;
    incomingVoucher.version = envelope.version;
    incomingVoucher.updatedAt = envelope.updatedAt;
    incomingVoucher.isDeleted = (envelope.isDeleted == 1 || envelope.action.toUpperCase() == "DELETE") ? 1 : incomingVoucher.isDeleted;

    return applyVoucherMutation(currentVouchers, incomingVoucher);
  }

  /// Core LWW State Machine for Voucher Objects (Handles Create, Modify, Cancel, and Delete)
  static bool applyVoucherMutation(List<Voucher> currentVouchers, Voucher incoming) {
    final String cleanIncomingId = incoming.id.trim();
    final String cleanIncomingNo = incoming.voucherNo.trim().toUpperCase();

    // 1. Check if delete operation
    if (incoming.isDeleted == 1 || incoming.status == "Deleted") {
      D1SalesLedgerService.markPermanentlyDeleted(cleanIncomingId, cleanIncomingNo);
      final int beforeLen = currentVouchers.length;
      currentVouchers.removeWhere((v) =>
        (cleanIncomingId.isNotEmpty && v.id.trim() == cleanIncomingId) ||
        (cleanIncomingNo.isNotEmpty && v.voucherNo.trim().toUpperCase() == cleanIncomingNo)
      );
      if (currentVouchers.length != beforeLen) {
        debugPrint("🗑️ [VoucherSyncModule] Deleted voucher evicted: ${incoming.voucherNo} (${incoming.id})");
        return true;
      }
      return false;
    }

    // Ignore if permanently tombstoned in D1
    if (D1SalesLedgerService.isBillDeleted(cleanIncomingId, cleanIncomingNo)) {
      return false;
    }

    D1SalesLedgerService.recordKnownVersion(cleanIncomingId, cleanIncomingNo, incoming.version);

    final int idx = currentVouchers.indexWhere((v) =>
      (cleanIncomingId.isNotEmpty && v.id.trim() == cleanIncomingId) ||
      (cleanIncomingNo.isNotEmpty && v.voucherNo.trim().toUpperCase() == cleanIncomingNo)
    );

    // 2. Existing record check (Update or Cancel)
    if (idx > -1) {
      final local = currentVouchers[idx];
      if (incoming.version < local.version && incoming.updatedAt < local.updatedAt) {
        return false;
      }
      if (incoming.version == local.version &&
          incoming.updatedAt < local.updatedAt &&
          incoming.status == local.status) {
        return false;
      }
      currentVouchers[idx] = incoming;
      // Deduplicate any secondary copy with same voucherNo
      for (int j = currentVouchers.length - 1; j >= 0; j--) {
        if (j != idx) {
          final v = currentVouchers[j];
          if ((cleanIncomingId.isNotEmpty && v.id.trim() == cleanIncomingId) ||
              (cleanIncomingNo.isNotEmpty && v.voucherNo.trim().toUpperCase() == cleanIncomingNo)) {
            currentVouchers.removeAt(j);
          }
        }
      }
      debugPrint("🔄 [VoucherSyncModule] In-place updated voucher: ${incoming.voucherNo} (v${incoming.version}, status=${incoming.status})");
      return true;
    } else {
      currentVouchers.insert(0, incoming);
      debugPrint("✨ [VoucherSyncModule] Added new remote voucher: ${incoming.voucherNo} (${incoming.id})");
      return true;
    }
  }
}
