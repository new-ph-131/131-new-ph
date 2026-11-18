// FILE: lib/sync_core/d1_sales_ledger_service.dart
// 🛡️ D1 EDGE SALES LEDGER & OPTIMISTIC CONCURRENCY SERVICE (#PH-REV-680)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../logic/app_settings_model.dart';
import '../web_live_sync/web_cloud_config.dart';
import 'modules/sale_challan_sync_module.dart';
import 'modules/purchase_challan_sync_module.dart';

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
    final String fy = normalizeFyString((targetFy != null && targetFy.trim().isNotEmpty)
        ? targetFy.trim()
        : activeFinancialYear.trim());
    if (fy.isEmpty) return true;
    if (rawPayload is Map) {
      final String payloadFy = normalizeFyString((rawPayload["fy"] ?? "").toString());
      if (payloadFy.isNotEmpty) {
        return payloadFy == fy;
      }
      // Check if primary or secondary key has explicit FY scoping (e.g. 2026-27::INV-1)
      final idStr = (rawPayload["id"] ?? rawPayload["sync_id"] ?? rawPayload["bill_id"] ?? "").toString().trim();
      if (idStr.contains("::")) {
        final scopedFy = normalizeFyString(idStr.split("::")[0]);
        if (scopedFy.isNotEmpty) return scopedFy == fy;
      }
      final secStr = (rawPayload["billNo"] ?? rawPayload["bill_no"] ?? rawPayload["internalNo"] ?? "").toString().trim();
      if (secStr.contains("::")) {
        final scopedFy = normalizeFyString(secStr.split("::")[0]);
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
      final String payloadFy = normalizeFyString((rawPayload["fy"] ?? "").toString());
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

  /// 🛡️ Serial Async Mutex for Gravestone SharedPreferences writes
  static Future<void> _gravestonePrefsLock = Future<void>.value();

  static Future<T> _runGravestoneLocked<T>(Future<T> Function() action) {
    final prev = _gravestonePrefsLock;
    final completer = Future<T>(() async {
      try {
        await prev;
      } catch (_) {}
      return await action();
    });
    _gravestonePrefsLock = completer.then((_) {}, onError: (_) {});
    return completer;
  }

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

    // Timestamps (e.g. 1712345678901) or ISO dates or standard UUIDs (including prefixed UUIDs like PUR-UUID-101, SCH-WEB-<ms>, PCH-WEB-<ms>)
    if (RegExp(r"^\d{10,}$").hasMatch(k) || RegExp(r"^\d{4}-\d{2}-\d{2}").hasMatch(k) ||
        RegExp(r"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$").hasMatch(k) ||
        k.contains("-UUID-") ||
        RegExp(r"-WEB-\d{10,}").hasMatch(k) ||
        (k.contains("-") && k.length >= 24)) {
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
      _runGravestoneLocked(() async {
        final prefs = await SharedPreferences.getInstance();
        final existing = prefs.getStringList("d1_permanent_gravestones") ?? [];
        final set = existing.where((k) => !isUnscopedSeriesKey(k)).toSet();
        if (idKey.isNotEmpty && _permanentDeletedKeys.contains(idKey)) set.add(idKey);
        if (cleanSec.isNotEmpty && _permanentDeletedKeys.contains(cleanSec)) set.add(cleanSec);
        if (cleanTer.isNotEmpty && _permanentDeletedKeys.contains(cleanTer)) set.add(cleanTer);
        await prefs.setStringList("d1_permanent_gravestones", set.toList());
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
        if (idKey.isNotEmpty && _permanentDeletedKeys.contains(idKey)) {
          tsMap[idKey] = _permanentDeletedTimestamps[idKey] ?? delTs;
        }
        if (cleanSec.isNotEmpty && _permanentDeletedKeys.contains(cleanSec)) {
          tsMap[cleanSec] = _permanentDeletedTimestamps[cleanSec] ?? delTs;
        }
        if (cleanTer.isNotEmpty && _permanentDeletedKeys.contains(cleanTer)) {
          tsMap[cleanTer] = _permanentDeletedTimestamps[cleanTer] ?? delTs;
        }
        await prefs.setString("d1_permanent_gravestone_ts", jsonEncode(tsMap));
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
      _runGravestoneLocked(() async {
        final prefs = await SharedPreferences.getInstance();
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
        await prefs.setStringList("d1_permanent_gravestones", set.toList());
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
            await prefs.setString("d1_permanent_gravestone_ts", jsonEncode(tsMap));
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  // =========================================================================
  // 🛡️ SALE CHALLAN UUID-FIRST GRAVESTONES & VERSION SHIELD
  // =========================================================================
  /// Checks ONLY whether the immutable SaleChallan UUID [id] itself was permanently deleted.
  /// Never matches a reused series number (e.g. SC-1) so a re-created SaleChallan with a new UUID
  /// is never poisoned by an earlier deleted SaleChallan that had the same challan number.
  static bool isSaleChallanIdDeleted(String id, [String? fy]) {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return false;
    final scopedId = isUnscopedSeriesKey(cleanId) ? scopeSecondaryKey(cleanId, fy) : cleanId;
    return _permanentDeletedKeys.contains(cleanId) ||
        _permanentDeletedKeys.contains(cleanId.toUpperCase()) ||
        (scopedId.isNotEmpty &&
            (_permanentDeletedKeys.contains(scopedId) ||
             _permanentDeletedKeys.contains(scopedId.toUpperCase())));
  }

  static int getSaleChallanSecondaryDeleteTimestamp(String billNo, [String? fy]) {
    final cleanSec = scopeSecondaryKey(billNo, fy);
    if (cleanSec.isEmpty || !_permanentDeletedKeys.contains(cleanSec)) return 0;
    return _permanentDeletedTimestamps[cleanSec] ?? 0;
  }

  static bool isSaleChallanDeleted(
    String id,
    String billNo, [
    String? fy,
    int? recordUpdatedAt,
  ]) {
    final cleanId = id.trim();
    if (isSaleChallanIdDeleted(cleanId, fy)) {
      return true;
    }
    if (cleanId.isNotEmpty) {
      return false;
    }
    final cleanSec = scopeSecondaryKey(billNo, fy);
    if (cleanSec.isEmpty || !_permanentDeletedKeys.contains(cleanSec)) {
      return false;
    }
    if (cleanId.isNotEmpty && recordUpdatedAt != null && recordUpdatedAt > 0) {
      final int secTs = _permanentDeletedTimestamps[cleanSec] ?? 0;
      if (secTs > 0 && recordUpdatedAt > secTs) {
        return false;
      }
    }
    return true;
  }

  static int getSaleChallanIdKnownVersion(String id, [String? fy]) {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return 0;
    final scopedId = isUnscopedSeriesKey(cleanId) ? scopeSecondaryKey(cleanId, fy) : cleanId;
    final v1 = _knownBillVersions[cleanId] ?? 0;
    final v2 = scopedId.isNotEmpty ? (_knownBillVersions[scopedId] ?? 0) : 0;
    return v1 > v2 ? v1 : v2;
  }

  static void markSaleChallanPermanentlyDeleted(String id, String billNo, [String? fy, int? deletedAtMs]) {
    final cleanId = id.trim();
    final cleanBill = billNo.trim().toUpperCase();
    markPermanentlyDeleted(cleanId, cleanBill, "", fy, false, deletedAtMs);
    if (cleanId.isNotEmpty) {
      markPermanentlyDeleted(cleanId.toUpperCase(), "", "", fy, false, deletedAtMs);
    }
  }

  static void unmarkSaleChallanPermanentlyDeleted(String id, String billNo, [String? fy]) {
    final cleanId = id.trim();
    final cleanBill = billNo.trim().toUpperCase();
    unmarkPermanentlyDeleted(cleanId, cleanBill, "", fy, false);
    if (cleanId.isNotEmpty) {
      unmarkPermanentlyDeleted(cleanId.toUpperCase(), "", "", fy, false);
    }
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

  /// Strict UUID-first gravestone check for PurchaseChallans (mirrors [isSaleChallanDeleted]).
  /// When [id] is non-empty, ONLY checks the immutable UUID (via [isPurchaseIdDeleted]),
  /// so a carry-forward or new-FY PurchaseChallan sharing `WPCH-1` / `PCH-1` or supplier `billNo`
  /// is never poisoned by a secondary tombstone from another UUID.
  static bool isPurchaseChallanDeleted(
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
    if (cleanId.isNotEmpty) {
      return false;
    }
    return isPurchaseDeleted(id, partyId, billNo, internalNo, fy, recordUpdatedAt);
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
            "updatedAt": DateTime.now().millisecondsSinceEpoch,
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
        if (data["status"] == "SUCCESS") {
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
            "updatedAt": DateTime.now().millisecondsSinceEpoch,
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
        if (data["status"] == "SUCCESS") {
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

      // Skip Purchase, Challan, Voucher, GST Diary Session, and AppConfig events so they NEVER pollute Sales
      if (rawSale is Map &&
          (rawSale["doc_type"] == "PURCHASE" ||
           rawSale["doc_type"] == "SALE_CHALLAN" ||
           rawSale["doc_type"] == "PURCHASE_CHALLAN" ||
           rawSale["doc_type"] == "CHALLAN" ||
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

  /// Extracts `linkedChallanIds` + item `sourceChallanId` from any D1 `sale_events`
  /// INSERT/UPDATE event and safely marks matching SaleChallans / PurchaseChallans
  /// as `"Billed"` within `targetFy`.
  /// Idempotent & LWW-safe: will NOT mark billed if the event is older than the challan's updatedAt.
  static ({bool saleChallansMutated, bool purchaseChallansMutated}) billLinkedChallansFromSaveEvents({
    required List<Map<String, dynamic>> events,
    required String targetFy,
    List<SaleChallan>? saleChallans,
    List<PurchaseChallan>? purchaseChallans,
    void Function(SaleChallan)? onSaleChallanBilled,
    void Function(PurchaseChallan)? onPurchaseChallanBilled,
  }) {
    if (events.isEmpty || targetFy.trim().isEmpty) {
      return (saleChallansMutated: false, purchaseChallansMutated: false);
    }
    final String effFy = targetFy.trim();
    bool scMutated = false;
    bool pcMutated = false;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;

    final Set<String> deletedBillIdsInBatch = {};
    final Set<String> deletedBillNosInBatch = {};
    for (final ev in events) {
      final String action = (ev["action"] ?? "").toString().toUpperCase();
      final dynamic rawData = ev["sale_data"];
      final bool payloadDel = rawData is Map &&
          ((int.tryParse(rawData["is_deleted"]?.toString() ?? rawData["isDeleted"]?.toString() ?? "0") ?? 0) == 1 ||
              rawData["status"] == "Deleted");
      if (action == "DELETE" || action.startsWith("DELETE_") || payloadDel) {
        final String dId = (ev["bill_id"] ?? (rawData is Map ? (rawData["id"] ?? rawData["billId"]) : "") ?? "").toString().trim();
        final String dNo = (ev["bill_no"] ?? (rawData is Map ? (rawData["billNo"] ?? rawData["internalNo"]) : "") ?? "").toString().trim().toUpperCase();
        if (dId.isNotEmpty) deletedBillIdsInBatch.add(dId);
        if (dNo.isNotEmpty) deletedBillNosInBatch.add(dNo);
      }
    }

    for (final ev in events) {
      final String action = (ev["action"] ?? "").toString().toUpperCase();
      final dynamic rawData = ev["sale_data"];
      final String billId = (ev["bill_id"] ?? (rawData is Map ? (rawData["id"] ?? rawData["billId"]) : "") ?? "").toString().trim();
      final String billNo = (ev["bill_no"] ?? (rawData is Map ? (rawData["billNo"] ?? rawData["internalNo"]) : "") ?? "").toString().trim();
      final bool payloadDel = rawData is Map &&
          ((int.tryParse(rawData["is_deleted"]?.toString() ?? rawData["isDeleted"]?.toString() ?? "0") ?? 0) == 1 ||
              rawData["status"] == "Deleted");
      if (action == "DELETE" || action.startsWith("DELETE_") || payloadDel) {
        continue;
      }
      if ((billId.isNotEmpty && deletedBillIdsInBatch.contains(billId)) ||
          (billNo.isNotEmpty && deletedBillNosInBatch.contains(billNo.toUpperCase()))) {
        continue;
      }
      if (isBillDeleted(billId, billNo, "", effFy)) {
        continue;
      }

      if (rawData is Map &&
          (rawData["doc_type"] == "SALE_CHALLAN" ||
           rawData["doc_type"] == "PURCHASE_CHALLAN" ||
           rawData["doc_type"] == "CHALLAN" ||
           rawData["doc_type"] == "VOUCHER" ||
           rawData["doc_type"] == "SALE_RETURN" ||
           rawData["doc_type"] == "CREDIT_NOTE" ||
           rawData["doc_type"] == "PURCHASE_RETURN" ||
           rawData["doc_type"] == "DEBIT_NOTE" ||
           rawData["doc_type"] == "GST_DIARY_SESSION" ||
           rawData["doc_type"] == "GST_SESSION")) {
        continue;
      }

      final String evFy = normalizeFyString((ev["fy"] ?? (rawData is Map ? rawData["fy"] : "") ?? "").toString());
      final String normEffFy = normalizeFyString(effFy);
      DateTime? evDate;
      if (rawData is Map && rawData["date"] != null) {
        evDate = DateTime.tryParse(rawData["date"].toString());
      }
      if (evFy.isNotEmpty && evFy != normEffFy) continue;
      if (evDate != null && !doesEventBelongToActiveFY(rawData, evDate, normEffFy)) continue;

      final bool isPurchaseEvent = action.contains("PURCHASE") ||
          (rawData is Map &&
              (rawData["doc_type"] == "PURCHASE" ||
               rawData.containsKey("distributorName") ||
               rawData.containsKey("internalNo")));

      final int evTs = int.tryParse(
            (rawData is Map ? (rawData["updatedAt"] ?? rawData["updated_at"]) : null)?.toString() ??
                ev["created_at"]?.toString() ??
                "0",
          ) ??
          0;
      final int evVer = int.tryParse(ev["version"]?.toString() ?? "1") ?? 1;

      final links = ChallanLinkMatcher.extractLinks(
        linkedChallanIds: (rawData is Map && rawData["linkedChallanIds"] is List)
            ? (rawData["linkedChallanIds"] as List)
            : const [],
        items: (rawData is Map && rawData["items"] is List)
            ? (rawData["items"] as List)
            : const [],
      );
      if (links.explicitIds.isEmpty && links.legacyNos.isEmpty) continue;

      final String billPartyId = (rawData is Map ? (rawData["partyId"] ?? "") : "").toString().trim();
      final String billFy = evFy.isNotEmpty
          ? evFy
          : (evDate != null ? deriveFyFromDate(evDate) : normEffFy);

      if (isPurchaseEvent && purchaseChallans != null) {
        for (final ch in purchaseChallans) {
          if (ch.isDeleted == 1) continue;
          final bool match = ChallanLinkMatcher.matchesPurchaseChallan(
            ch,
            explicitIds: links.explicitIds,
            legacyNos: links.legacyNos,
            billPartyId: billPartyId,
            billFy: billFy,
          );
          final String invNo = (rawData is Map ? (rawData["billNo"] ?? rawData["internalNo"] ?? billNo) : billNo).toString().trim();
          if (match && (ch.status != "Billed" || ch.billedInvoiceNo.isEmpty) && (evTs == 0 || ch.updatedAt == 0 || evTs >= ch.updatedAt)) {
            ch.markBilled(
              invoiceFy: billFy,
              invoiceId: billId,
              invoiceNo: invNo,
              invoiceDate: evDate,
            );
            ch.version = (ch.version < evVer ? evVer : ch.version) + 1;
            ch.updatedAt = evTs > ch.updatedAt ? evTs : nowMs;
            onPurchaseChallanBilled?.call(ch);
            pcMutated = true;
          }
        }
      } else if (!isPurchaseEvent && saleChallans != null) {
        for (final ch in saleChallans) {
          if (ch.isDeleted == 1) continue;
          final bool match = ChallanLinkMatcher.matchesSaleChallan(
            ch,
            explicitIds: links.explicitIds,
            legacyNos: links.legacyNos,
            billPartyId: billPartyId,
            billFy: billFy,
          );
          final String invNo = (rawData is Map ? (rawData["billNo"] ?? billNo) : billNo).toString().trim();
          if (match && (ch.status != "Billed" || ch.billedInvoiceNo.isEmpty) && (evTs == 0 || ch.updatedAt == 0 || evTs >= ch.updatedAt)) {
            ch.markBilled(
              invoiceFy: billFy,
              invoiceId: billId,
              invoiceNo: invNo,
              invoiceDate: evDate,
            );
            ch.version = (ch.version < evVer ? evVer : ch.version) + 1;
            ch.updatedAt = evTs > ch.updatedAt ? evTs : nowMs;
            onSaleChallanBilled?.call(ch);
            scMutated = true;
          }
        }
      }
    }
    return (saleChallansMutated: scMutated, purchaseChallansMutated: pcMutated);
  }

  /// Extracts `linkedChallanIds` + item `sourceChallanId`/`sourceChallanNo` from any D1 `sale_events`
  /// DELETE event (paired with local bills before deletion) and safely reverts matching SaleChallans /
  /// PurchaseChallans back to `"Pending"` within `targetFy`.
  /// Idempotent & LWW-safe: will NOT un-bill a challan whose `updatedAt` is strictly newer than the delete event.
  static ({bool saleChallansMutated, bool purchaseChallansMutated}) revertLinkedChallansFromDeleteEvents({
    required List<Map<String, dynamic>> events,
    required String targetFy,
    List<Sale> existingSalesBeforeDelete = const [],
    List<Purchase> existingPurchasesBeforeDelete = const [],
    List<SaleChallan>? saleChallans,
    List<PurchaseChallan>? purchaseChallans,
    void Function(SaleChallan)? onSaleChallanReverted,
    void Function(PurchaseChallan)? onPurchaseChallanReverted,
  }) {
    if (events.isEmpty || targetFy.trim().isEmpty) {
      return (saleChallansMutated: false, purchaseChallansMutated: false);
    }
    final String effFy = targetFy.trim();
    bool scMutated = false;
    bool pcMutated = false;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;

    for (final ev in events) {
      final String action = (ev["action"] ?? "").toString().toUpperCase();
      final dynamic rawData = ev["sale_data"];
      final bool payloadDel = rawData is Map &&
          ((int.tryParse(rawData["is_deleted"]?.toString() ?? rawData["isDeleted"]?.toString() ?? "0") ?? 0) == 1 ||
              rawData["status"] == "Deleted");
      if (!(action == "DELETE" || action.startsWith("DELETE_") || payloadDel)) {
        continue;
      }

      if (rawData is Map &&
          (rawData["doc_type"] == "SALE_CHALLAN" ||
           rawData["doc_type"] == "PURCHASE_CHALLAN" ||
           rawData["doc_type"] == "CHALLAN" ||
           rawData["doc_type"] == "VOUCHER" ||
           rawData["doc_type"] == "SALE_RETURN" ||
           rawData["doc_type"] == "CREDIT_NOTE" ||
           rawData["doc_type"] == "PURCHASE_RETURN" ||
           rawData["doc_type"] == "DEBIT_NOTE" ||
           rawData["doc_type"] == "GST_DIARY_SESSION" ||
           rawData["doc_type"] == "GST_SESSION")) {
        continue;
      }

      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final String billNo = (ev["bill_no"] ?? "").toString().trim();
      final String evFy = normalizeFyString((ev["fy"] ?? (rawData is Map ? rawData["fy"] : "") ?? "").toString());
      final String normEffFy = normalizeFyString(effFy);
      DateTime? evDate;
      if (rawData is Map && rawData["date"] != null) {
        evDate = DateTime.tryParse(rawData["date"].toString());
      }
      if (evFy.isNotEmpty && evFy != normEffFy) continue;
      if (evDate != null && !doesEventBelongToActiveFY(rawData, evDate, normEffFy)) continue;

      final bool isPurchaseEvent = action.contains("PURCHASE") ||
          (rawData is Map &&
              (rawData["doc_type"] == "PURCHASE" ||
               rawData.containsKey("distributorName") ||
               rawData.containsKey("internalNo"))) ||
          (billId.isNotEmpty && existingPurchasesBeforeDelete.any((p) => p.id == billId));

      final int evTs = int.tryParse(
            (rawData is Map ? (rawData["updatedAt"] ?? rawData["updated_at"]) : null)?.toString() ??
                ev["created_at"]?.toString() ??
                "0",
          ) ??
          0;

      final List<dynamic> combinedLinked = <dynamic>[
        if (rawData is Map && rawData["linkedChallanIds"] is List)
          ...(rawData["linkedChallanIds"] as List),
      ];
      final List<dynamic> combinedItems = <dynamic>[
        if (rawData is Map && rawData["items"] is List)
          ...(rawData["items"] as List),
      ];
      String billPartyId = (rawData is Map ? (rawData["partyId"] ?? "") : "").toString().trim();
      String billFy = evFy.isNotEmpty ? evFy : (evDate != null ? deriveFyFromDate(evDate) : normEffFy);

      if (isPurchaseEvent) {
        final String pIntNo = (rawData is Map ? (rawData["internalNo"] ?? "") : "").toString().trim().toUpperCase();
        final String pBillNo = (rawData is Map ? (rawData["billNo"] ?? billNo) : billNo).toString().trim();
        final String pPartyId = billPartyId.toUpperCase();
        for (final p in existingPurchasesBeforeDelete) {
          final bool idMatch = billId.isNotEmpty && p.id == billId;
          final bool intMatch = pIntNo.isNotEmpty && p.internalNo.trim().toUpperCase() == pIntNo && inferFyFromDate(p.date) == normEffFy;
          final bool compMatch = pPartyId.isNotEmpty && pBillNo.isNotEmpty &&
              p.partyId.trim().toUpperCase() == pPartyId &&
              p.billNo.trim() == pBillNo &&
              inferFyFromDate(p.date) == normEffFy;
          if (idMatch || intMatch || compMatch) {
            if (billPartyId.isEmpty && p.partyId.trim().isNotEmpty) billPartyId = p.partyId.trim();
            combinedLinked.addAll(p.linkedChallanIds);
            combinedItems.addAll(p.items);
          }
        }
        final links = ChallanLinkMatcher.extractLinks(
          linkedChallanIds: combinedLinked,
          items: combinedItems,
        );
        final bool hasBilledRef = billId.isNotEmpty || pIntNo.isNotEmpty || pBillNo.isNotEmpty;
        if ((links.explicitIds.isNotEmpty || links.legacyNos.isNotEmpty || hasBilledRef) && purchaseChallans != null) {
          for (final ch in purchaseChallans) {
            if (ch.isDeleted == 1) continue;
            final bool directLinkMatch = (links.explicitIds.isNotEmpty || links.legacyNos.isNotEmpty) &&
                ChallanLinkMatcher.matchesPurchaseChallan(
                  ch,
                  explicitIds: links.explicitIds,
                  legacyNos: links.legacyNos,
                  billPartyId: billPartyId,
                  billFy: billFy,
                );
            final String chBilledFy = normalizeFyString(ch.billedInFy);
            final bool fyOk = chBilledFy.isEmpty || chBilledFy == normEffFy;
            final bool billedRefMatch = fyOk && (
                (billId.isNotEmpty && ch.billedInvoiceId.trim() == billId) ||
                (pIntNo.isNotEmpty && ch.billedInvoiceNo.trim().toUpperCase() == pIntNo) ||
                (pBillNo.isNotEmpty && ch.billedInvoiceNo.trim().toUpperCase() == pBillNo.toUpperCase() &&
                    (pPartyId.isEmpty || ch.partyId.trim().toUpperCase() == pPartyId))
            );
            final bool match = directLinkMatch || billedRefMatch;
            if (match && ch.status != "Pending" && (evTs == 0 || ch.updatedAt == 0 || evTs >= ch.updatedAt)) {
              final String chFy = ch.effectiveOriginalFy.isNotEmpty ? ch.effectiveOriginalFy : effFy;
              final int knownVer = getPurchaseIdKnownVersion(ch.id, chFy);
              final int knownVerEff = chFy != effFy ? getPurchaseIdKnownVersion(ch.id, effFy) : 0;
              final int maxKnown = knownVer > knownVerEff ? knownVer : knownVerEff;
              final int baseVer = ch.version > maxKnown ? ch.version : maxKnown;
              unmarkPurchasePermanentlyDeleted(ch.id, ch.partyId, ch.billNo, ch.internalNo, effFy);
              if (chFy != effFy) {
                unmarkPurchasePermanentlyDeleted(ch.id, ch.partyId, ch.billNo, ch.internalNo, chFy);
              }
              ch.status = "Pending";
              ch.clearBilledMeta();
              ch.version = (baseVer < 1 ? 1 : baseVer) + 1;
              ch.updatedAt = evTs > ch.updatedAt ? evTs : nowMs;
              recordPurchaseKnownVersion(ch.id, ch.partyId, ch.billNo, ch.version, ch.internalNo, chFy);
              if (chFy != effFy) {
                recordPurchaseKnownVersion(ch.id, ch.partyId, ch.billNo, ch.version, ch.internalNo, effFy);
              }
              onPurchaseChallanReverted?.call(ch);
              pcMutated = true;
            }
          }
        }
      } else {
        final String cleanBNo = billNo.trim().toUpperCase();
        for (final s in existingSalesBeforeDelete) {
          final bool idMatch = billId.isNotEmpty && s.id == billId;
          final bool noMatch = cleanBNo.isNotEmpty && s.billNo.trim().toUpperCase() == cleanBNo && inferFyFromDate(s.date) == normEffFy;
          if (idMatch || noMatch) {
            if (billPartyId.isEmpty && s.partyId.trim().isNotEmpty) billPartyId = s.partyId.trim();
            combinedLinked.addAll(s.linkedChallanIds);
            combinedItems.addAll(s.items);
          }
        }
        final links = ChallanLinkMatcher.extractLinks(
          linkedChallanIds: combinedLinked,
          items: combinedItems,
        );
        final bool hasBilledRef = billId.isNotEmpty || cleanBNo.isNotEmpty;
        if ((links.explicitIds.isNotEmpty || links.legacyNos.isNotEmpty || hasBilledRef) && saleChallans != null) {
          for (final ch in saleChallans) {
            if (ch.isDeleted == 1) continue;
            final bool directLinkMatch = (links.explicitIds.isNotEmpty || links.legacyNos.isNotEmpty) &&
                ChallanLinkMatcher.matchesSaleChallan(
                  ch,
                  explicitIds: links.explicitIds,
                  legacyNos: links.legacyNos,
                  billPartyId: billPartyId,
                  billFy: billFy,
                );
            final String chBilledFy = normalizeFyString(ch.billedInFy);
            final bool fyOk = chBilledFy.isEmpty || chBilledFy == normEffFy;
            final bool billedRefMatch = fyOk && (
                (billId.isNotEmpty && ch.billedInvoiceId.trim() == billId) ||
                (cleanBNo.isNotEmpty && ch.billedInvoiceNo.trim().toUpperCase() == cleanBNo)
            );
            final bool match = directLinkMatch || billedRefMatch;
            if (match && ch.status != "Pending" && (evTs == 0 || ch.updatedAt == 0 || evTs >= ch.updatedAt)) {
              final String chFy = ch.effectiveOriginalFy.isNotEmpty ? ch.effectiveOriginalFy : effFy;
              final int knownVer = getSaleChallanIdKnownVersion(ch.id, chFy);
              final int knownVerEff = chFy != effFy ? getSaleChallanIdKnownVersion(ch.id, effFy) : 0;
              final int maxKnown = knownVer > knownVerEff ? knownVer : knownVerEff;
              final int baseVer = ch.version > maxKnown ? ch.version : maxKnown;
              unmarkSaleChallanPermanentlyDeleted(ch.id, ch.billNo, effFy);
              if (chFy != effFy) {
                unmarkSaleChallanPermanentlyDeleted(ch.id, ch.billNo, chFy);
              }
              ch.status = "Pending";
              ch.clearBilledMeta();
              ch.version = (baseVer < 1 ? 1 : baseVer) + 1;
              ch.updatedAt = evTs > ch.updatedAt ? evTs : nowMs;
              recordKnownVersion(ch.id, ch.billNo, ch.version, chFy);
              if (chFy != effFy) {
                recordKnownVersion(ch.id, ch.billNo, ch.version, effFy);
              }
              onSaleChallanReverted?.call(ch);
              scMutated = true;
            }
          }
        }
      }
    }

    return (saleChallansMutated: scMutated, purchaseChallansMutated: pcMutated);
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
          (rawData["doc_type"] == "SALE_CHALLAN" ||
           rawData["doc_type"] == "PURCHASE_CHALLAN" ||
           rawData["doc_type"] == "CHALLAN" ||
           rawData["doc_type"] == "VOUCHER" ||
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


  /// =========================================================================
  /// CHALLAN EDGE LEDGER (SALE CHALLAN & PURCHASE CHALLAN - D1 SEQ + OCC)
  /// =========================================================================

  /// Called when a SaleChallan is created or modified from either App or Web
  static Future<bool> onSaleChallanSaved(
    SaleChallan challan,
    String storeToken, {
    bool isUpdate = false,
    String clientSource = "APP_MOBILE",
    String? fy,
    void Function(int serverSeq)? onServerSeq,
  }) async {
    final String rawFy = (fy != null && fy.trim().isNotEmpty)
        ? fy.trim()
        : (challan.effectiveOriginalFy.isNotEmpty
            ? challan.effectiveOriginalFy
            : (activeFinancialYear.isNotEmpty ? activeFinancialYear.trim() : inferFyFromDate(challan.date)));
    final String effFy = normalizeFyString(rawFy);
    final int prevKnown = getSaleChallanIdKnownVersion(challan.id, effFy);
    unmarkSaleChallanPermanentlyDeleted(challan.id, challan.billNo, effFy);
    final int keepVer = challan.version > prevKnown ? challan.version : prevKnown;
    if (keepVer > 0) {
      recordKnownVersion(challan.id, challan.billNo, keepVer, effFy);
    }
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;

    try {
      final chMap = challan.toMap();
      chMap["doc_type"] = "SALE_CHALLAN";
      chMap["fy"] = effFy;
      if ((chMap["originalFy"] ?? "").toString().trim().isEmpty && effFy.isNotEmpty) {
        chMap["originalFy"] = effFy;
        chMap["original_fy"] = effFy;
      }
      final String cleanBNo = challan.billNo.trim().toUpperCase();
      final String scopedBNo = cleanBNo.isNotEmpty ? scopeSecondaryKey(cleanBNo, effFy) : "";

      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": isUpdate ? "UPDATE_SALE_CHALLAN" : "INSERT_SALE_CHALLAN",
        "entityType": "SALE_CHALLAN",
        "entityId": challan.id,
        "fy": effFy,
        "unmarkedIds": [
          challan.id,
          if (scopedBNo.isNotEmpty) scopedBNo,
          if (cleanBNo.isNotEmpty) cleanBNo,
        ],
        "sale_event": {
          "id": challan.id,
          "bill_no": challan.billNo,
          "version": challan.version,
          "action": isUpdate ? "UPDATE" : "INSERT",
          "status": challan.status,
          "client_source": clientSource,
          "payload": chMap,
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
          recordKnownVersion(challan.id, challan.billNo, challan.version, effFy);
          final int? newSeq = int.tryParse(data["seq"]?.toString() ?? '');
          if (newSeq != null && newSeq > 0) onServerSeq?.call(newSeq);
          return true;
        }
      } else if (res.statusCode == 410) {
        markSaleChallanPermanentlyDeleted(challan.id, challan.billNo, effFy);
        return false;
      } else if (res.statusCode == 409) {
        try {
          final data = jsonDecode(res.body);
          final int serverVer = int.tryParse(data["current_version"]?.toString() ?? "0") ?? 0;
          if (data["status"] == "DELETED" || serverVer >= 99999) {
            markSaleChallanPermanentlyDeleted(challan.id, challan.billNo, effFy);
            return false;
          }
          if (serverVer > 0) {
            recordKnownVersion(challan.id, challan.billNo, serverVer, effFy);
            challan.version = serverVer + 1;
            return await onSaleChallanSaved(
              challan,
              storeToken,
              isUpdate: true,
              clientSource: clientSource,
              fy: effFy,
            );
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] onSaleChallanSaved Network Error: $e");
    }
    return false;
  }


  /// Called when a SaleChallan is cancelled (Middle-Challan Cancel)
  static Future<bool> onSaleChallanCancelled(
    SaleChallan challan,
    String storeToken, {
    String clientSource = "APP_MOBILE",
    String? fy,
    Map<String, dynamic>? audit,
    void Function(int serverSeq)? onServerSeq,
  }) async {
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;
    final String effFy = normalizeFyString(
      (fy != null && fy.trim().isNotEmpty)
          ? fy.trim()
          : (challan.effectiveOriginalFy.isNotEmpty ? challan.effectiveOriginalFy : activeFinancialYear.trim()),
    );
    final String cleanBNo = challan.billNo.trim().toUpperCase();
    final String scopedBNo = cleanBNo.isNotEmpty ? scopeSecondaryKey(cleanBNo, effFy) : "";
    try {
      final chMap = challan.toMap();
      chMap["doc_type"] = "SALE_CHALLAN";
      chMap["status"] = "Cancelled";
      chMap["isDeleted"] = 0;
      chMap["is_deleted"] = 0;
      chMap["originalFy"] = effFy;
      chMap["fy"] = effFy;
      if (audit != null && audit.isNotEmpty) {
        chMap["audit"] = audit;
      }

      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "unmarkedIds": [
          challan.id,
          if (scopedBNo.isNotEmpty) scopedBNo,
          if (cleanBNo.isNotEmpty) cleanBNo,
        ],
        "sale_event": {
          "id": challan.id,
          "bill_no": challan.billNo,
          "version": challan.version,
          "action": "CANCEL",
          "status": "Cancelled",
          "client_source": clientSource,
          "payload": chMap,
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
          recordKnownVersion(challan.id, challan.billNo, challan.version, effFy);
          return true;
        }
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] onSaleChallanCancelled Network Error: $e");
    }
    return false;
  }

  /// Called when a SaleChallan is permanently deleted from either App or Web
  static Future<bool> onSaleChallanDeleted(
    dynamic challanOrId,
    String storeToken, {
    String billNo = "",
    String clientSource = "APP_MOBILE",
    String? fy,
    int? deletedAtMs,
    Map<String, dynamic>? hwmRollback,
    Map<String, dynamic>? audit,
    void Function(int serverSeq)? onServerSeq,
  }) async {
    final String cId = challanOrId is SaleChallan ? challanOrId.id.trim() : challanOrId.toString().trim();
    final String cBill = challanOrId is SaleChallan
        ? challanOrId.billNo.trim()
        : billNo.trim();
    final String rawFy = (fy != null && fy.trim().isNotEmpty)
        ? fy.trim()
        : (challanOrId is SaleChallan && challanOrId.effectiveOriginalFy.isNotEmpty
            ? challanOrId.effectiveOriginalFy
            : activeFinancialYear.trim());
    final String effFy = normalizeFyString(rawFy);
    final int delTs = (deletedAtMs != null && deletedAtMs > 0)
        ? deletedAtMs
        : (challanOrId is SaleChallan && challanOrId.updatedAt > 0
            ? challanOrId.updatedAt
            : DateTime.now().millisecondsSinceEpoch);

    markSaleChallanPermanentlyDeleted(cId, cBill, effFy, delTs);
    if (cId.isNotEmpty) {
      recordKnownVersion(cId, "", 999999, effFy);
    }
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;

    try {
      final String cleanBNo = cBill.toUpperCase();
      final String scopedBNo = cleanBNo.isNotEmpty ? scopeSecondaryKey(cleanBNo, effFy) : "";
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "DELETE_SALE_CHALLAN",
        "entityType": "SALE_CHALLAN",
        "entityId": cId,
        "fy": effFy,
        "deletedIds": [
          if (cId.isNotEmpty) cId,
          if (scopedBNo.isNotEmpty) scopedBNo,
        ],
        "sale_event": {
          "id": cId,
          "bill_no": cleanBNo,
          "version": 999999,
          "action": "DELETE",
          "status": "Deleted",
          "client_source": clientSource,
          "payload": {
            "doc_type": "SALE_CHALLAN",
            "id": cId,
            "billNo": cleanBNo,
            "fy": effFy,
            "originalFy": effFy,
            "original_fy": effFy,
            "is_deleted": 1,
            "isDeleted": 1,
            "status": "Deleted",
            "updatedAt": delTs,
            if (hwmRollback != null && hwmRollback.isNotEmpty) "hwmRollback": hwmRollback,
            if (audit != null && audit.isNotEmpty) "audit": audit,
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
          final int? newSeq = int.tryParse(data["seq"]?.toString() ?? '');
          if (newSeq != null && newSeq > 0) onServerSeq?.call(newSeq);
        } catch (_) {}
        return true;
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] onSaleChallanDeleted Network Error: $e");
    }
    return false;
  }

  /// Merges incoming D1 sale_events for SaleChallan into local SaleChallans list
  static bool applyEventsToLocalSaleChallans(
    List<SaleChallan> localChallans,
    List<Map<String, dynamic>> events, [
    String? targetFyOverride,
  ]) {
    if (events.isEmpty) return false;
    final String effFy = normalizeFyString(
      (targetFyOverride != null && targetFyOverride.trim().isNotEmpty)
          ? targetFyOverride.trim()
          : activeFinancialYear.trim(),
    );
    final bool isStrictFyVaultSlice = targetFyOverride != null && targetFyOverride.trim().isNotEmpty;
    bool mutated = false;

    for (final ev in events) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final String billNo = (ev["bill_no"] ?? "").toString().trim();
      final String action = (ev["action"] ?? "INSERT").toString().toUpperCase();
      final int version = int.tryParse(ev["version"]?.toString() ?? "1") ?? 1;
      final dynamic rawData = ev["sale_data"];

      final String docType = rawData is Map ? (rawData["doc_type"] ?? "").toString().trim().toUpperCase() : "";
      final bool isSaleChallanDoc = docType == "SALE_CHALLAN" ||
          docType == "CHALLAN" ||
          action.contains("SALE_CHALLAN");

      final bool payloadIsDeleted = rawData is Map &&
          ((int.tryParse(rawData["is_deleted"]?.toString() ?? rawData["isDeleted"]?.toString() ?? "0") ?? 0) == 1 ||
              rawData["status"] == "Deleted");
      final bool isDeleteEvt = action == "DELETE" || action.startsWith("DELETE_") || payloadIsDeleted;

      if (!isSaleChallanDoc) {
        // On generic DELETE without explicit doc_type, only process if billId matches an existing local SaleChallan
        if (!(isDeleteEvt && docType.isEmpty && billId.isNotEmpty && localChallans.any((c) => c.id.trim() == billId))) {
          continue;
        }
      }

      final String evFy = normalizeFyString(
        (rawData is Map ? (rawData["originalFy"] ?? rawData["original_fy"] ?? rawData["fy"]) : null)?.toString() ??
            (ev["fy"] ?? "").toString(),
      );
      DateTime? evDate;
      if (rawData is Map && rawData["date"] != null) {
        evDate = DateTime.tryParse(rawData["date"].toString());
      }
      final String resolvedEvFy = evFy.isNotEmpty
          ? evFy
          : (evDate != null ? inferFyFromDate(evDate) : effFy);

      if (isDeleteEvt) {
        final String cleanBNo = (rawData is Map ? (rawData["billNo"] ?? billNo) : billNo).toString().trim().toUpperCase();
        final int delTs = int.tryParse(
              (rawData is Map ? (rawData["updatedAt"] ?? rawData["updated_at"]) : null)?.toString() ??
                  ev["created_at"]?.toString() ??
                  "0",
            ) ??
            0;
        final String scopeFy = resolvedEvFy.isNotEmpty ? resolvedEvFy : effFy;
        final bool hasActiveNewChallan = localChallans.any((c) =>
            c.id.trim() != billId &&
            cleanBNo.isNotEmpty &&
            c.billNo.trim().toUpperCase() == cleanBNo &&
            c.isDeleted != 1 &&
            (scopeFy.isEmpty || c.effectiveOriginalFy == scopeFy));

        if (billId.isNotEmpty) {
          markPermanentlyDeleted(billId, "", "", scopeFy, false, delTs > 0 ? delTs : null);
          recordKnownVersion(billId, "", version > 99999 ? version : 999999, scopeFy);
        }
        if (!hasActiveNewChallan && cleanBNo.isNotEmpty) {
          markSaleChallanPermanentlyDeleted(billId, cleanBNo, scopeFy, delTs > 0 ? delTs : null);
        }

        final int beforeLen = localChallans.length;
        localChallans.removeWhere((c) {
          if (c.status.trim().toUpperCase() == "BILLED") return false;
          if (billId.isNotEmpty && c.id.trim() == billId) return true;
          if (!hasActiveNewChallan && cleanBNo.isNotEmpty && c.id.trim().isEmpty && c.billNo.trim().toUpperCase() == cleanBNo) {
            return scopeFy.isEmpty || c.effectiveOriginalFy == scopeFy;
          }
          return false;
        });
        if (localChallans.length != beforeLen) mutated = true;
      } else if (rawData is Map<String, dynamic>) {
        final incoming = SaleChallan.fromMap(rawData);
        if (billId.isNotEmpty) incoming.id = billId;
        incoming.version = version;
        if (incoming.originalFy.isEmpty && resolvedEvFy.isNotEmpty) {
          incoming.originalFy = resolvedEvFy;
        }
        final String challanFy = incoming.effectiveOriginalFy.isNotEmpty ? incoming.effectiveOriginalFy : effFy;

        // FY Isolation with Cross-FY Pending Challan support on active memory list
        if (effFy.isNotEmpty && challanFy.isNotEmpty) {
          if (compareFyStrings(challanFy, effFy) > 0) {
            continue; // 🛡️ Hard reject: Future-FY challan must NEVER enter older FY local list!
          }
          if (challanFy != effFy) {
            final bool alreadyInLocal = incoming.id.trim().isNotEmpty && localChallans.any((c) => c.id.trim() == incoming.id.trim());
            final bool isCrossFyPendingAllowed = !isStrictFyVaultSlice &&
                (incoming.status.trim().toUpperCase() == "PENDING" || alreadyInLocal);
            if (!isCrossFyPendingAllowed) {
              continue;
            }
          }
        }

        if (incoming.id.trim().isNotEmpty) {
          if (isSaleChallanIdDeleted(incoming.id, challanFy)) {
            continue;
          }
          final int knownIdVer = getSaleChallanIdKnownVersion(incoming.id, challanFy);
          if (knownIdVer >= 99999 || version < knownIdVer) {
            continue;
          }
        } else {
          if (isSaleChallanDeleted(incoming.id, incoming.billNo, challanFy, incoming.updatedAt)) {
            continue;
          }
        }

        unmarkSaleChallanPermanentlyDeleted(incoming.id, incoming.billNo, challanFy);
        recordKnownVersion(incoming.id, incoming.billNo, version, challanFy);

        final int existingIdx = localChallans.indexWhere((c) {
          if (incoming.id.trim().isNotEmpty && c.id.trim().isNotEmpty) {
            return c.id.trim() == incoming.id.trim();
          }
          if (incoming.id.trim().isEmpty && c.id.trim().isEmpty && incoming.billNo.trim().isNotEmpty) {
            return c.billNo.trim().toUpperCase() == incoming.billNo.trim().toUpperCase() &&
                c.effectiveOriginalFy == incoming.effectiveOriginalFy;
          }
          return false;
        });

        if (existingIdx != -1) {
          final local = localChallans[existingIdx];
          final int localRank = SaleChallanSyncModule.statusRank(local.status);
          final int incRank = SaleChallanSyncModule.statusRank(incoming.status);
          if (localRank > incRank &&
              (version < local.version ||
                  (version == local.version && incoming.updatedAt <= local.updatedAt))) {
            continue;
          }
          if (version > local.version ||
              (version == local.version &&
                  (incoming.updatedAt > local.updatedAt ||
                      (incoming.updatedAt == local.updatedAt && incRank >= localRank)))) {
            if (incoming.status == "Billed" && incoming.billedInvoiceNo.isEmpty && local.billedInvoiceNo.isNotEmpty) {
              incoming.billedInFy = local.billedInFy;
              incoming.billedInvoiceId = local.billedInvoiceId;
              incoming.billedInvoiceNo = local.billedInvoiceNo;
              incoming.billedDate = local.billedDate;
            }
            localChallans[existingIdx] = incoming;
            mutated = true;
          }
        } else {
          localChallans.insert(0, incoming);
          mutated = true;
        }
      }
    }

    return mutated;
  }

  /// Called when a PurchaseChallan is created or modified from either App or Web
  static Future<bool> onPurchaseChallanSaved(
    PurchaseChallan challan,
    String storeToken, {
    bool isUpdate = false,
    String clientSource = "APP_MOBILE",
    String? fy,
    void Function(int serverSeq)? onServerSeq,
  }) async {
    final String rawFy = (fy != null && fy.trim().isNotEmpty)
        ? fy.trim()
        : (challan.effectiveOriginalFy.isNotEmpty
            ? challan.effectiveOriginalFy
            : (activeFinancialYear.isNotEmpty ? activeFinancialYear.trim() : inferFyFromDate(challan.date)));
    final String effFy = normalizeFyString(rawFy);
    final int prevKnown = getPurchaseIdKnownVersion(challan.id, effFy);
    unmarkPurchasePermanentlyDeleted(
      challan.id,
      challan.partyId,
      challan.billNo,
      challan.internalNo,
      effFy,
    );
    final int keepVer = challan.version > prevKnown ? challan.version : prevKnown;
    if (keepVer > 0) {
      recordPurchaseKnownVersion(
        challan.id,
        challan.partyId,
        challan.billNo,
        keepVer,
        challan.internalNo,
        effFy,
      );
    }
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;

    try {
      final chMap = challan.toMap();
      chMap["doc_type"] = "PURCHASE_CHALLAN";
      chMap["fy"] = effFy;
      if ((chMap["originalFy"] ?? "").toString().trim().isEmpty && effFy.isNotEmpty) {
        chMap["originalFy"] = effFy;
        chMap["original_fy"] = effFy;
      }
      final String cleanParty = challan.partyId.trim().toUpperCase();
      final String cleanBill = challan.billNo.trim();
      final String cleanInt = challan.internalNo.trim().toUpperCase();
      final String scopedInt = cleanInt.isNotEmpty ? scopeSecondaryKey(cleanInt, effFy) : "";
      final String compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty)
          ? scopeSecondaryKey("${cleanParty}_$cleanBill", effFy, true)
          : "";
      final String compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
          ? scopeSecondaryKey("${cleanParty}_${cleanBill}_$cleanInt", effFy, true)
          : "";
      final String refNo = cleanInt.isNotEmpty ? cleanInt : cleanBill;

      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": isUpdate ? "UPDATE_PURCHASE_CHALLAN" : "INSERT_PURCHASE_CHALLAN",
        "entityType": "PURCHASE_CHALLAN",
        "entityId": challan.id,
        "fy": effFy,
        "unmarkedIds": [
          challan.id,
          if (scopedInt.isNotEmpty) scopedInt,
          if (compKey2.isNotEmpty) compKey2,
          if (compKey3.isNotEmpty) compKey3,
        ],
        "sale_event": {
          "id": challan.id,
          "bill_no": refNo,
          "version": challan.version,
          "action": isUpdate ? "UPDATE" : "INSERT",
          "status": challan.status,
          "client_source": clientSource,
          "payload": chMap,
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
            challan.id,
            challan.partyId,
            challan.billNo,
            challan.version,
            challan.internalNo,
            effFy,
          );
          final int? newSeq = int.tryParse(data["seq"]?.toString() ?? '');
          if (newSeq != null && newSeq > 0) onServerSeq?.call(newSeq);
          return true;
        }
      } else if (res.statusCode == 410) {
        markPurchasePermanentlyDeleted(
          challan.id,
          challan.partyId,
          challan.billNo,
          challan.internalNo,
          effFy,
        );
        return false;
      } else if (res.statusCode == 409) {
        try {
          final data = jsonDecode(res.body);
          final int serverVer = int.tryParse(data["current_version"]?.toString() ?? "0") ?? 0;
          if (data["status"] == "DELETED" || serverVer >= 99999) {
            markPurchasePermanentlyDeleted(
              challan.id,
              challan.partyId,
              challan.billNo,
              challan.internalNo,
              effFy,
            );
            return false;
          }
          if (serverVer > 0) {
            recordPurchaseKnownVersion(
              challan.id,
              challan.partyId,
              challan.billNo,
              serverVer,
              challan.internalNo,
              effFy,
            );
            challan.version = serverVer + 1;
            return await onPurchaseChallanSaved(
              challan,
              storeToken,
              isUpdate: true,
              clientSource: clientSource,
              fy: effFy,
            );
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] onPurchaseChallanSaved Network Error: $e");
    }
    return false;
  }


  /// Called when a PurchaseChallan is cancelled (Middle-Challan Cancel)
  static Future<bool> onPurchaseChallanCancelled(
    PurchaseChallan challan,
    String storeToken, {
    String clientSource = "APP_MOBILE",
    String? fy,
    Map<String, dynamic>? audit,
    void Function(int serverSeq)? onServerSeq,
  }) async {
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;
    final String effFy = normalizeFyString(
      (fy != null && fy.trim().isNotEmpty)
          ? fy.trim()
          : (challan.effectiveOriginalFy.isNotEmpty ? challan.effectiveOriginalFy : activeFinancialYear.trim()),
    );
    final String cleanINo = challan.internalNo.trim().toUpperCase();
    final String cleanBNo = challan.billNo.trim();
    final String cleanPId = challan.partyId.trim().toUpperCase();
    final String scopedINo = cleanINo.isNotEmpty ? scopeSecondaryKey(cleanINo, effFy) : "";
    final String compKey2 = (cleanPId.isNotEmpty && cleanBNo.isNotEmpty) ? "${cleanPId}_$cleanBNo" : "";
    final String compKey3 = PurchaseChallanSyncModule.makeCompositeKey(cleanPId, cleanBNo, cleanINo);
    final String scopedComp2 = compKey2.isNotEmpty ? scopeSecondaryKey(compKey2, effFy, true) : "";
    final String scopedComp3 = compKey3.isNotEmpty ? scopeSecondaryKey(compKey3, effFy, true) : "";

    try {
      final chMap = challan.toMap();
      chMap["doc_type"] = "PURCHASE_CHALLAN";
      chMap["status"] = "Cancelled";
      chMap["isDeleted"] = 0;
      chMap["is_deleted"] = 0;
      chMap["originalFy"] = effFy;
      chMap["fy"] = effFy;
      if (audit != null && audit.isNotEmpty) {
        chMap["audit"] = audit;
      }

      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "unmarkedIds": [
          challan.id,
          if (scopedINo.isNotEmpty) scopedINo,
          if (cleanINo.isNotEmpty) cleanINo,
          if (scopedComp2.isNotEmpty) scopedComp2,
          if (scopedComp3.isNotEmpty) scopedComp3,
        ],
        "sale_event": {
          "id": challan.id,
          "bill_no": challan.billNo,
          "version": challan.version,
          "action": "CANCEL",
          "status": "Cancelled",
          "client_source": clientSource,
          "payload": chMap,
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
            challan.id,
            challan.partyId,
            challan.billNo,
            challan.version,
            challan.internalNo,
            effFy,
          );
          return true;
        }
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] onPurchaseChallanCancelled Network Error: $e");
    }
    return false;
  }

  /// Called when a PurchaseChallan is permanently deleted from either App or Web
  static Future<bool> onPurchaseChallanDeleted(
    dynamic challanOrId,
    String storeToken, {
    String partyId = "",
    String billNo = "",
    String internalNo = "",
    String clientSource = "APP_MOBILE",
    String? fy,
    int? deletedAtMs,
    Map<String, dynamic>? hwmRollback,
    Map<String, dynamic>? audit,
    void Function(int serverSeq)? onServerSeq,
  }) async {
    final String cId = challanOrId is PurchaseChallan ? challanOrId.id.trim() : challanOrId.toString().trim();
    final String cParty = challanOrId is PurchaseChallan ? challanOrId.partyId.trim() : partyId.trim();
    final String cBill = challanOrId is PurchaseChallan ? challanOrId.billNo.trim() : billNo.trim();
    final String cInt = challanOrId is PurchaseChallan ? challanOrId.internalNo.trim() : internalNo.trim();
    final String rawFy = (fy != null && fy.trim().isNotEmpty)
        ? fy.trim()
        : (challanOrId is PurchaseChallan && challanOrId.effectiveOriginalFy.isNotEmpty
            ? challanOrId.effectiveOriginalFy
            : activeFinancialYear.trim());
    final String effFy = normalizeFyString(rawFy);
    final int delTs = (deletedAtMs != null && deletedAtMs > 0)
        ? deletedAtMs
        : (challanOrId is PurchaseChallan && challanOrId.updatedAt > 0
            ? challanOrId.updatedAt
            : DateTime.now().millisecondsSinceEpoch);

    markPurchasePermanentlyDeleted(cId, cParty, cBill, cInt, effFy, delTs);
    if (cId.isNotEmpty) {
      recordKnownVersion(cId, "", 999999, effFy);
    }
    if (!USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;

    try {
      final String cleanParty = cParty.toUpperCase();
      final String cleanBill = cBill;
      final String cleanInt = cInt.toUpperCase();
      final String scopedInt = cleanInt.isNotEmpty ? scopeSecondaryKey(cleanInt, effFy) : "";
      final String compKey2 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty)
          ? scopeSecondaryKey("${cleanParty}_$cleanBill", effFy, true)
          : "";
      final String compKey3 = (cleanParty.isNotEmpty && cleanBill.isNotEmpty && cleanInt.isNotEmpty)
          ? scopeSecondaryKey("${cleanParty}_${cleanBill}_$cleanInt", effFy, true)
          : "";

      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "DELETE_PURCHASE_CHALLAN",
        "entityType": "PURCHASE_CHALLAN",
        "entityId": cId,
        "fy": effFy,
        "deletedIds": [
          if (cId.isNotEmpty) cId,
          if (scopedInt.isNotEmpty) scopedInt,
          if (compKey2.isNotEmpty) compKey2,
          if (compKey3.isNotEmpty) compKey3,
        ],
        "sale_event": {
          "id": cId,
          "bill_no": cleanInt.isNotEmpty ? cleanInt : cleanBill,
          "version": 999999,
          "action": "DELETE",
          "status": "Deleted",
          "client_source": clientSource,
          "payload": {
            "doc_type": "PURCHASE_CHALLAN",
            "id": cId,
            "partyId": cParty,
            "billNo": cBill,
            "internalNo": cInt,
            "fy": effFy,
            "originalFy": effFy,
            "original_fy": effFy,
            "is_deleted": 1,
            "isDeleted": 1,
            "status": "Deleted",
            "updatedAt": delTs,
            if (hwmRollback != null && hwmRollback.isNotEmpty) "hwmRollback": hwmRollback,
            if (audit != null && audit.isNotEmpty) "audit": audit,
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
          final int? newSeq = int.tryParse(data["seq"]?.toString() ?? '');
          if (newSeq != null && newSeq > 0) onServerSeq?.call(newSeq);
        } catch (_) {}
        return true;
      }
    } catch (e) {
      debugPrint("⚠ [D1SalesLedger] onPurchaseChallanDeleted Network Error: $e");
    }
    return false;
  }

  /// Merges incoming D1 sale_events for PurchaseChallan into local PurchaseChallans list
  static bool applyEventsToLocalPurchaseChallans(
    List<PurchaseChallan> localChallans,
    List<Map<String, dynamic>> events, [
    String? targetFyOverride,
  ]) {
    if (events.isEmpty) return false;
    final String effFy = normalizeFyString(
      (targetFyOverride != null && targetFyOverride.trim().isNotEmpty)
          ? targetFyOverride.trim()
          : activeFinancialYear.trim(),
    );
    final bool isStrictFyVaultSlice = targetFyOverride != null && targetFyOverride.trim().isNotEmpty;
    bool mutated = false;

    for (final ev in events) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final String billNo = (ev["bill_no"] ?? "").toString().trim();
      final String action = (ev["action"] ?? "INSERT").toString().toUpperCase();
      final int version = int.tryParse(ev["version"]?.toString() ?? "1") ?? 1;
      final dynamic rawData = ev["sale_data"];

      final String docType = rawData is Map ? (rawData["doc_type"] ?? "").toString().trim().toUpperCase() : "";
      final bool isPurchaseChallanDoc = docType == "PURCHASE_CHALLAN" ||
          action.contains("PURCHASE_CHALLAN");

      final bool payloadIsDeleted = rawData is Map &&
          ((int.tryParse(rawData["is_deleted"]?.toString() ?? rawData["isDeleted"]?.toString() ?? "0") ?? 0) == 1 ||
              rawData["status"] == "Deleted");
      final bool isDeleteEvt = action == "DELETE" || action.startsWith("DELETE_") || payloadIsDeleted;

      if (!isPurchaseChallanDoc) {
        if (!(isDeleteEvt && docType.isEmpty && billId.isNotEmpty && localChallans.any((c) => c.id.trim() == billId))) {
          continue;
        }
      }

      final String evFy = normalizeFyString(
        (rawData is Map ? (rawData["originalFy"] ?? rawData["original_fy"] ?? rawData["fy"]) : null)?.toString() ??
            (ev["fy"] ?? "").toString(),
      );
      DateTime? evDate;
      if (rawData is Map && rawData["date"] != null) {
        evDate = DateTime.tryParse(rawData["date"].toString());
      }
      final String resolvedEvFy = evFy.isNotEmpty
          ? evFy
          : (evDate != null ? inferFyFromDate(evDate) : effFy);

      if (isDeleteEvt) {
        final String partyId = (rawData is Map ? (rawData["partyId"] ?? "") : "").toString().trim().toUpperCase();
        final String pBillNo = (rawData is Map ? (rawData["billNo"] ?? billNo) : billNo).toString().trim();
        final String intNo = (rawData is Map ? (rawData["internalNo"] ?? "") : "").toString().trim().toUpperCase();
        final int delTs = int.tryParse(
              (rawData is Map ? (rawData["updatedAt"] ?? rawData["updated_at"]) : null)?.toString() ??
                  ev["created_at"]?.toString() ??
                  "0",
            ) ??
            0;
        final String scopeFy = resolvedEvFy.isNotEmpty ? resolvedEvFy : effFy;
        final bool hasActiveNewChallan = localChallans.any((c) =>
            c.id.trim() != billId &&
            c.isDeleted != 1 &&
            (scopeFy.isEmpty || c.effectiveOriginalFy == scopeFy) &&
            ((intNo.isNotEmpty && c.internalNo.trim().toUpperCase() == intNo) ||
                (partyId.isNotEmpty && pBillNo.isNotEmpty &&
                    c.partyId.trim().toUpperCase() == partyId &&
                    c.billNo.trim() == pBillNo)));

        if (billId.isNotEmpty) {
          markPermanentlyDeleted(billId, "", "", scopeFy, false, delTs > 0 ? delTs : null);
          if (hasActiveNewChallan) {
            recordKnownVersion(billId, "", version > 99999 ? version : 999999, scopeFy);
          } else {
            recordPurchaseKnownVersion(billId, partyId, pBillNo, version > 99999 ? version : 999999, intNo, scopeFy);
          }
        }
        if (!hasActiveNewChallan && (intNo.isNotEmpty || partyId.isNotEmpty)) {
          markPurchasePermanentlyDeleted(billId, partyId, pBillNo, intNo, scopeFy, delTs > 0 ? delTs : null);
        }

        final int beforeLen = localChallans.length;
        localChallans.removeWhere((c) {
          if (c.status.trim().toUpperCase() == "BILLED") return false;
          if (billId.isNotEmpty && c.id.trim() == billId) return true;
          if (!hasActiveNewChallan && c.id.trim().isEmpty && (scopeFy.isEmpty || c.effectiveOriginalFy == scopeFy)) {
            if (intNo.isNotEmpty && c.internalNo.trim().toUpperCase() == intNo) return true;
            if (partyId.isNotEmpty && pBillNo.isNotEmpty &&
                c.partyId.trim().toUpperCase() == partyId &&
                c.billNo.trim() == pBillNo) {
              return true;
            }
          }
          return false;
        });
        if (localChallans.length != beforeLen) mutated = true;
      } else if (rawData is Map<String, dynamic>) {
        final incoming = PurchaseChallan.fromMap(rawData);
        if (billId.isNotEmpty) incoming.id = billId;
        incoming.version = version;
        if (incoming.originalFy.isEmpty && resolvedEvFy.isNotEmpty) {
          incoming.originalFy = resolvedEvFy;
        }
        final String challanFy = incoming.effectiveOriginalFy.isNotEmpty ? incoming.effectiveOriginalFy : effFy;

        if (effFy.isNotEmpty && challanFy.isNotEmpty) {
          if (compareFyStrings(challanFy, effFy) > 0) {
            continue; // 🛡️ Hard reject: Future-FY purchase challan must NEVER enter older FY local list!
          }
          if (challanFy != effFy) {
            final bool alreadyInLocal = incoming.id.trim().isNotEmpty && localChallans.any((c) => c.id.trim() == incoming.id.trim());
            final bool isCrossFyPendingAllowed = !isStrictFyVaultSlice &&
                (incoming.status.trim().toUpperCase() == "PENDING" || alreadyInLocal);
            if (!isCrossFyPendingAllowed) {
              continue;
            }
          }
        }

        if (incoming.id.trim().isNotEmpty) {
          if (isPurchaseIdDeleted(incoming.id, challanFy)) {
            continue;
          }
          final int knownIdVer = getPurchaseIdKnownVersion(incoming.id, challanFy);
          if (knownIdVer >= 99999 || version < knownIdVer) {
            continue;
          }
        } else {
          if (isPurchaseDeleted(
            incoming.id,
            incoming.partyId,
            incoming.billNo,
            incoming.internalNo,
            challanFy,
            incoming.updatedAt,
          )) {
            continue;
          }
        }

        unmarkPurchasePermanentlyDeleted(
          incoming.id,
          incoming.partyId,
          incoming.billNo,
          incoming.internalNo,
          challanFy,
        );
        recordPurchaseKnownVersion(
          incoming.id,
          incoming.partyId,
          incoming.billNo,
          version,
          incoming.internalNo,
          challanFy,
        );

        final String cleanInt = incoming.internalNo.trim().toUpperCase();
        final String cleanBill = incoming.billNo.trim();
        final String cleanParty = incoming.partyId.trim().toUpperCase();
        final int existingIdx = localChallans.indexWhere((c) {
          if (incoming.id.trim().isNotEmpty && c.id.trim().isNotEmpty) {
            return c.id.trim() == incoming.id.trim();
          }
          if (incoming.id.trim().isEmpty || c.id.trim().isEmpty) {
            if (cleanInt.isNotEmpty &&
                c.internalNo.trim().toUpperCase() == cleanInt &&
                c.effectiveOriginalFy == incoming.effectiveOriginalFy) {
              if (cleanBill.isNotEmpty && cleanParty.isNotEmpty &&
                  c.billNo.trim().isNotEmpty && c.partyId.trim().isNotEmpty) {
                return c.billNo.trim() == cleanBill && c.partyId.trim().toUpperCase() == cleanParty;
              }
              return true;
            }
          }
          return false;
        });

        if (existingIdx != -1) {
          final local = localChallans[existingIdx];
          final int localRank = PurchaseChallanSyncModule.statusRank(local.status);
          final int incRank = PurchaseChallanSyncModule.statusRank(incoming.status);
          if (localRank > incRank &&
              (version < local.version ||
                  (version == local.version && incoming.updatedAt <= local.updatedAt))) {
            continue;
          }
          if (version > local.version ||
              (version == local.version &&
                  (incoming.updatedAt > local.updatedAt ||
                      (incoming.updatedAt == local.updatedAt && incRank >= localRank)))) {
            if (incoming.status == "Billed" && incoming.billedInvoiceNo.isEmpty && local.billedInvoiceNo.isNotEmpty) {
              incoming.billedInFy = local.billedInFy;
              incoming.billedInvoiceId = local.billedInvoiceId;
              incoming.billedInvoiceNo = local.billedInvoiceNo;
              incoming.billedDate = local.billedDate;
            }
            localChallans[existingIdx] = incoming;
            mutated = true;
          }
        } else {
          localChallans.insert(0, incoming);
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


  /// Applies incoming D1 edge `hwmRollback` + Challan HWM SET transitions (using server `seq` -> causal `gen`)
  /// and extracts structured Challan `audit` entries without depending on client wall-clock timestamps.
  static bool applyEdgeHwmAndAuditFromEvents({
    required AppConfig currentConfig,
    required List<Map<String, dynamic>> edgeEvents,
    String companyID = "",
    Map<String, int> recordFloor = const {},
    List<LogEntry>? targetLogs,
  }) {
    if (edgeEvents.isEmpty) return false;
    final Map<String, int> incHwm = Map<String, int>.from(currentConfig.challanHwm);
    final Map<String, ChallanHwmState> incMeta =
        currentConfig.challanHwmMeta.map((k, v) => MapEntry(k, v.copy()));
    bool hasHwmUpdate = false;
    bool auditMutated = false;

    int lookupFloor(String key) {
      if (recordFloor.containsKey(key)) return recordFloor[key]!;
      final parts = key.split('::');
      if (parts.length == 5) {
        final suffix = '::${parts[1]}::${parts[2]}::${parts[3]}::${parts[4]}';
        int best = 0;
        recordFloor.forEach((rk, rv) {
          if (rk.endsWith(suffix) && rv > best) best = rv;
        });
        return best;
      }
      return 0;
    }

    void foldState(String key, ChallanHwmState st) {
      final prev = incMeta[key] ??
          (incHwm.containsKey(key)
              ? ChallanHwmState(value: incHwm[key]!, seq: 0, gen: incHwm[key]!, op: 'SET')
              : null);
      final int fl = lookupFloor(key);
      final resolved = AppConfig.resolveCausalHwmState(prev, st, floor: fl);
      incMeta[key] = resolved;
      if (resolved.value > 0) {
        incHwm[key] = resolved.value;
      } else {
        incHwm.remove(key);
      }
      hasHwmUpdate = true;
    }

    for (final ev in edgeEvents) {
      final int evSeq = int.tryParse(ev["seq"]?.toString() ?? "0") ?? 0;
      final dynamic rawData = ev["sale_data"];
      if (rawData is! Map) continue;
      final rawMap = Map<String, dynamic>.from(rawData);

      // 1. Extract optional structured audit entry
      if (targetLogs != null && rawMap["audit"] is Map) {
        try {
          final aMap = Map<String, dynamic>.from(rawMap["audit"] as Map);
          final String logId = (aMap["id"] ?? "${ev['bill_id'] ?? ''}_${aMap['action'] ?? 'LOG'}_$evSeq").toString().trim();
          final String action = (aMap["action"] ?? ev["action"] ?? "LOG").toString().trim();
          final String details = (aMap["details"] ?? "").toString().trim();
          final DateTime t = DateTime.tryParse((aMap["time"] ?? "").toString()) ?? DateTime.now();
          if (details.isNotEmpty && !targetLogs.any((l) => l.id == logId || (l.action == action && l.details == details))) {
            targetLogs.add(LogEntry(id: logId, action: action, details: details, time: t));
            auditMutated = true;
          }
        } catch (_) {}
      }

      // 2. Apply explicit hwmRollback attached to Challan DELETE event
      if (rawMap["hwmRollback"] is Map) {
        final rb = Map<String, dynamic>.from(rawMap["hwmRollback"] as Map);
        final String key = (rb["key"] ?? "").toString().trim();
        if (key.isNotEmpty) {
          final st = ChallanHwmState.fromMap({
            ...rb,
            'op': 'ROLLBACK',
            if (evSeq > 0) 'seq': evSeq,
          });
          foldState(key, st);
          final parts = key.split('::');
          if (parts.length == 5) {
            final suffix = '::${parts[1]}::${parts[2]}::${parts[3]}::${parts[4]}';
            for (final exK in currentConfig.challanHwm.keys.toList()) {
              if (exK.endsWith(suffix) && exK != key) {
                foldState(exK, st);
              }
            }
            for (final exK in currentConfig.challanHwmMeta.keys.toList()) {
              if (exK.endsWith(suffix) && exK != key) {
                foldState(exK, st);
              }
            }
            if (companyID.trim().isNotEmpty) {
              final localKey = '${companyID.trim()}$suffix';
              if (localKey != key) {
                foldState(localKey, st);
              }
            }
          }
        }
      } else {
        // 3. Fold non-deleted Challan create/save events cleanly with their D1 seq
        final String docType = (rawMap["doc_type"] ?? "").toString().trim().toUpperCase();
        final String act = (ev["action"] ?? "").toString().trim().toUpperCase();
        final int isDel = int.tryParse((rawMap["is_deleted"] ?? rawMap["isDeleted"] ?? "0").toString()) ?? 0;
        final bool isDeleteEvt = act == "DELETE" || act.startsWith("DELETE_") || isDel == 1 || rawMap["status"] == "Deleted";
        if (!isDeleteEvt && (docType == "SALE_CHALLAN" || docType == "CHALLAN" || docType == "PURCHASE_CHALLAN")) {
          final bool isPur = docType == "PURCHASE_CHALLAN";
          final String numStr = (isPur ? (rawMap["internalNo"] ?? "") : (rawMap["billNo"] ?? "")).toString();
          final parsed = AppConfig.parseSeriesNumber(numStr);
          if (parsed.prefix.isNotEmpty && parsed.number != null) {
            final String evFy = normalizeFyString((rawMap["originalFy"] ?? rawMap["original_fy"] ?? rawMap["fy"] ?? ev["fy"] ?? "").toString());
            final String env = AppConfig.inferIsWebChallanRecord(rawMap) ? "WEB" : "APP";
            final String normType = isPur ? "PURCHASE_CHALLAN" : "SALE_CHALLAN";
            final String comp = companyID.trim();
            final String key = '${comp}::${evFy}::${normType}::${env}::${parsed.prefix}';
            final int prevGen = incMeta[key]?.gen ?? (incHwm[key] ?? 0);
            foldState(
              key,
              ChallanHwmState(
                value: parsed.number!,
                seq: evSeq,
                gen: prevGen + 1 > parsed.number! ? prevGen + 1 : parsed.number!,
                op: 'SET',
                updatedAt: int.tryParse((rawMap["updatedAt"] ?? rawMap["updated_at"] ?? "0").toString()) ?? 0,
              ),
            );
          }
        }
      }
    }

    if (hasHwmUpdate) {
      final merged = AppConfig.mergeHwmMapsWithMeta(
        localHwm: currentConfig.challanHwm,
        localMeta: currentConfig.challanHwmMeta,
        remoteHwm: incHwm,
        remoteMeta: incMeta,
        recordFloor: recordFloor,
      );
      currentConfig.challanHwm = merged.hwm;
      currentConfig.challanHwmMeta = merged.meta;
    }
    return hasHwmUpdate || auditMutated;
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
