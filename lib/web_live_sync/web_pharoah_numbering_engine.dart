// FILE: lib/web_live_sync/web_pharoah_numbering_engine.dart
// Revision: #PH-REV-815 (MONOTONIC-CHALLAN-HWM-ENTERPRISE-ISOLATION)
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../logic/app_settings_model.dart';
import '../../models.dart' show normalizeFyString;
import 'web_models.dart';

class WebPharoahNumberingEngine {
  /// In-memory cache of monotonic High-Water Marks for fast synchronous access
  static final Map<String, int> _cachedHwm = {};

  /// Monotonically absorbs incoming HWM values into the in-memory cache
  static void absorbChallanHwmMap(Map<String, int> incoming) {
    incoming.forEach((key, val) {
      final cleanK = key.trim();
      final current = _cachedHwm[cleanK] ?? 0;
      if (val > current) {
        _cachedHwm[cleanK] = val;
      }
    });
  }

  /// Initializes HWM cache from local storage / SharedPreferences
  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final k in keys) {
        if (k.startsWith('challan_hwm_')) {
          final val = prefs.getInt(k);
          if (val != null) {
            _cachedHwm[k] = val;
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ [WebPharoahNumberingEngine] Failed to load prefs HWM: $e");
    }
  }

  /// Checks if a prefix represents a Challan series
  static bool isChallanPrefix(String prefix) {
    final p = prefix.trim().toUpperCase();
    return p == "WSCH-" || p == "SCH-" || p == "WPCH-" || p == "PCH-";
  }

  /// Monotonically records issued Challan number into persistent HWM cache and SharedPreferences
  static void recordChallanHwm({
    required String prefix,
    required String number,
    required String fy,
    String env = "WEB",
    AppConfig? config,
    String companyID = "",
  }) {
    final cleanNum = number.trim().toUpperCase();
    final cleanPrefix = prefix.trim().toUpperCase();
    if (!cleanNum.startsWith(cleanPrefix)) return;
    final numPart = cleanNum.substring(cleanPrefix.length).trim();
    final int? issuedInt = int.tryParse(numPart);
    if (issuedInt == null) return;

    final cleanFy = normalizeFyString(fy);
    final normEnv = env.trim().toUpperCase();
    final normType = (cleanPrefix.contains("PCH")) ? "PURCHASE_CHALLAN" : "SALE_CHALLAN";
    final cleanComp = companyID.trim();

    final cacheKey = 'challan_hwm_${cleanComp}_${cleanFy}_${normType}_${normEnv}_$cleanPrefix';
    final current = _cachedHwm[cacheKey] ?? 0;
    if (issuedInt > current) {
      _cachedHwm[cacheKey] = issuedInt;
    }

    if (config != null) {
      final configKey = '${cleanComp}::${cleanFy}::${normType}::${normEnv}::$cleanPrefix';
      final existingCfg = config.challanHwm[configKey] ?? 0;
      if (issuedInt > existingCfg) {
        config.challanHwm[configKey] = issuedInt;
      }
    }

    // Persist asynchronously to SharedPreferences
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getInt(cacheKey) ?? 0;
      if (issuedInt > saved) {
        prefs.setInt(cacheKey, issuedInt);
      }
    }).catchError((_) {});
  }

  /// Coordinated sequential number generator matching Mobile App.
  /// 🛡️ STRICT SERIES PREFIX ISOLATION & MONOTONIC HWM FOR CHALLANS:
  /// Challans advance monotonically without gap-filling, preserving cancelled & deleted numbers.
  static String getNextNumber({
    required String prefix,
    required int startFrom,
    required List<dynamic> currentList,
    String? targetFy,
    String env = "WEB",
    Map<String, int>? configHwm,
    Iterable<String>? tombstones,
  }) {
    List<int> existingNumbers = [];
    final String cleanPrefix = prefix.trim().toUpperCase();
    final String cleanTargetFy = normalizeFyString(targetFy ?? '');
    final String normEnv = env.trim().toUpperCase();

    bool isChallanList = isChallanPrefix(cleanPrefix);
    if (!isChallanList && currentList.isNotEmpty) {
      final first = currentList.first;
      if (first is SaleChallan || first is PurchaseChallan) {
        isChallanList = true;
      }
    }

    for (var item in currentList) {
      String idToParse = "";
      try {
        if (item is Sale) {
          idToParse = item.billNo;
        } else if (item is Purchase) {
          idToParse = item.internalNo;
        } else if (item is SaleChallan) {
          if (item.isDeleted == 1) continue;
          // 🛡️ STRICT FY ISOLATION: Do not count carry-forward challans from prior financial years
          if (cleanTargetFy.isNotEmpty && normalizeFyString(item.effectiveOriginalFy) != cleanTargetFy) {
            continue;
          }
          idToParse = item.billNo;
        } else if (item is PurchaseChallan) {
          if (item.isDeleted == 1) continue;
          // 🛡️ STRICT FY ISOLATION: Do not count carry-forward purchase challans from prior financial years
          if (cleanTargetFy.isNotEmpty && normalizeFyString(item.effectiveOriginalFy) != cleanTargetFy) {
            continue;
          }
          idToParse = item.internalNo;
        } else if (item is SaleReturn) {
          idToParse = item.billNo;
        } else if (item is PurchaseReturn) {
          idToParse = item.billNo;
        } else if (item is Voucher) {
          idToParse = item.voucherNo;
        } else if (item is Medicine) {
          idToParse = item.systemId;
        } else if (item is Map<String, dynamic>) {
          final String mapFy = normalizeFyString((item['originalFy'] ?? item['original_fy'] ?? item['fy'] ?? '').toString());
          if (cleanTargetFy.isNotEmpty && mapFy.isNotEmpty && mapFy != cleanTargetFy) {
            continue;
          }
          idToParse = (item['billNo'] ??
                  item['internalNo'] ??
                  item['voucherNo'] ??
                  item['systemId'] ??
                  '')
              .toString();
        }
      } catch (_) {
        idToParse = "";
      }

      final String upperId = idToParse.trim().toUpperCase();
      // 🛡️ Strict Prefix Match: Only extract sequential integer if the ID starts with this exact prefix
      if (cleanPrefix.isNotEmpty && upperId.startsWith(cleanPrefix)) {
        final String numPart = upperId.substring(cleanPrefix.length).trim();
        final int? n = int.tryParse(numPart);
        if (n != null) {
          existingNumbers.add(n);
        }
      }
    }

    // -------------------------------------------------------------------------
    // CHALLAN MONOTONIC HIGH-WATER MARK (NO GAP FILLING)
    // -------------------------------------------------------------------------
    if (isChallanList) {
      final String normType = cleanPrefix.contains("PCH") ? "PURCHASE_CHALLAN" : "SALE_CHALLAN";
      int cachedVal = 0;
      for (final entry in _cachedHwm.entries) {
        if (entry.key.contains(cleanPrefix) &&
            (cleanTargetFy.isEmpty || entry.key.contains(cleanTargetFy))) {
          if (entry.value > cachedVal) cachedVal = entry.value;
        }
      }

      int cfgVal = 0;
      if (configHwm != null && configHwm.isNotEmpty) {
        for (final entry in configHwm.entries) {
          if (entry.key.contains(cleanPrefix) &&
              (cleanTargetFy.isEmpty || entry.key.contains(cleanTargetFy))) {
            if (entry.value > cfgVal) cfgVal = entry.value;
          }
        }
      }

      int maxExisting = existingNumbers.isNotEmpty ? existingNumbers.reduce(max) : 0;

      int maxTomb = 0;
      if (tombstones != null) {
        for (final t in tombstones) {
          final ut = t.trim().toUpperCase();
          final rawKey = ut.contains('::') ? ut.split('::').last : ut;
          if (cleanPrefix.isNotEmpty && rawKey.startsWith(cleanPrefix)) {
            final numPart = rawKey.substring(cleanPrefix.length).trim();
            final int? n = int.tryParse(numPart);
            if (n != null && n > maxTomb) maxTomb = n;
          }
        }
      }

      int hwm = max(cachedVal, max(cfgVal, max(maxExisting, maxTomb)));
      int next = (hwm >= startFrom) ? (hwm + 1) : startFrom;
      return "$prefix$next";
    }

    // -------------------------------------------------------------------------
    // STANDARD BILLS: CONTINUOUS GAP-FILLING
    // -------------------------------------------------------------------------
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
}
