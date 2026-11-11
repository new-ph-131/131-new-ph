// FILE: lib/sync_core/d1_sales_ledger_service.dart
// 🛡️ D1 EDGE SALES LEDGER & OPTIMISTIC CONCURRENCY SERVICE (#PH-REV-680)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../web_live_sync/web_cloud_config.dart';

class D1SalesLedgerService {
  /// 🎚️ MASTER SAFETY SWITCH: Toggle true for D1 Edge sync, false to safely fallback
  static const bool USE_D1_EDGE_LEDGER = true;
  static String activeFinancialYear = "";

  static String inferFyFromDate(DateTime dt) {
    if (dt.month >= 4) {
      return "${dt.year}-${(dt.year + 1).toString().substring(2)}";
    } else {
      return "${dt.year - 1}-${dt.year.toString().substring(2)}";
    }
  }

  /// Strict Financial Year Isolation Guard:
  /// Ensures D1 events from 2026-27 never pollute a fresh 2027-28 year or a 2025-26 back-year.
  static bool doesEventBelongToActiveFY(dynamic rawPayload, DateTime? recordDate, [String? targetFy]) {
    final String fy = (targetFy != null && targetFy.trim().isNotEmpty)
        ? targetFy.trim()
        : activeFinancialYear.trim();
    if (fy.isEmpty) return true;
    if (rawPayload is Map) {
      final String payloadFy = (rawPayload["fy"] ?? "").toString().trim();
      if (payloadFy.isNotEmpty) {
        return payloadFy == fy;
      }
    }
    if (recordDate != null) {
      return inferFyFromDate(recordDate) == fy;
    }
    return true;
  }

  /// Extracts the Financial Year from an incoming raw edge event payload or record date
  static String extractEventFy(dynamic rawPayload, DateTime? recordDate) {
    if (rawPayload is Map) {
      final String payloadFy = (rawPayload["fy"] ?? "").toString().trim();
      if (payloadFy.isNotEmpty) return payloadFy;
    }
    if (recordDate != null) {
      return inferFyFromDate(recordDate);
    }
    return "";
  }

  /// 🛡️ PERMANENT GRAVESTONES: Once marked deleted in D1, Google Drive can NEVER resurrect
  static final Set<String> _permanentDeletedKeys = {};

  /// 🛡️ MASTER KNOWN VERSIONS: Google Drive can NEVER downgrade a known higher version
  static final Map<String, int> _knownBillVersions = {};

  /// Checks if a key is a human-readable bill/series number or composite key (which repeats across FYs)
  static bool isUnscopedSeriesKey(String key) {
    final k = key.trim().toUpperCase();
    if (k.isEmpty || k.contains("::")) return false;
    if (k.startsWith("COMP_") || k.startsWith("SALT_") || k.startsWith("ROUTE_") || k.startsWith("SESS_") || k.startsWith("PARTY-")) {
      // Note: PARTY-123_BILLNO contains '_' so check if it has '_'
      if (!k.contains("_")) return false;
    }
    if (RegExp(r'^\d{10,}$').hasMatch(k) || RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(k)) return false;
    // 🛡️ All human numeric sequence numbers (1, 2, 001, 10, etc.) are series keys that reset across FYs! (#PH-REV-806)
    if (RegExp(r'^\d{1,9}$').hasMatch(k)) return true;
    return k.startsWith("INV-") || k.startsWith("WSALE-") || k.startsWith("PUR-") || k.startsWith("WPUR-") ||
           k.startsWith("SCH-") || k.startsWith("WSCH-") || k.startsWith("PCH-") || k.startsWith("WPCH-") ||
           k.startsWith("TXN-") || k.startsWith("WCN-") || k.startsWith("WDN-") || k.startsWith("SR-") ||
           k.startsWith("CN-") || k.startsWith("PR-") || k.startsWith("DN-") || k.startsWith("RCT-") ||
           k.startsWith("WRCT-") || k.startsWith("PAY-") || k.startsWith("WPAY-") || k.startsWith("CNT-") ||
           k.startsWith("EXP-") || k.startsWith("BILL-") || k.startsWith("VOU-") || k.contains("_");
  }

  /// Scopes a secondary/series key (e.g. INV-1, PUR-1, PARTY_BILL) to the target Financial Year
  /// so bill numbers that reset to #1 in a new FY never collide with or delete old FY bills.
  static String scopeSecondaryKey(String secKey, [String? fy]) {
    final clean = secKey.trim().toUpperCase();
    if (clean.isEmpty) return "";
    if (clean.contains("::")) return clean;
    final effFy = (fy != null && fy.trim().isNotEmpty) ? fy.trim() : activeFinancialYear.trim();
    if (effFy.isEmpty) return clean;
    return "$effFy::$clean";
  }

  static bool isBillDeleted(String id, [String secondaryKey = "", String tertiaryKey = "", String? fy]) {
    final cleanId = id.trim();
    final String idKey = isUnscopedSeriesKey(cleanId) ? scopeSecondaryKey(cleanId, fy) : cleanId;
    final String cleanSec = scopeSecondaryKey(secondaryKey, fy);
    final String cleanTer = scopeSecondaryKey(tertiaryKey, fy);
    return (idKey.isNotEmpty && (_permanentDeletedKeys.contains(idKey) || _permanentDeletedKeys.contains(idKey.toUpperCase()))) ||
           (cleanSec.isNotEmpty && _permanentDeletedKeys.contains(cleanSec)) ||
           (cleanTer.isNotEmpty && _permanentDeletedKeys.contains(cleanTer));
  }

  static int getKnownVersion(String id, [String secondaryKey = "", String tertiaryKey = "", String? fy]) {
    final cleanId = id.trim();
    final String idKey = isUnscopedSeriesKey(cleanId) ? scopeSecondaryKey(cleanId, fy) : cleanId;
    final String cleanSec = scopeSecondaryKey(secondaryKey, fy);
    final String cleanTer = scopeSecondaryKey(tertiaryKey, fy);
    int maxV = idKey.isNotEmpty ? (_knownBillVersions[idKey] ?? 0) : 0;
    if (cleanSec.isNotEmpty && (_knownBillVersions[cleanSec] ?? 0) > maxV) {
      maxV = _knownBillVersions[cleanSec]!;
    }
    if (cleanTer.isNotEmpty && (_knownBillVersions[cleanTer] ?? 0) > maxV) {
      maxV = _knownBillVersions[cleanTer]!;
    }
    return maxV;
  }

  static void recordKnownVersion(String id, [String secondaryKey = "", int version = 1, String? fy]) {
    final cleanId = id.trim();
    final String idKey = isUnscopedSeriesKey(cleanId) ? scopeSecondaryKey(cleanId, fy) : cleanId;
    final String cleanSec = scopeSecondaryKey(secondaryKey, fy);
    if (idKey.isNotEmpty && version > (_knownBillVersions[idKey] ?? 0)) {
      _knownBillVersions[idKey] = version;
    }
    if (cleanSec.isNotEmpty && version > (_knownBillVersions[cleanSec] ?? 0)) {
      _knownBillVersions[cleanSec] = version;
    }
  }

  static void markPermanentlyDeleted(String id, [String secondaryKey = "", String tertiaryKey = "", String? fy]) {
    final cleanId = id.trim();
    final String idKey = isUnscopedSeriesKey(cleanId) ? scopeSecondaryKey(cleanId, fy) : cleanId;
    final String cleanSec = scopeSecondaryKey(secondaryKey, fy);
    final String cleanTer = scopeSecondaryKey(tertiaryKey, fy);
    if (idKey.isNotEmpty) _permanentDeletedKeys.add(idKey);
    if (cleanSec.isNotEmpty) _permanentDeletedKeys.add(cleanSec);
    if (cleanTer.isNotEmpty) _permanentDeletedKeys.add(cleanTer);
    try {
      SharedPreferences.getInstance().then((prefs) {
        final existing = prefs.getStringList("d1_permanent_gravestones") ?? [];
        final set = existing.where((k) => !isUnscopedSeriesKey(k)).toSet();
        if (idKey.isNotEmpty) set.add(idKey);
        if (cleanSec.isNotEmpty) set.add(cleanSec);
        if (cleanTer.isNotEmpty) set.add(cleanTer);
        prefs.setStringList("d1_permanent_gravestones", set.toList());
      });
    } catch (_) {}
  }

  static void unmarkPermanentlyDeleted(String id, [String secondaryKey = "", String tertiaryKey = "", String? fy]) {
    final cleanId = id.trim();
    final cleanSecRaw = secondaryKey.trim().toUpperCase();
    final cleanTerRaw = tertiaryKey.trim().toUpperCase();
    final scopedId = scopeSecondaryKey(cleanId, fy);
    final scopedSec = scopeSecondaryKey(cleanSecRaw, fy);
    final scopedTer = scopeSecondaryKey(cleanTerRaw, fy);

    void removeEverywhere(String k) {
      if (k.isEmpty) return;
      _permanentDeletedKeys.remove(k);
      _permanentDeletedKeys.remove(k.toUpperCase());
      _knownBillVersions.remove(k);
      _knownBillVersions.remove(k.toUpperCase());
    }

    removeEverywhere(cleanId);
    removeEverywhere(scopedId);
    removeEverywhere(cleanSecRaw);
    removeEverywhere(scopedSec);
    removeEverywhere(cleanTerRaw);
    removeEverywhere(scopedTer);

    try {
      SharedPreferences.getInstance().then((prefs) {
        final existing = prefs.getStringList("d1_permanent_gravestones") ?? [];
        final set = existing.where((k) => !isUnscopedSeriesKey(k)).toSet();
        for (final k in [cleanId, cleanId.toUpperCase(), scopedId, cleanSecRaw, scopedSec, cleanTerRaw, scopedTer]) {
          if (k.isNotEmpty) set.remove(k);
        }
        prefs.setStringList("d1_permanent_gravestones", set.toList());
      });
    } catch (_) {}
  }

  // =========================================================================
  // 🛡️ PURCHASE COMPOSITE CONCURRENCY & GRAVESTONES (PARTY_ID + BILL_NO + INTERNAL_NO)
  // =========================================================================
  static bool isPurchaseDeleted(String id, String partyId, String billNo, [String internalNo = "", String? fy]) {
    final cleanId = id.trim();
    if (cleanId.isNotEmpty && !isUnscopedSeriesKey(cleanId)) {
      return _permanentDeletedKeys.contains(cleanId) ||
             _permanentDeletedKeys.contains(cleanId.toUpperCase());
    }
    final cleanInt = scopeSecondaryKey(internalNo, fy);
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_$cleanBill", fy)
        : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && internalNo.trim().isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_${cleanBill}_${internalNo.trim().toUpperCase()}", fy)
        : "";
    return (cleanInt.isNotEmpty && _permanentDeletedKeys.contains(cleanInt)) ||
           (compKey2.isNotEmpty && _permanentDeletedKeys.contains(compKey2)) ||
           (compKey3.isNotEmpty && _permanentDeletedKeys.contains(compKey3));
  }

  static int getPurchaseKnownVersion(String id, String partyId, String billNo, [String internalNo = "", String? fy]) {
    final cleanId = id.trim();
    if (cleanId.isNotEmpty && !isUnscopedSeriesKey(cleanId)) {
      return _knownBillVersions[cleanId] ?? 0;
    }
    final cleanInt = scopeSecondaryKey(internalNo, fy);
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_$cleanBill", fy)
        : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && internalNo.trim().isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_${cleanBill}_${internalNo.trim().toUpperCase()}", fy)
        : "";
    int maxV = 0;
    if (cleanInt.isNotEmpty && (_knownBillVersions[cleanInt] ?? 0) > maxV) {
      maxV = _knownBillVersions[cleanInt]!;
    }
    if (compKey2.isNotEmpty && (_knownBillVersions[compKey2] ?? 0) > maxV) {
      maxV = _knownBillVersions[compKey2]!;
    }
    if (compKey3.isNotEmpty && (_knownBillVersions[compKey3] ?? 0) > maxV) {
      maxV = _knownBillVersions[compKey3]!;
    }
    return maxV;
  }

  static void recordPurchaseKnownVersion(String id, String partyId, String billNo, int version, [String internalNo = "", String? fy]) {
    final cleanId = id.trim();
    final cleanInt = scopeSecondaryKey(internalNo, fy);
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_$cleanBill", fy)
        : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && internalNo.trim().isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_${cleanBill}_${internalNo.trim().toUpperCase()}", fy)
        : "";
    if (cleanId.isNotEmpty) {
      _knownBillVersions[cleanId] = version;
    }
    if (cleanInt.isNotEmpty) {
      _knownBillVersions[cleanInt] = version;
    }
    if (compKey2.isNotEmpty) {
      _knownBillVersions[compKey2] = version;
    }
    if (compKey3.isNotEmpty) {
      _knownBillVersions[compKey3] = version;
    }
  }

  /// Called when a Purchase is created or modified from either App or Web
  static Future<bool> onPurchaseSaved(
    Purchase purchase,
    String storeToken, {
    bool isUpdate = false,
    String clientSource = "APP_MOBILE",
  }) async {
    unmarkPurchasePermanentlyDeleted(
      purchase.id,
      purchase.partyId,
      purchase.billNo,
      purchase.internalNo,
    );
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;

    try {
      final purMap = purchase.toMap();
      purMap["doc_type"] = "PURCHASE";
      purMap["fy"] = activeFinancialYear.isNotEmpty ? activeFinancialYear : inferFyFromDate(purchase.date);
      final String cleanParty = purchase.partyId.trim().toUpperCase();
      final String cleanBill = purchase.billNo.trim().toUpperCase();
      final String cleanInt = purchase.internalNo.trim().toUpperCase();
      final String compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
      final String compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
          ? "${cleanParty}_${cleanBill}_$cleanInt"
          : "";
      final String refNo = cleanInt.isNotEmpty ? cleanInt : cleanBill;

      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": isUpdate ? "UPDATE_PURCHASE" : "INSERT_PURCHASE",
        "entityId": purchase.id,
        "unmarkedIds": [
          purchase.id,
          if (cleanInt.isNotEmpty) cleanInt,
          if (cleanBill.isNotEmpty) cleanBill,
          if (compKey2.isNotEmpty) compKey2,
          if (compKey3.isNotEmpty) compKey3,
        ],
        "sale_event": {
          "id": purchase.id,
          "bill_no": refNo,
          "version": purchase.version,
          "action": isUpdate ? "UPDATE" : "INSERT",
          "status": "Active",
          "client_source": clientSource,
          "payload": purMap,
        },
      };

      final res = await http.post(
        Uri.parse(endpoint),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["status"] == "SUCCESS") {
          recordPurchaseKnownVersion(
            purchase.id,
            purchase.partyId,
            purchase.billNo,
            purchase.version,
            purchase.internalNo,
          );
          final int? newSeq = data["seq"];
          if (newSeq != null && newSeq > 0) {
            await _updateHighestLocalSeq(storeToken, newSeq);
          }
          return true;
        }
      } else if (res.statusCode == 409) {
        try {
          final data = jsonDecode(res.body);
          final int serverVer = int.tryParse(data["current_version"]?.toString() ?? "0") ?? 0;
          if (serverVer > 0) {
            recordPurchaseKnownVersion(
              purchase.id,
              purchase.partyId,
              purchase.billNo,
              serverVer,
              purchase.internalNo,
            );
            purchase.version = serverVer + 1;
            return await onPurchaseSaved(purchase, storeToken, isUpdate: true, clientSource: clientSource);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] onPurchaseSaved Network Error: $e");
    }
    return false;
  }

  /// Called when a Purchase is permanently deleted from either App or Web
  static Future<bool> onPurchaseDeleted(
    String purchaseId,
    String partyId,
    String billNo,
    String internalNo,
    String storeToken, {
    String clientSource = "APP_MOBILE",
    List<String> linkedChallanIds = const [],
  }) async {
    markPurchasePermanentlyDeleted(purchaseId, partyId, billNo, internalNo);
    if (linkedChallanIds.isNotEmpty) {
      for (var cid in linkedChallanIds) {
        if (cid.trim().isNotEmpty) unmarkPermanentlyDeleted(cid.trim());
      }
    }
    if (storeToken.trim().isEmpty) return false;
    try {
      final cleanParty = partyId.trim().toUpperCase();
      final cleanBill = billNo.trim().toUpperCase();
      final cleanInt = internalNo.trim().toUpperCase();
      final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
      final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
          ? "${cleanParty}_${cleanBill}_$cleanInt"
          : "";
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "DELETE_PURCHASE",
        "entityId": purchaseId,
        "deletedIds": [
          purchaseId,
          if (cleanInt.isNotEmpty) cleanInt,
          if (compKey2.isNotEmpty) compKey2,
          if (compKey3.isNotEmpty) compKey3,
        ],
        "sale_event": {
          "id": purchaseId,
          "bill_no": cleanInt.isNotEmpty ? cleanInt : cleanBill,
          "version": 999999,
          "action": "DELETE",
          "status": "Deleted",
          "client_source": clientSource,
          "payload": {
            "doc_type": "PURCHASE",
            "id": purchaseId,
            "partyId": partyId,
            "billNo": billNo,
            "internalNo": internalNo,
            "is_deleted": 1,
            "fy": activeFinancialYear,
            "linkedChallanIds": linkedChallanIds,
          },
        },
      };
      final res = await http.post(
        Uri.parse(endpoint),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        try {
          final data = jsonDecode(res.body);
          if (data["seq"] != null) {
            await _updateHighestLocalSeq(storeToken, data["seq"]);
          }
        } catch (_) {}
        return true;
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] onPurchaseDeleted Network Error: $e");
    }
    return false;
  }

  static void markPurchasePermanentlyDeleted(String id, String partyId, String billNo, [String internalNo = "", String? fy]) {
    final cleanId = id.trim();
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
        ? "${cleanParty}_${cleanBill}_$cleanInt"
        : "";
    markPermanentlyDeleted(cleanId, cleanInt, compKey2, fy);
    if (cleanId.isNotEmpty) markPermanentlyDeleted(cleanId.toUpperCase(), "", "", fy);
    if (compKey3.isNotEmpty) markPermanentlyDeleted(compKey3, "", "", fy);
  }

  static void unmarkPurchasePermanentlyDeleted(String id, String partyId, String billNo, [String internalNo = "", String? fy]) {
    final cleanId = id.trim();
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
        ? "${cleanParty}_${cleanBill}_$cleanInt"
        : "";
    unmarkPermanentlyDeleted(cleanId, cleanInt, compKey2, fy);
    if (cleanId.isNotEmpty) unmarkPermanentlyDeleted(cleanId.toUpperCase(), "", "", fy);
    if (compKey3.isNotEmpty) unmarkPermanentlyDeleted(compKey3, "", "", fy);
    if (cleanBill.isNotEmpty) unmarkPermanentlyDeleted(cleanBill, "", "", fy);
  }

  static Future<void> loadPersistedGravestones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList("d1_permanent_gravestones") ?? [];
      final sanitized = list.where((k) => !isUnscopedSeriesKey(k)).toList();
      _permanentDeletedKeys
        ..clear()
        ..addAll(sanitized);
      if (sanitized.length != list.length) {
        await prefs.setStringList("d1_permanent_gravestones", sanitized);
      }
    } catch (_) {}
  }

  static String get endpoint {
    return "${WebCloudConfig.webPortalUrl}/api/lab_signal";
  }

  static const Map<String, String> _headers = {
    "Content-Type": "application/json",
    "Accept": "application/json",
  };

  /// =========================================================================
  /// 1. EVENT DISPATCHERS (ADD / MODIFY / CANCEL / DELETE)
  /// =========================================================================

  /// Called when a Sale is created or modified
  static Future<bool> onSaleSaved(
    Sale sale, 
    String storeToken, {
    bool isUpdate = false, 
    String clientSource = "APP_MOBILE",
  }) async {
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;

    try {
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": isUpdate ? "UPDATE_SALE" : "INSERT_SALE",
        "sale_event": {
          "id": sale.id,
          "bill_no": sale.billNo,
          "version": sale.version,
          "action": isUpdate ? "UPDATE" : "INSERT",
          "status": sale.status,
          "client_source": clientSource,
          "payload": {
            ...sale.toMap(),
            "fy": activeFinancialYear.isNotEmpty ? activeFinancialYear : inferFyFromDate(sale.date),
          },
        },
      };

      final res = await http.post(
        Uri.parse(endpoint),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["status"] == "SUCCESS") {
          recordKnownVersion(sale.id, sale.billNo, sale.version);
          final int? newSeq = data["seq"];
          if (newSeq != null && newSeq > 0) {
            await _updateHighestLocalSeq(storeToken, newSeq);
          }
          return true;
        }
      } else if (res.statusCode == 409) {
        debugPrint("⚠ [D1SalesLedger] OCC Conflict: Bill modified elsewhere. Initiating Enterprise Auto-Rebase...");
        try {
          final data = jsonDecode(res.body);
          final int serverVer = int.tryParse(data["current_version"]?.toString() ?? "0") ?? 0;
          if (serverVer > 0) {
            recordKnownVersion(sale.id, sale.billNo, serverVer);
            sale.version = serverVer + 1;
            debugPrint("🔄 [D1SalesLedger] Auto-Rebasing sale ${sale.billNo} to version ${sale.version} and retrying...");
            return await onSaleSaved(sale, storeToken, isUpdate: true, clientSource: clientSource);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] onSaleSaved Network Error: $e");
    }
    return false;
  }

  /// Called when a Sale is CANCELLED (GST Compliant: Bill No NOT reused)
  static Future<bool> onSaleCancelled(
    Sale sale, 
    String storeToken, {
    String clientSource = "APP_MOBILE",
  }) async {
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;

    try {
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "CANCEL_SALE",
        "sale_event": {
          "id": sale.id,
          "bill_no": sale.billNo,
          "version": sale.version + 1,
          "action": "CANCEL",
          "status": "Cancelled",
          "client_source": clientSource,
          "payload": {
            ...sale.toMap(),
            "fy": activeFinancialYear.isNotEmpty ? activeFinancialYear : inferFyFromDate(sale.date),
          },
        },
      };

      final res = await http.post(
        Uri.parse(endpoint),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["status"] == "SUCCESS" && data["seq"] != null) {
          final int s = data["seq"];
          await _updateHighestLocalSeq(storeToken, s);
          return true;
        }
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] onSaleCancelled Network Error: $e");
    }
    return false;
  }

  /// Called when a Sale is DELETED (Gap-Filling: Bill No freed up & reused)
  static Future<bool> onSaleDeleted(
    String saleId, 
    String billNo, 
    String storeToken, {
    String clientSource = "APP_MOBILE",
    List<String> linkedChallanIds = const [],
  }) async {
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;

    try {
      markPermanentlyDeleted(saleId, billNo);
      if (linkedChallanIds.isNotEmpty) {
        for (var cid in linkedChallanIds) {
          if (cid.trim().isNotEmpty) unmarkPermanentlyDeleted(cid.trim());
        }
      }
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "DELETE_SALE",
        "sale_event": {
          "id": saleId,
          "bill_no": billNo,
          "version": 99999,
          "action": "DELETE",
          "status": "Deleted",
          "client_source": clientSource,
          "payload": {
            "id": saleId,
            "billNo": billNo,
            "is_deleted": 1,
            "status": "Deleted",
            "fy": activeFinancialYear,
            "linkedChallanIds": linkedChallanIds,
          },
        },
      };

      final res = await http.post(
        Uri.parse(endpoint),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["status"] == "SUCCESS" && data["seq"] != null) {
          final int s = data["seq"];
          await _updateHighestLocalSeq(storeToken, s);
          return true;
        }
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] onSaleDeleted Network Error: $e");
    }
    return false;
  }

  /// =========================================================================
  /// 2. DELTA SYNC PULL & LOCAL MERGE
  /// =========================================================================

  /// Pulls all sequential mutations committed after sinceSeq
  static Future<List<Map<String, dynamic>>> fetchSaleDeltas(
    String storeToken, {
    int? customSinceSeq,
  }) async {
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return [];

    try {
      final sinceSeq = customSinceSeq ?? await getLatestLocalSeq(storeToken);
      final uri = Uri.parse("$endpoint?storeToken=${Uri.encodeComponent(storeToken.trim().toUpperCase())}&since_seq=$sinceSeq");

      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["status"] == "SUCCESS" && data["events"] is List) {
          final List<Map<String, dynamic>> events = 
              List<Map<String, dynamic>>.from(data["events"]);
          
          if (events.isNotEmpty && data["max_seq"] != null) {
            final int mSeq = data["max_seq"];
            await _updateHighestLocalSeq(storeToken, mSeq);
          }
          return events;
        }
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] fetchSaleDeltas Error: $e");
    }
    return [];
  }

  /// Merges incoming edge events into local Sales memory list
  static bool applyEventsToLocalSales(
    List<Sale> localSales, 
    List<Map<String, dynamic>> events, [
    String? targetFyOverride,
  ]) {
    final String effFy = (targetFyOverride != null && targetFyOverride.trim().isNotEmpty)
        ? targetFyOverride.trim()
        : activeFinancialYear;
    bool mutated = false;
    // Purge any non-sale / ghost records (e.g. SESS_ or APP_CONFIG_MASTER or 0-amount empty billNo rows)
    final int beforeClean = localSales.length;
    localSales.removeWhere((s) =>
        s.id.startsWith("SESS_") ||
        s.id == "APP_CONFIG_MASTER" ||
        (s.billNo.trim().isEmpty && s.partyName.trim().isEmpty && s.items.isEmpty) ||
        (s.billNo.trim().isEmpty && s.items.isEmpty && s.totalAmount <= 0));
    if (localSales.length != beforeClean) {
      mutated = true;
    }

    if (events.isEmpty) return mutated;

    for (final ev in events) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final String billNo = (ev["bill_no"] ?? "").toString().trim();
      final String action = (ev["action"] ?? "INSERT").toString().toUpperCase();
      final int version = int.tryParse(ev["version"]?.toString() ?? "1") ?? 1;
      final dynamic rawSale = ev["sale_data"];

      if (billId.startsWith("SESS_") ||
          billId == "APP_CONFIG_MASTER" ||
          billNo == "APP_CONFIG") {
        continue;
      }

      // Skip Purchase, Voucher, GST Diary Session, and AppConfig events so they NEVER pollute Sales
      if (rawSale is Map &&
          (rawSale["doc_type"] == "PURCHASE" ||
           rawSale["doc_type"] == "VOUCHER" ||
           rawSale["doc_type"] == "GST_DIARY_SESSION" ||
           rawSale["doc_type"] == "GST_SESSION" ||
           rawSale["doc_type"] == "APP_CONFIG" ||
           rawSale["doc_type"] == "CONFIG" ||
           rawSale.containsKey("distributorName") ||
           rawSale.containsKey("internalNo") ||
           rawSale.containsKey("voucherNo") ||
           rawSale.containsKey("depositedIn") ||
           rawSale.containsKey("includedBillIds") ||
           rawSale.containsKey("deductedAmount") ||
           rawSale.containsKey("developerAllowGstDiaryToUser"))) {
        continue;
      }

      if (billId.isEmpty && billNo.isEmpty) continue;

      if (rawSale is Map && (rawSale["fy"] != null || rawSale["date"] != null)) {
        DateTime? evDate;
        if (rawSale["date"] != null) {
          evDate = DateTime.tryParse(rawSale["date"].toString());
        }
        if (!doesEventBelongToActiveFY(rawSale, evDate, effFy)) {
          continue;
        }
      }

      recordKnownVersion(billId, billNo, version, effFy);

      if (action == "DELETE") {
        if (billId.isNotEmpty) markPermanentlyDeleted(billId);
        final cleanBNo = billNo.trim().toUpperCase();
        final bool hasActiveNewSale = localSales.any((s) => s.id != billId && cleanBNo.isNotEmpty && s.billNo.trim().toUpperCase() == cleanBNo && s.isDeleted != 1);
        if (!hasActiveNewSale && cleanBNo.isNotEmpty) {
          markPermanentlyDeleted(billId, cleanBNo, "", effFy);
        }
        final initialLen = localSales.length;
        localSales.removeWhere((s) => s.id == billId || (!hasActiveNewSale && cleanBNo.isNotEmpty && s.billNo.trim().toUpperCase() == cleanBNo));
        if (localSales.length != initialLen) mutated = true;
      } else if (action == "CANCEL") {
        int existingIdx = localSales.indexWhere((s) => s.id == billId || (billNo.isNotEmpty && s.billNo.trim().toUpperCase() == billNo.trim().toUpperCase()));
        if (existingIdx != -1) {
          localSales[existingIdx].status = "Cancelled";
          mutated = true;
        }
      } else {
        // INSERT or UPDATE
        if (rawSale is Map<String, dynamic>) {
          final incomingSale = Sale.fromMap(rawSale);
          if (billId.isNotEmpty) incomingSale.id = billId;
          incomingSale.version = version;
          // Guard against non-sale payloads with empty billNo and empty items
          if (incomingSale.billNo.trim().isEmpty &&
              incomingSale.items.isEmpty &&
              incomingSale.totalAmount <= 0) {
            continue;
          }
          // Strict Financial Year Isolation Guard
          if (!doesEventBelongToActiveFY(rawSale, incomingSale.date, effFy)) {
            continue;
          }
          unmarkPermanentlyDeleted(incomingSale.id, incomingSale.billNo, "", effFy);
          int existingIdx = localSales.indexWhere((s) => s.id == billId || (billNo.isNotEmpty && s.billNo.trim().toUpperCase() == billNo.trim().toUpperCase()));
          if (existingIdx != -1) {
            if (version >= localSales[existingIdx].version ||
                incomingSale.id != localSales[existingIdx].id ||
                incomingSale.updatedAt >= localSales[existingIdx].updatedAt) {
              localSales[existingIdx] = incomingSale;
              mutated = true;
            }
          } else {
            localSales.add(incomingSale);
            mutated = true;
          }
        }
      }
    }

    return mutated;
  }

  /// Merges incoming edge events into local Purchases memory list
  static bool applyEventsToLocalPurchases(
    List<Purchase> localPurchases,
    List<Map<String, dynamic>> events, [
    String? targetFyOverride,
  ]) {
    if (events.isEmpty) return false;
    final String effFy = (targetFyOverride != null && targetFyOverride.trim().isNotEmpty)
        ? targetFyOverride.trim()
        : activeFinancialYear;
    bool mutated = false;

    for (final ev in events) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final String billNo = (ev["bill_no"] ?? "").toString().trim();
      final String action = (ev["action"] ?? "INSERT").toString().toUpperCase();
      final int version = int.tryParse(ev["version"]?.toString() ?? "1") ?? 1;
      final dynamic rawData = ev["sale_data"];

      if (rawData is Map &&
          (rawData["doc_type"] == "VOUCHER" ||
           rawData.containsKey("voucherNo") ||
           rawData.containsKey("depositedIn"))) {
        continue;
      }
      final bool isPurchasePayload = rawData is Map &&
          (rawData["doc_type"] == "PURCHASE" ||
           rawData.containsKey("distributorName") ||
           rawData.containsKey("internalNo"));

      if (rawData is Map && (rawData["fy"] != null || rawData["date"] != null)) {
        DateTime? evDate;
        if (rawData["date"] != null) {
          evDate = DateTime.tryParse(rawData["date"].toString());
        }
        if (!doesEventBelongToActiveFY(rawData, evDate, effFy)) {
          continue;
        }
      }

      if (action == "DELETE") {
        final String partyId = (rawData is Map ? (rawData["partyId"] ?? "") : "").toString().trim().toUpperCase();
        final String pBillNo = (rawData is Map ? (rawData["billNo"] ?? billNo) : billNo).toString().trim().toUpperCase();
        final String intNo = (rawData is Map ? (rawData["internalNo"] ?? "") : "").toString().trim().toUpperCase();
        final bool hasActiveNewPur = localPurchases.any((p) => p.id != billId && intNo.isNotEmpty && p.internalNo.trim().toUpperCase() == intNo && p.isDeleted != 1);
        if (billId.isNotEmpty) {
          markPermanentlyDeleted(billId);
        }
        if (!hasActiveNewPur && (isPurchasePayload || intNo.isNotEmpty || partyId.isNotEmpty)) {
          markPurchasePermanentlyDeleted(billId, partyId, pBillNo, intNo, effFy);
        }
        final initialLen = localPurchases.length;
        localPurchases.removeWhere((p) =>
          (billId.isNotEmpty && p.id == billId) ||
          (!hasActiveNewPur && intNo.isNotEmpty && p.internalNo.trim().toUpperCase() == intNo) ||
          (!hasActiveNewPur && partyId.isNotEmpty && pBillNo.isNotEmpty &&
           p.partyId.trim().toUpperCase() == partyId &&
           p.billNo.trim().toUpperCase() == pBillNo)
        );
        if (localPurchases.length != initialLen) mutated = true;
      } else if (isPurchasePayload && rawData is Map<String, dynamic>) {
        final incomingPur = Purchase.fromMap(rawData);
        if (billId.isNotEmpty) incomingPur.id = billId;
        incomingPur.version = version;
        if (!doesEventBelongToActiveFY(rawData, incomingPur.date, effFy)) {
          continue;
        }
        unmarkPurchasePermanentlyDeleted(
          incomingPur.id,
          incomingPur.partyId,
          incomingPur.billNo,
          incomingPur.internalNo,
          effFy,
        );
        recordPurchaseKnownVersion(
          incomingPur.id,
          incomingPur.partyId,
          incomingPur.billNo,
          version,
          incomingPur.internalNo,
          effFy,
        );
        final cleanInt = incomingPur.internalNo.trim().toUpperCase();
        int existingIdx = localPurchases.indexWhere((p) =>
          (incomingPur.id.isNotEmpty && p.id == incomingPur.id) ||
          (cleanInt.isNotEmpty && p.internalNo.trim().toUpperCase() == cleanInt)
        );
        if (existingIdx != -1) {
          if (version >= localPurchases[existingIdx].version ||
              incomingPur.id != localPurchases[existingIdx].id ||
              incomingPur.updatedAt >= localPurchases[existingIdx].updatedAt) {
            localPurchases[existingIdx] = incomingPur;
            mutated = true;
          }
        } else {
          localPurchases.insert(0, incomingPur);
          mutated = true;
        }
      }
    }

    return mutated;
  }

  /// =========================================================================
  /// 3. LOCAL SEQUENCE PERSISTENCE
  /// =========================================================================

  static String _seqKey(String storeToken) {
    final cleanToken = storeToken.trim().toUpperCase();
    final cleanFy = activeFinancialYear.trim();
    if (cleanFy.isEmpty) return "d1_sale_seq_$cleanToken";
    return "d1_sale_seq_${cleanToken}_$cleanFy";
  }

  static Future<int> getLatestLocalSeq(String storeToken) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_seqKey(storeToken)) ?? 0;
  }

  static Future<void> _updateHighestLocalSeq(String storeToken, int seq) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _seqKey(storeToken);
    final current = prefs.getInt(key) ?? 0;
    if (seq > current) {
      await prefs.setInt(key, seq);
    }
  }
}
