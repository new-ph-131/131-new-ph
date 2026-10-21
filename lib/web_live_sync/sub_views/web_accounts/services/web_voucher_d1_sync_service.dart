// FILE: lib/web_live_sync/sub_views/web_accounts/services/web_voucher_d1_sync_service.dart
// Revision: #PH-REV-743 (ENTERPRISE-VOUCHER-D1-EDGE-SYNC-SERVICE)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../models.dart';
import '../../../../sync_core/modules/voucher_sync_module.dart';
import '../../../../sync_core/outbox/sync_queue_manager.dart';
import '../../../../sync_core/d1_sales_ledger_service.dart';

/// 🌐 WebVoucherD1SyncService
/// Dedicated synchronization service for Vouchers, Payments, Receipts, and Contras.
/// Bridges Web and Mobile App through Cloudflare D1 (erp_master_sync / lab_signal).
/// Strict File Separation Rule: Isolated from Sales, Purchases, and Challans.
class WebVoucherD1SyncService {
  static const String docType = "VOUCHER";

  /// Dispatches a created or updated voucher to Cloudflare D1 Edge Bus
  static void onVoucherSaved(Voucher voucher, String storeToken) {
    if (storeToken.trim().isEmpty) return;

    // 1. Unmark any previous tombstones in D1 so it is not suppressed
    final vNo = voucher.voucherNo.trim().toUpperCase();
    D1SalesLedgerService.unmarkPermanentlyDeleted(voucher.id);
    if (vNo.isNotEmpty) {
      D1SalesLedgerService.unmarkPermanentlyDeleted(vNo);
    }

    // 2. Enqueue mutation via VoucherSyncModule into outbox buffer
    VoucherSyncModule.onVoucherSaved(voucher, storeToken);
    debugPrint("⚡ [WebVoucherD1Sync] Voucher ${voucher.voucherNo} (${voucher.id}) queued for D1 Edge Sync");
  }

  /// Dispatches a soft delete to Cloudflare D1 Edge Bus
  static void onVoucherDeleted(Voucher voucher, String storeToken) {
    if (storeToken.trim().isEmpty) return;

    final vNo = voucher.voucherNo.trim().toUpperCase();
    D1SalesLedgerService.markPermanentlyDeleted(voucher.id, vNo);
    VoucherSyncModule.onVoucherDeleted(voucher, storeToken);
    debugPrint("🗑️ [WebVoucherD1Sync] Voucher ${voucher.voucherNo} marked deleted and queued for D1");
  }

  /// Merges incoming D1 batch operations for Vouchers into local state list
  static bool applyIncomingD1Vouchers(List<Voucher> localVouchers, List<dynamic> batchOperations) {
    bool hasChanges = false;

    for (var op in batchOperations) {
      if (op is! Map) continue;
      final type = (op["document_type"] ?? op["type"] ?? "").toString().toUpperCase();
      if (type != docType) continue;

      final syncId = (op["sync_id"] ?? op["id"] ?? "").toString().trim();
      if (syncId.isEmpty) continue;

      final int version = int.tryParse(op["version"]?.toString() ?? "1") ?? 1;
      final int updatedAt = int.tryParse(op["updated_at"]?.toString() ?? "0") ?? 0;
      final int isDeleted = int.tryParse(op["is_deleted"]?.toString() ?? "0") ?? 0;

      // Extract voucher data
      dynamic rawData = op["data"] ?? op["bill_data"];
      Map<String, dynamic> vMap;
      if (rawData is Map) {
        vMap = Map<String, dynamic>.from(rawData);
      } else if (rawData is String && rawData.isNotEmpty) {
        try {
          vMap = jsonDecode(rawData);
        } catch (_) {
          continue;
        }
      } else {
        continue;
      }

      final incoming = Voucher.fromMap(vMap);
      incoming.id = syncId;
      incoming.version = version;
      incoming.updatedAt = updatedAt;
      incoming.isDeleted = isDeleted;

      // Apply with LWW state machine
      if (VoucherSyncModule.applyVoucherMutation(localVouchers, incoming)) {
        hasChanges = true;
      }
    }

    return hasChanges;
  }
}
