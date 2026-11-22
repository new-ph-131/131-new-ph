// FILE: lib/logic/pharoah_numbering_engine.dart (TAIL-ROLLBACK & CAUSAL HWM CHALLAN ENGINE)

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import 'app_settings_model.dart';

class PharoahNumberingEngine {
  static final Map<String, int> _cachedHwm = {};
  static final Map<String, ChallanHwmState> _cachedMeta = {};
  static final Set<String> _activeCompanyScopes = {};

  static void setActiveCompanyScopes(Iterable<String> scopes) {
    _activeCompanyScopes
      ..clear()
      ..addAll(scopes.map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty));
  }

  static void clearActiveCompanyScopes() {
    _activeCompanyScopes.clear();
  }

  @visibleForTesting
  static void debugResetHwmCache() {
    _cachedHwm.clear();
    _cachedMeta.clear();
    _activeCompanyScopes.clear();
  }

  static Set<String> _resolveAllowedScopes(
    String companyID, [
    Iterable<String> extraScopes = const [],
  ]) {
    final Set<String> scopes = {};
    final String cleanComp = companyID.trim().toUpperCase();
    if (cleanComp.isNotEmpty) {
      scopes.add(cleanComp);
    }
    for (final s in extraScopes) {
      final c = s.trim().toUpperCase();
      if (c.isNotEmpty) scopes.add(c);
    }
    if (cleanComp.isEmpty || _activeCompanyScopes.contains(cleanComp)) {
      scopes.addAll(_activeCompanyScopes);
    }
    return scopes;
  }

  static String? _extractCompanyFromConfigKey(String key) {
    final parts = key.split('::');
    if (parts.length == 5) return parts[0].trim().toUpperCase();
    return null;
  }

  static bool _matchesScopedSuffix(
    String key, {
    required String cfgSuffix,
    required String prefSuffix,
    required Set<String> allowedScopes,
  }) {
    if (cfgSuffix.isNotEmpty && key.endsWith(cfgSuffix)) {
      final String comp = key.substring(0, key.length - cfgSuffix.length).trim().toUpperCase();
      return allowedScopes.isEmpty ? comp.isEmpty : allowedScopes.contains(comp);
    }
    if (prefSuffix.isNotEmpty && key.endsWith(prefSuffix)) {
      String? comp;
      if (key.startsWith('challan_hwm_meta_')) {
        comp = key.substring('challan_hwm_meta_'.length, key.length - prefSuffix.length);
      } else if (key.startsWith('challan_hwm_')) {
        comp = key.substring('challan_hwm_'.length, key.length - prefSuffix.length);
      }
      if (comp == null) return false;
      final String clean = comp.trim().toUpperCase();
      return allowedScopes.isEmpty ? clean.isEmpty : allowedScopes.contains(clean);
    }
    return false;
  }

  static bool _matchesScopedLegacyLastId(
    String key, {
    required String cleanPrefix,
    required String cleanFy,
    required Set<String> allowedScopes,
  }) {
    if (!key.startsWith('lastID_')) return false;
    if (!(key.contains('_CHALLAN_') ||
        key.contains('_SALE_CHALLAN_') ||
        key.contains('_PURCHASE_CHALLAN_') ||
        key.contains('_CHALLAN_PUR_'))) {
      return false;
    }
    final String prefixToken = '_${cleanPrefix}_';
    final String fySuffix = '_$cleanFy';
    if (!key.contains(prefixToken) || !key.endsWith(fySuffix)) return false;
    final int pIdx = key.indexOf(prefixToken);
    final int compStart = pIdx + prefixToken.length;
    final int compEnd = key.length - fySuffix.length;
    if (compEnd < compStart) return false;
    final String compSeg = key.substring(compStart, compEnd).trim().toUpperCase();
    return allowedScopes.isEmpty ? compSeg.isEmpty : (compSeg.isEmpty || allowedScopes.contains(compSeg));
  }

  /// Checks whether a numbering type belongs to Challans
  static bool isChallanType(String type) {
    final u = type.trim().toUpperCase();
    return u == "CHALLAN" ||
        u == "SALE_CHALLAN" ||
        u == "CHALLAN_SALE" ||
        u == "CHALLAN_PUR" ||
        u == "PURCHASE_CHALLAN";
  }

  /// Checks whether a numbering type belongs specifically to Purchase Challans
  static bool isPurchaseChallanType(String type) {
    final u = type.trim().toUpperCase();
    return u == "CHALLAN_PUR" || u == "PURCHASE_CHALLAN";
  }

  /// Identifies whether a Challan record originated from Web Portal vs Mobile App
  static bool isWebChallanRecord(dynamic item) {
    return AppConfig.inferIsWebChallanRecord(item);
  }

  static String _prefKey(String comp, String fy, String normType, String normEnv, String prefix) =>
      'challan_hwm_${comp}_${fy}_${normType}_${normEnv}_$prefix';

  static String _metaPrefKey(String comp, String fy, String normType, String normEnv, String prefix) =>
      'challan_hwm_meta_${comp}_${fy}_${normType}_${normEnv}_$prefix';

  static String _configKey(String comp, String fy, String normType, String normEnv, String prefix) =>
      '${comp}::${fy}::${normType}::${normEnv}::$prefix';

  static String? _configKeyToPrefKey(String cfgKey, {bool meta = false}) {
    final parts = cfgKey.split('::');
    if (parts.length != 5) return null;
    return meta
        ? _metaPrefKey(parts[0], parts[1], parts[2], parts[3], parts[4])
        : _prefKey(parts[0], parts[1], parts[2], parts[3], parts[4]);
  }

  static bool _isMetaStateNewer(ChallanHwmState candidate, ChallanHwmState? current) {
    if (current == null) return true;
    if (candidate.seq > 0 && current.seq > 0 && candidate.seq != current.seq) {
      return candidate.seq > current.seq;
    }
    if (candidate.gen != current.gen) return candidate.gen > current.gen;
    if (candidate.op != current.op) return candidate.op != 'ROLLBACK';
    return candidate.value >= current.value;
  }

  /// Updates the server-authoritative D1 `seq` on an existing cached/config Challan HWM state
  /// across both `companyID` and any active company alias scopes (e.g. `storeToken`).
  static void updateChallanHwmServerSeq({
    required String companyID,
    required String fy,
    required String normType,
    required String env,
    required String prefix,
    required int serverSeq,
    AppConfig? config,
  }) {
    if (serverSeq <= 0) return;
    final cleanComp = companyID.trim();
    final cleanFy = normalizeFyString(fy);
    final resolvedNormType = isPurchaseChallanType(normType) ? "PURCHASE_CHALLAN" : "SALE_CHALLAN";
    final normEnv = env.trim().toUpperCase();
    final cleanPrefix = prefix.trim().toUpperCase();
    if (cleanPrefix.isEmpty) return;

    final configKey = _configKey(cleanComp, cleanFy, resolvedNormType, normEnv, cleanPrefix);
    final metaPrefKey = _metaPrefKey(cleanComp, cleanFy, resolvedNormType, normEnv, cleanPrefix);
    final Set<String> allowedScopes = _resolveAllowedScopes(cleanComp);
    final prefSuffix = '_${cleanFy}_${resolvedNormType}_${normEnv}_$cleanPrefix';
    final cfgSuffix = '::${cleanFy}::${resolvedNormType}::${normEnv}::$cleanPrefix';

    ChallanHwmState? bestMeta = _cachedMeta[configKey] ?? _cachedMeta[metaPrefKey] ?? config?.challanHwmMeta[configKey];
    for (final entry in _cachedMeta.entries) {
      if (_matchesScopedSuffix(entry.key, cfgSuffix: cfgSuffix, prefSuffix: prefSuffix, allowedScopes: allowedScopes)) {
        if (_isMetaStateNewer(entry.value, bestMeta)) {
          bestMeta = entry.value;
        }
      }
    }
    if (bestMeta == null) return;
    if (serverSeq <= bestMeta.seq) return;

    final updated = bestMeta.copy()..seq = serverSeq;
    _cachedMeta[configKey] = updated.copy();
    _cachedMeta[metaPrefKey] = updated.copy();
    for (final k in _cachedMeta.keys.toList()) {
      if (_matchesScopedSuffix(k, cfgSuffix: cfgSuffix, prefSuffix: prefSuffix, allowedScopes: allowedScopes)) {
        final existing = _cachedMeta[k];
        if (existing == null || serverSeq > existing.seq || _isMetaStateNewer(updated, existing)) {
          _cachedMeta[k] = updated.copy();
        }
      }
    }
    if (config != null) {
      config.challanHwmMeta[configKey] = updated.copy();
      for (final k in config.challanHwmMeta.keys.toList()) {
        if (_matchesScopedSuffix(k, cfgSuffix: cfgSuffix, prefSuffix: '', allowedScopes: allowedScopes)) {
          final existing = config.challanHwmMeta[k];
          if (existing == null || serverSeq > existing.seq || _isMetaStateNewer(updated, existing)) {
            config.challanHwmMeta[k] = updated.copy();
          }
        }
      }
    }

    lastPersistFuture = (lastPersistFuture ?? Future.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(metaPrefKey, jsonEncode(updated.toMap()));
      for (final k in prefs.getKeys()) {
        if (k.startsWith('challan_hwm_meta_') &&
            _matchesScopedSuffix(k, cfgSuffix: '', prefSuffix: prefSuffix, allowedScopes: allowedScopes)) {
          await prefs.setString(k, jsonEncode(updated.toMap()));
        }
      }
    }).catchError((_) {});
  }

  static List<String> _legacyLastIdKeys(String type, String normType, String cleanPrefix, String cleanComp, String cleanFy) {
    final Set<String> aliases = {
      type.trim().toUpperCase(),
      normType,
      normType == "PURCHASE_CHALLAN" ? "CHALLAN_PUR" : "CHALLAN",
    };
    return aliases
        .where((a) => a.isNotEmpty)
        .map((a) => 'lastID_${a}_${cleanPrefix}_${cleanComp}_$cleanFy')
        .toList();
  }

  /// Absorbs an incoming `challanHwm` map + optional `challanHwmMeta` into in-memory cache
  /// using causal (`seq` -> `gen`) resolution + `recordFloor` so rollbacks persist cleanly.
  static void absorbChallanHwmState({
    required Map<String, int> hwm,
    Map<String, ChallanHwmState> meta = const {},
    Map<String, int> recordFloor = const {},
    Iterable<String> companyScopes = const [],
  }) {
    final Set<String> allowedScopes = {};
    for (final s in companyScopes) {
      final c = s.trim().toUpperCase();
      if (c.isNotEmpty) allowedScopes.add(c);
    }
    for (final k in [...hwm.keys, ...meta.keys]) {
      final c = _extractCompanyFromConfigKey(k);
      if (c != null && c.isNotEmpty) allowedScopes.add(c);
    }
    if (allowedScopes.isEmpty || allowedScopes.any(_activeCompanyScopes.contains)) {
      allowedScopes.addAll(_activeCompanyScopes);
    }
    final bool allowEmptyComp = allowedScopes.isEmpty;
    bool scopeMatchesCfg(String k) {
      final c = _extractCompanyFromConfigKey(k);
      if (c == null) return false;
      return c.isEmpty ? allowEmptyComp : allowedScopes.contains(c);
    }

    final Map<String, int> curCfgHwm = {};
    final Map<String, ChallanHwmState> curCfgMeta = {};
    _cachedHwm.forEach((k, v) {
      if (k.contains('::') && scopeMatchesCfg(k)) curCfgHwm[k] = v;
    });
    _cachedMeta.forEach((k, v) {
      if (k.contains('::') && scopeMatchesCfg(k)) curCfgMeta[k] = v;
    });

    final resolved = AppConfig.mergeHwmMapsWithMeta(
      localHwm: curCfgHwm,
      localMeta: curCfgMeta,
      remoteHwm: hwm,
      remoteMeta: meta,
      recordFloor: recordFloor,
    );

    final Set<String> affectedKeys = {
      ...curCfgHwm.keys,
      ...curCfgMeta.keys,
      ...resolved.hwm.keys,
      ...resolved.meta.keys,
    };

    for (final cfgKey in affectedKeys) {
      final int val = resolved.hwm[cfgKey] ?? 0;
      final ChallanHwmState? st = resolved.meta[cfgKey];
      final String? prefKey = _configKeyToPrefKey(cfgKey);
      final String? metaPrefKey = _configKeyToPrefKey(cfgKey, meta: true);

      if (val > 0) {
        _cachedHwm[cfgKey] = val;
        if (prefKey != null) _cachedHwm[prefKey] = val;
      } else {
        _cachedHwm.remove(cfgKey);
        if (prefKey != null) _cachedHwm.remove(prefKey);
      }

      if (st != null) {
        _cachedMeta[cfgKey] = st.copy();
        if (metaPrefKey != null) _cachedMeta[metaPrefKey] = st.copy();
      }

      // Harmonize memory cache entries belonging ONLY to the same company scopes
      final parts = cfgKey.split('::');
      if (parts.length == 5) {
        final cfgSuffix = '::${parts[1]}::${parts[2]}::${parts[3]}::${parts[4]}';
        final prefSuffix = '_${parts[1]}_${parts[2]}_${parts[3]}_${parts[4]}';
        final keyComp = parts[0].trim().toUpperCase();
        final Set<String> keyScopes = keyComp.isNotEmpty
            ? {keyComp, if (allowedScopes.contains(keyComp)) ...allowedScopes}
            : allowedScopes;
        for (final k in _cachedHwm.keys.toList()) {
          if (_matchesScopedSuffix(k, cfgSuffix: cfgSuffix, prefSuffix: prefSuffix, allowedScopes: keyScopes)) {
            if (val > 0) {
              _cachedHwm[k] = val;
            } else {
              _cachedHwm.remove(k);
            }
          }
        }
        for (final k in _cachedMeta.keys.toList()) {
          if (_matchesScopedSuffix(k, cfgSuffix: cfgSuffix, prefSuffix: prefSuffix, allowedScopes: keyScopes)) {
            if (st != null) {
              _cachedMeta[k] = st.copy();
            }
          }
        }
      }
    }

    // Persist any causally resolved rollbacks/updates to SharedPreferences serialized via lastPersistFuture
    lastPersistFuture = (lastPersistFuture ?? Future.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      for (final cfgKey in affectedKeys) {
        final parts = cfgKey.split('::');
        if (parts.length != 5) continue;
        final String prefKey = _prefKey(parts[0], parts[1], parts[2], parts[3], parts[4]);
        final String metaPrefKey = _metaPrefKey(parts[0], parts[1], parts[2], parts[3], parts[4]);
        final int val = resolved.hwm[cfgKey] ?? 0;
        final ChallanHwmState? st = resolved.meta[cfgKey];
        if (val > 0) {
          await prefs.setInt(prefKey, val);
        } else {
          await prefs.remove(prefKey);
        }
        if (st != null) {
          await prefs.setString(metaPrefKey, jsonEncode(st.toMap()));
          final prefSuffix = '_${parts[1]}_${parts[2]}_${parts[3]}_${parts[4]}';
          final keyComp = parts[0].trim().toUpperCase();
          final Set<String> keyScopes = keyComp.isNotEmpty
              ? {keyComp, if (allowedScopes.contains(keyComp)) ...allowedScopes}
              : allowedScopes;
          for (final k in prefs.getKeys()) {
            if (_matchesScopedSuffix(k, cfgSuffix: '', prefSuffix: prefSuffix, allowedScopes: keyScopes)) {
              if (k.startsWith('challan_hwm_meta_')) {
                await prefs.setString(k, jsonEncode(st.toMap()));
              } else if (k.startsWith('challan_hwm_')) {
                if (val > 0) {
                  await prefs.setInt(k, val);
                } else {
                  await prefs.remove(k);
                }
              }
            }
          }
          if (st.op == 'ROLLBACK' && (parts[3] == 'APP' || parts[3] == 'WEB')) {
            for (final legKey in _legacyLastIdKeys(parts[2], parts[2], parts[4], parts[0], parts[1])) {
              if (val > 0) {
                final existingLeg = prefs.getInt(legKey) ?? 0;
                if (existingLeg > val) await prefs.setInt(legKey, val);
              } else {
                await prefs.remove(legKey);
              }
            }
            // Sweep legacy keys ONLY within the same company scopes
            for (final k in prefs.getKeys()) {
              if (_matchesScopedLegacyLastId(
                k,
                cleanPrefix: parts[4],
                cleanFy: parts[1],
                allowedScopes: keyScopes,
              )) {
                if (val > 0) {
                  final existingLeg = prefs.getInt(k) ?? 0;
                  if (existingLeg > val) await prefs.setInt(k, val);
                } else {
                  await prefs.remove(k);
                }
              }
            }
          }
        }
      }
    }).catchError((_) {});
  }

  static void absorbChallanHwmMap(Map<String, int> incoming) {
    if (incoming.isEmpty) return;
    absorbChallanHwmState(hwm: incoming);
  }

  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, int> prefHwm = {};
      final Map<String, ChallanHwmState> prefMeta = {};

      for (final k in prefs.getKeys()) {
        if (k.startsWith('challan_hwm_meta_')) {
          final rawStr = prefs.getString(k);
          if (rawStr != null && rawStr.trim().isNotEmpty) {
            try {
              final decoded = jsonDecode(rawStr);
              if (decoded is Map) {
                prefMeta[k] = ChallanHwmState.fromMap(decoded);
              }
            } catch (_) {}
          }
        } else if (k.startsWith('challan_hwm_')) {
          final val = prefs.getInt(k);
          if (val != null && val >= 0) {
            prefHwm[k] = val;
          }
        }
      }

      prefMeta.forEach((metaK, st) {
        final hwmK = metaK.replaceFirst('challan_hwm_meta_', 'challan_hwm_');
        final existingHwm = _cachedHwm[hwmK];
        final existingMeta = _cachedMeta[metaK];
        if (_isMetaStateNewer(st, existingMeta)) {
          _cachedMeta[metaK] = st.copy();
          if (st.value > 0) {
            _cachedHwm[hwmK] = st.value;
          } else {
            _cachedHwm.remove(hwmK);
          }
        } else if (existingHwm == null && st.value > 0 && existingMeta?.op != 'ROLLBACK') {
          _cachedHwm[hwmK] = st.value;
        }
      });

      prefHwm.forEach((hwmK, val) {
        final metaK = hwmK.replaceFirst('challan_hwm_', 'challan_hwm_meta_');
        if (!_cachedMeta.containsKey(metaK) && val > (_cachedHwm[hwmK] ?? 0)) {
          _cachedHwm[hwmK] = val;
        }
      });
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
    final exactPrefKey = _prefKey(cleanComp, cleanFy, normType, normEnv, cleanPrefix);
    final exactCfgKey = _configKey(cleanComp, cleanFy, normType, normEnv, cleanPrefix);
    if ((_cachedHwm[exactPrefKey] ?? 0) > best) best = _cachedHwm[exactPrefKey]!;
    if ((_cachedHwm[exactCfgKey] ?? 0) > best) best = _cachedHwm[exactCfgKey]!;

    final Set<String> allowedScopes = _resolveAllowedScopes(cleanComp);
    final prefSuffix = '_${cleanFy}_${normType}_${normEnv}_$cleanPrefix';
    final cfgSuffix = '::${cleanFy}::${normType}::${normEnv}::$cleanPrefix';

    // Check if winning causal meta for this company-scoped series indicates ROLLBACK
    ChallanHwmState? winningMeta;
    for (final entry in _cachedMeta.entries) {
      if (_matchesScopedSuffix(entry.key, cfgSuffix: cfgSuffix, prefSuffix: prefSuffix, allowedScopes: allowedScopes)) {
        if (_isMetaStateNewer(entry.value, winningMeta)) {
          winningMeta = entry.value;
        }
      }
    }
    if (winningMeta != null && winningMeta.op == 'ROLLBACK') {
      return winningMeta.value;
    }

    for (final entry in _cachedHwm.entries) {
      if (_matchesScopedSuffix(entry.key, cfgSuffix: cfgSuffix, prefSuffix: prefSuffix, allowedScopes: allowedScopes)) {
        if (entry.value > best) best = entry.value;
      }
    }
    if (configHwm != null && configHwm.isNotEmpty) {
      if ((configHwm[exactCfgKey] ?? 0) > best) best = configHwm[exactCfgKey]!;
      final legacy4Part = '${cleanFy}::${normType}::${normEnv}::$cleanPrefix';
      for (final entry in configHwm.entries) {
        if (entry.key == legacy4Part ||
            _matchesScopedSuffix(entry.key, cfgSuffix: cfgSuffix, prefSuffix: '', allowedScopes: allowedScopes)) {
          if (entry.value > best) best = entry.value;
        }
      }
    }
    return best;
  }

  // ===========================================================================
  // 1. GET NEXT SMART NUMBER (FY-Isolated, Tail-Rollback HWM for Challans, Gap-Filling for Bills)
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
    Iterable<String>? tombstones, // Retained for signature compatibility; ignored for Challan tail reclaim
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanComp = companyID.trim();
    final String currentFY = normalizeFyString(
        (targetFy != null && targetFy.trim().isNotEmpty)
            ? targetFy
            : (prefs.getString('active_fy_$cleanComp') ?? "default_fy"));
    final cleanPrefix = prefix.trim().toUpperCase();
    final normEnv = env.trim().toUpperCase();
    final int safeStart = startFrom < 1 ? 1 : startFrom;

    // -------------------------------------------------------------------------
    // CHALLAN NUMBERING: TAIL-ROLLBACK HWM (RESERVES CANCELLED, RECLAIMS DELETED TAIL)
    // -------------------------------------------------------------------------
    if (isChallanType(type)) {
      final String normType = isPurchaseChallanType(type) ? "PURCHASE_CHALLAN" : "SALE_CHALLAN";
      final String hwmPrefKey = _prefKey(cleanComp, currentFY, normType, normEnv, cleanPrefix);
      final String metaPrefKey = _metaPrefKey(cleanComp, currentFY, normType, normEnv, cleanPrefix);
      int savedHwm = prefs.getInt(hwmPrefKey) ?? 0;
      ChallanHwmState? prefMeta;
      if (prefs.containsKey(metaPrefKey)) {
        try {
          final dec = jsonDecode(prefs.getString(metaPrefKey) ?? '{}');
          if (dec is Map) {
            prefMeta = ChallanHwmState.fromMap(dec);
          }
        } catch (_) {}
      }

      final Set<String> allowedScopes = _resolveAllowedScopes(cleanComp);
      final cfgSuffix = '::${currentFY}::${normType}::${normEnv}::$cleanPrefix';
      final prefSuffix = '_${currentFY}_${normType}_${normEnv}_$cleanPrefix';
      ChallanHwmState? winningMeta;
      for (final entry in _cachedMeta.entries) {
        if (_matchesScopedSuffix(entry.key, cfgSuffix: cfgSuffix, prefSuffix: prefSuffix, allowedScopes: allowedScopes)) {
          if (_isMetaStateNewer(entry.value, winningMeta)) {
            winningMeta = entry.value;
          }
        }
      }
      if (prefMeta != null && _isMetaStateNewer(prefMeta, winningMeta)) {
        winningMeta = prefMeta;
      }

      final int cachedVal = getCachedChallanHwm(
        companyID: cleanComp,
        type: normType,
        prefix: cleanPrefix,
        fy: currentFY,
        env: normEnv,
        configHwm: configHwm,
      );

      bool isRollbackActive = false;
      if (winningMeta != null) {
        if (winningMeta.op == 'ROLLBACK') {
          isRollbackActive = true;
          savedHwm = winningMeta.value;
        } else if (prefMeta == null || _isMetaStateNewer(winningMeta, prefMeta) || winningMeta.value > savedHwm) {
          savedHwm = winningMeta.value;
        }
      }

      if (!isRollbackActive) {
        if (cachedVal > savedHwm) savedHwm = cachedVal;
        if (normEnv == "APP") {
          for (final legacyKey in _legacyLastIdKeys(type, normType, cleanPrefix, cleanComp, currentFY)) {
            final int legacyVal = prefs.getInt(legacyKey) ?? 0;
            if (legacyVal > savedHwm) savedHwm = legacyVal;
          }
        }
      }

      int maxExisting = 0;
      for (var item in currentList) {
        if (item is SaleChallan) {
          if (item.isDeleted == 1 || item.status.trim().toUpperCase() == "DELETED") continue;
          if (currentFY.isNotEmpty && currentFY != "default_fy" &&
              normalizeFyString(item.effectiveOriginalFy) != currentFY) {
            continue;
          }
          final bool itemIsWeb = isWebChallanRecord(item);
          if (normEnv == "APP" && itemIsWeb) continue;
          if (normEnv == "WEB" && !itemIsWeb) continue;
        } else if (item is PurchaseChallan) {
          if (item.isDeleted == 1 || item.status.trim().toUpperCase() == "DELETED") continue;
          if (currentFY.isNotEmpty && currentFY != "default_fy" &&
              normalizeFyString(item.effectiveOriginalFy) != currentFY) {
            continue;
          }
          final bool itemIsWeb = isWebChallanRecord(item);
          if (normEnv == "APP" && itemIsWeb) continue;
          if (normEnv == "WEB" && !itemIsWeb) continue;
        } else if (item is Map) {
          final int isDel = int.tryParse((item['isDeleted'] ?? item['is_deleted'] ?? '0').toString()) ?? 0;
          final String st = (item['status'] ?? '').toString().trim().toUpperCase();
          if (isDel == 1 || st == 'DELETED') continue;
        }

        String idToParse = "";
        try {
          if (normType == "PURCHASE_CHALLAN") {
            idToParse = item is Map ? (item['internalNo'] ?? '').toString() : item.internalNo;
          } else {
            idToParse = item is Map ? (item['billNo'] ?? '').toString() : item.billNo;
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

      int hwm = max(savedHwm, maxExisting);
      int next = (hwm >= safeStart) ? (hwm + 1) : safeStart;
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
      for (int i = safeStart; i <= existingNumbers.last; i++) {
        if (!existingNumbers.contains(i)) {
          return "$prefix$i";
        }
      }
      return "$prefix${existingNumbers.last + 1}";
    }
    return "$prefix$safeStart";
  }

  // ===========================================================================
  // 2. UPDATE PERSISTENT POINTER, CHALLAN HWM SET & TAIL ROLLBACK
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

  /// Records an issued Challan number into persistent HWM cache, `challanHwmMeta`, and SharedPreferences.
  static Future<void> recordChallanHwm({
    required String companyID,
    required String type,
    required String prefix,
    required String number,
    required String fy,
    String env = "APP",
    AppConfig? config,
    int d1Seq = 0,
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

    final hwmKey = _prefKey(cleanComp, cleanFy, normType, normEnv, cleanPrefix);
    final metaPrefKey = _metaPrefKey(cleanComp, cleanFy, normType, normEnv, cleanPrefix);
    final configKey = _configKey(cleanComp, cleanFy, normType, normEnv, cleanPrefix);

    final Set<String> allowedScopes = _resolveAllowedScopes(cleanComp);
    final rPrefSuffix = '_${cleanFy}_${normType}_${normEnv}_$cleanPrefix';
    final rCfgSuffix = '::${cleanFy}::${normType}::${normEnv}::$cleanPrefix';

    int prevVal = max(
      _cachedHwm[hwmKey] ?? 0,
      max(_cachedHwm[configKey] ?? 0, config?.challanHwm[configKey] ?? 0),
    );
    int prevGen = max(
      prevVal,
      max(
        _cachedMeta[configKey]?.gen ?? 0,
        max(_cachedMeta[metaPrefKey]?.gen ?? 0, config?.challanHwmMeta[configKey]?.gen ?? 0),
      ),
    );
    int prevSeq = max(
      d1Seq,
      max(_cachedMeta[configKey]?.seq ?? 0, config?.challanHwmMeta[configKey]?.seq ?? 0),
    );
    for (final entry in _cachedMeta.entries) {
      if (_matchesScopedSuffix(entry.key, cfgSuffix: rCfgSuffix, prefSuffix: rPrefSuffix, allowedScopes: allowedScopes)) {
        if (entry.value.gen > prevGen) prevGen = entry.value.gen;
        if (entry.value.seq > prevSeq) prevSeq = entry.value.seq;
      }
    }

    bool wasRollback = _cachedMeta[configKey]?.op == 'ROLLBACK' ||
        _cachedMeta[metaPrefKey]?.op == 'ROLLBACK' ||
        config?.challanHwmMeta[configKey]?.op == 'ROLLBACK';
    if (!wasRollback) {
      for (final entry in _cachedMeta.entries) {
        if (_matchesScopedSuffix(entry.key, cfgSuffix: rCfgSuffix, prefSuffix: rPrefSuffix, allowedScopes: allowedScopes)) {
          if (entry.value.op == 'ROLLBACK') {
            wasRollback = true;
            break;
          }
        }
      }
    }

    final int effVal = issuedInt > prevVal ? issuedInt : prevVal;
    final bool needsMetaUpdate = issuedInt > prevVal || !_cachedMeta.containsKey(configKey) ||
        wasRollback ||
        (config != null && !config.challanHwmMeta.containsKey(configKey));

    if (issuedInt > (_cachedHwm[hwmKey] ?? 0)) {
      _cachedHwm[hwmKey] = issuedInt;
    }
    if (issuedInt > (_cachedHwm[configKey] ?? 0)) {
      _cachedHwm[configKey] = issuedInt;
    }
    for (final k in _cachedHwm.keys.toList()) {
      if (_matchesScopedSuffix(k, cfgSuffix: rCfgSuffix, prefSuffix: rPrefSuffix, allowedScopes: allowedScopes)) {
        if (effVal > (_cachedHwm[k] ?? 0)) _cachedHwm[k] = effVal;
      }
    }

    if (needsMetaUpdate) {
      final int nextGen = (issuedInt > prevVal || wasRollback) ? (prevGen + 1) : max(prevGen, issuedInt);
      final st = ChallanHwmState(
        value: effVal,
        seq: prevSeq,
        gen: nextGen,
        op: 'SET',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _cachedMeta[configKey] = st.copy();
      _cachedMeta[metaPrefKey] = st.copy();
      for (final k in _cachedMeta.keys.toList()) {
        if (_matchesScopedSuffix(k, cfgSuffix: rCfgSuffix, prefSuffix: rPrefSuffix, allowedScopes: allowedScopes)) {
          _cachedMeta[k] = st.copy();
        }
      }
      if (config != null) {
        config.challanHwm[configKey] = effVal;
        config.challanHwmMeta[configKey] = st.copy();
      }
      final Future<void> persistTask = (lastPersistFuture ?? Future.value()).then((_) async {
        final prefs = await SharedPreferences.getInstance();
        final currentSaved = prefs.getInt(hwmKey) ?? 0;
        if (effVal > currentSaved || wasRollback) {
          await prefs.setInt(hwmKey, effVal);
        }
        await prefs.setString(metaPrefKey, jsonEncode(st.toMap()));
        for (final k in prefs.getKeys()) {
          if (_matchesScopedSuffix(k, cfgSuffix: '', prefSuffix: rPrefSuffix, allowedScopes: allowedScopes)) {
            if (k.startsWith('challan_hwm_meta_')) {
              await prefs.setString(k, jsonEncode(st.toMap()));
            } else if (k.startsWith('challan_hwm_')) {
              final curK = prefs.getInt(k) ?? 0;
              if (effVal > curK || wasRollback) {
                await prefs.setInt(k, effVal);
              }
            }
          }
        }
      }).catchError((_) {});
      lastPersistFuture = persistTask;
      await persistTask;
    } else {
      if (config != null) {
        final existingCfgHwm = config.challanHwm[configKey] ?? 0;
        if (effVal > existingCfgHwm) {
          config.challanHwm[configKey] = effVal;
        }
      }
      final Future<void> persistTask = (lastPersistFuture ?? Future.value()).then((_) async {
        final prefs = await SharedPreferences.getInstance();
        final currentSaved = prefs.getInt(hwmKey) ?? 0;
        if (effVal > currentSaved) {
          await prefs.setInt(hwmKey, effVal);
        }
      }).catchError((_) {});
      lastPersistFuture = persistTask;
      await persistTask;
    }
  }

  /// Safely rolls back the Challan HWM for a specific `(companyID, fy, normType, env, prefix)` scope
  /// down to [newTail] after permanently deleting the series tail challan [deletedNum].
  /// Also rolls back legacy `lastID_` keys on APP so gap/tail reclaim works immediately across restarts.
  static Future<void>? lastPersistFuture;

  static ChallanHwmState? rollbackChallanHwmToTail({
    required String companyID,
    String type = "",
    String normType = "",
    required String prefix,
    required int newTail,
    required int deletedNum,
    required String fy,
    String env = "APP",
    AppConfig? config,
    String tombUuid = "",
    int d1Seq = 0,
  }) {
    final cleanPrefix = prefix.trim().toUpperCase();
    if (cleanPrefix.isEmpty) return null;

    final effectiveType = type.trim().isNotEmpty ? type : normType;
    final cleanComp = companyID.trim();
    final cleanFy = normalizeFyString(fy);
    final resolvedNormType = isPurchaseChallanType(effectiveType) ? "PURCHASE_CHALLAN" : "SALE_CHALLAN";
    final normEnv = env.trim().toUpperCase();
    final int safeTail = newTail < 0 ? 0 : newTail;

    final hwmKey = _prefKey(cleanComp, cleanFy, resolvedNormType, normEnv, cleanPrefix);
    final metaPrefKey = _metaPrefKey(cleanComp, cleanFy, resolvedNormType, normEnv, cleanPrefix);
    final configKey = _configKey(cleanComp, cleanFy, resolvedNormType, normEnv, cleanPrefix);

    final Set<String> allowedScopes = _resolveAllowedScopes(cleanComp);
    final prefSuffix = '_${cleanFy}_${resolvedNormType}_${normEnv}_$cleanPrefix';
    final cfgSuffix = '::${cleanFy}::${resolvedNormType}::${normEnv}::$cleanPrefix';

    int prevVal = max(
      deletedNum,
      max(
        _cachedHwm[hwmKey] ?? 0,
        max(_cachedHwm[configKey] ?? 0, config?.challanHwm[configKey] ?? 0),
      ),
    );
    for (final entry in _cachedHwm.entries) {
      if (_matchesScopedSuffix(entry.key, cfgSuffix: cfgSuffix, prefSuffix: prefSuffix, allowedScopes: allowedScopes)) {
        if (entry.value > prevVal) prevVal = entry.value;
      }
    }
    int prevGen = max(
      prevVal,
      max(
        _cachedMeta[configKey]?.gen ?? 0,
        max(_cachedMeta[metaPrefKey]?.gen ?? 0, config?.challanHwmMeta[configKey]?.gen ?? 0),
      ),
    );
    int prevSeq = d1Seq > 0
        ? d1Seq
        : max(_cachedMeta[configKey]?.seq ?? 0, config?.challanHwmMeta[configKey]?.seq ?? 0);
    for (final entry in _cachedMeta.entries) {
      if (_matchesScopedSuffix(entry.key, cfgSuffix: cfgSuffix, prefSuffix: prefSuffix, allowedScopes: allowedScopes)) {
        if (entry.value.gen > prevGen) prevGen = entry.value.gen;
        if (d1Seq == 0 && entry.value.seq > prevSeq) prevSeq = entry.value.seq;
      }
    }

    final state = ChallanHwmState(
      value: safeTail,
      seq: prevSeq,
      gen: prevGen + 1,
      op: 'ROLLBACK',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      deletedNum: deletedNum,
      tombUuid: tombUuid.trim(),
    );

    // Update exact keys and alias keys belonging ONLY to the same company scopes
    for (final k in _cachedHwm.keys.toList()) {
      if (_matchesScopedSuffix(k, cfgSuffix: cfgSuffix, prefSuffix: prefSuffix, allowedScopes: allowedScopes)) {
        if (safeTail > 0) {
          _cachedHwm[k] = safeTail;
        } else {
          _cachedHwm.remove(k);
        }
      }
    }
    if (safeTail > 0) {
      _cachedHwm[hwmKey] = safeTail;
      _cachedHwm[configKey] = safeTail;
    } else {
      _cachedHwm.remove(hwmKey);
      _cachedHwm.remove(configKey);
    }

    _cachedMeta[configKey] = state.copy();
    _cachedMeta[metaPrefKey] = state.copy();
    for (final k in _cachedMeta.keys.toList()) {
      if (_matchesScopedSuffix(k, cfgSuffix: cfgSuffix, prefSuffix: prefSuffix, allowedScopes: allowedScopes)) {
        _cachedMeta[k] = state.copy();
      }
    }

    if (config != null) {
      for (final k in config.challanHwm.keys.toList()) {
        if (k.endsWith(cfgSuffix)) {
          if (safeTail > 0) {
            config.challanHwm[k] = safeTail;
          } else {
            config.challanHwm.remove(k);
          }
        }
      }
      for (final k in config.challanHwmMeta.keys.toList()) {
        if (k.endsWith(cfgSuffix)) {
          config.challanHwmMeta[k] = state.copy();
        }
      }
      if (safeTail > 0) {
        config.challanHwm[configKey] = safeTail;
      } else {
        config.challanHwm.remove(configKey);
      }
      config.challanHwmMeta[configKey] = state.copy();
    }

    lastPersistFuture = (lastPersistFuture ?? Future.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (safeTail > 0) {
        await prefs.setInt(hwmKey, safeTail);
      } else {
        await prefs.remove(hwmKey);
      }
      await prefs.setString(metaPrefKey, jsonEncode(state.toMap()));

      for (final k in prefs.getKeys()) {
        if (_matchesScopedSuffix(k, cfgSuffix: '', prefSuffix: prefSuffix, allowedScopes: allowedScopes)) {
          if (k.startsWith('challan_hwm_meta_')) {
            await prefs.setString(k, jsonEncode(state.toMap()));
          } else if (k.startsWith('challan_hwm_')) {
            if (safeTail > 0) {
              await prefs.setInt(k, safeTail);
            } else {
              await prefs.remove(k);
            }
          }
        }
      }

      if (normEnv == "APP") {
        for (final legKey in _legacyLastIdKeys(effectiveType, resolvedNormType, cleanPrefix, cleanComp, cleanFy)) {
          if (safeTail > 0) {
            await prefs.setInt(legKey, safeTail);
          } else {
            await prefs.remove(legKey);
          }
        }
        for (final k in prefs.getKeys()) {
          if (_matchesScopedLegacyLastId(
            k,
            cleanPrefix: cleanPrefix,
            cleanFy: cleanFy,
            allowedScopes: allowedScopes,
          )) {
            if (safeTail > 0) {
              final existingLeg = prefs.getInt(k) ?? 0;
              if (existingLeg > safeTail) await prefs.setInt(k, safeTail);
            } else {
              await prefs.remove(k);
            }
          }
        }
      }
    }).catchError((e) {
      debugPrint("⚠️ [PharoahNumberingEngine] rollback prefs error: $e");
    });

    return state;
  }

  /// One-time migration self-heal on store load (`!config.challanHwmTailMigrated`):
  /// Clears orphan legacy HWMs (where no `challanHwmMeta` exists and `hwm > actual remaining non-deleted floor`),
  /// fixing legacy fresh stores stuck at `#2` after past tail deletes.
  static Future<bool> reconcileLegacyHwmOnLoad({
    required String companyID,
    required String fy,
    required AppConfig config,
    required Iterable<dynamic> saleChallans,
    required Iterable<dynamic> purchaseChallans,
  }) async {
    final String cleanComp = companyID.trim();
    final String cleanFy = normalizeFyString(fy);
    final Map<String, int> floor = AppConfig.computeChallanRecordFloor(
      companyID: cleanComp,
      saleChallans: saleChallans,
      purchaseChallans: purchaseChallans,
      targetFy: cleanFy,
    );

    bool mutated = false;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final String scopeHeader = '${cleanComp}::${cleanFy}::';

    if (!config.challanHwmTailMigrated) {
      final String legacy4Header = '${cleanFy}::';
      final Set<String> legacyCfgKeys = {
        ...config.challanHwm.keys.where((k) => k.startsWith(scopeHeader) || k.startsWith(legacy4Header)),
        ..._cachedHwm.keys.where((k) => k.startsWith(scopeHeader) || k.startsWith(legacy4Header)),
      };

      for (final rawKey in legacyCfgKeys) {
        final rawParts = rawKey.split('::');
        final bool is4Part = rawParts.length == 4;
        if (!is4Part && rawParts.length != 5) continue;
        final String cfgKey = is4Part
            ? _configKey(cleanComp, rawParts[0], rawParts[1], rawParts[2], rawParts[3])
            : rawKey;
        final parts = cfgKey.split('::');
        if (config.challanHwmMeta.containsKey(cfgKey) || config.challanHwmMeta.containsKey(rawKey)) continue;
        final int curHwm = max(
          max(config.challanHwm[cfgKey] ?? 0, config.challanHwm[rawKey] ?? 0),
          max(_cachedHwm[cfgKey] ?? 0, _cachedHwm[rawKey] ?? 0),
        );
        final int fl = floor[cfgKey] ?? 0;
        if (is4Part) {
          config.challanHwm.remove(rawKey);
          _cachedHwm.remove(rawKey);
          if (fl > 0 && curHwm <= fl) {
            config.challanHwm[cfgKey] = fl;
            _cachedHwm[cfgKey] = fl;
            mutated = true;
          }
        }
        if (curHwm > fl) {
          final String pKey = _prefKey(parts[0], parts[1], parts[2], parts[3], parts[4]);
          final String mKey = _metaPrefKey(parts[0], parts[1], parts[2], parts[3], parts[4]);
          final st = ChallanHwmState(
            value: fl,
            seq: 0,
            gen: curHwm + 1,
            op: 'ROLLBACK',
            updatedAt: nowMs,
          );
          if (fl > 0) {
            config.challanHwm[cfgKey] = fl;
            _cachedHwm[cfgKey] = fl;
            _cachedHwm[pKey] = fl;
          } else {
            config.challanHwm.remove(cfgKey);
            _cachedHwm.remove(cfgKey);
            _cachedHwm.remove(pKey);
          }
          config.challanHwmMeta[cfgKey] = st.copy();
          _cachedMeta[cfgKey] = st.copy();
          _cachedMeta[mKey] = st.copy();
          mutated = true;
        }
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        final String prefPrefix = 'challan_hwm_${cleanComp}_${cleanFy}_';
        for (final k in prefs.getKeys().toList()) {
          if (k.startsWith(prefPrefix) && !k.startsWith('challan_hwm_meta_')) {
            final suffix = k.substring('challan_hwm_'.length);
            // Parse <comp>_<fy>_<normType>_<env>_<prefix> safely via prefix match
            final rest = k.substring(prefPrefix.length);
            String? normType;
            String? restAfterType;
            if (rest.startsWith('SALE_CHALLAN_')) {
              normType = 'SALE_CHALLAN';
              restAfterType = rest.substring('SALE_CHALLAN_'.length);
            } else if (rest.startsWith('PURCHASE_CHALLAN_')) {
              normType = 'PURCHASE_CHALLAN';
              restAfterType = rest.substring('PURCHASE_CHALLAN_'.length);
            }
            if (normType == null || restAfterType == null) continue;
            final usIdx = restAfterType.indexOf('_');
            if (usIdx <= 0) continue;
            final String env = restAfterType.substring(0, usIdx);
            final String prefix = restAfterType.substring(usIdx + 1);
            final String cfgKey = _configKey(cleanComp, cleanFy, normType, env, prefix);
            final String metaK = _metaPrefKey(cleanComp, cleanFy, normType, env, prefix);
            if (config.challanHwmMeta.containsKey(cfgKey) || prefs.containsKey(metaK)) continue;

            final int savedVal = prefs.getInt(k) ?? 0;
            final int fl = floor[cfgKey] ?? 0;
            if (savedVal > fl) {
              final st = ChallanHwmState(
                value: fl,
                seq: 0,
                gen: savedVal + 1,
                op: 'ROLLBACK',
                updatedAt: nowMs,
              );
              if (fl > 0) {
                await prefs.setInt(k, fl);
                config.challanHwm[cfgKey] = fl;
                _cachedHwm[cfgKey] = fl;
                _cachedHwm[k] = fl;
              } else {
                await prefs.remove(k);
                config.challanHwm.remove(cfgKey);
                _cachedHwm.remove(cfgKey);
                _cachedHwm.remove(k);
              }
              await prefs.setString(metaK, jsonEncode(st.toMap()));
              config.challanHwmMeta[cfgKey] = st.copy();
              _cachedMeta[cfgKey] = st.copy();
              _cachedMeta[metaK] = st.copy();
              if (env == 'APP') {
                for (final legKey in _legacyLastIdKeys(normType, normType, prefix, cleanComp, cleanFy)) {
                  if (fl > 0) {
                    await prefs.setInt(legKey, fl);
                  } else {
                    await prefs.remove(legKey);
                  }
                }
              }
              mutated = true;
            } else if (suffix.isEmpty) {
              continue;
            }
          }
        }
      } catch (_) {}

      config.challanHwmTailMigrated = true;
      mutated = true;
    }

    absorbChallanHwmState(
      hwm: config.challanHwm,
      meta: config.challanHwmMeta,
      recordFloor: floor,
      companyScopes: [if (cleanComp.isNotEmpty) cleanComp],
    );
    return mutated;
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
      debugPrint("🛡️ [PharoahNumberingEngine] Refusing bulk resetSeries for Challan $type (use rollbackChallanHwmToTail)");
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    String currentFY = prefs.getString('active_fy_$companyID') ?? "default_fy";
    String counterKey = 'lastID_${type}_${prefix}_${companyID}_$currentFY';
    await prefs.remove(counterKey);
  }
}
