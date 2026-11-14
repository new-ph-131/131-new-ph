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
      // Check if primary or secondary key has explicit FY scoping (e.g. 2026-27::INV-1)
      final idStr = (rawPayload["id"] ?? rawPayload["sync_id"] ?? rawPayload["bill_id"] ?? "").toString().trim();
      if (idStr.contains("::")) {
        final scopedFy = idStr.split("::")[0].trim();
        if (scopedFy.isNotEmpty) return scopedFy == fy;
      }
      final secStr = (rawPayload["billNo"] ?? rawPayload["bill_no"] ?? rawPayload["internalNo"] ?? "").toString().trim();
      if (secStr.contains("::")) {
        final scopedFy = secStr.split("::")[0].trim();
        if (scopedFy.isNotEmpty) return scopedFy == fy;
      }
    }
    if (recordDate != null) {
      return inferFyFromDate(recordDate) == fy;
    }
    // 🛡️ ZERO-LEAK GUARD (#PH-REV-810): Minimal transaction deletions without FY or date
    // must NEVER bypass validation and destroy current active year records!
    if (rawPayload is Map) {
      final isDel = (rawPayload["action"]?.toString().toUpperCase() == "DELETE" ||
                     rawPayload["is_deleted"] == 1 ||
                     rawPayload["isDeleted"] == 1 ||
                     rawPayload["status"] == "Deleted");
      final isTxn = (rawPayload["doc_type"] != null ||
                     rawPayload.containsKey("billNo") ||
                     rawPayload.containsKey("internalNo") ||
                     rawPayload.containsKey("voucherNo"));
      if (isDel && isTxn) {
        return false;
      }
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

  /// 🕒 Deletion timestamps for gravestones (ms since epoch) so brand-new re-created entities
  /// with a distinct UUID can supersede an older secondary/series tombstone without resurrecting the deleted UUID.
  static final Map<String, int> _permanentDeletedTimestamps = {};

  /// 🛡️ MASTER KNOWN VERSIONS: Google Drive can NEVER downgrade a known higher version
  static final Map<String, int> _knownBillVersions = {};

  /// Checks if a key is a human-readable bill/series number or composite key (which repeats across FYs)
  /// Checks if a key is a human-readable bill/series number or composite key (which repeats across FYs)
  static bool isUnscopedSeriesKey(String key) {
    final k = key.trim().toUpperCase();
    if (k.isEmpty || k.contains("::")) return false;

    // Master entity identifiers that are globally unique across all FYs (must NOT be scoped)
    if (k.startsWith("COMP_") || k.startsWith("SALT_") || k.startsWith("ROUTE_") || 
        k.startsWith("SESS_") || k.startsWith("APP_CONFIG") || k.startsWith("BANK_") ||
        k.startsWith("STAFF_") || k.startsWith("USER_")) {
      return false;
    }
    if (k.startsWith("PARTY-") && !k.contains("_")) return false;
    if (k.startsWith("MED_") || (k.startsWith("PH-") && RegExp(r"^PH-\d{4,}$").hasMatch(k))) return false;

    // Timestamps (e.g. 1712345678901) or ISO dates or standard UUIDs (including prefixed UUIDs like PUR-UUID-101)
    if (RegExp(r"^\d{10,}$").hasMatch(k) || RegExp(r"^\d{4}-\d{2}-\d{2}").hasMatch(k) ||
        RegExp(r"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$").hasMatch(k) ||
        k.contains("-UUID-") || (k.contains("-") && k.length >= 24)) {
      return false;
    }

    // 🛡️ All human numeric sequence numbers (1, 2, 001, 10, etc.) are series keys that reset across FYs!
    if (RegExp(r"^\d{1,9}$").hasMatch(k)) return true;

    // Specific transaction series prefixes (Web & App & Standard ERPs)
    const knownPrefixes = [
      "INV-", "INV ", "INV", "WSALE-", "WSALE ", "WSALE",
      "W-", "W ", "SALE-", "SALE ", "PUR-", "PUR ", "WPUR-", "WPUR ",
      "SCH-", "SCH ", "WSCH-", "WSCH ", "PCH-", "PCH ", "WPCH-", "WPCH ",
      "SC-", "SC ", "PC-", "PC ", "CH-", "CH ",
      "TXN-", "TXN ", "WCN-", "WCN ", "WDN-", "WDN ",
      "SR-", "SR ", "WSR-", "WSR ", "CN-", "CN ", "PR-", "PR ", "DN-", "DN ",
      "RCT-", "RCT ", "WRCT-", "WRCT ", "PAY-", "PAY ", "WPAY-", "WPAY ",
      "CNT-", "CNT ", "WCNT-", "WCNT ", "EXP-", "EXP ", "WEXP-", "WEXP ",
      "BILL-", "BILL ", "WBILL-", "WBILL ", "TAX-", "TAX ", "WTAX-", "WTAX ",
      "VOU-", "VOU ", "WVOU-", "WVOU "
    ];
    for (final pfx in knownPrefixes) {
      if (k.startsWith(pfx)) return true;
    }

    // Generic transaction numbers (e.g. custom user series like GST-1, A-1, 2024/001, or composite PARTY_BILL)
    if (k.contains("_") || k.contains("/") || RegExp(r"[A-Z0-9]+[- /]?[0-9]+$").hasMatch(k)) {
      return true;
    }

    return false;
  }

  /// Scopes a secondary/series key (e.g. INV-1, PUR-1, PARTY_BILL) to the target Financial Year
  /// so bill numbers that reset to #1 in a new FY never collide with or delete old FY bills.
  static String scopeSecondaryKey(String secKey, [String? fy, bool preserveCase = false]) {
    final clean = preserveCase ? secKey.trim() : secKey.trim().toUpperCase();
    if (clean.isEmpty) return "";
    if (clean.contains("::")) return clean;
    final effFy = (fy != null && fy.trim().isNotEmpty) ? fy.trim() : activeFinancialYear.trim();
    if (effFy.isEmpty) return clean;
    return "$effFy::$clean";
  }

  /// Scopes a purchase/challan composite key preserving exact case of supplier [billNo].
  static String scopePurchaseKey(String partyId, String billNo, [String internalNo = "", String? fy]) {
    final p = partyId.trim().toUpperCase();
    final b = billNo.trim();
    final i = internalNo.trim().toUpperCase();
    String raw = "";
    if (p.isNotEmpty && b.isNotEmpty && i.isNotEmpty) {
      raw = "${p}_${b}_$i";
    } else if (p.isNotEmpty && b.isNotEmpty) {
      raw = "${p}_$b";
    } else if (i.isNotEmpty) {
      raw = i;
    } else {
      return "";
    }
    return scopeSecondaryKey(raw, fy, true);
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

  static void markPermanentlyDeleted(String id, [String secondaryKey = "", String tertiaryKey = "", String? fy, bool preserveCase = false, int? deletedAtMs]) {
    final cleanId = id.trim();
    final bool keepIdCase = preserveCase || cleanId.contains("_");
    final String idKey = isUnscopedSeriesKey(cleanId) ? scopeSecondaryKey(cleanId, fy, keepIdCase) : cleanId;
    final String cleanSec = scopeSecondaryKey(secondaryKey, fy, preserveCase || secondaryKey.contains("_"));
    final String cleanTer = scopeSecondaryKey(tertiaryKey, fy, preserveCase || tertiaryKey.contains("_"));
    final int delTs = (deletedAtMs != null && deletedAtMs > 0) ? deletedAtMs : DateTime.now().millisecondsSinceEpoch;
    void recordKey(String k) {
      if (k.isEmpty) return;
      _permanentDeletedKeys.add(k);
      final prev = _permanentDeletedTimestamps[k] ?? 0;
      if (delTs >= prev) _permanentDeletedTimestamps[k] = delTs;
    }
    recordKey(idKey);
    recordKey(cleanSec);
    recordKey(cleanTer);
    try {
      SharedPreferences.getInstance().then((prefs) {
        final existing = prefs.getStringList("d1_permanent_gravestones") ?? [];
        final set = existing.where((k) => !isUnscopedSeriesKey(k)).toSet();
        if (idKey.isNotEmpty) set.add(idKey);
        if (cleanSec.isNotEmpty) set.add(cleanSec);
        if (cleanTer.isNotEmpty) set.add(cleanTer);
        prefs.setStringList("d1_permanent_gravestones", set.toList());
        final rawTs = prefs.getString("d1_permanent_gravestone_ts");
        final Map<String, int> tsMap = {};
        if (rawTs != null && rawTs.isNotEmpty) {
          try {
            (jsonDecode(rawTs) as Map).forEach((k, v) {
              final ks = k.toString().trim();
              if (ks.isNotEmpty && !isUnscopedSeriesKey(ks)) {
                tsMap[ks] = int.tryParse(v.toString()) ?? 0;
              }
            });
          } catch (_) {}
        }
        if (idKey.isNotEmpty) tsMap[idKey] = _permanentDeletedTimestamps[idKey] ?? delTs;
        if (cleanSec.isNotEmpty) tsMap[cleanSec] = _permanentDeletedTimestamps[cleanSec] ?? delTs;
        if (cleanTer.isNotEmpty) tsMap[cleanTer] = _permanentDeletedTimestamps[cleanTer] ?? delTs;
        prefs.setString("d1_permanent_gravestone_ts", jsonEncode(tsMap));
      });
    } catch (_) {}
  }

  static void unmarkPermanentlyDeleted(String id, [String secondaryKey = "", String tertiaryKey = "", String? fy, bool preserveCase = false]) {
    final cleanId = id.trim();
    final bool keepSecCase = preserveCase || secondaryKey.contains("_");
    final bool keepTerCase = preserveCase || tertiaryKey.contains("_");
    final cleanSecRaw = keepSecCase ? secondaryKey.trim() : secondaryKey.trim().toUpperCase();
    final cleanTerRaw = keepTerCase ? tertiaryKey.trim() : tertiaryKey.trim().toUpperCase();
    final scopedId = scopeSecondaryKey(cleanId, fy, preserveCase || cleanId.contains("_"));
    final scopedSec = scopeSecondaryKey(cleanSecRaw, fy, keepSecCase);
    final scopedTer = scopeSecondaryKey(cleanTerRaw, fy, keepTerCase);

    void removeEverywhere(String k, {bool exactOnly = false}) {
      if (k.isEmpty) return;
      _permanentDeletedKeys.remove(k);
      _permanentDeletedTimestamps.remove(k);
      _knownBillVersions.remove(k);
      if (!exactOnly) {
        _permanentDeletedKeys.remove(k.toUpperCase());
        _permanentDeletedTimestamps.remove(k.toUpperCase());
        _knownBillVersions.remove(k.toUpperCase());
      }
    }

    removeEverywhere(cleanId, exactOnly: preserveCase || cleanId.contains("_"));
    removeEverywhere(scopedId, exactOnly: preserveCase || scopedId.contains("_"));
    removeEverywhere(cleanSecRaw, exactOnly: keepSecCase);
    removeEverywhere(scopedSec, exactOnly: keepSecCase);
    removeEverywhere(cleanTerRaw, exactOnly: keepTerCase);
    removeEverywhere(scopedTer, exactOnly: keepTerCase);

    try {
      SharedPreferences.getInstance().then((prefs) {
        final existing = prefs.getStringList("d1_permanent_gravestones") ?? [];
        final set = existing.where((k) => !isUnscopedSeriesKey(k)).toSet();
        final toRemove = <String>{
          cleanId,
          if (!preserveCase && !cleanId.contains("_")) cleanId.toUpperCase(),
          scopedId,
          cleanSecRaw,
          scopedSec,
          cleanTerRaw,
          scopedTer,
        }..removeWhere((e) => e.isEmpty);
        set.removeAll(toRemove);
        prefs.setStringList("d1_permanent_gravestones", set.toList());
        final rawTs = prefs.getString("d1_permanent_gravestone_ts");
        if (rawTs != null && rawTs.isNotEmpty) {
          try {
            final Map<String, int> tsMap = {};
            (jsonDecode(rawTs) as Map).forEach((k, v) {
              final ks = k.toString().trim();
              if (ks.isNotEmpty && !toRemove.contains(ks) && !isUnscopedSeriesKey(ks)) {
                tsMap[ks] = int.tryParse(v.toString()) ?? 0;
              }
            });
            prefs.setString("d1_permanent_gravestone_ts", jsonEncode(tsMap));
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  // =========================================================================
  // 🛡️ PURCHASE COMPOSITE CONCURRENCY & GRAVESTONES (PARTY_ID + BILL_NO + INTERNAL_NO)
  // =========================================================================
  /// Checks ONLY whether the immutable Purchase UUID [id] itself was permanently deleted.
  /// Never matches reused series/composite keys so a newly re-created Purchase entity
  /// cannot be poisoned by a previously deleted Purchase's PUR-* number.
  static bool isPurchaseIdDeleted(String id, [String? fy]) {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return false;
    final scopedId = isUnscopedSeriesKey(cleanId) ? scopeSecondaryKey(cleanId, fy) : cleanId;
    return _permanentDeletedKeys.contains(cleanId) ||
        _permanentDeletedKeys.contains(cleanId.toUpperCase()) ||
        (scopedId.isNotEmpty &&
            (_permanentDeletedKeys.contains(scopedId) ||
             _permanentDeletedKeys.contains(scopedId.toUpperCase())));
  }

  /// Returns the highest known deletion timestamp (ms) recorded against any secondary
  /// key (`internalNo`, `party_billNo`, `party_billNo_internalNo`) for a Purchase in [fy].
  static int getPurchaseSecondaryDeleteTimestamp(
    String partyId,
    String billNo, [
    String internalNo = "",
    String? fy,
  ]) {
    final cleanInt = scopeSecondaryKey(internalNo, fy);
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_$cleanBill", fy, true)
        : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && internalNo.trim().isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_${cleanBill}_${internalNo.trim().toUpperCase()}", fy, true)
        : "";
    final compKey2Upper = compKey2.isNotEmpty ? scopeSecondaryKey("${cleanParty}_${cleanBill.toUpperCase()}", fy, true) : "";
    final compKey3Upper = compKey3.isNotEmpty ? scopeSecondaryKey("${cleanParty}_${cleanBill.toUpperCase()}_${internalNo.trim().toUpperCase()}", fy, true) : "";
    int maxTs = 0;
    for (final k in [cleanInt, compKey2, compKey3, compKey2Upper, compKey3Upper]) {
      if (k.isNotEmpty && _permanentDeletedKeys.contains(k)) {
        final t = _permanentDeletedTimestamps[k] ?? 0;
        if (t > maxTs) maxTs = t;
      }
    }
    return maxTs;
  }

  static bool isPurchaseDeleted(
    String id,
    String partyId,
    String billNo, [
    String internalNo = "",
    String? fy,
    int? recordUpdatedAt,
  ]) {
    final cleanId = id.trim();
    if (isPurchaseIdDeleted(cleanId, fy)) {
      return true;
    }
    final cleanInt = scopeSecondaryKey(internalNo, fy);
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_$cleanBill", fy, true)
        : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && internalNo.trim().isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_${cleanBill}_${internalNo.trim().toUpperCase()}", fy, true)
        : "";
    final compKey2Upper = compKey2.isNotEmpty ? scopeSecondaryKey("${cleanParty}_${cleanBill.toUpperCase()}", fy, true) : "";
    final compKey3Upper = compKey3.isNotEmpty ? scopeSecondaryKey("${cleanParty}_${cleanBill.toUpperCase()}_${internalNo.trim().toUpperCase()}", fy, true) : "";

    final bool hasSecTomb = (cleanInt.isNotEmpty && _permanentDeletedKeys.contains(cleanInt)) ||
           (compKey2.isNotEmpty && _permanentDeletedKeys.contains(compKey2)) ||
           (compKey3.isNotEmpty && _permanentDeletedKeys.contains(compKey3)) ||
           (compKey2Upper.isNotEmpty && _permanentDeletedKeys.contains(compKey2Upper)) ||
           (compKey3Upper.isNotEmpty && _permanentDeletedKeys.contains(compKey3Upper));
    if (!hasSecTomb) return false;

    // If caller provides a non-empty distinct UUID AND a valid record timestamp strictly newer
    // than every secondary gravestone timestamp, allow the re-created Purchase entity.
    if (cleanId.isNotEmpty && recordUpdatedAt != null && recordUpdatedAt > 0) {
      int maxSecDelTs = 0;
      for (final k in [cleanInt, compKey2, compKey3, compKey2Upper, compKey3Upper]) {
        if (k.isNotEmpty && _permanentDeletedKeys.contains(k)) {
          final ts = _permanentDeletedTimestamps[k] ?? 0;
          if (ts == 0) {
            return true; // Timestamp unknown -> conservative block
          }
          if (ts > maxSecDelTs) maxSecDelTs = ts;
        }
      }
      if (maxSecDelTs > 0 && recordUpdatedAt > maxSecDelTs) {
        return false;
      }
    }
    return true;
  }

  static int getPurchaseIdKnownVersion(String id, [String? fy]) {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return 0;
    final scopedId = isUnscopedSeriesKey(cleanId) ? scopeSecondaryKey(cleanId, fy) : cleanId;
    final v1 = _knownBillVersions[cleanId] ?? 0;
    final v2 = scopedId.isNotEmpty ? (_knownBillVersions[scopedId] ?? 0) : 0;
    return v1 > v2 ? v1 : v2;
  }

  static int getPurchaseKnownVersion(String id, String partyId, String billNo, [String internalNo = "", String? fy]) {
    final cleanId = id.trim();
    if (cleanId.isNotEmpty && !isUnscopedSeriesKey(cleanId)) {
      return _knownBillVersions[cleanId] ?? 0;
    }
    final cleanInt = scopeSecondaryKey(internalNo, fy);
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_$cleanBill", fy, true)
        : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && internalNo.trim().isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_${cleanBill}_${internalNo.trim().toUpperCase()}", fy, true)
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
    final cleanBill = billNo.trim();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_$cleanBill", fy, true)
        : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && internalNo.trim().isNotEmpty)
        ? scopeSecondaryKey("${cleanParty}_${cleanBill}_${internalNo.trim().toUpperCase()}", fy, true)
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
    String? fy,
  }) async {
    final String effFy = (fy != null && fy.trim().isNotEmpty)
        ? fy.trim()
        : (activeFinancialYear.isNotEmpty ? activeFinancialYear.trim() : inferFyFromDate(purchase.date));
    unmarkPurchasePermanentlyDeleted(
      purchase.id,
      purchase.partyId,
      purchase.billNo,
      purchase.internalNo,
      effFy,
    );
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;

    try {
      final purMap = purchase.toMap();
      purMap["doc_type"] = "PURCHASE";
      purMap["fy"] = effFy;
      final String cleanParty = purchase.partyId.trim().toUpperCase();
      final String cleanBill = purchase.billNo.trim();
      final String cleanInt = purchase.internalNo.trim().toUpperCase();
      final String scopedInt = cleanInt.isNotEmpty ? scopeSecondaryKey(cleanInt, effFy) : "";
      final String compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? scopeSecondaryKey("${cleanParty}_$cleanBill", effFy, true) : "";
      final String compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
          ? scopeSecondaryKey("${cleanParty}_${cleanBill}_$cleanInt", effFy, true)
          : "";
      final String refNo = cleanInt.isNotEmpty ? cleanInt : cleanBill;

      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": isUpdate ? "UPDATE_PURCHASE" : "INSERT_PURCHASE",
        "entityId": purchase.id,
        "fy": effFy,
        "unmarkedIds": [
          purchase.id,
          if (scopedInt.isNotEmpty) scopedInt,
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
            effFy,
          );
          final int? newSeq = data["seq"];
          if (newSeq != null && newSeq > 0) {
            await _updateHighestLocalSeq(storeToken, newSeq);
          }
          return true;
        }
      } else if (res.statusCode == 410) {
        markPurchasePermanentlyDeleted(purchase.id, purchase.partyId, purchase.billNo, purchase.internalNo, effFy);
        return false;
      } else if (res.statusCode == 409) {
        try {
          final data = jsonDecode(res.body);
          if (data["status"] == "DELETED") {
            markPurchasePermanentlyDeleted(purchase.id, purchase.partyId, purchase.billNo, purchase.internalNo, effFy);
            return false;
          }
          final int serverVer = int.tryParse(data["current_version"]?.toString() ?? "0") ?? 0;
          if (serverVer >= 99999) {
            markPurchasePermanentlyDeleted(purchase.id, purchase.partyId, purchase.billNo, purchase.internalNo, effFy);
            return false;
          }
          if (serverVer > 0) {
            recordPurchaseKnownVersion(
              purchase.id,
              purchase.partyId,
              purchase.billNo,
              serverVer,
              purchase.internalNo,
              effFy,
            );
            purchase.version = serverVer + 1;
            return await onPurchaseSaved(purchase, storeToken, isUpdate: true, clientSource: clientSource, fy: effFy);
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
    String? fy,
  }) async {
    final String effFy = (fy != null && fy.trim().isNotEmpty)
        ? fy.trim()
        : activeFinancialYear.trim();
    markPurchasePermanentlyDeleted(purchaseId, partyId, billNo, internalNo, effFy);
    if (linkedChallanIds.isNotEmpty) {
      for (var cid in linkedChallanIds) {
        if (cid.trim().isNotEmpty) unmarkPermanentlyDeleted(cid.trim(), "", "", effFy);
      }
    }
    if (storeToken.trim().isEmpty) return false;
    try {
      final cleanParty = partyId.trim().toUpperCase();
      final cleanBill = billNo.trim();
      final cleanInt = internalNo.trim().toUpperCase();
      final scopedInt = cleanInt.isNotEmpty ? scopeSecondaryKey(cleanInt, effFy) : "";
      final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? scopeSecondaryKey("${cleanParty}_$cleanBill", effFy, true) : "";
      final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
          ? scopeSecondaryKey("${cleanParty}_${cleanBill}_$cleanInt", effFy, true)
          : "";
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "DELETE_PURCHASE",
        "entityId": purchaseId,
        "fy": effFy,
        "deletedIds": [
          purchaseId,
          if (scopedInt.isNotEmpty) scopedInt,
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
            "fy": effFy,
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

  static void markPurchasePermanentlyDeleted(String id, String partyId, String billNo, [String internalNo = "", String? fy, int? deletedAtMs]) {
    final cleanId = id.trim();
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
        ? "${cleanParty}_${cleanBill}_$cleanInt"
        : "";
    markPermanentlyDeleted(cleanId, cleanInt, compKey2, fy, true, deletedAtMs);
    if (cleanId.isNotEmpty) markPermanentlyDeleted(cleanId.toUpperCase(), "", "", fy, false, deletedAtMs);
    if (compKey3.isNotEmpty) markPermanentlyDeleted(compKey3, "", "", fy, true, deletedAtMs);
  }

  static void unmarkPurchasePermanentlyDeleted(String id, String partyId, String billNo, [String internalNo = "", String? fy]) {
    final cleanId = id.trim();
    final cleanInt = internalNo.trim().toUpperCase();
    final cleanParty = partyId.trim().toUpperCase();
    final cleanBill = billNo.trim();
    final compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty) ? "${cleanParty}_$cleanBill" : "";
    final compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
        ? "${cleanParty}_${cleanBill}_$cleanInt"
        : "";
    final compKey2Upper = compKey2.isNotEmpty ? "${cleanParty}_${cleanBill.toUpperCase()}" : "";
    final compKey3Upper = compKey3.isNotEmpty ? "${cleanParty}_${cleanBill.toUpperCase()}_$cleanInt" : "";
    unmarkPermanentlyDeleted(cleanId, cleanInt, compKey2, fy, true);
    if (cleanId.isNotEmpty) unmarkPermanentlyDeleted(cleanId.toUpperCase(), "", "", fy);
    if (compKey3.isNotEmpty) unmarkPermanentlyDeleted(compKey3, "", "", fy, true);
    if (compKey2Upper.isNotEmpty && compKey2Upper != compKey2) {
      unmarkPermanentlyDeleted(compKey2Upper, "", "", fy, true);
    }
    if (compKey3Upper.isNotEmpty && compKey3Upper != compKey3) {
      unmarkPermanentlyDeleted(compKey3Upper, "", "", fy, true);
    }
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
      _permanentDeletedTimestamps.clear();
      final rawTs = prefs.getString("d1_permanent_gravestone_ts");
      if (rawTs != null && rawTs.isNotEmpty) {
        try {
          (jsonDecode(rawTs) as Map).forEach((k, v) {
            final ks = k.toString().trim();
            if (ks.isNotEmpty && !isUnscopedSeriesKey(ks)) {
              _permanentDeletedTimestamps[ks] = int.tryParse(v.toString()) ?? 0;
            }
          });
        } catch (_) {}
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
      } else if (res.statusCode == 410) {
        markPermanentlyDeleted(sale.id, sale.billNo);
        return false;
      } else if (res.statusCode == 409) {
        debugPrint("⚠ [D1SalesLedger] OCC Conflict: Bill modified elsewhere. Initiating Enterprise Auto-Rebase...");
        try {
          final data = jsonDecode(res.body);
          final int serverVer = int.tryParse(data["current_version"]?.toString() ?? "0") ?? 0;
          if (data["status"] == "DELETED" || serverVer >= 99999) {
            markPermanentlyDeleted(sale.id, sale.billNo);
            return false;
          }
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
    String? fy,
  }) async {
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;
    final String effFy = (fy != null && fy.trim().isNotEmpty)
        ? fy.trim()
        : activeFinancialYear.trim();

    try {
      markPermanentlyDeleted(saleId, billNo, "", effFy);
      if (linkedChallanIds.isNotEmpty) {
        for (var cid in linkedChallanIds) {
          if (cid.trim().isNotEmpty) unmarkPermanentlyDeleted(cid.trim(), "", "", effFy);
        }
      }
      final cleanBNo = billNo.trim().toUpperCase();
      final scopedBNo = cleanBNo.isNotEmpty ? scopeSecondaryKey(cleanBNo, effFy) : "";
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "DELETE_SALE",
        "fy": effFy,
        "deletedIds": [
          saleId,
          if (scopedBNo.isNotEmpty) scopedBNo,
        ],
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
            "fy": effFy,
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

  /// Commits highest processed D1 seq cursor ONLY after caller has persisted mutations/tombstones.
  static Future<void> commitSaleDeltaSeq(String storeToken, int seq) async {
    if (storeToken.trim().isEmpty || seq <= 0) return;
    await _updateHighestLocalSeq(storeToken, seq);
  }

  /// Pulls sequential mutations committed after sinceSeq without advancing local cursor prematurely.
  static Future<({List<Map<String, dynamic>> events, int maxSeq})> fetchSaleDeltasWithCursor(
    String storeToken, {
    int? customSinceSeq,
  }) async {
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) {
      return (events: <Map<String, dynamic>>[], maxSeq: 0);
    }

    int cursor = customSinceSeq ?? await getLatestLocalSeq(storeToken);
    int highestMaxSeq = cursor;
    final List<Map<String, dynamic>> allEvents = [];
    try {
      for (int page = 0; page < 5; page++) {
        final uri = Uri.parse("$endpoint?storeToken=${Uri.encodeComponent(storeToken.trim().toUpperCase())}&since_seq=$cursor");
        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) break;
        final data = jsonDecode(res.body);
        if (data["status"] != "SUCCESS" || data["events"] is! List) break;
        final List<Map<String, dynamic>> pageEvents =
            List<Map<String, dynamic>>.from(data["events"]);
        if (pageEvents.isEmpty) break;
        allEvents.addAll(pageEvents);
        final int? mSeq = int.tryParse(data["max_seq"]?.toString() ?? '');
        if (mSeq != null && mSeq > highestMaxSeq) {
          highestMaxSeq = mSeq;
          cursor = mSeq;
        } else {
          break;
        }
        if (pageEvents.length < 250) break;
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] fetchSaleDeltasWithCursor Error: $e");
    }
    return (events: allEvents, maxSeq: highestMaxSeq);
  }

  /// Pulls all sequential mutations committed after sinceSeq
  static Future<List<Map<String, dynamic>>> fetchSaleDeltas(
    String storeToken, {
    int? customSinceSeq,
  }) async {
    final res = await fetchSaleDeltasWithCursor(storeToken, customSinceSeq: customSinceSeq);
    if (res.events.isNotEmpty && res.maxSeq > 0) {
      await commitSaleDeltaSeq(storeToken, res.maxSeq);
    }
    return res.events;
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
           rawSale["doc_type"] == "SALE_RETURN" ||
           rawSale["doc_type"] == "CREDIT_NOTE" ||
           rawSale["doc_type"] == "PURCHASE_RETURN" ||
           rawSale["doc_type"] == "DEBIT_NOTE" ||
           rawSale["doc_type"] == "GST_DIARY_SESSION" ||
           rawSale["doc_type"] == "GST_SESSION" ||
           rawSale["doc_type"] == "APP_CONFIG" ||
           rawSale["doc_type"] == "CONFIG" ||
           rawSale.containsKey("returnType") ||
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

      final String evFy = (ev["fy"] ?? (rawSale is Map ? rawSale["fy"] : "") ?? "").toString().trim();
      DateTime? evDate;
      if (rawSale is Map && rawSale["date"] != null) {
        evDate = DateTime.tryParse(rawSale["date"].toString());
      }
      if (evFy.isNotEmpty && evFy != effFy) {
        continue;
      }
      if (evDate != null && !doesEventBelongToActiveFY(rawSale, evDate, effFy)) {
        continue;
      }

      recordKnownVersion(billId, billNo, version, effFy);

      if (action == "DELETE" || action.startsWith("DELETE_")) {
        if (billId.isNotEmpty) markPermanentlyDeleted(billId, "", "", effFy);
        final cleanBNo = billNo.trim().toUpperCase();
        final bool hasActiveNewSale = localSales.any((s) => s.id != billId && cleanBNo.isNotEmpty && s.billNo.trim().toUpperCase() == cleanBNo && s.isDeleted != 1);
        if (!hasActiveNewSale && cleanBNo.isNotEmpty) {
          markPermanentlyDeleted(billId, cleanBNo, "", effFy);
        }
        final initialLen = localSales.length;
        localSales.removeWhere((s) {
          if (billId.isNotEmpty && s.id == billId) return true;
          if (!hasActiveNewSale && cleanBNo.isNotEmpty && s.billNo.trim().toUpperCase() == cleanBNo) {
            final sFy = inferFyFromDate(s.date);
            return sFy == effFy;
          }
          return false;
        });
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
           rawData["doc_type"] == "SALE_RETURN" ||
           rawData["doc_type"] == "CREDIT_NOTE" ||
           rawData["doc_type"] == "PURCHASE_RETURN" ||
           rawData["doc_type"] == "DEBIT_NOTE" ||
           rawData.containsKey("returnType") ||
           rawData.containsKey("voucherNo") ||
           rawData.containsKey("depositedIn"))) {
        continue;
      }
      final bool isPurchasePayload = rawData is Map &&
          (rawData["doc_type"] == "PURCHASE" ||
           rawData.containsKey("distributorName") ||
           rawData.containsKey("internalNo"));

      final String evFy = (ev["fy"] ?? (rawData is Map ? rawData["fy"] : "") ?? "").toString().trim();
      DateTime? evDate;
      if (rawData is Map && rawData["date"] != null) {
        evDate = DateTime.tryParse(rawData["date"].toString());
      }
      if (evFy.isNotEmpty && evFy != effFy) {
        continue;
      }
      if (evDate != null && !doesEventBelongToActiveFY(rawData, evDate, effFy)) {
        continue;
      }

      final bool payloadIsDeleted = rawData is Map &&
          ((int.tryParse(rawData["is_deleted"]?.toString() ?? rawData["isDeleted"]?.toString() ?? "0") ?? 0) == 1 ||
           rawData["status"] == "Deleted");
      if (action == "DELETE" || action.startsWith("DELETE_") || payloadIsDeleted) {
        final String partyId = (rawData is Map ? (rawData["partyId"] ?? "") : "").toString().trim().toUpperCase();
        final String pBillNo = (rawData is Map ? (rawData["billNo"] ?? billNo) : billNo).toString().trim();
        final String intNo = (rawData is Map ? (rawData["internalNo"] ?? "") : "").toString().trim().toUpperCase();
        final int delTs = int.tryParse((rawData is Map ? (rawData["updatedAt"] ?? rawData["updated_at"]) : null)?.toString() ?? ev["created_at"]?.toString() ?? "0") ?? 0;
        final bool hasActiveNewPur = localPurchases.any((p) => p.id != billId && intNo.isNotEmpty && p.internalNo.trim().toUpperCase() == intNo && p.isDeleted != 1);
        if (billId.isNotEmpty) {
          markPermanentlyDeleted(billId, "", "", effFy, false, delTs > 0 ? delTs : null);
          if (hasActiveNewPur) {
            recordKnownVersion(billId, "", version > 99999 ? version : 999999, effFy);
          } else {
            recordPurchaseKnownVersion(billId, partyId, pBillNo, version > 99999 ? version : 999999, intNo, effFy);
          }
        }
        if (!hasActiveNewPur && (isPurchasePayload || intNo.isNotEmpty || partyId.isNotEmpty)) {
          markPurchasePermanentlyDeleted(billId, partyId, pBillNo, intNo, effFy, delTs > 0 ? delTs : null);
        }
        final initialLen = localPurchases.length;
        localPurchases.removeWhere((p) {
          if (billId.isNotEmpty && p.id == billId) return true;
          final pFy = inferFyFromDate(p.date);
          if (pFy != effFy) return false;
          return (!hasActiveNewPur && intNo.isNotEmpty && p.internalNo.trim().toUpperCase() == intNo) ||
                 (!hasActiveNewPur && partyId.isNotEmpty && pBillNo.isNotEmpty &&
                  p.partyId.trim().toUpperCase() == partyId &&
                  p.billNo.trim() == pBillNo);
        });
        if (localPurchases.length != initialLen) mutated = true;
      } else if (isPurchasePayload && rawData is Map<String, dynamic>) {
        final incomingPur = Purchase.fromMap(rawData);
        if (billId.isNotEmpty) incomingPur.id = billId;
        incomingPur.version = version;
        if (!doesEventBelongToActiveFY(rawData, incomingPur.date, effFy)) {
          continue;
        }
        if (incomingPur.id.trim().isNotEmpty) {
          // Only block if this exact Purchase UUID itself was deleted; never block a brand-new UUID
          // re-created after an older Purchase with the same series/supplier billNo was deleted.
          if (isPurchaseIdDeleted(incomingPur.id, effFy)) {
            continue;
          }
          final int knownIdVer = getPurchaseIdKnownVersion(incomingPur.id, effFy);
          if (knownIdVer >= 99999 || version < knownIdVer) {
            continue;
          }
        } else {
          if (isPurchaseDeleted(incomingPur.id, incomingPur.partyId, incomingPur.billNo, incomingPur.internalNo, effFy)) {
            continue;
          }
          final int knownVer = getPurchaseKnownVersion(
            incomingPur.id,
            incomingPur.partyId,
            incomingPur.billNo,
            incomingPur.internalNo,
            effFy,
          );
          if (knownVer >= 99999 || version < knownVer) {
            continue;
          }
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
        int existingIdx = localPurchases.indexWhere((p) {
          if (incomingPur.id.trim().isNotEmpty && p.id.trim().isNotEmpty) {
            return p.id.trim() == incomingPur.id.trim();
          }
          if (cleanInt.isNotEmpty && p.internalNo.trim().toUpperCase() == cleanInt) {
            if (incomingPur.partyId.trim().isNotEmpty && p.partyId.trim().isNotEmpty &&
                incomingPur.billNo.trim().isNotEmpty && p.billNo.trim().isNotEmpty) {
              return p.partyId.trim().toUpperCase() == incomingPur.partyId.trim().toUpperCase() &&
                     p.billNo.trim() == incomingPur.billNo.trim();
            }
            return incomingPur.id.trim().isEmpty && p.id.trim().isEmpty;
          }
          return false;
        });
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


  static Future<bool> onSaleReturnSaved(
    SaleReturn ret,
    String storeToken, {
    bool isUpdate = true,
    String clientSource = "APP_MOBILE",
    String? fy,
    String? fyOverride,
  }) async {
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;
    final String? chosenFy = (fyOverride != null && fyOverride.trim().isNotEmpty) ? fyOverride : fy;
    final String effFy = (chosenFy != null && chosenFy.trim().isNotEmpty)
        ? chosenFy.trim()
        : (activeFinancialYear.isNotEmpty ? activeFinancialYear : inferFyFromDate(ret.date));
    try {
      unmarkPermanentlyDeleted(ret.id, ret.billNo, "", effFy);
      recordKnownVersion(ret.id, ret.billNo, ret.version);
      final map = ret.toMap();
      map["doc_type"] = "SALE_RETURN";
      map["fy"] = effFy;
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "SALE_RETURN_SAVED",
        "fy": effFy,
        "entityId": ret.id,
        "unmarkedIds": [ret.id, if (ret.billNo.trim().isNotEmpty) ret.billNo.trim().toUpperCase()],
        "sale_event": {
          "id": ret.id,
          "bill_no": ret.billNo,
          "version": ret.version,
          "action": ret.status == "Cancelled" ? "CANCEL" : "UPDATE",
          "status": ret.status,
          "client_source": clientSource,
          "payload": map,
        },
      };
      final res = await http.post(Uri.parse(endpoint), headers: _headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> onSaleReturnDeleted(
    dynamic retOrId,
    String storeTokenOrBillNo, [
    String? maybeStoreToken,
  ]) async {
    return _onSaleReturnDeletedInternal(retOrId, storeTokenOrBillNo, maybeStoreToken);
  }

  static Future<bool> _onSaleReturnDeletedInternal(
    dynamic retOrId,
    String storeTokenOrBillNo, [
    String? maybeStoreToken,
    String clientSource = "APP_MOBILE",
    String? fy,
  ]) async {
    final String retId = retOrId is SaleReturn ? retOrId.id : retOrId.toString();
    final String billNo = retOrId is SaleReturn ? retOrId.billNo : (maybeStoreToken != null ? storeTokenOrBillNo : "");
    final String storeToken = maybeStoreToken ?? storeTokenOrBillNo;
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;
    final String effFy = (fy != null && fy.trim().isNotEmpty) ? fy.trim() : activeFinancialYear.trim();
    try {
      markPermanentlyDeleted(retId, billNo, "", effFy);
      final cleanBNo = billNo.trim().toUpperCase();
      final scopedBNo = cleanBNo.isNotEmpty ? scopeSecondaryKey(cleanBNo, effFy) : "";
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "DELETE_SALE_RETURN",
        "fy": effFy,
        "deletedIds": [retId, if (scopedBNo.isNotEmpty) scopedBNo],
        "sale_event": {
          "id": retId,
          "bill_no": cleanBNo,
          "version": 999999,
          "action": "DELETE",
          "status": "Deleted",
          "client_source": clientSource,
          "payload": {
            "doc_type": "SALE_RETURN",
            "id": retId,
            "billNo": cleanBNo,
            "fy": effFy,
            "is_deleted": 1,
            "isDeleted": 1,
            "status": "Deleted",
          },
        },
      };
      final res = await http.post(Uri.parse(endpoint), headers: _headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static bool applyEventsToLocalSaleReturns(
    List<SaleReturn> localReturns,
    List<Map<String, dynamic>> events, [
    String? targetFyOverride,
  ]) {
    if (events.isEmpty) return false;
    final String effFy = (targetFyOverride != null && targetFyOverride.trim().isNotEmpty)
        ? targetFyOverride.trim()
        : activeFinancialYear.trim();
    bool mutated = false;
    for (final ev in events) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final String billNo = (ev["bill_no"] ?? "").toString().trim().toUpperCase();
      final String action = (ev["action"] ?? "INSERT").toString().toUpperCase();
      final int version = int.tryParse(ev["version"]?.toString() ?? "1") ?? 1;
      final dynamic rawData = ev["sale_data"];
      final bool isSrPayload = rawData is Map &&
          (rawData["doc_type"] == "SALE_RETURN" ||
           rawData["doc_type"] == "CREDIT_NOTE" ||
           (rawData.containsKey("returnType") && !rawData.containsKey("distributorName")));
      final String evFy = (ev["fy"] ?? (rawData is Map ? rawData["fy"] : "") ?? "").toString().trim();
      if (evFy.isNotEmpty && effFy.isNotEmpty && evFy != effFy) continue;
      if (action == "DELETE" || action.startsWith("DELETE_")) {
        final String bNo = (rawData is Map ? (rawData["billNo"] ?? billNo) : billNo).toString().trim().toUpperCase();
        final bool matchesLocal = localReturns.any((r) => (billId.isNotEmpty && r.id.trim() == billId) || (bNo.isNotEmpty && r.billNo.trim().toUpperCase() == bNo));
        if (isSrPayload || matchesLocal) {
          markPermanentlyDeleted(billId, bNo, "", effFy);
          final int before = localReturns.length;
          localReturns.removeWhere((r) => (billId.isNotEmpty && r.id.trim() == billId) || (bNo.isNotEmpty && r.billNo.trim().toUpperCase() == bNo));
          if (localReturns.length != before) mutated = true;
        }
      } else if (isSrPayload && rawData is Map<String, dynamic>) {
        final inc = SaleReturn.fromMap(rawData);
        if (billId.isNotEmpty) inc.id = billId;
        inc.version = version;
        if (!doesEventBelongToActiveFY(rawData, inc.date, effFy)) continue;
        if (action == "CANCEL") inc.status = "Cancelled";
        unmarkPermanentlyDeleted(inc.id, inc.billNo, "", effFy);
        final int idx = localReturns.indexWhere((r) => r.id == inc.id || (inc.billNo.trim().isNotEmpty && r.billNo.trim().toUpperCase() == inc.billNo.trim().toUpperCase()));
        if (idx != -1) {
          if (inc.version >= localReturns[idx].version || inc.updatedAt >= localReturns[idx].updatedAt) {
            localReturns[idx] = inc;
            mutated = true;
          }
        } else {
          localReturns.insert(0, inc);
          mutated = true;
        }
      }
    }
    return mutated;
  }

  static Future<bool> onPurchaseReturnSaved(
    PurchaseReturn ret,
    String storeToken, {
    bool isUpdate = true,
    String clientSource = "APP_MOBILE",
    String? fy,
    String? fyOverride,
  }) async {
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;
    final String? chosenFy = (fyOverride != null && fyOverride.trim().isNotEmpty) ? fyOverride : fy;
    final String effFy = (chosenFy != null && chosenFy.trim().isNotEmpty)
        ? chosenFy.trim()
        : (activeFinancialYear.isNotEmpty ? activeFinancialYear : inferFyFromDate(ret.date));
    try {
      unmarkPermanentlyDeleted(ret.id, ret.billNo, "", effFy);
      recordKnownVersion(ret.id, ret.billNo, ret.version);
      final map = ret.toMap();
      map["doc_type"] = "PURCHASE_RETURN";
      map["fy"] = effFy;
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "PURCHASE_RETURN_SAVED",
        "fy": effFy,
        "entityId": ret.id,
        "unmarkedIds": [ret.id, if (ret.billNo.trim().isNotEmpty) ret.billNo.trim().toUpperCase()],
        "sale_event": {
          "id": ret.id,
          "bill_no": ret.billNo,
          "version": ret.version,
          "action": ret.status == "Cancelled" ? "CANCEL" : "UPDATE",
          "status": ret.status,
          "client_source": clientSource,
          "payload": map,
        },
      };
      final res = await http.post(Uri.parse(endpoint), headers: _headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> onPurchaseReturnDeleted(
    dynamic retOrId,
    String storeTokenOrBillNo, [
    String? maybeStoreToken,
  ]) async {
    return _onPurchaseReturnDeletedInternal(retOrId, storeTokenOrBillNo, maybeStoreToken);
  }

  static Future<bool> _onPurchaseReturnDeletedInternal(
    dynamic retOrId,
    String storeTokenOrBillNo, [
    String? maybeStoreToken,
    String clientSource = "APP_MOBILE",
    String? fy,
  ]) async {
    final String retId = retOrId is PurchaseReturn ? retOrId.id : retOrId.toString();
    final String billNo = retOrId is PurchaseReturn ? retOrId.billNo : (maybeStoreToken != null ? storeTokenOrBillNo : "");
    final String storeToken = maybeStoreToken ?? storeTokenOrBillNo;
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;
    final String effFy = (fy != null && fy.trim().isNotEmpty) ? fy.trim() : activeFinancialYear.trim();
    try {
      markPermanentlyDeleted(retId, billNo, "", effFy);
      final cleanBNo = billNo.trim().toUpperCase();
      final scopedBNo = cleanBNo.isNotEmpty ? scopeSecondaryKey(cleanBNo, effFy) : "";
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "DELETE_PURCHASE_RETURN",
        "fy": effFy,
        "deletedIds": [retId, if (scopedBNo.isNotEmpty) scopedBNo],
        "sale_event": {
          "id": retId,
          "bill_no": cleanBNo,
          "version": 999999,
          "action": "DELETE",
          "status": "Deleted",
          "client_source": clientSource,
          "payload": {
            "doc_type": "PURCHASE_RETURN",
            "id": retId,
            "billNo": cleanBNo,
            "fy": effFy,
            "is_deleted": 1,
            "isDeleted": 1,
            "status": "Deleted",
          },
        },
      };
      final res = await http.post(Uri.parse(endpoint), headers: _headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static bool applyEventsToLocalPurchaseReturns(
    List<PurchaseReturn> localReturns,
    List<Map<String, dynamic>> events, [
    String? targetFyOverride,
  ]) {
    if (events.isEmpty) return false;
    final String effFy = (targetFyOverride != null && targetFyOverride.trim().isNotEmpty)
        ? targetFyOverride.trim()
        : activeFinancialYear.trim();
    bool mutated = false;
    for (final ev in events) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final String billNo = (ev["bill_no"] ?? "").toString().trim().toUpperCase();
      final String action = (ev["action"] ?? "INSERT").toString().toUpperCase();
      final int version = int.tryParse(ev["version"]?.toString() ?? "1") ?? 1;
      final dynamic rawData = ev["sale_data"];
      final bool isPrPayload = rawData is Map &&
          (rawData["doc_type"] == "PURCHASE_RETURN" ||
           rawData["doc_type"] == "DEBIT_NOTE" ||
           (rawData.containsKey("returnType") && rawData.containsKey("distributorName")));
      final String evFy = (ev["fy"] ?? (rawData is Map ? rawData["fy"] : "") ?? "").toString().trim();
      if (evFy.isNotEmpty && effFy.isNotEmpty && evFy != effFy) continue;
      if (action == "DELETE" || action.startsWith("DELETE_")) {
        final String bNo = (rawData is Map ? (rawData["billNo"] ?? billNo) : billNo).toString().trim().toUpperCase();
        final bool matchesLocal = localReturns.any((r) => (billId.isNotEmpty && r.id.trim() == billId) || (bNo.isNotEmpty && r.billNo.trim().toUpperCase() == bNo));
        if (isPrPayload || matchesLocal) {
          markPermanentlyDeleted(billId, bNo, "", effFy);
          final int before = localReturns.length;
          localReturns.removeWhere((r) => (billId.isNotEmpty && r.id.trim() == billId) || (bNo.isNotEmpty && r.billNo.trim().toUpperCase() == bNo));
          if (localReturns.length != before) mutated = true;
        }
      } else if (isPrPayload && rawData is Map<String, dynamic>) {
        final inc = PurchaseReturn.fromMap(rawData);
        if (billId.isNotEmpty) inc.id = billId;
        inc.version = version;
        if (!doesEventBelongToActiveFY(rawData, inc.date, effFy)) continue;
        if (action == "CANCEL") inc.status = "Cancelled";
        unmarkPermanentlyDeleted(inc.id, inc.billNo, "", effFy);
        final int idx = localReturns.indexWhere((r) => r.id == inc.id || (inc.billNo.trim().isNotEmpty && r.billNo.trim().toUpperCase() == inc.billNo.trim().toUpperCase()));
        if (idx != -1) {
          if (inc.version >= localReturns[idx].version || inc.updatedAt >= localReturns[idx].updatedAt) {
            localReturns[idx] = inc;
            mutated = true;
          }
        } else {
          localReturns.insert(0, inc);
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
