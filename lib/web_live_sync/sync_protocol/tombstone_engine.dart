// FILE: lib/web_live_sync/sync_protocol/tombstone_engine.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../pharoah_manager.dart';
import '../../sync_core/d1_sales_ledger_service.dart';

class TombstoneEngine {
  static String _normalizeKeyForStorage(String key, [String? fy, bool preserveCase = false]) {
    final clean = key.trim();
    if (clean.isEmpty) return "";
    if (D1SalesLedgerService.isUnscopedSeriesKey(clean)) {
      return D1SalesLedgerService.scopeSecondaryKey(clean, fy, preserveCase || clean.contains('_'));
    }
    return clean;
  }

  /// Returns a map of { key : deletedAtTimestampMs } for chronological anti-zombie resolution.
  /// Automatically strips legacy unscoped series keys (e.g. "INV-1", "PUR-1") so they never poison other FYs.
  static Future<Map<String, int>> getTombstoneRegistry(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tombstone_registry_$companyId');
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, int>{};
      bool hadUnscoped = false;
      decoded.forEach((k, v) {
        final cleanK = k.toString().trim();
        if (cleanK.isNotEmpty) {
          if (D1SalesLedgerService.isUnscopedSeriesKey(cleanK)) {
            hadUnscoped = true;
          } else {
            result[cleanK] = int.tryParse(v.toString()) ?? 0;
          }
        }
      });
      if (hadUnscoped) {
        await prefs.setString('tombstone_registry_$companyId', jsonEncode(result));
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveTombstoneRegistry(String companyId, Map<String, int> registry) async {
    final prefs = await SharedPreferences.getInstance();
    final sanitized = <String, int>{};
    registry.forEach((k, v) {
      final cleanK = k.trim();
      if (cleanK.isNotEmpty && !D1SalesLedgerService.isUnscopedSeriesKey(cleanK)) {
        sanitized[cleanK] = v;
      }
    });
    await prefs.setString('tombstone_registry_$companyId', jsonEncode(sanitized));
  }

  /// Records a deletion with high-precision timestamp into registry (ID and FY-Scoped Secondary Keys)
  static Future<void> recordTombstoneWithTimestamp(
    String companyId, {
    required String id,
    String? secondaryKey,
    int? timestamp,
    String? fy,
  }) async {
    final registry = await getTombstoneRegistry(companyId);
    final int ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final cleanId = _normalizeKeyForStorage(id, fy, id.contains('_'));
    if (cleanId.isNotEmpty) {
      registry[cleanId] = ts;
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      final cleanSec = D1SalesLedgerService.scopeSecondaryKey(secondaryKey, fy, secondaryKey.contains('_'));
      if (cleanSec.isNotEmpty) {
        registry[cleanSec] = ts;
      }
    }
    await saveTombstoneRegistry(companyId, registry);
    await recordTombstone(companyId, id: cleanId, secondaryKey: secondaryKey, fy: fy);
  }

  /// Returns timestamped unmark map so stale unmarks never block newer cloud deletions.
  static Future<Map<String, int>> getUnmarkedRegistry(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('unmarked_registry_$companyId');
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final res = <String, int>{};
      decoded.forEach((k, v) {
        final ck = k.toString().trim();
        if (ck.isNotEmpty) res[ck] = int.tryParse(v.toString()) ?? 0;
      });
      return res;
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveUnmarkedRegistry(String companyId, Map<String, int> reg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('unmarked_registry_$companyId', jsonEncode(reg));
  }

  /// Unmarks a tombstone when a bill is explicitly re-created or updated with a newer timestamp
  static Future<void> unmarkTombstoneWithTimestamp(
    String companyId, {
    required String id,
    String? secondaryKey,
    String? fy,
    int? timestamp,
  }) async {
    final int unmarkTs = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final registry = await getTombstoneRegistry(companyId);
    final unmarkReg = await getUnmarkedRegistry(companyId);
    final cleanId = id.trim();
    final bool keepIdCase = cleanId.contains('_');
    final scopedId = D1SalesLedgerService.scopeSecondaryKey(cleanId, fy, keepIdCase);
    if (cleanId.isNotEmpty) {
      registry.remove(cleanId);
      if (!keepIdCase) registry.remove(cleanId.toUpperCase());
      registry.remove(scopedId);
      unmarkReg[cleanId] = unmarkTs;
      if (!keepIdCase) unmarkReg[cleanId.toUpperCase()] = unmarkTs;
      if (scopedId.isNotEmpty) unmarkReg[scopedId] = unmarkTs;
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      final rawSec = secondaryKey.trim();
      final bool keepSecCase = rawSec.contains('_');
      final scopedSec = D1SalesLedgerService.scopeSecondaryKey(rawSec, fy, keepSecCase);
      registry.remove(rawSec);
      if (!keepSecCase) registry.remove(rawSec.toUpperCase());
      registry.remove(scopedSec);
      unmarkReg[rawSec] = unmarkTs;
      if (!keepSecCase) unmarkReg[rawSec.toUpperCase()] = unmarkTs;
      if (scopedSec.isNotEmpty) unmarkReg[scopedSec] = unmarkTs;
    }
    await saveTombstoneRegistry(companyId, registry);
    await saveUnmarkedRegistry(companyId, unmarkReg);
    await unmarkTombstone(companyId, id: cleanId, secondaryKey: secondaryKey, fy: fy);
  }

  // --- Set-based APIs ---
  static Future<Set<String>> getLocalTombstones(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('tombstones_$companyId') ?? [];
    final filtered = list.where((k) => k.trim().isNotEmpty && !D1SalesLedgerService.isUnscopedSeriesKey(k)).toSet();
    if (filtered.length != list.length) {
      await prefs.setStringList('tombstones_$companyId', filtered.toList());
    }
    return filtered;
  }

  static Future<void> saveLocalTombstones(String companyId, Set<String> tombstones) async {
    final prefs = await SharedPreferences.getInstance();
    final sanitized = tombstones
        .where((k) => k.trim().isNotEmpty && !D1SalesLedgerService.isUnscopedSeriesKey(k))
        .toList();
    await prefs.setStringList('tombstones_$companyId', sanitized);
  }

  static Future<Set<String>> getUnmarkedKeys(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('unmarked_tombstones_$companyId') ?? []).toSet();
  }

  static Future<void> saveUnmarkedKeys(String companyId, Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('unmarked_tombstones_$companyId', keys.toList());
  }

  static Future<void> unmarkTombstone(
    String companyId, {
    required String id,
    String? secondaryKey,
    String? fy,
  }) async {
    final tombstones = await getLocalTombstones(companyId);
    final unmarked = await getUnmarkedKeys(companyId);
    final cleanId = id.trim();
    final bool keepIdCase = cleanId.contains('_');
    final scopedId = D1SalesLedgerService.scopeSecondaryKey(cleanId, fy, keepIdCase);
    if (cleanId.isNotEmpty) {
      tombstones.remove(cleanId);
      if (!keepIdCase) tombstones.remove(cleanId.toUpperCase());
      tombstones.remove(scopedId);
      unmarked.add(cleanId);
      if (!keepIdCase) unmarked.add(cleanId.toUpperCase());
      if (scopedId.isNotEmpty) unmarked.add(scopedId);
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      final cleanSec = secondaryKey.trim();
      final bool keepSecCase = cleanSec.contains('_');
      final scopedSec = D1SalesLedgerService.scopeSecondaryKey(cleanSec, fy, keepSecCase);
      tombstones.remove(cleanSec);
      if (!keepSecCase) tombstones.remove(cleanSec.toUpperCase());
      tombstones.remove(scopedSec);
      unmarked.add(cleanSec);
      if (!keepSecCase) unmarked.add(cleanSec.toUpperCase());
      if (scopedSec.isNotEmpty) unmarked.add(scopedSec);
    }
    await saveLocalTombstones(companyId, tombstones);
    await saveUnmarkedKeys(companyId, unmarked);
  }

  static Future<Set<String>> recordTombstone(
    String companyId, {
    required String id,
    String? secondaryKey,
    String? fy,
  }) async {
    final tombstones = await getLocalTombstones(companyId);
    final unmarked = await getUnmarkedKeys(companyId);
    final bool keepIdCase = id.contains('_');
    final cleanId = _normalizeKeyForStorage(id, fy, keepIdCase);
    if (cleanId.isNotEmpty) {
      tombstones.add(cleanId);
      unmarked.remove(cleanId);
      if (!keepIdCase) unmarked.remove(cleanId.toUpperCase());
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      final bool keepSecCase = secondaryKey.contains('_');
      final cleanSec = D1SalesLedgerService.scopeSecondaryKey(secondaryKey, fy, keepSecCase);
      if (cleanSec.isNotEmpty) {
        tombstones.add(cleanSec);
        unmarked.remove(cleanSec);
        if (!keepSecCase) unmarked.remove(secondaryKey.trim().toUpperCase());
      }
    }
    await saveLocalTombstones(companyId, tombstones);
    await saveUnmarkedKeys(companyId, unmarked);
    return tombstones;
  }

  static Future<Set<String>> recordBatchTombstones(
    String companyId,
    Iterable<String> keys, {
    int? timestamp,
    String? fy,
  }) async {
    final registry = await getTombstoneRegistry(companyId);
    final int ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final tombstones = await getLocalTombstones(companyId);
    final unmarked = await getUnmarkedKeys(companyId);
    final unmarkReg = await getUnmarkedRegistry(companyId);
    for (var k in keys) {
      final rawK = k.trim();
      if (rawK.isEmpty) continue;
      final bool keepCase = rawK.contains('_');
      final cleanK = _normalizeKeyForStorage(rawK, fy, keepCase);
      if (cleanK.isNotEmpty) {
        registry[cleanK] = ts;
        if (!keepCase) registry[cleanK.toUpperCase()] = ts;
        tombstones.add(cleanK);
        if (!keepCase) tombstones.add(cleanK.toUpperCase());
        unmarked.remove(cleanK);
        unmarkReg.remove(cleanK);
        if (!keepCase) {
          unmarked.remove(cleanK.toUpperCase());
          unmarkReg.remove(cleanK.toUpperCase());
        }
        unmarked.remove(rawK);
        unmarkReg.remove(rawK);
        if (!keepCase) {
          unmarked.remove(rawK.toUpperCase());
          unmarkReg.remove(rawK.toUpperCase());
        }
      }
    }
    await saveTombstoneRegistry(companyId, registry);
    await saveLocalTombstones(companyId, tombstones);
    await saveUnmarkedKeys(companyId, unmarked);
    await saveUnmarkedRegistry(companyId, unmarkReg);
    return tombstones;
  }

  /// Removes unmarked status when an authoritative newer cloud deletion is observed.
  static Future<void> clearUnmarkedForDeletedKeys(String companyId, Iterable<String> keys) async {
    final unmarked = await getUnmarkedKeys(companyId);
    final unmarkReg = await getUnmarkedRegistry(companyId);
    bool changed = false;
    for (final k in keys) {
      final ck = k.trim();
      if (ck.isEmpty) continue;
      if (unmarked.remove(ck)) changed = true;
      if (unmarkReg.remove(ck) != null) changed = true;
      if (!ck.contains('_')) {
        if (unmarked.remove(ck.toUpperCase())) changed = true;
        if (unmarkReg.remove(ck.toUpperCase()) != null) changed = true;
      }
    }
    if (changed) {
      await saveUnmarkedKeys(companyId, unmarked);
      await saveUnmarkedRegistry(companyId, unmarkReg);
    }
  }

    /// 🛡️ SELF-HEALING DISINFECTION (#PH-REV-807):
  /// Scans SharedPreferences and purges all poisoned legacy naked series keys (e.g. "INV-1", "W-1", "PUR-1")
  /// that lack a financial year prefix ("FY::"), ensuring past back-year deletions stop killing bills in new FYs!
  static Future<void> purgeNakedSeriesTombstones(String companyId) async {
    if (companyId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = "tombstones_$companyId";
      final list = prefs.getStringList(key) ?? [];
      final sanitized = list.where((k) {
        final clean = k.trim();
        if (clean.isEmpty) return false;
        if (clean.contains("::")) return true;
        return !D1SalesLedgerService.isUnscopedSeriesKey(clean);
      }).toList();
      if (sanitized.length != list.length) {
        await prefs.setStringList(key, sanitized);
      }

      final regKey = "tombstone_registry_$companyId";
      final regRaw = prefs.getString(regKey);
      if (regRaw != null && regRaw.isNotEmpty) {
        final decoded = jsonDecode(regRaw) as Map<String, dynamic>;
        final cleanReg = <String, dynamic>{};
        bool hadUnscoped = false;
        decoded.forEach((k, v) {
          final clean = k.toString().trim();
          if (clean.contains("::") || !D1SalesLedgerService.isUnscopedSeriesKey(clean)) {
            cleanReg[clean] = v;
          } else {
            hadUnscoped = true;
          }
        });
        if (hadUnscoped) {
          await prefs.setString(regKey, jsonEncode(cleanReg));
        }
      }
    } catch (_) {}
  }

  static Future<Set<String>> sanitizeCloudTombstones(
    String companyId,
    Iterable<String> incomingCloudTombstones, {
    Map<String, int>? cloudRegistry,
    Set<String>? absentFromCloudIds,
  }) async {
    final unmarked = await getUnmarkedKeys(companyId);
    final unmarkReg = await getUnmarkedRegistry(companyId);
    final sanitized = <String>{};
    for (var k in incomingCloudTombstones) {
      final cleanK = k.trim();
      if (cleanK.isEmpty) continue;
      if (D1SalesLedgerService.isUnscopedSeriesKey(cleanK)) continue;
      // If cloud tombstone has a strictly newer deletion timestamp than our local unmark, accept the deletion!
      final int unmarkTs = unmarkReg[cleanK] ?? (!cleanK.contains('_') ? (unmarkReg[cleanK.toUpperCase()] ?? 0) : 0);
      final int cloudTs = cloudRegistry != null
          ? (cloudRegistry[cleanK] ?? (!cleanK.contains('_') ? (cloudRegistry[cleanK.toUpperCase()] ?? 0) : 0))
          : 0;
      
      if (unmarkTs > 0) {
        if (cloudTs > 0 && cloudTs >= unmarkTs) {
          sanitized.add(cleanK);
        }
        continue;
      }

      final bool isMarkedUnmarked = unmarked.contains(cleanK) || (!cleanK.contains('_') && unmarked.contains(cleanK.toUpperCase()));
      if (!isMarkedUnmarked) {
        sanitized.add(cleanK);
        continue;
      }
      if (cloudTs > 0 && cloudTs >= unmarkTs) {
        sanitized.add(cleanK);
        continue;
      }
      // If record is explicitly absent from cloud snapshot, an older unmark must not block cloud tombstone.
      if (absentFromCloudIds != null &&
          !absentFromCloudIds.contains(cleanK) &&
          (cleanK.contains('_') || !absentFromCloudIds.contains(cleanK.toUpperCase()))) {
        sanitized.add(cleanK);
      }
    }
    return sanitized;
  }

  /// 🛡️ Chronological Anti-Zombie Registry Purge (Strictly Scoped to ph.currentFY for secondary keys):
  static void purgeDeletedRecordsWithRegistry(PharoahManager ph, Map<String, int> registry) {
    if (registry.isEmpty) return;
    final String fy = ph.currentFY.trim();

    ph.sales.removeWhere((e) {
      final bNo = D1SalesLedgerService.scopeSecondaryKey(e.billNo, fy);
      final int? idDelTime = registry[e.id] ?? registry[e.id.toUpperCase()];
      if (idDelTime != null) {
        return e.updatedAt == 0 || idDelTime >= e.updatedAt;
      }
      final delTime = bNo.isNotEmpty ? registry[bNo] : null;
      return delTime != null && e.updatedAt > 0 && delTime >= e.updatedAt;
    });

    ph.purchases.removeWhere((e) {
      final iNo = D1SalesLedgerService.scopeSecondaryKey(e.internalNo, fy);
      final pId = e.partyId.trim().toUpperCase();
      final bNo = e.billNo.trim();
      final compKey2 = (pId.isNotEmpty && bNo.isNotEmpty) ? D1SalesLedgerService.scopeSecondaryKey("${pId}_$bNo", fy, true) : "";
      final compKey3 = (pId.isNotEmpty && bNo.isNotEmpty && e.internalNo.trim().isNotEmpty)
          ? D1SalesLedgerService.scopeSecondaryKey("${pId}_${bNo}_${e.internalNo.trim().toUpperCase()}", fy, true)
          : "";
      final int? idDelTime = registry[e.id] ?? registry[e.id.toUpperCase()];
      if (idDelTime != null) {
        return e.updatedAt == 0 || idDelTime >= e.updatedAt;
      }
      final int? delTime = (iNo.isNotEmpty ? registry[iNo] : null) ??
          (compKey3.isNotEmpty ? registry[compKey3] : null) ??
          (compKey2.isNotEmpty ? registry[compKey2] : null);
      return delTime != null && e.updatedAt > 0 && delTime >= e.updatedAt;
    });

    ph.saleChallans.removeWhere((e) {
      final bNo = D1SalesLedgerService.scopeSecondaryKey(e.billNo, fy);
      final int? idDelTime = registry[e.id] ?? registry[e.id.toUpperCase()];
      if (idDelTime != null) {
        final int uAt = e.toMap()['updatedAt'] ?? 0;
        return uAt == 0 || idDelTime >= uAt;
      }
      final delTime = bNo.isNotEmpty ? registry[bNo] : null;
      final int uAt = e.toMap()['updatedAt'] ?? 0;
      return delTime != null && uAt > 0 && delTime >= uAt;
    });

    ph.purchaseChallans.removeWhere((e) {
      final iNo = D1SalesLedgerService.scopeSecondaryKey(e.internalNo, fy);
      final pId = e.partyId.trim().toUpperCase();
      final bNo = e.billNo.trim();
      final compKey2 = (pId.isNotEmpty && bNo.isNotEmpty) ? D1SalesLedgerService.scopeSecondaryKey("${pId}_$bNo", fy, true) : "";
      final compKey3 = (pId.isNotEmpty && bNo.isNotEmpty && e.internalNo.trim().isNotEmpty)
          ? D1SalesLedgerService.scopeSecondaryKey("${pId}_${bNo}_${e.internalNo.trim().toUpperCase()}", fy, true)
          : "";
      final int? idDelTime = registry[e.id] ?? registry[e.id.toUpperCase()];
      if (idDelTime != null) {
        return e.updatedAt == 0 || idDelTime >= e.updatedAt;
      }
      final int? delTime = (iNo.isNotEmpty ? registry[iNo] : null) ??
          (compKey3.isNotEmpty ? registry[compKey3] : null) ??
          (compKey2.isNotEmpty ? registry[compKey2] : null);
      return delTime != null && e.updatedAt > 0 && delTime >= e.updatedAt;
    });

    ph.saleReturns.removeWhere((e) {
      final bNo = D1SalesLedgerService.scopeSecondaryKey(e.billNo, fy);
      final int? idDelTime = registry[e.id] ?? registry[e.id.toUpperCase()];
      if (idDelTime != null) {
        final int uAt = e.toMap()['updatedAt'] ?? 0;
        return uAt == 0 || idDelTime >= uAt;
      }
      final delTime = bNo.isNotEmpty ? registry[bNo] : null;
      final int uAt = e.toMap()['updatedAt'] ?? 0;
      return delTime != null && uAt > 0 && delTime >= uAt;
    });

    ph.purchaseReturns.removeWhere((e) {
      final bNo = D1SalesLedgerService.scopeSecondaryKey(e.billNo, fy);
      final int? idDelTime = registry[e.id] ?? registry[e.id.toUpperCase()];
      if (idDelTime != null) {
        final int uAt = e.toMap()['updatedAt'] ?? 0;
        return uAt == 0 || idDelTime >= uAt;
      }
      final delTime = bNo.isNotEmpty ? registry[bNo] : null;
      final int uAt = e.toMap()['updatedAt'] ?? 0;
      return delTime != null && uAt > 0 && delTime >= uAt;
    });

    ph.vouchers.removeWhere((e) {
      final vNo = D1SalesLedgerService.scopeSecondaryKey(e.voucherNo, fy);
      final int? idDelTime = registry[e.id] ?? registry[e.id.toUpperCase()];
      if (idDelTime != null) {
        final int uAt = e.toMap()['updatedAt'] ?? 0;
        return uAt == 0 || idDelTime >= uAt;
      }
      final delTime = vNo.isNotEmpty ? registry[vNo] : null;
      final int uAt = e.toMap()['updatedAt'] ?? 0;
      return delTime != null && uAt > 0 && delTime >= uAt;
    });

    ph.companies.removeWhere((c) {
      if (registry.containsKey(c.id) || registry.containsKey(c.id.toUpperCase())) return true;
      final cleanKey = "COMP_${c.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase()}";
      final delTime = registry[cleanKey];
      return delTime != null && (c.updatedAt == 0 || delTime >= c.updatedAt);
    });

    ph.salts.removeWhere((s) {
      if (registry.containsKey(s.id) || registry.containsKey(s.id.toUpperCase())) return true;
      final cleanKey = "SALT_${s.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase()}";
      final delTime = registry[cleanKey];
      return delTime != null && (s.updatedAt == 0 || delTime >= s.updatedAt);
    });

    ph.routes.removeWhere((r) {
      if (registry.containsKey(r.id) || registry.containsKey(r.id.toUpperCase())) return true;
      final cleanKey = "ROUTE_${r.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase()}";
      final delTime = registry[cleanKey];
      return delTime != null && (r.updatedAt == 0 || delTime >= r.updatedAt);
    });

    ph.gstDiarySessions.removeWhere((gs) {
      if (registry.containsKey(gs.id) || registry.containsKey(gs.id.toUpperCase())) {
        final delTime = registry[gs.id] ?? registry[gs.id.toUpperCase()];
        return delTime == null || gs.updatedAt == 0 || delTime >= gs.updatedAt;
      }
      return false;
    });
  }

  /// 🛡️ Multi-Key Anti-Zombie Purge (Strictly Scoped to ph.currentFY for secondary keys):
  static void purgeDeletedRecords(PharoahManager ph, Set<String> allTombstones, [Map<String, int>? registry]) {
    if (allTombstones.isEmpty) return;
    final String fy = ph.currentFY.trim();
    final upperTombstones = allTombstones.map((k) => k.trim().toUpperCase()).toSet();

    ph.sales.removeWhere((e) {
      final bNo = D1SalesLedgerService.scopeSecondaryKey(e.billNo, fy);
      if (allTombstones.contains(e.id) || upperTombstones.contains(e.id.toUpperCase())) {
        if (registry != null) {
          final idDelTime = registry[e.id] ?? registry[e.id.toUpperCase()];
          if (idDelTime != null && e.updatedAt > 0) return idDelTime >= e.updatedAt;
        }
        return true;
      }
      final isTomb = bNo.isNotEmpty && (allTombstones.contains(bNo) || upperTombstones.contains(bNo));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = bNo.isNotEmpty ? registry[bNo] : null;
        if (delTime != null) return e.updatedAt > 0 && delTime >= e.updatedAt;
      }
      return false;
    });

    ph.purchases.removeWhere((e) {
      final iNo = D1SalesLedgerService.scopeSecondaryKey(e.internalNo, fy);
      final pId = e.partyId.trim().toUpperCase();
      final bNo = e.billNo.trim();
      final compKey2 = (pId.isNotEmpty && bNo.isNotEmpty) ? D1SalesLedgerService.scopeSecondaryKey("${pId}_$bNo", fy, true) : "";
      final compKey3 = (pId.isNotEmpty && bNo.isNotEmpty && e.internalNo.trim().isNotEmpty)
          ? D1SalesLedgerService.scopeSecondaryKey("${pId}_${bNo}_${e.internalNo.trim().toUpperCase()}", fy, true)
          : "";
      if (allTombstones.contains(e.id) || upperTombstones.contains(e.id.toUpperCase())) {
        if (registry != null) {
          final idDelTime = registry[e.id] ?? registry[e.id.toUpperCase()];
          if (idDelTime != null && e.updatedAt > 0) return idDelTime >= e.updatedAt;
        }
        return true;
      }
      final isTomb = (iNo.isNotEmpty && (allTombstones.contains(iNo) || upperTombstones.contains(iNo))) ||
          (compKey3.isNotEmpty && allTombstones.contains(compKey3)) ||
          (compKey2.isNotEmpty && allTombstones.contains(compKey2));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = (iNo.isNotEmpty ? registry[iNo] : null) ??
            (compKey3.isNotEmpty ? registry[compKey3] : null) ??
            (compKey2.isNotEmpty ? registry[compKey2] : null);
        if (delTime != null) return e.updatedAt > 0 && delTime >= e.updatedAt;
        return false;
      }
      return false;
    });

    ph.saleChallans.removeWhere((e) {
      final bNo = D1SalesLedgerService.scopeSecondaryKey(e.billNo, fy);
      final isTomb = allTombstones.contains(e.id) || (bNo.isNotEmpty && (allTombstones.contains(bNo) || upperTombstones.contains(bNo)));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = registry[e.id] ?? (bNo.isNotEmpty ? registry[bNo] : null);
        if (delTime != null) return delTime >= (e.toMap()['updatedAt'] ?? 0);
      }
      return allTombstones.contains(e.id);
    });

    ph.purchaseChallans.removeWhere((e) {
      final iNo = D1SalesLedgerService.scopeSecondaryKey(e.internalNo, fy);
      final pId = e.partyId.trim().toUpperCase();
      final bNo = e.billNo.trim();
      final compKey2 = (pId.isNotEmpty && bNo.isNotEmpty) ? D1SalesLedgerService.scopeSecondaryKey("${pId}_$bNo", fy, true) : "";
      final compKey3 = (pId.isNotEmpty && bNo.isNotEmpty && e.internalNo.trim().isNotEmpty)
          ? D1SalesLedgerService.scopeSecondaryKey("${pId}_${bNo}_${e.internalNo.trim().toUpperCase()}", fy, true)
          : "";
      if (allTombstones.contains(e.id) || upperTombstones.contains(e.id.toUpperCase())) {
        return true;
      }
      final isTomb = (iNo.isNotEmpty && (allTombstones.contains(iNo) || upperTombstones.contains(iNo))) ||
          (compKey3.isNotEmpty && allTombstones.contains(compKey3)) ||
          (compKey2.isNotEmpty && allTombstones.contains(compKey2));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = (iNo.isNotEmpty ? registry[iNo] : null) ??
            (compKey3.isNotEmpty ? registry[compKey3] : null) ??
            (compKey2.isNotEmpty ? registry[compKey2] : null);
        if (delTime != null) return e.updatedAt > 0 && delTime >= e.updatedAt;
        return false;
      }
      return false;
    });

    ph.saleReturns.removeWhere((e) {
      final bNo = D1SalesLedgerService.scopeSecondaryKey(e.billNo, fy);
      final isTomb = allTombstones.contains(e.id) || (bNo.isNotEmpty && (allTombstones.contains(bNo) || upperTombstones.contains(bNo)));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = registry[e.id] ?? (bNo.isNotEmpty ? registry[bNo] : null);
        if (delTime != null) return delTime >= (e.toMap()['updatedAt'] ?? 0);
      }
      return allTombstones.contains(e.id);
    });

    ph.purchaseReturns.removeWhere((e) {
      final bNo = D1SalesLedgerService.scopeSecondaryKey(e.billNo, fy);
      final isTomb = allTombstones.contains(e.id) || (bNo.isNotEmpty && (allTombstones.contains(bNo) || upperTombstones.contains(bNo)));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = registry[e.id] ?? (bNo.isNotEmpty ? registry[bNo] : null);
        if (delTime != null) return delTime >= (e.toMap()['updatedAt'] ?? 0);
      }
      return allTombstones.contains(e.id);
    });

    ph.vouchers.removeWhere((e) {
      final vNo = D1SalesLedgerService.scopeSecondaryKey(e.voucherNo, fy);
      final isTomb = allTombstones.contains(e.id) || (vNo.isNotEmpty && (allTombstones.contains(vNo) || upperTombstones.contains(vNo)));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = registry[e.id] ?? (vNo.isNotEmpty ? registry[vNo] : null);
        if (delTime != null) return delTime >= (e.toMap()['updatedAt'] ?? 0);
      }
      return allTombstones.contains(e.id);
    });

    ph.companies.removeWhere((c) {
      final cleanKey = "COMP_${c.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase()}";
      return allTombstones.contains(c.id) || upperTombstones.contains(c.id.toUpperCase()) || upperTombstones.contains(cleanKey);
    });

    ph.salts.removeWhere((s) {
      final cleanKey = "SALT_${s.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase()}";
      return allTombstones.contains(s.id) || upperTombstones.contains(s.id.toUpperCase()) || upperTombstones.contains(cleanKey);
    });

    ph.routes.removeWhere((r) {
      final cleanKey = "ROUTE_${r.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase()}";
      return allTombstones.contains(r.id) || upperTombstones.contains(r.id.toUpperCase()) || upperTombstones.contains(cleanKey);
    });

    ph.gstDiarySessions.removeWhere((gs) {
      final isTomb = allTombstones.contains(gs.id) || upperTombstones.contains(gs.id.toUpperCase());
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = registry[gs.id] ?? registry[gs.id.toUpperCase()];
        if (delTime != null && gs.updatedAt > 0) return delTime >= gs.updatedAt;
      }
      return true;
    });
  }
}
