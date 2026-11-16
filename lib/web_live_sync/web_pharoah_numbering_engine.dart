// FILE: lib/web_live_sync/web_pharoah_numbering_engine.dart
// Revision: #PH-REV-820 (TAIL-ROLLBACK-AND-CAUSAL-CHALLAN-HWM-WEB-ENGINE)

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../logic/app_settings_model.dart';
import '../../models.dart' show normalizeFyString;
import 'web_models.dart';

class WebPharoahNumberingEngine {
  /// In-memory cache of Challan High-Water Marks and Causal Metadata for fast synchronous access
  static final Map<String, int> _cachedHwm = {};
  static final Map<String, ChallanHwmState> _cachedMeta = {};

  @visibleForTesting
  static void debugResetHwmCache() {
    _cachedHwm.clear();
    _cachedMeta.clear();
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

  /// Causally absorbs incoming HWM values & metadata into the in-memory cache and SharedPreferences
  static void absorbChallanHwmState({
    required Map<String, int> hwm,
    Map<String, ChallanHwmState> meta = const {},
    Map<String, int> recordFloor = const {},
  }) {
    final Map<String, int> curCfgHwm = {};
    final Map<String, ChallanHwmState> curCfgMeta = {};
    _cachedHwm.forEach((k, v) {
      if (k.contains('::')) curCfgHwm[k] = v;
    });
    _cachedMeta.forEach((k, v) {
      if (k.contains('::')) curCfgMeta[k] = v;
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

      // Harmonize all memory cache entries matching this series suffix
      final parts = cfgKey.split('::');
      if (parts.length == 5) {
        final cfgSuffix = '::${parts[1]}::${parts[2]}::${parts[3]}::${parts[4]}';
        final prefSuffix = '_${parts[1]}_${parts[2]}_${parts[3]}_${parts[4]}';
        for (final k in _cachedHwm.keys.toList()) {
          if (k.endsWith(cfgSuffix) || k.endsWith(prefSuffix)) {
            if (val > 0) {
              _cachedHwm[k] = val;
            } else {
              _cachedHwm.remove(k);
            }
          }
        }
        for (final k in _cachedMeta.keys.toList()) {
          if (k.endsWith(cfgSuffix) || k.endsWith(prefSuffix)) {
            if (st != null) {
              _cachedMeta[k] = st.copy();
            }
          }
        }
      }
    }

    SharedPreferences.getInstance().then((prefs) {
      for (final cfgKey in affectedKeys) {
        final parts = cfgKey.split('::');
        if (parts.length != 5) continue;
        final String prefKey = _prefKey(parts[0], parts[1], parts[2], parts[3], parts[4]);
        final String metaPrefKey = _metaPrefKey(parts[0], parts[1], parts[2], parts[3], parts[4]);
        final int val = resolved.hwm[cfgKey] ?? 0;
        final ChallanHwmState? st = resolved.meta[cfgKey];
        if (val > 0) {
          prefs.setInt(prefKey, val);
        } else {
          prefs.remove(prefKey);
        }
        if (st != null) {
          prefs.setString(metaPrefKey, jsonEncode(st.toMap()));
          final prefSuffix = '_${parts[1]}_${parts[2]}_${parts[3]}_${parts[4]}';
          for (final k in prefs.getKeys()) {
            if (k.startsWith('challan_hwm_') && !k.startsWith('challan_hwm_meta_') && k.endsWith(prefSuffix)) {
              if (val > 0) {
                prefs.setInt(k, val);
              } else {
                prefs.remove(k);
              }
            } else if (k.startsWith('challan_hwm_meta_') && k.endsWith(prefSuffix)) {
              prefs.setString(k, jsonEncode(st.toMap()));
            }
          }
        }
      }
    }).catchError((_) {});
  }

  /// Backward-compatible HWM map absorption helper
  static void absorbChallanHwmMap(Map<String, int> incoming) {
    if (incoming.isEmpty) return;
    absorbChallanHwmState(hwm: incoming);
  }

  /// Initializes HWM & Meta cache from local storage / SharedPreferences
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
              final dec = jsonDecode(rawStr);
              if (dec is Map) {
                prefMeta[k] = ChallanHwmState.fromMap(dec);
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
        final existingMeta = _cachedMeta[metaK];
        if (existingMeta == null || st.gen > existingMeta.gen || (st.seq > 0 && st.seq > existingMeta.seq)) {
          _cachedMeta[metaK] = st.copy();
          if (st.value > 0) {
            _cachedHwm[hwmK] = st.value;
          } else {
            _cachedHwm.remove(hwmK);
          }
        }
      });

      prefHwm.forEach((hwmK, val) {
        final metaK = hwmK.replaceFirst('challan_hwm_', 'challan_hwm_meta_');
        if (!_cachedMeta.containsKey(metaK) && val > (_cachedHwm[hwmK] ?? 0)) {
          _cachedHwm[hwmK] = val;
        }
      });
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
    return AppConfig.inferIsWebChallanRecord(item);
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

    // Check if winning causal meta for this series suffix indicates ROLLBACK
    ChallanHwmState? winningMeta;
    for (final entry in _cachedMeta.entries) {
      if (entry.key.endsWith(cfgSuffix) || entry.key.endsWith(prefSuffix)) {
        if (winningMeta == null ||
            entry.value.gen > winningMeta.gen ||
            (entry.value.seq > 0 && entry.value.seq > winningMeta.seq)) {
          winningMeta = entry.value;
        }
      }
    }
    if (winningMeta != null && winningMeta.op == 'ROLLBACK') {
      return winningMeta.value;
    }

    for (final entry in _cachedHwm.entries) {
      if (entry.key.endsWith(prefSuffix) || entry.key.endsWith(cfgSuffix)) {
        if (entry.value > best) best = entry.value;
      }
    }
    if (configHwm != null && configHwm.isNotEmpty) {
      final legacy4Part = (cleanFy.isNotEmpty)
          ? '${cleanFy}::${normType}::${normEnv}::$cleanPrefix'
          : '${normType}::${normEnv}::$cleanPrefix';
      for (final entry in configHwm.entries) {
        if (entry.key == legacy4Part) {
          if (entry.value > best) best = entry.value;
          continue;
        }
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

  /// Records issued Challan number into persistent HWM cache, `challanHwmMeta`, and SharedPreferences
  static void recordChallanHwm({
    required String prefix,
    required String number,
    required String fy,
    String env = "WEB",
    AppConfig? config,
    String companyID = "",
    int d1Seq = 0,
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

    final cacheKey = _prefKey(cleanComp, cleanFy, normType, normEnv, cleanPrefix);
    final metaPrefKey = _metaPrefKey(cleanComp, cleanFy, normType, normEnv, cleanPrefix);
    final configKey = _configKey(cleanComp, cleanFy, normType, normEnv, cleanPrefix);

    final int prevVal = max(
      _cachedHwm[cacheKey] ?? 0,
      max(_cachedHwm[configKey] ?? 0, config?.challanHwm[configKey] ?? 0),
    );
    final int prevGen = max(
      prevVal,
      max(
        _cachedMeta[configKey]?.gen ?? 0,
        max(_cachedMeta[metaPrefKey]?.gen ?? 0, config?.challanHwmMeta[configKey]?.gen ?? 0),
      ),
    );
    final int prevSeq = max(
      d1Seq,
      max(_cachedMeta[configKey]?.seq ?? 0, config?.challanHwmMeta[configKey]?.seq ?? 0),
    );

    final int effVal = issuedInt > prevVal ? issuedInt : prevVal;
    final bool needsMetaUpdate = issuedInt > prevVal ||
        !_cachedMeta.containsKey(configKey) ||
        (config != null && !config.challanHwmMeta.containsKey(configKey));

    if (issuedInt > (_cachedHwm[cacheKey] ?? 0)) {
      _cachedHwm[cacheKey] = issuedInt;
    }
    if (issuedInt > (_cachedHwm[configKey] ?? 0)) {
      _cachedHwm[configKey] = issuedInt;
    }
    final rPrefSuffix = (cleanFy.isNotEmpty)
        ? '_${cleanFy}_${normType}_${normEnv}_$cleanPrefix'
        : '_${normType}_${normEnv}_$cleanPrefix';
    final rCfgSuffix = (cleanFy.isNotEmpty)
        ? '::${cleanFy}::${normType}::${normEnv}::$cleanPrefix'
        : '::${normType}::${normEnv}::$cleanPrefix';
    for (final k in _cachedHwm.keys.toList()) {
      if (k.endsWith(rPrefSuffix) || k.endsWith(rCfgSuffix)) {
        if (effVal > (_cachedHwm[k] ?? 0)) _cachedHwm[k] = effVal;
      }
    }

    ChallanHwmState? stToPersist;
    if (needsMetaUpdate) {
      final int nextGen = issuedInt > prevVal ? (prevGen + 1) : max(prevGen, issuedInt);
      stToPersist = ChallanHwmState(
        value: effVal,
        seq: prevSeq,
        gen: nextGen,
        op: 'SET',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _cachedMeta[configKey] = stToPersist.copy();
      _cachedMeta[metaPrefKey] = stToPersist.copy();
      if (config != null) {
        config.challanHwm[configKey] = effVal;
        config.challanHwmMeta[configKey] = stToPersist.copy();
      }
    } else if (config != null) {
      final existingCfg = config.challanHwm[configKey] ?? 0;
      if (effVal > existingCfg) {
        config.challanHwm[configKey] = effVal;
      }
    }

    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getInt(cacheKey) ?? 0;
      if (effVal > saved) {
        prefs.setInt(cacheKey, effVal);
      }
      if (stToPersist != null) {
        prefs.setString(metaPrefKey, jsonEncode(stToPersist.toMap()));
      }
    }).catchError((_) {});
  }

  /// Safely rolls back the Web Challan HWM for `(companyID, fy, normType, env, prefix)` to [newTail]
  /// after permanently deleting the series tail challan [deletedNum].
  static ChallanHwmState? rollbackChallanHwmToTail({
    required String prefix,
    required String normType,
    required int newTail,
    required int deletedNum,
    required String fy,
    String env = "WEB",
    AppConfig? config,
    String companyID = "",
    String tombUuid = "",
    int d1Seq = 0,
  }) {
    final cleanPrefix = prefix.trim().toUpperCase();
    if (cleanPrefix.isEmpty) return null;

    final cleanFy = normalizeFyString(fy);
    final normEnv = env.trim().toUpperCase();
    final cleanComp = companyID.trim();
    final int safeTail = newTail < 0 ? 0 : newTail;

    final cacheKey = _prefKey(cleanComp, cleanFy, normType, normEnv, cleanPrefix);
    final metaPrefKey = _metaPrefKey(cleanComp, cleanFy, normType, normEnv, cleanPrefix);
    final configKey = _configKey(cleanComp, cleanFy, normType, normEnv, cleanPrefix);

    final int prevVal = max(
      deletedNum,
      max(
        _cachedHwm[cacheKey] ?? 0,
        max(_cachedHwm[configKey] ?? 0, config?.challanHwm[configKey] ?? 0),
      ),
    );
    final int prevGen = max(
      prevVal,
      max(
        _cachedMeta[configKey]?.gen ?? 0,
        max(_cachedMeta[metaPrefKey]?.gen ?? 0, config?.challanHwmMeta[configKey]?.gen ?? 0),
      ),
    );
    final int prevSeq = d1Seq > 0
        ? d1Seq
        : max(_cachedMeta[configKey]?.seq ?? 0, config?.challanHwmMeta[configKey]?.seq ?? 0);

    final state = ChallanHwmState(
      value: safeTail,
      seq: prevSeq,
      gen: prevGen + 1,
      op: 'ROLLBACK',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      deletedNum: deletedNum,
      tombUuid: tombUuid.trim(),
    );

    final prefSuffix = (cleanFy.isNotEmpty)
        ? '_${cleanFy}_${normType}_${normEnv}_$cleanPrefix'
        : '_${normType}_${normEnv}_$cleanPrefix';
    final cfgSuffix = (cleanFy.isNotEmpty)
        ? '::${cleanFy}::${normType}::${normEnv}::$cleanPrefix'
        : '::${normType}::${normEnv}::$cleanPrefix';

    for (final k in _cachedHwm.keys.toList()) {
      if (k.endsWith(prefSuffix) || k.endsWith(cfgSuffix)) {
        if (safeTail > 0) {
          _cachedHwm[k] = safeTail;
        } else {
          _cachedHwm.remove(k);
        }
      }
    }
    if (safeTail > 0) {
      _cachedHwm[cacheKey] = safeTail;
      _cachedHwm[configKey] = safeTail;
    } else {
      _cachedHwm.remove(cacheKey);
      _cachedHwm.remove(configKey);
    }

    _cachedMeta[configKey] = state.copy();
    _cachedMeta[metaPrefKey] = state.copy();
    for (final k in _cachedMeta.keys.toList()) {
      if (k.endsWith(prefSuffix) || k.endsWith(cfgSuffix)) {
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

    SharedPreferences.getInstance().then((prefs) {
      if (safeTail > 0) {
        prefs.setInt(cacheKey, safeTail);
      } else {
        prefs.remove(cacheKey);
      }
      prefs.setString(metaPrefKey, jsonEncode(state.toMap()));

      for (final k in prefs.getKeys()) {
        if (k.startsWith('challan_hwm_') && !k.startsWith('challan_hwm_meta_') && k.endsWith(prefSuffix)) {
          if (safeTail > 0) {
            prefs.setInt(k, safeTail);
          } else {
            prefs.remove(k);
          }
        } else if (k.startsWith('challan_hwm_meta_') && k.endsWith(prefSuffix)) {
          prefs.setString(k, jsonEncode(state.toMap()));
        }
      }
    }).catchError((_) {});

    return state;
  }

  /// One-time migration self-heal on store load (`!config.challanHwmTailMigrated`):
  /// Clears orphan legacy Web/App HWMs lacking `challanHwmMeta` where no active/cancelled record exists
  /// (fixing fresh stores stuck at `WSCH-2` / `WPCH-2`).
  static bool reconcileLegacyHwmOnLoad({
    required String companyID,
    required String fy,
    required AppConfig config,
    required Iterable<dynamic> saleChallans,
    required Iterable<dynamic> purchaseChallans,
  }) {
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

      SharedPreferences.getInstance().then((prefs) {
        final String prefPrefix = 'challan_hwm_${cleanComp}_${cleanFy}_';
        for (final k in prefs.getKeys().toList()) {
          if (k.startsWith(prefPrefix) && !k.startsWith('challan_hwm_meta_')) {
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
                prefs.setInt(k, fl);
              } else {
                prefs.remove(k);
              }
              prefs.setString(metaK, jsonEncode(st.toMap()));
            }
          }
        }
      }).catchError((_) {});

      config.challanHwmTailMigrated = true;
      mutated = true;
    }

    absorbChallanHwmState(
      hwm: config.challanHwm,
      meta: config.challanHwmMeta,
      recordFloor: floor,
    );
    return mutated;
  }

  /// Coordinated sequential number generator matching Mobile App.
  /// TAIL-ROLLBACK HWM FOR CHALLANS:
  /// Preserves cancelled & active numbers while allowing deleted series tails to be reclaimed.
  static String getNextNumber({
    required String prefix,
    required int startFrom,
    required List<dynamic> currentList,
    String? targetFy,
    String env = "WEB",
    String companyID = "",
    Map<String, int>? configHwm,
    Iterable<String>? tombstones, // Retained for signature compatibility; ignored for Challan tail reclaim
    bool isChallanDoc = false,
  }) {
    List<int> existingNumbers = [];
    final String cleanPrefix = prefix.trim().toUpperCase();
    final String cleanTargetFy = normalizeFyString(targetFy ?? '');
    final String normEnv = env.trim().toUpperCase();
    final int safeStart = startFrom < 1 ? 1 : startFrom;
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
          if (item.isDeleted == 1 || item.status.trim().toUpperCase() == "DELETED") continue;
          if (cleanTargetFy.isNotEmpty && normalizeFyString(item.effectiveOriginalFy) != cleanTargetFy) {
            continue;
          }
          final bool itemIsWeb = isWebChallanRecord(item);
          if (normEnv == "WEB" && !itemIsWeb) continue;
          if (normEnv == "APP" && itemIsWeb) continue;
          idToParse = item.billNo;
        } else if (item is PurchaseChallan) {
          if (item.isDeleted == 1 || item.status.trim().toUpperCase() == "DELETED") continue;
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
          final int isDel = int.tryParse((item['isDeleted'] ?? item['is_deleted'] ?? '0').toString()) ?? 0;
          final String st = (item['status'] ?? '').toString().trim().toUpperCase();
          if (isChallanList && (isDel == 1 || st == 'DELETED')) continue;
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
    // CHALLAN TAIL-ROLLBACK HIGH-WATER MARK (NO MIDDLE GAP-FILLING)
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
      int hwm = max(cachedOrCfg, maxExisting);
      int next = (hwm >= safeStart) ? (hwm + 1) : safeStart;
      return "$prefix$next";
    }

    // -------------------------------------------------------------------------
    // STANDARD BILLS: CONTINUOUS GAP-FILLING
    // -------------------------------------------------------------------------
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
}
