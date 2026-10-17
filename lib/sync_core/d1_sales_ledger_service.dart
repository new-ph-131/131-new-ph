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

  /// 🛡️ PERMANENT GRAVESTONES: Once marked deleted in D1, Google Drive can NEVER resurrect
  static final Set<String> _permanentDeletedKeys = {};

  /// 🛡️ MASTER KNOWN VERSIONS: Google Drive can NEVER downgrade a known higher version
  static final Map<String, int> _knownBillVersions = {};

  static bool isBillDeleted(String id, [String secondaryKey = "", String tertiaryKey = ""]) {
    final cleanId = id.trim();
    final cleanSec = secondaryKey.trim().toUpperCase();
    final cleanTer = tertiaryKey.trim().toUpperCase();
    return (cleanId.isNotEmpty && _permanentDeletedKeys.contains(cleanId)) ||
           (cleanSec.isNotEmpty && _permanentDeletedKeys.contains(cleanSec)) ||
           (cleanTer.isNotEmpty && _permanentDeletedKeys.contains(cleanTer));
  }

  static int getKnownVersion(String id, [String secondaryKey = "", String tertiaryKey = ""]) {
    final cleanId = id.trim();
    final cleanSec = secondaryKey.trim().toUpperCase();
    final cleanTer = tertiaryKey.trim().toUpperCase();
    int maxV = cleanId.isNotEmpty ? (_knownBillVersions[cleanId] ?? 0) : 0;
    if (cleanSec.isNotEmpty && (_knownBillVersions[cleanSec] ?? 0) > maxV) {
      maxV = _knownBillVersions[cleanSec]!;
    }
    if (cleanTer.isNotEmpty && (_knownBillVersions[cleanTer] ?? 0) > maxV) {
      maxV = _knownBillVersions[cleanTer]!;
    }
    return maxV;
  }

  static void recordKnownVersion(String id, [String secondaryKey = "", int version = 1]) {
    final cleanId = id.trim();
    final cleanSec = secondaryKey.trim().toUpperCase();
    if (cleanId.isNotEmpty && version > (_knownBillVersions[cleanId] ?? 0)) {
      _knownBillVersions[cleanId] = version;
    }
    if (cleanSec.isNotEmpty && version > (_knownBillVersions[cleanSec] ?? 0)) {
      _knownBillVersions[cleanSec] = version;
    }
  }

  static void markPermanentlyDeleted(String id, [String secondaryKey = "", String tertiaryKey = ""]) {
    final cleanId = id.trim();
    final cleanSec = secondaryKey.trim().toUpperCase();
    final cleanTer = tertiaryKey.trim().toUpperCase();
    if (cleanId.isNotEmpty) _permanentDeletedKeys.add(cleanId);
    if (cleanSec.isNotEmpty) _permanentDeletedKeys.add(cleanSec);
    if (cleanTer.isNotEmpty) _permanentDeletedKeys.add(cleanTer);
    try {
      SharedPreferences.getInstance().then((prefs) {
        final existing = prefs.getStringList("d1_permanent_gravestones") ?? [];
        final set = existing.toSet();
        if (cleanId.isNotEmpty) set.add(cleanId);
        if (cleanSec.isNotEmpty) set.add(cleanSec);
        if (cleanTer.isNotEmpty) set.add(cleanTer);
        prefs.setStringList("d1_permanent_gravestones", set.toList());
      });
    } catch (_) {}
  }

  static void unmarkPermanentlyDeleted(String id, [String secondaryKey = "", String tertiaryKey = ""]) {
    final cleanId = id.trim();
    final cleanSec = secondaryKey.trim().toUpperCase();
    final cleanTer = tertiaryKey.trim().toUpperCase();
    if (cleanId.isNotEmpty) _permanentDeletedKeys.remove(cleanId);
    if (cleanSec.isNotEmpty) _permanentDeletedKeys.remove(cleanSec);
    if (cleanTer.isNotEmpty) _permanentDeletedKeys.remove(cleanTer);
    try {
      SharedPreferences.getInstance().then((prefs) {
        final existing = prefs.getStringList("d1_permanent_gravestones") ?? [];
        final set = existing.toSet();
        if (cleanId.isNotEmpty) set.remove(cleanId);
        if (cleanSec.isNotEmpty) set.remove(cleanSec);
        if (cleanTer.isNotEmpty) set.remove(cleanTer);
        prefs.setStringList("d1_permanent_gravestones", set.toList());
      });
    } catch (_) {}
  }

  // =========================================================================
  // 🛡️ PURCHASE COMPOSITE CONCURRENCY & GRAVESTONES (PARTY_ID + BILL_NO + INTERNAL_NO)
  // =========================================================================
  static bool isPurchaseDeleted(String id, String partyId, String billNo, [String internalNo = ""]) {
    final cleanId = id.trim();
    if (cleanId.isNotEmpty) {
      return _permanentDeletedKeys.contains(cleanId) ||
             _permanentDeletedKeys.contains(cleanId.toUpperCase());
    }
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
        ? "${cleanParty}_${cleanBill}_$cleanInt"
        : "";
    return (cleanInt.isNotEmpty && _permanentDeletedKeys.contains(cleanInt)) ||
           (compKey2.isNotEmpty && _permanentDeletedKeys.contains(compKey2)) ||
           (compKey3.isNotEmpty && _permanentDeletedKeys.contains(compKey3));
  }

  static int getPurchaseKnownVersion(String id, String partyId, String billNo, [String internalNo = ""]) {
    final cleanId = id.trim();
    if (cleanId.isNotEmpty) {
      return _knownBillVersions[cleanId] ?? 0;
    }
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
        ? "${cleanParty}_${cleanBill}_$cleanInt"
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

  static void recordPurchaseKnownVersion(String id, String partyId, String billNo, int version, [String internalNo = ""]) {
    final cleanId = id.trim();
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
        ? "${cleanParty}_${cleanBill}_$cleanInt"
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
  }) async {
    markPurchasePermanentlyDeleted(purchaseId, partyId, billNo, internalNo);
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

  static void markPurchasePermanentlyDeleted(String id, String partyId, String billNo, [String internalNo = ""]) {
    final cleanId = id.trim();
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
        ? "${cleanParty}_${cleanBill}_$cleanInt"
        : "";
    markPermanentlyDeleted(cleanId, cleanInt, compKey2);
    if (cleanId.isNotEmpty) markPermanentlyDeleted(cleanId.toUpperCase());
    if (compKey3.isNotEmpty) markPermanentlyDeleted(compKey3);
  }

  static void unmarkPurchasePermanentlyDeleted(String id, String partyId, String billNo, [String internalNo = ""]) {
    final cleanId = id.trim();
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
        ? "${cleanParty}_${cleanBill}_$cleanInt"
        : "";
    unmarkPermanentlyDeleted(cleanId, cleanInt, compKey2);
    if (cleanId.isNotEmpty) unmarkPermanentlyDeleted(cleanId.toUpperCase());
    if (compKey3.isNotEmpty) unmarkPermanentlyDeleted(compKey3);
    if (cleanBill.isNotEmpty) unmarkPermanentlyDeleted(cleanBill);
  }

  static Future<void> loadPersistedGravestones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList("d1_permanent_gravestones") ?? [];
      _permanentDeletedKeys.addAll(list);
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
          "payload": sale.toMap(),
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
          "payload": sale.toMap(),
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
  }) async {
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;

    try {
      markPermanentlyDeleted(saleId, billNo);
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
    List<Map<String, dynamic>> events,
  ) {
    if (events.isEmpty) return false;
    bool mutated = false;

    for (final ev in events) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final String billNo = (ev["bill_no"] ?? "").toString().trim();
      final String action = (ev["action"] ?? "INSERT").toString().toUpperCase();
      final int version = int.tryParse(ev["version"]?.toString() ?? "1") ?? 1;
      final dynamic rawSale = ev["sale_data"];

      // Skip Purchase events so they never pollute Sales
      if (rawSale is Map &&
          (rawSale["doc_type"] == "PURCHASE" ||
           rawSale.containsKey("distributorName") ||
           rawSale.containsKey("internalNo"))) {
        continue;
      }

      if (billId.isEmpty && billNo.isEmpty) continue;

      recordKnownVersion(billId, billNo, version);

      if (action == "DELETE") {
        markPermanentlyDeleted(billId, billNo);
        final initialLen = localSales.length;
        localSales.removeWhere((s) => s.id == billId || (billNo.isNotEmpty && s.billNo.trim().toUpperCase() == billNo.trim().toUpperCase()));
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
          unmarkPermanentlyDeleted(incomingSale.id, incomingSale.billNo);
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
    List<Map<String, dynamic>> events,
  ) {
    if (events.isEmpty) return false;
    bool mutated = false;

    for (final ev in events) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final String billNo = (ev["bill_no"] ?? "").toString().trim();
      final String action = (ev["action"] ?? "INSERT").toString().toUpperCase();
      final int version = int.tryParse(ev["version"]?.toString() ?? "1") ?? 1;
      final dynamic rawData = ev["sale_data"];

      final bool isPurchasePayload = rawData is Map &&
          (rawData["doc_type"] == "PURCHASE" ||
           rawData.containsKey("distributorName") ||
           rawData.containsKey("internalNo"));

      if (action == "DELETE") {
        final String partyId = (rawData is Map ? (rawData["partyId"] ?? "") : "").toString().trim().toUpperCase();
        final String pBillNo = (rawData is Map ? (rawData["billNo"] ?? billNo) : billNo).toString().trim().toUpperCase();
        final String intNo = (rawData is Map ? (rawData["internalNo"] ?? "") : "").toString().trim().toUpperCase();
        if (isPurchasePayload || intNo.isNotEmpty || partyId.isNotEmpty) {
          markPurchasePermanentlyDeleted(billId, partyId, pBillNo, intNo);
        }
        final initialLen = localPurchases.length;
        localPurchases.removeWhere((p) =>
          (billId.isNotEmpty && p.id == billId) ||
          (intNo.isNotEmpty && p.internalNo.trim().toUpperCase() == intNo) ||
          (billNo.isNotEmpty && p.internalNo.trim().toUpperCase() == billNo.toUpperCase()) ||
          (partyId.isNotEmpty && pBillNo.isNotEmpty &&
           p.partyId.trim().toUpperCase() == partyId && p.billNo.trim().toUpperCase() == pBillNo)
        );
        if (localPurchases.length != initialLen) mutated = true;
      } else if (isPurchasePayload && rawData is Map<String, dynamic>) {
        final incomingPur = Purchase.fromMap(rawData);
        if (billId.isNotEmpty) incomingPur.id = billId;
        incomingPur.version = version;
        unmarkPurchasePermanentlyDeleted(
          incomingPur.id,
          incomingPur.partyId,
          incomingPur.billNo,
          incomingPur.internalNo,
        );
        recordPurchaseKnownVersion(
          incomingPur.id,
          incomingPur.partyId,
          incomingPur.billNo,
          version,
          incomingPur.internalNo,
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

  static Future<int> getLatestLocalSeq(String storeToken) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt("d1_sale_seq_${storeToken.trim().toUpperCase()}") ?? 0;
  }

  static Future<void> _updateHighestLocalSeq(String storeToken, int seq) async {
    final prefs = await SharedPreferences.getInstance();
    final key = "d1_sale_seq_${storeToken.trim().toUpperCase()}";
    final current = prefs.getInt(key) ?? 0;
    if (seq > current) {
      await prefs.setInt(key, seq);
    }
  }
}
