// FILE: lib/web_live_sync/web_pharoah_numbering_engine.dart
// Revision: #PH-REV-816 (MONOTONIC-CHALLAN-HWM-CROSS-ENV-ISOLATION)

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../logic/app_settings_model.dart';
import '../../models.dart' show normalizeFyString;
import 'web_models.dart';

class WebPharoahNumberingEngine {
  /// In-memory cache of monotonic High-Water Marks for fast synchronous access
  static final Map<String, int> _cachedHwm = {};

  @visibleForTesting
  static void debugResetHwmCache() {
    _cachedHwm.clear();
  }

  /// Monotonically absorbs incoming HWM values into the in-memory cache
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

  /// Initializes HWM cache from local storage / SharedPreferences
  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final k in keys) {
        if (k.startsWith('challan_hwm_')) {
          final val = prefs.getInt(k);
          if (val != null && val > (_cachedHwm[k] ?? 0)) {
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

  /// Reads cached/config HWM for a specific (companyID, fy, docType, env, prefix) without prefix substring collisions
  static int getCachedChallanHwm({
    required String prefix,
    required String fy,
    required String normType,
    String env = "WEB",
    String companyID = "",
    Map<String, int>? configHwm,
  }) {
    final cleanPrefix = prefix.trim().toUpperCase();
    if (cleanPrefix.isEmpty) return 0;
    final cleanFy = normalizeFyString(fy);
    final normEnv = env.trim().toUpperCase();
    final cleanComp = companyID.trim();

    int best = 0;
    final prefSuffix = (cleanFy.isNotEmpty)
        ? '_${cleanFy}_${normType}_${normEnv}_$cleanPrefix'
        : '_${normType}_${normEnv}_$cleanPrefix';
    final cfgSuffix = (cleanFy.isNotEmpty)
        ? '::${cleanFy}::${normType}::${normEnv}::$cleanPrefix'
        : '::${normType}::${normEnv}::$cleanPrefix';

    for (final entry in _cachedHwm.entries) {
      if (cleanComp.isNotEmpty &&
          !entry.key.startsWith('challan_hwm_${cleanComp}_') &&
          !entry.key.startsWith('${cleanComp}::')) {
        continue;
      }
      if (entry.key.endsWith(prefSuffix) || entry.key.endsWith(cfgSuffix)) {
        if (entry.value > best) best = entry.value;
      }
    }
    if (configHwm != null && configHwm.isNotEmpty) {
      for (final entry in configHwm.entries) {
        if (cleanComp.isNotEmpty && !entry.key.startsWith('${cleanComp}::')) {
          continue;
        }
        if (entry.key.endsWith(cfgSuffix)) {
          if (entry.value > best) best = entry.value;
        }
      }
    }
    return best;
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
    if (cleanPrefix.isEmpty || !cleanNum.startsWith(cleanPrefix)) return;
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
      if (issuedInt > (_cachedHwm[configKey] ?? 0)) {
        _cachedHwm[configKey] = issuedInt;
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
    String companyID = "",
    Map<String, int>? configHwm,
    Iterable<String>? tombstones,
    bool isChallanDoc = false,
  }) {
    List<int> existingNumbers = [];
    final String cleanPrefix = prefix.trim().toUpperCase();
    final String cleanTargetFy = normalizeFyString(targetFy ?? '');
    final String normEnv = env.trim().toUpperCase();
    bool isChallanList = isChallanDoc || isChallanPrefix(cleanPrefix);
    bool inferredPurchaseChallan = cleanPrefix.contains("PCH");
    if (!isChallanList && currentList.isNotEmpty) {
      final first = currentList.first;
      if (first is SaleChallan || first is PurchaseChallan) {
        isChallanList = true;
        if (first is PurchaseChallan) inferredPurchaseChallan = true;
      }
    } else if (currentList.any((e) => e is PurchaseChallan)) {
      inferredPurchaseChallan = true;
    }

    for (var item in currentList) {
      String idToParse = "";
      try {
        if (item is Sale) {
          idToParse = item.billNo;
        } else if (item is Purchase) {
          idToParse = item.internalNo;
        } else if (item is SaleChallan) {
          if (cleanTargetFy.isNotEmpty && normalizeFyString(item.effectiveOriginalFy) != cleanTargetFy) {
            continue;
          }
          final bool itemIsWeb = isWebChallanRecord(item);
          if (normEnv == "WEB" && !itemIsWeb) continue;
          if (normEnv == "APP" && itemIsWeb) continue;
          idToParse = item.billNo;
        } else if (item is PurchaseChallan) {
          if (cleanTargetFy.isNotEmpty && normalizeFyString(item.effectiveOriginalFy) != cleanTargetFy) {
            continue;
          }
          final bool itemIsWeb = isWebChallanRecord(item);
          if (normEnv == "WEB" && !itemIsWeb) continue;
          if (normEnv == "APP" && itemIsWeb) continue;
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
          if (isChallanList) {
            final bool itemIsWeb = isWebChallanRecord(item);
            if (normEnv == "WEB" && !itemIsWeb) continue;
            if (normEnv == "APP" && itemIsWeb) continue;
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
      final String normType = inferredPurchaseChallan ? "PURCHASE_CHALLAN" : "SALE_CHALLAN";
      final int cachedOrCfg = getCachedChallanHwm(
        prefix: cleanPrefix,
        fy: cleanTargetFy,
        normType: normType,
        env: normEnv,
        companyID: companyID,
        configHwm: configHwm,
      );
      int maxExisting = existingNumbers.isNotEmpty ? existingNumbers.reduce(max) : 0;
      int maxTomb = 0;
      if (tombstones != null) {
        for (final t in tombstones) {
          final ut = t.trim().toUpperCase();
          if (ut.isEmpty) continue;
          if (ut.contains('::')) {
            final parts = ut.split('::');
            if (parts.length >= 2) {
              final first = parts[0].trim();
              if (RegExp(r'^\d{4}-\d{2,4}$').hasMatch(first) && cleanTargetFy.isNotEmpty) {
                if (normalizeFyString(first) != cleanTargetFy) continue;
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
            if (n != null && n > maxTomb) maxTomb = n;
          }
        }
      }

      int hwm = max(cachedOrCfg, max(maxExisting, maxTomb));
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
