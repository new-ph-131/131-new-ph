// FILE: lib/sync_core/modules/voucher_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// VoucherSyncModule: Isolated Synchronization & Conflict Resolution Engine for Vouchers/Payments.
/// Strictly decoupled from Sales, Purchases, and Challans (File Separation Rule).
class VoucherSyncModule {
  static const String documentType = "VOUCHER";

  /// Dispatches a voucher creation or modification to the Outbox queue
  static void onVoucherSaved(Voucher voucher, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(
      syncId: voucher.id,
      storeToken: storeToken,
      docType: documentType,
      currentVersion: voucher.version,
      isDelete: false,
      rawPayload: voucher.toMap(),
    );
  }

  /// Dispatches a soft-delete operation to the Outbox queue
  static void onVoucherDeleted(Voucher voucher, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    voucher.isDeleted = 1;
    voucher.status = "Cancelled";
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
    incomingVoucher.isDeleted = envelope.isDeleted;

    return applyVoucherMutation(currentVouchers, incomingVoucher);
  }

  /// Core LWW State Machine for Voucher Objects
  static bool applyVoucherMutation(List<Voucher> currentVouchers, Voucher incoming) {
    final idx = currentVouchers.indexWhere((v) => v.id == incoming.id);

    // 1. Check if delete operation
    if (incoming.isDeleted == 1) {
      if (idx != -1) {
        final local = currentVouchers[idx];
        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
          currentVouchers.removeAt(idx);
          debugPrint("🗑️ [VoucherSyncModule] Soft-deleted voucher evicted: ${incoming.voucherNo} (${incoming.id})");
          return true;
        }
      }
      return false;
    }

    // 2. Existing record check
    if (idx > -1) {
      final local = currentVouchers[idx];
      if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) {
        return false;
      }
      currentVouchers[idx] = incoming;
      debugPrint("🔄 [VoucherSyncModule] In-place updated voucher: ${incoming.voucherNo} (v${incoming.version})");
      return true;
    } else {
      int noIdx = incoming.voucherNo.isNotEmpty
          ? currentVouchers.indexWhere((v) => v.voucherNo.trim() == incoming.voucherNo.trim())
          : -1;

      if (noIdx != -1) {
        final existing = currentVouchers[noIdx];
        if (incoming.updatedAt >= existing.updatedAt) {
          currentVouchers[noIdx] = incoming;
          debugPrint("🔄 [VoucherSyncModule] Replaced voucher by number: ${incoming.voucherNo}");
          return true;
        }
        return false;
      } else {
        currentVouchers.insert(0, incoming);
        debugPrint("✨ [VoucherSyncModule] Added new remote voucher: ${incoming.voucherNo} (${incoming.id})");
        return true;
      }
    }
  }
}
