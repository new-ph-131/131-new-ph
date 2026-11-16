// FILE: lib/logic/pharoah_numbering_engine.dart (UPGRADED MONOTONIC HWM CHALLAN ENGINE)
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import 'app_settings_model.dart';

class PharoahNumberingEngine {
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

      // Legacy fallback check
      final String legacyKey = 'lastID_${type}_${cleanPrefix}_${cleanComp}_$currentFY';
      final int legacyVal = prefs.getInt(legacyKey) ?? 0;
      if (legacyVal > savedHwm) savedHwm = legacyVal;

      // Check configHwm
      int configHwmVal = 0;
      if (configHwm != null && configHwm.isNotEmpty) {
        final exactKey = '${cleanComp}::${currentFY}::${normType}::${normEnv}::$cleanPrefix';
        if (configHwm.containsKey(exactKey)) {
          configHwmVal = configHwm[exactKey] ?? 0;
        } else {
          final suffix = '::${currentFY}::${normType}::${normEnv}::$cleanPrefix';
          for (final entry in configHwm.entries) {
            if (entry.key.endsWith(suffix) && entry.value > configHwmVal) {
              configHwmVal = entry.value;
            }
          }
        }
      }

      int maxExisting = 0;
      for (var item in currentList) {
        // 🛡️ STRICT FY ISOLATION:
        // Carry-forward pending challans from prior financial years must NEVER advance or consume
        // the new financial year's sequential numbers.
        if (item is SaleChallan) {
          if (item.isDeleted == 1) continue; // Hard deleted
          if (currentFY.isNotEmpty && currentFY != "default_fy" &&
              normalizeFyString(item.effectiveOriginalFy) != currentFY) {
            continue;
          }
        } else if (item is PurchaseChallan) {
          if (item.isDeleted == 1) continue; // Hard deleted
          if (currentFY.isNotEmpty && currentFY != "default_fy" &&
              normalizeFyString(item.effectiveOriginalFy) != currentFY) {
            continue;
          }
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

      // Check tombstones so deleted challans never reissue numbers
      int maxTomb = 0;
      if (tombstones != null) {
        for (final t in tombstones) {
          final ut = t.trim().toUpperCase();
          final rawKey = ut.contains('::') ? ut.split('::').last : ut;
          if (cleanPrefix.isNotEmpty && rawKey.startsWith(cleanPrefix)) {
            final numPart = rawKey.substring(cleanPrefix.length).trim();
            final int? n = int.tryParse(numPart);
            if (n != null && n > maxTomb) {
              maxTomb = n;
            }
          }
        }
      }

      int hwm = max(savedHwm, max(configHwmVal, max(maxExisting, maxTomb)));
      int next = (hwm >= startFrom) ? (hwm + 1) : startFrom;
      return "$prefix$next";
    }

    // -------------------------------------------------------------------------
    // STANDARD BILLS / PRODUCTS / VOUCHERS: SEQUENTIAL & GAP FILLING LOGIC
    // -------------------------------------------------------------------------
    String counterKey = 'lastID_${type}_${cleanPrefix}_${cleanComp}_$currentFY';
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
  }) async {
    final upperUsed = usedNumber.trim().toUpperCase();
    final upperPrefix = prefix.trim().toUpperCase();
    if (!upperUsed.startsWith(upperPrefix)) return;
    final prefs = await SharedPreferences.getInstance();

    String currentFY = prefs.getString('active_fy_$companyID') ?? "default_fy";
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
    if (!cleanNum.startsWith(cleanPrefix)) return;
    final numPart = cleanNum.substring(cleanPrefix.length).trim();
    final int? issuedInt = int.tryParse(numPart);
    if (issuedInt == null) return;

    final cleanComp = companyID.trim();
    final cleanFy = normalizeFyString(fy);
    final normType = isPurchaseChallanType(type) ? "PURCHASE_CHALLAN" : "SALE_CHALLAN";
    final normEnv = env.trim().toUpperCase();

    final prefs = await SharedPreferences.getInstance();
    final hwmKey = 'challan_hwm_${cleanComp}_${cleanFy}_${normType}_${normEnv}_$cleanPrefix';
    final currentSaved = prefs.getInt(hwmKey) ?? 0;
    if (issuedInt > currentSaved) {
      await prefs.setInt(hwmKey, issuedInt);
    }

    if (config != null) {
      final configKey = '${cleanComp}::${cleanFy}::${normType}::${normEnv}::$cleanPrefix';
      final existingCfgHwm = config.challanHwm[configKey] ?? 0;
      if (issuedInt > existingCfgHwm) {
        config.challanHwm[configKey] = issuedInt;
      }
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
