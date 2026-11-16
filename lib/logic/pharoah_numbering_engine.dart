// FILE: lib/logic/pharoah_numbering_engine.dart (UPGRADED MONOTONIC HWM CHALLAN ENGINE)
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../web_live_sync/sync_protocol/tombstone_engine.dart';
import 'app_settings_model.dart';

class PharoahNumberingEngine {
  static final Map<String, int> _cachedHwm = {};

  @visibleForTesting
  static void debugResetHwmCache() {
    _cachedHwm.clear();
  }

  /// Checks whether a numbering type belongs to Challans
  static bool isChallanType(String type) {
    final u = type.trim().toUpperCase();
    return u == "CHALLAN" || u == "SALE_CHALLAN" || u == "CHALLAN_SALE" ||
        u == "CHALLAN_PUR" || u == "PURCHASE_CHALLAN";
  }

  /// Checks whether a numbering type belongs specifically to Purchase Challans
  static bool isPurchaseChallanType(String type) {
    final u = type.trim().toUpperCase();
    return u == "CHALLAN_PUR" || u == "PURCHASE_CHALLAN";
  }

  /// Identifies whether a Challan record originated from Web Portal vs Mobile App
  static bool isWebChallanRecord(dynamic item) {
    try {
      if (item is SaleChallan) {
        return item.id.trim().startsWith("SCH-WEB") ||
            item.salesmanName.trim().toUpperCase() == "WEB-PORTAL" ||
            item.billNo.trim().toUpperCase().startsWith("WSCH-");
      }
      if (item is PurchaseChallan) {
        return item.id.trim().startsWith("PCH-WEB") ||
            item.internalNo.trim().toUpperCase().startsWith("WPCH-") ||
            item.remarks.contains("WEB-PORTAL");
      }
      if (item is Map) {
        final id = (item['id'] ?? '').toString().trim();
        final sm = (item['salesmanName'] ?? '').toString().trim().toUpperCase();
        final rem = (item['remarks'] ?? '').toString();
        final bNo = (item['billNo'] ?? '').toString().trim().toUpperCase();
        final iNo = (item['internalNo'] ?? '').toString().trim().toUpperCase();
        return id.startsWith("SCH-WEB") ||
            id.startsWith("PCH-WEB") ||
            sm == "WEB-PORTAL" ||
            rem.contains("WEB-PORTAL") ||
            bNo.startsWith("WSCH-") ||
            iNo.startsWith("WPCH-");
      }
    } catch (_) {}
    return false;
  }

  static void absorbChallanHwmMap(Map<String, int> incoming) {
    incoming.forEach((key, val) {
      final cleanK = key.trim();
      if (cleanK.isEmpty || val <= 0) return;
      final current = _cachedHwm[cleanK] ?? 0;
      if (val > current) {
        _cachedHwm[cleanK] = val;
      }
      final parts = cleanK.split('::');
      if (parts.length == 5) {
        final prefKey = 'challan_hwm_${parts[0]}_${parts[1]}_${parts[2]}_${parts[3]}_${parts[4]}';
        final curPref = _cachedHwm[prefKey] ?? 0;
        if (val > curPref) {
          _cachedHwm[prefKey] = val;
        }
      }
    });
  }

  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        if (k.startsWith('challan_hwm_')) {
          final val = prefs.getInt(k);
          if (val != null && val > (_cachedHwm[k] ?? 0)) {
            _cachedHwm[k] = val;
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ [PharoahNumberingEngine] loadFromPrefs error: $e");
    }
  }

  static int getCachedChallanHwm({
    required String companyID,
    required String type,
    required String prefix,
    required String fy,
    String env = "APP",
    Map<String, int>? configHwm,
  }) {
    final cleanComp = companyID.trim();
    final cleanFy = normalizeFyString(fy);
    final normType = isPurchaseChallanType(type) ? "PURCHASE_CHALLAN" : "SALE_CHALLAN";
    final normEnv = env.trim().toUpperCase();
    final cleanPrefix = prefix.trim().toUpperCase();
    if (cleanPrefix.isEmpty) return 0;

    int best = 0;
    final exactPrefKey = 'challan_hwm_${cleanComp}_${cleanFy}_${normType}_${normEnv}_$cleanPrefix';
    final exactCfgKey = '${cleanComp}::${cleanFy}::${normType}::${normEnv}::$cleanPrefix';
    if ((_cachedHwm[exactPrefKey] ?? 0) > best) best = _cachedHwm[exactPrefKey]!;
    if ((_cachedHwm[exactCfgKey] ?? 0) > best) best = _cachedHwm[exactCfgKey]!;

    final prefSuffix = '_${cleanFy}_${normType}_${normEnv}_$cleanPrefix';
    final cfgSuffix = '::${cleanFy}::${normType}::${normEnv}::$cleanPrefix';
    for (final entry in _cachedHwm.entries) {
      if ((cleanComp.isEmpty || entry.key.startsWith('challan_hwm_${cleanComp}_') || entry.key.startsWith('${cleanComp}::')) &&
          (entry.key.endsWith(prefSuffix) || entry.key.endsWith(cfgSuffix))) {
        if (entry.value > best) best = entry.value;
      }
    }
    if (configHwm != null && configHwm.isNotEmpty) {
      if ((configHwm[exactCfgKey] ?? 0) > best) best = configHwm[exactCfgKey]!;
      for (final entry in configHwm.entries) {
        if ((cleanComp.isEmpty || entry.key.startsWith('${cleanComp}::')) && entry.key.endsWith(cfgSuffix)) {
          if (entry.value > best) best = entry.value;
        }
      }
    }
    return best;
  }

  static int _scanTombstoneMax({
    required Iterable<String> tombstones,
    required String cleanPrefix,
    required String currentFY,
    required String normEnv,
  }) {
    int maxTomb = 0;
    for (final t in tombstones) {
      final ut = t.trim().toUpperCase();
      if (ut.isEmpty) continue;
      if (ut.contains('::')) {
        final parts = ut.split('::');
        if (parts.length >= 2) {
          final first = parts[0].trim();
          if (RegExp(r'^\d{4}-\d{2,4}$').hasMatch(first) && currentFY.isNotEmpty && currentFY != "default_fy") {
            if (normalizeFyString(first) != currentFY) continue;
          }
          if (parts.length >= 3) {
            final envPart = parts[1].trim();
            if ((envPart == "APP" || envPart == "WEB") && envPart != normEnv) {
              continue;
            }
          }
        }
      }
      final rawKey = ut.contains('::') ? ut.split('::').last.trim() : ut;
      if (cleanPrefix.isNotEmpty && rawKey.startsWith(cleanPrefix)) {
        final numPart = rawKey.substring(cleanPrefix.length).trim();
        final int? n = int.tryParse(numPart);
        if (n != null && n > maxTomb) {
          maxTomb = n;
        }
      }
    }
    return maxTomb;
  }

  // ===========================================================================
  // 1. GET NEXT SMART NUMBER (FY-Isolated, Monotonic HWM for Challans, Gap-Filling for Bills)
  // ===========================================================================
  static Future<String> getNextNumber({
    required String type,           // SALE, PURCHASE, PRODUCT, CHALLAN, etc.
    required String companyID,
    required String prefix,
    required int startFrom,
    required List<dynamic> currentList,
    String? targetFy,
    String env = "APP",
    Map<String, int>? configHwm,
    Iterable<String>? tombstones,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanComp = companyID.trim();
    final String currentFY = normalizeFyString(
        (targetFy != null && targetFy.trim().isNotEmpty)
            ? targetFy
            : (prefs.getString('active_fy_$cleanComp') ?? "default_fy"));
    final cleanPrefix = prefix.trim().toUpperCase();
    final normEnv = env.trim().toUpperCase();

    // -------------------------------------------------------------------------
    // CHALLAN NUMBERING: MONOTONIC HIGH-WATER MARK (NO GAP-FILLING)
    // -------------------------------------------------------------------------
    if (isChallanType(type)) {
      final String normType = isPurchaseChallanType(type) ? "PURCHASE_CHALLAN" : "SALE_CHALLAN";
      final String hwmPrefKey = 'challan_hwm_${cleanComp}_${currentFY}_${normType}_${normEnv}_$cleanPrefix';
      int savedHwm = prefs.getInt(hwmPrefKey) ?? 0;

      final int cachedVal = getCachedChallanHwm(
        companyID: cleanComp,
        type: normType,
        prefix: cleanPrefix,
        fy: currentFY,
        env: normEnv,
        configHwm: configHwm,
      );
      if (cachedVal > savedHwm) savedHwm = cachedVal;

      if (normEnv == "APP") {
        final String legacyKey = 'lastID_${type}_${cleanPrefix}_${cleanComp}_$currentFY';
        final int legacyVal = prefs.getInt(legacyKey) ?? 0;
        if (legacyVal > savedHwm) savedHwm = legacyVal;
      }

      int maxExisting = 0;
      for (var item in currentList) {
        if (item is SaleChallan) {
          if (currentFY.isNotEmpty && currentFY != "default_fy" &&
              normalizeFyString(item.effectiveOriginalFy) != currentFY) {
            continue;
          }
          final bool itemIsWeb = isWebChallanRecord(item);
          if (normEnv == "APP" && itemIsWeb) continue;
          if (normEnv == "WEB" && !itemIsWeb) continue;
        } else if (item is PurchaseChallan) {
          if (currentFY.isNotEmpty && currentFY != "default_fy" &&
              normalizeFyString(item.effectiveOriginalFy) != currentFY) {
            continue;
          }
          final bool itemIsWeb = isWebChallanRecord(item);
          if (normEnv == "APP" && itemIsWeb) continue;
          if (normEnv == "WEB" && !itemIsWeb) continue;
        }

        String idToParse = "";
        try {
          if (normType == "PURCHASE_CHALLAN") {
            idToParse = item.internalNo;
          } else {
            idToParse = item.billNo;
          }
        } catch (_) {
          idToParse = "";
        }
        final upperId = idToParse.trim().toUpperCase();
        if (cleanPrefix.isNotEmpty && upperId.startsWith(cleanPrefix)) {
          final numPart = upperId.substring(cleanPrefix.length).trim();
          final int? n = int.tryParse(numPart);
          if (n != null && n > maxExisting) {
            maxExisting = n;
          }
        }
      }

      Iterable<String>? effTombstones = tombstones;
      if (effTombstones == null && cleanComp.isNotEmpty) {
        try {
          effTombstones = await TombstoneEngine.getLocalTombstones(cleanComp);
        } catch (_) {}
      }
      final int maxTomb = effTombstones != null
          ? _scanTombstoneMax(
              tombstones: effTombstones,
              cleanPrefix: cleanPrefix,
              currentFY: currentFY,
              normEnv: normEnv,
            )
          : 0;

      int hwm = max(savedHwm, max(maxExisting, maxTomb));
      int next = (hwm >= startFrom) ? (hwm + 1) : startFrom;
      return "$prefix$next";
    }

    // -------------------------------------------------------------------------
    // STANDARD BILLS / PRODUCTS / VOUCHERS: SEQUENTIAL & GAP FILLING LOGIC
    // -------------------------------------------------------------------------
    List<int> existingNumbers = [];
    for (var item in currentList) {
      String idToParse = "";
      try {
        if (type == "PURCHASE") {
          idToParse = item.internalNo;
        } else if (type == "PRODUCT") {
          idToParse = item.systemId;
        } else if (type == "RECEIPT" || type == "PAYMENT") {
          idToParse = item.voucherNo;
        } else {
          idToParse = item.billNo;
        }
      } catch (e) {
        idToParse = "";
      }
      final upperId = idToParse.trim().toUpperCase();
      if (upperId.startsWith(cleanPrefix)) {
        String numPart = upperId.substring(cleanPrefix.length).trim();
        int? n = int.tryParse(numPart);
        if (n != null) existingNumbers.add(n);
      }
    }

    if (existingNumbers.isNotEmpty) {
      existingNumbers.sort();
      for (int i = startFrom; i <= existingNumbers.last; i++) {
        if (!existingNumbers.contains(i)) {
          return "$prefix$i";
        }
      }
      return "$prefix${existingNumbers.last + 1}";
    }
    return "$prefix$startFrom";
  }

  // ===========================================================================
  // 2. UPDATE PERSISTENT POINTER & CHALLAN HIGH-WATER MARK
  // ===========================================================================
  static Future<void> updateSeriesCounter({
    required String type,
    required String companyID,
    required String usedNumber,
    required String prefix,
    String? targetFy,
    String env = "APP",
    AppConfig? config,
  }) async {
    final upperUsed = usedNumber.trim().toUpperCase();
    final upperPrefix = prefix.trim().toUpperCase();
    if (!upperUsed.startsWith(upperPrefix)) return;

    final prefs = await SharedPreferences.getInstance();
    String currentFY = normalizeFyString(
        (targetFy != null && targetFy.trim().isNotEmpty)
            ? targetFy
            : (prefs.getString('active_fy_$companyID') ?? "default_fy"));
    if (isChallanType(type)) {
      await recordChallanHwm(
        companyID: companyID,
        type: type,
        prefix: prefix,
        number: usedNumber,
        fy: currentFY,
        env: env,
        config: config,
      );
      return;
    }

    String counterKey = 'lastID_${type}_${upperPrefix}_${companyID}_$currentFY';
    String numStr = upperUsed.substring(upperPrefix.length).trim();
    int? usedInt = int.tryParse(numStr);
    if (usedInt != null) {
      int currentSaved = prefs.getInt(counterKey) ?? 0;
      if (usedInt > currentSaved) {
        await prefs.setInt(counterKey, usedInt);
      }
    }
  }

  /// Monotonically records issued Challan number into persistent HWM storage
  static Future<void> recordChallanHwm({
    required String companyID,
    required String type,
    required String prefix,
    required String number,
    required String fy,
    String env = "APP",
    AppConfig? config,
  }) async {
    final cleanNum = number.trim().toUpperCase();
    final cleanPrefix = prefix.trim().toUpperCase();
    if (cleanPrefix.isEmpty || !cleanNum.startsWith(cleanPrefix)) return;
    final numPart = cleanNum.substring(cleanPrefix.length).trim();
    final int? issuedInt = int.tryParse(numPart);
    if (issuedInt == null) return;

    final cleanComp = companyID.trim();
    final cleanFy = normalizeFyString(fy);
    final normType = isPurchaseChallanType(type) ? "PURCHASE_CHALLAN" : "SALE_CHALLAN";
    final normEnv = env.trim().toUpperCase();

    final hwmKey = 'challan_hwm_${cleanComp}_${cleanFy}_${normType}_${normEnv}_$cleanPrefix';
    if (issuedInt > (_cachedHwm[hwmKey] ?? 0)) {
      _cachedHwm[hwmKey] = issuedInt;
    }

    if (config != null) {
      final configKey = '${cleanComp}::${cleanFy}::${normType}::${normEnv}::$cleanPrefix';
      final existingCfgHwm = config.challanHwm[configKey] ?? 0;
      if (issuedInt > existingCfgHwm) {
        config.challanHwm[configKey] = issuedInt;
      }
      if (issuedInt > (_cachedHwm[configKey] ?? 0)) {
        _cachedHwm[configKey] = issuedInt;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final currentSaved = prefs.getInt(hwmKey) ?? 0;
    if (issuedInt > currentSaved) {
      await prefs.setInt(hwmKey, issuedInt);
    }
  }

  // ===========================================================================
  // 3. COUNTER RESET (DANGER ZONE - Isolated to Active FY, Refuses Challan HWM)
  // ===========================================================================
  static Future<void> resetSeries({
    required String type,
    required String companyID,
    required String prefix,
  }) async {
    if (isChallanType(type)) {
      debugPrint("🛡️ [PharoahNumberingEngine] Refusing to reset monotonic Challan HWM for $type");
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    String currentFY = prefs.getString('active_fy_$companyID') ?? "default_fy";
    String counterKey = 'lastID_${type}_${prefix}_${companyID}_$currentFY';
    await prefs.remove(counterKey);
  }
}
