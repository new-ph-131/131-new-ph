// FILE: lib/web_live_sync/sub_views/web_accounts/services/web_voucher_d1_sync_service.dart
// Revision: #PH-REV-755 (ENTERPRISE-VOUCHER-D1-EDGE-SYNC-SERVICE)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../../models.dart';
import '../../../../sync_core/modules/voucher_sync_module.dart';
import '../../../../sync_core/d1_sales_ledger_service.dart';

/// 🌐 WebVoucherD1SyncService
/// Dedicated synchronization service for Vouchers, Payments, Receipts, Contras, and Expenses.
/// Bridges Web and Mobile App through Cloudflare D1 (erp_master_sync + d1_sales_ledger / lab_signal).
/// Strict File Separation Rule: Isolated from Sales, Purchases, and Challans.
class WebVoucherD1SyncService {
  static const String docType = "VOUCHER";

  static Map<String, String> get _headers => {
    "Content-Type": "application/json",
    "Accept": "application/json",
  };

  /// Dispatches a created or modified voucher to Cloudflare D1 Edge Bus + Outbox
  static void onVoucherSaved(
    Voucher voucher,
    String storeToken, {
    String clientSource = "WEB_PORTAL",
  }) {
    if (storeToken.trim().isEmpty) return;

    final vNo = voucher.voucherNo.trim().toUpperCase();
    voucher.isDeleted = 0;
    if (voucher.updatedAt <= 0) {
      voucher.updatedAt = DateTime.now().millisecondsSinceEpoch;
    }

    // 1. Unmark any previous tombstones in D1 so it is not suppressed
    D1SalesLedgerService.unmarkPermanentlyDeleted(voucher.id, vNo);
    if (vNo.isNotEmpty) {
      D1SalesLedgerService.unmarkPermanentlyDeleted(vNo);
    }

    // 2. Record monotonic known version
    final int knownVer = D1SalesLedgerService.getKnownVersion(voucher.id, vNo);
    if (knownVer >= voucher.version) {
      voucher.version = knownVer + 1;
    }
    D1SalesLedgerService.recordKnownVersion(voucher.id, vNo, voucher.version);

    // 3. Enqueue mutation via VoucherSyncModule into outbox buffer
    VoucherSyncModule.onVoucherSaved(voucher, storeToken);

    // 4. Push instant D1 Edge Ledger mutation (<30ms)
    _pushVoucherEdgeEvent(
      voucher: voucher,
      storeToken: storeToken,
      action: voucher.status == "Cancelled" ? "CANCEL" : "UPDATE",
      clientSource: clientSource,
    );
    debugPrint("⚡ [WebVoucherD1Sync] Voucher ${voucher.voucherNo} (${voucher.id}) v${voucher.version} queued & pushed to D1 Edge");
  }

  /// Dispatches a voucher cancellation (status = Cancelled, isDeleted = 0) to Cloudflare D1 Edge Bus + Outbox
  static void onVoucherCancelled(
    Voucher voucher,
    String storeToken, {
    String clientSource = "WEB_PORTAL",
  }) {
    if (storeToken.trim().isEmpty) return;

    final vNo = voucher.voucherNo.trim().toUpperCase();
    voucher.status = "Cancelled";
    voucher.isDeleted = 0;
    if (!voucher.narration.startsWith("[CANCELLED]")) {
      voucher.narration = "[CANCELLED] ${voucher.narration}".trim();
    }
    voucher.updatedAt = DateTime.now().millisecondsSinceEpoch;

    final int knownVer = D1SalesLedgerService.getKnownVersion(voucher.id, vNo);
    if (knownVer >= voucher.version) {
      voucher.version = knownVer + 1;
    }
    D1SalesLedgerService.recordKnownVersion(voucher.id, vNo, voucher.version);

    D1SalesLedgerService.unmarkPermanentlyDeleted(voucher.id, vNo);
    VoucherSyncModule.onVoucherCancelled(voucher, storeToken);

    _pushVoucherEdgeEvent(
      voucher: voucher,
      storeToken: storeToken,
      action: "CANCEL",
      clientSource: clientSource,
    );
    debugPrint("🚫 [WebVoucherD1Sync] Voucher ${voucher.voucherNo} (${voucher.id}) v${voucher.version} marked Cancelled & pushed to D1 Edge");
  }

  /// Dispatches a permanent delete to Cloudflare D1 Edge Bus + Outbox
  static void onVoucherDeleted(
    Voucher voucher,
    String storeToken, {
    String clientSource = "WEB_PORTAL",
  }) {
    if (storeToken.trim().isEmpty) return;

    final vNo = voucher.voucherNo.trim().toUpperCase();
    D1SalesLedgerService.markPermanentlyDeleted(voucher.id, vNo);
    D1SalesLedgerService.recordKnownVersion(voucher.id, vNo, 999999);
    VoucherSyncModule.onVoucherDeleted(voucher, storeToken);

    _pushVoucherDeleteEdgeEvent(
      voucherId: voucher.id,
      voucherNo: vNo,
      storeToken: storeToken,
      clientSource: clientSource,
    );
    debugPrint("🗑️ [WebVoucherD1Sync] Voucher ${voucher.voucherNo} (${voucher.id}) marked deleted and pushed to D1 Edge");
  }

  static Future<bool> _pushVoucherEdgeEvent({
    required Voucher voucher,
    required String storeToken,
    required String action,
    required String clientSource,
  }) async {
    if (!D1SalesLedgerService.USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;
    try {
      final vMap = voucher.toMap();
      vMap["doc_type"] = docType;
      vMap["fy"] = D1SalesLedgerService.activeFinancialYear.isNotEmpty ? D1SalesLedgerService.activeFinancialYear : D1SalesLedgerService.inferFyFromDate(voucher.date);
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": action == "CANCEL" ? "CANCEL_VOUCHER" : "VOUCHER_SAVED",
        "entityId": voucher.id,
        "unmarkedIds": [
          voucher.id,
          if (voucher.voucherNo.trim().isNotEmpty) voucher.voucherNo.trim().toUpperCase(),
        ],
        "sale_event": {
          "id": voucher.id,
          "bill_no": voucher.voucherNo,
          "version": voucher.version,
          "action": action,
          "status": voucher.status,
          "client_source": clientSource,
          "payload": vMap,
        },
      };
      final res = await http.post(
        Uri.parse(D1SalesLedgerService.endpoint),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint("⚠ [WebVoucherD1Sync] Edge push notice: $e");
      return false;
    }
  }

  static Future<bool> _pushVoucherDeleteEdgeEvent({
    required String voucherId,
    required String voucherNo,
    required String storeToken,
    required String clientSource,
  }) async {
    if (!D1SalesLedgerService.USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;
    try {
      final cleanNo = voucherNo.trim().toUpperCase();
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "DELETE_VOUCHER",
        "entityId": voucherId,
        "deletedIds": [
          voucherId,
          if (cleanNo.isNotEmpty) cleanNo,
        ],
        "sale_event": {
          "id": voucherId,
          "bill_no": cleanNo,
          "version": 999999,
          "action": "DELETE",
          "status": "Deleted",
          "client_source": clientSource,
          "payload": {
            "doc_type": docType,
            "id": voucherId,
            "voucherNo": cleanNo,
            "is_deleted": 1,
            "isDeleted": 1,
            "status": "Deleted",
          },
        },
      };
      final res = await http.post(
        Uri.parse(D1SalesLedgerService.endpoint),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint("⚠ [WebVoucherD1Sync] Edge delete notice: $e");
      return false;
    }
  }

  /// Merges incoming D1 Edge Ledger events (from fetchSaleDeltas) into local Vouchers list
  static bool applyEdgeEventsToLocalVouchers(
    List<Voucher> localVouchers,
    List<Map<String, dynamic>> events,
  ) {
    if (events.isEmpty) return false;
    bool mutated = false;

    for (final ev in events) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final String billNo = (ev["bill_no"] ?? "").toString().trim().toUpperCase();
      final String action = (ev["action"] ?? "INSERT").toString().toUpperCase();
      final int version = int.tryParse(ev["version"]?.toString() ?? "1") ?? 1;
      final dynamic rawData = ev["sale_data"];

      final bool isVoucherPayload = rawData is Map &&
          (rawData["doc_type"] == docType ||
           rawData.containsKey("voucherNo") ||
           rawData.containsKey("depositedIn"));

      if (action == "DELETE") {
        // Check if this delete belongs to a voucher or matches an existing voucher in localVouchers
        final String vNo = (rawData is Map ? (rawData["voucherNo"] ?? billNo) : billNo).toString().trim().toUpperCase();
        final bool matchesLocalVoucher = localVouchers.any((v) =>
          (billId.isNotEmpty && v.id.trim() == billId) ||
          (vNo.isNotEmpty && v.voucherNo.trim().toUpperCase() == vNo)
        );
        if (isVoucherPayload || matchesLocalVoucher) {
          D1SalesLedgerService.markPermanentlyDeleted(billId, vNo);
          D1SalesLedgerService.recordKnownVersion(billId, vNo, 999999);
          final int beforeLen = localVouchers.length;
          localVouchers.removeWhere((v) =>
            (billId.isNotEmpty && v.id.trim() == billId) ||
            (vNo.isNotEmpty && v.voucherNo.trim().toUpperCase() == vNo)
          );
          if (localVouchers.length != beforeLen) {
            mutated = true;
          }
        }
      } else if (isVoucherPayload && rawData is Map<String, dynamic>) {
        final incoming = Voucher.fromMap(rawData);
        if (billId.isNotEmpty) incoming.id = billId;
        incoming.version = version;
        if (action == "CANCEL") {
          incoming.status = "Cancelled";
          incoming.isDeleted = 0;
        }
        D1SalesLedgerService.unmarkPermanentlyDeleted(incoming.id, incoming.voucherNo);
        D1SalesLedgerService.recordKnownVersion(incoming.id, incoming.voucherNo, incoming.version);
        if (VoucherSyncModule.applyVoucherMutation(localVouchers, incoming)) {
          mutated = true;
        }
      }
    }

    return mutated;
  }

  /// Merges incoming D1 batch operations (from erp_master_sync) for Vouchers into local state list
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

      if (VoucherSyncModule.applyVoucherMutation(localVouchers, incoming)) {
        hasChanges = true;
      }
    }

    return hasChanges;
  }
}
