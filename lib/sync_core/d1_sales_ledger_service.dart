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
  // 🛡️ PURCHASE COMPOSITE CONCURRENCY & GRAVESTONES (PARTY_ID + BILL_NO)
  // =========================================================================
  static bool isPurchaseDeleted(String id, String partyId, String billNo, [String internalNo = ""]) {
    final cleanId = id.trim();
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    return (cleanId.isNotEmpty && _permanentDeletedKeys.contains(cleanId)) ||
           (cleanInt.isNotEmpty && _permanentDeletedKeys.contains(cleanInt)) ||
           (compKey.isNotEmpty && _permanentDeletedKeys.contains(compKey));
  }

  static int getPurchaseKnownVersion(String id, String partyId, String billNo, [String internalNo = ""]) {
    final cleanId = id.trim();
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    int maxV = cleanId.isNotEmpty ? (_knownBillVersions[cleanId] ?? 0) : 0;
    if (cleanInt.isNotEmpty && (_knownBillVersions[cleanInt] ?? 0) > maxV) {
      maxV = _knownBillVersions[cleanInt]!;
    }
    if (compKey.isNotEmpty && (_knownBillVersions[compKey] ?? 0) > maxV) {
      maxV = _knownBillVersions[compKey]!;
    }
    return maxV;
  }

  static void recordPurchaseKnownVersion(String id, String partyId, String billNo, int version, [String internalNo = ""]) {
    final cleanId = id.trim();
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    if (cleanId.isNotEmpty && version > (_knownBillVersions[cleanId] ?? 0)) {
      _knownBillVersions[cleanId] = version;
    }
    if (cleanInt.isNotEmpty && version > (_knownBillVersions[cleanInt] ?? 0)) {
      _knownBillVersions[cleanInt] = version;
    }
    if (compKey.isNotEmpty && version > (_knownBillVersions[compKey] ?? 0)) {
      _knownBillVersions[compKey] = version;
    }
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
      final compKey = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "DELETE_PURCHASE",
        "entityId": purchaseId,
        "deletedIds": [
          purchaseId,
          if (internalNo.trim().isNotEmpty) internalNo.trim().toUpperCase(),
          if (compKey.isNotEmpty) compKey,
        ],
        "sale_event": {
          "id": purchaseId,
          "bill_no": billNo,
          "version": 999999,
          "action": "DELETE",
          "status": "Deleted",
          "client_source": clientSource,
          "payload": {"partyId": partyId, "billNo": billNo, "internalNo": internalNo},
        },
      };
      final res = await http.post(
        Uri.parse(endpoint),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
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
    final compKey = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    markPermanentlyDeleted(cleanId, cleanInt, compKey);
  }

  static void unmarkPurchasePermanentlyDeleted(String id, String partyId, String billNo, [String internalNo = ""]) {
    final cleanId = id.trim();
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim().toUpperCase();
    final compKey = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    unmarkPermanentlyDeleted(cleanId, cleanInt, compKey);
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

  /// Merges incoming edge events into local memory list
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
          int existingIdx = localSales.indexWhere((s) => s.id == billId || (billNo.isNotEmpty && s.billNo.trim().toUpperCase() == billNo.trim().toUpperCase()));
          if (existingIdx != -1) {
            // OCC / Version Check
            if (version >= localSales[existingIdx].version) {
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
