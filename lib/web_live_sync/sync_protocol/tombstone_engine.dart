// FILE: lib/web_live_sync/sync_protocol/tombstone_engine.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../pharoah_manager.dart';

/// 🛡️ RE-USABLE SEQUENCE SYNC & TOMBSTONE RECONCILER ENGINE
/// Protects all entities (Sales, Purchases, Vouchers, Challans, Returns)
/// against cloud rollback and zombie resurrection across App and Web.
class TombstoneEngine {
  /// 🛡️ Persistent high-precision Timestamp-backed Tombstone Registry: { "key": epoch_millis }
  static Future<Map<String, int>> getTombstoneRegistry(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tombstone_registry_$companyId');
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, int>{};
      decoded.forEach((k, v) {
        final cleanK = k.toString().trim();
        if (cleanK.isNotEmpty) {
          result[cleanK] = int.tryParse(v.toString()) ?? 0;
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveTombstoneRegistry(String companyId, Map<String, int> registry) async {
    final prefs = await SharedPreferences.getInstance();
    final sanitized = Map<String, int>.from(registry);
    await prefs.setString('tombstone_registry_$companyId', jsonEncode(sanitized));
  }

  /// Records a deletion with high-precision timestamp into registry (ID and Secondary Keys)
  static Future<void> recordTombstoneWithTimestamp(
    String companyId, {
    required String id,
    String? secondaryKey,
    int? timestamp,
  }) async {
    final registry = await getTombstoneRegistry(companyId);
    final int ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final cleanId = id.trim();
    if (cleanId.isNotEmpty) {
      registry[cleanId] = ts;
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      final cleanSec = secondaryKey.trim().toUpperCase();
      registry[cleanSec] = ts;
    }
    await saveTombstoneRegistry(companyId, registry);
    await recordTombstone(companyId, id: cleanId, secondaryKey: secondaryKey);
  }

  /// Unmarks a tombstone when a bill is explicitly re-created with a newer timestamp
  static Future<void> unmarkTombstoneWithTimestamp(String companyId, {required String id, String? secondaryKey}) async {
    final registry = await getTombstoneRegistry(companyId);
    final cleanId = id.trim();
    if (cleanId.isNotEmpty) {
      registry.remove(cleanId);
      registry.remove(cleanId.toUpperCase());
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      registry.remove(secondaryKey.trim());
      registry.remove(secondaryKey.trim().toUpperCase());
    }
    await saveTombstoneRegistry(companyId, registry);
    await unmarkTombstone(companyId, id: cleanId, secondaryKey: secondaryKey);
  }

  // --- Set-based APIs ---
  static Future<Set<String>> getLocalTombstones(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('tombstones_$companyId') ?? [];
    return list.where((k) => k.trim().isNotEmpty).toSet();
  }

  static Future<void> saveLocalTombstones(String companyId, Set<String> tombstones) async {
    final prefs = await SharedPreferences.getInstance();
    final sanitized = tombstones.where((k) => k.trim().isNotEmpty).toList();
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

  static Future<void> unmarkTombstone(String companyId, {required String id, String? secondaryKey}) async {
    final tombstones = await getLocalTombstones(companyId);
    final unmarked = await getUnmarkedKeys(companyId);
    final cleanId = id.trim();
    if (cleanId.isNotEmpty) {
      tombstones.remove(cleanId);
      tombstones.remove(cleanId.toUpperCase());
      unmarked.add(cleanId);
      unmarked.add(cleanId.toUpperCase());
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      final cleanSec = secondaryKey.trim();
      tombstones.remove(cleanSec);
      tombstones.remove(cleanSec.toUpperCase());
      unmarked.add(cleanSec);
      unmarked.add(cleanSec.toUpperCase());
    }
    await saveLocalTombstones(companyId, tombstones);
    await saveUnmarkedKeys(companyId, unmarked);
  }

  static Future<Set<String>> recordTombstone(String companyId, {required String id, String? secondaryKey}) async {
    final tombstones = await getLocalTombstones(companyId);
    final unmarked = await getUnmarkedKeys(companyId);
    final cleanId = id.trim();
    if (cleanId.isNotEmpty) {
      tombstones.add(cleanId);
      unmarked.remove(cleanId);
      unmarked.remove(cleanId.toUpperCase());
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      final cleanSec = secondaryKey.trim().toUpperCase();
      tombstones.add(cleanSec);
      unmarked.remove(cleanSec);
    }
    await saveLocalTombstones(companyId, tombstones);
    await saveUnmarkedKeys(companyId, unmarked);
    return tombstones;
  }

  static Future<Set<String>> recordBatchTombstones(String companyId, Iterable<String> keys, {int? timestamp}) async {
    final registry = await getTombstoneRegistry(companyId);
    final int ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final tombstones = await getLocalTombstones(companyId);
    final unmarked = await getUnmarkedKeys(companyId);
    for (var k in keys) {
      final cleanK = k.trim();
      if (cleanK.isNotEmpty) {
        registry[cleanK] = ts;
        registry[cleanK.toUpperCase()] = ts;
        tombstones.add(cleanK);
        tombstones.add(cleanK.toUpperCase());
        unmarked.remove(cleanK);
        unmarked.remove(cleanK.toUpperCase());
      }
    }
    await saveTombstoneRegistry(companyId, registry);
    await saveLocalTombstones(companyId, tombstones);
    await saveUnmarkedKeys(companyId, unmarked);
    return tombstones;
  }

  static Future<Set<String>> sanitizeCloudTombstones(String companyId, Iterable<String> incomingCloudTombstones) async {
    final unmarked = await getUnmarkedKeys(companyId);
    final sanitized = <String>{};
    for (var k in incomingCloudTombstones) {
      final cleanK = k.trim();
      if (cleanK.isNotEmpty && !unmarked.contains(cleanK) && !unmarked.contains(cleanK.toUpperCase())) {
        sanitized.add(cleanK);
      }
    }
    return sanitized;
  }

  /// 🛡️ Chronological Anti-Zombie Registry Purge:
  /// Evaluates ID AND secondary human identifiers (BillNo, InternalNo, VoucherNo, 2-part & 3-part Composite Keys).
  static void purgeDeletedRecordsWithRegistry(PharoahManager ph, Map<String, int> registry) {
    if (registry.isEmpty) return;
    ph.sales.removeWhere((e) {
      final bNo = e.billNo.trim().toUpperCase();
      if (registry.containsKey(e.id) || registry.containsKey(e.id.toUpperCase())) return true;
      final delTime = bNo.isNotEmpty ? registry[bNo] : null;
      return delTime != null && delTime >= e.updatedAt;
    });
    ph.purchases.removeWhere((e) {
      final iNo = e.internalNo.trim().toUpperCase();
      final pId = e.partyId.trim().toUpperCase();
      final bNo = e.billNo.trim().toUpperCase();
      final compKey2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
      final compKey3 = (pId.isNotEmpty && bNo.isNotEmpty && iNo.isNotEmpty) ? "${pId}_${bNo}_$iNo" : "";
      if (registry.containsKey(e.id) || registry.containsKey(e.id.toUpperCase())) {
        return true;
      }
      final int? delTime = (iNo.isNotEmpty ? registry[iNo] : null) ??
          (compKey3.isNotEmpty ? registry[compKey3] : null) ??
          (compKey2.isNotEmpty ? registry[compKey2] : null);
      return delTime != null && delTime >= e.updatedAt;
    });
    ph.saleChallans.removeWhere((e) {
      final bNo = e.billNo.trim().toUpperCase();
      if (registry.containsKey(e.id)) return true;
      final delTime = bNo.isNotEmpty ? registry[bNo] : null;
      return delTime != null && delTime >= (e.toMap()['updatedAt'] ?? 0);
    });
    ph.purchaseChallans.removeWhere((e) {
      final iNo = e.internalNo.trim().toUpperCase();
      final bNo = e.billNo.trim().toUpperCase();
      if (registry.containsKey(e.id) || (iNo.isNotEmpty && registry.containsKey(iNo))) return true;
      final delTime = bNo.isNotEmpty ? registry[bNo] : null;
      return delTime != null && delTime >= (e.toMap()['updatedAt'] ?? 0);
    });
    ph.saleReturns.removeWhere((e) {
      final bNo = e.billNo.trim().toUpperCase();
      if (registry.containsKey(e.id)) return true;
      final delTime = bNo.isNotEmpty ? registry[bNo] : null;
      return delTime != null && delTime >= (e.toMap()['updatedAt'] ?? 0);
    });
    ph.purchaseReturns.removeWhere((e) {
      final bNo = e.billNo.trim().toUpperCase();
      if (registry.containsKey(e.id)) return true;
      final delTime = bNo.isNotEmpty ? registry[bNo] : null;
      return delTime != null && delTime >= (e.toMap()['updatedAt'] ?? 0);
    });
    ph.vouchers.removeWhere((e) {
      final vNo = e.voucherNo.trim().toUpperCase();
      if (registry.containsKey(e.id)) return true;
      final delTime = vNo.isNotEmpty ? registry[vNo] : null;
      return delTime != null && delTime >= (e.toMap()['updatedAt'] ?? 0);
    });
  }

  /// 🛡️ Multi-Key Anti-Zombie Purge:
  static void purgeDeletedRecords(PharoahManager ph, Set<String> allTombstones, [Map<String, int>? registry]) {
    if (allTombstones.isEmpty) return;
    final upperTombstones = allTombstones.map((k) => k.trim().toUpperCase()).toSet();

    ph.sales.removeWhere((e) {
      final bNo = e.billNo.trim().toUpperCase();
      if (allTombstones.contains(e.id) || upperTombstones.contains(e.id.toUpperCase())) return true;
      final isTomb = bNo.isNotEmpty && (allTombstones.contains(bNo) || upperTombstones.contains(bNo));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = registry[e.id] ?? (bNo.isNotEmpty ? registry[bNo] : null);
        if (delTime != null) return delTime >= e.updatedAt;
      }
      return true;
    });

    ph.purchases.removeWhere((e) {
      final iNo = e.internalNo.trim().toUpperCase();
      final pId = e.partyId.trim().toUpperCase();
      final bNo = e.billNo.trim().toUpperCase();
      final compKey2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
      final compKey3 = (pId.isNotEmpty && bNo.isNotEmpty && iNo.isNotEmpty) ? "${pId}_${bNo}_$iNo" : "";
      if (allTombstones.contains(e.id) || upperTombstones.contains(e.id.toUpperCase())) {
        return true;
      }
      final isTomb = (iNo.isNotEmpty && (allTombstones.contains(iNo) || upperTombstones.contains(iNo))) ||
          (compKey3.isNotEmpty && (allTombstones.contains(compKey3) || upperTombstones.contains(compKey3))) ||
          (compKey2.isNotEmpty && (allTombstones.contains(compKey2) || upperTombstones.contains(compKey2)));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = (iNo.isNotEmpty ? registry[iNo] : null) ??
            (compKey3.isNotEmpty ? registry[compKey3] : null) ??
            (compKey2.isNotEmpty ? registry[compKey2] : null);
        if (delTime != null) return delTime >= e.updatedAt;
      }
      return true;
    });

    ph.saleChallans.removeWhere((e) {
      final bNo = e.billNo.trim().toUpperCase();
      final isTomb = allTombstones.contains(e.id) || (bNo.isNotEmpty && (allTombstones.contains(bNo) || upperTombstones.contains(bNo)));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = registry[e.id] ?? (bNo.isNotEmpty ? registry[bNo] : null);
        if (delTime != null) return delTime >= (e.toMap()['updatedAt'] ?? 0);
      }
      return true;
    });

    ph.purchaseChallans.removeWhere((e) {
      final iNo = e.internalNo.trim().toUpperCase();
      final bNo = e.billNo.trim().toUpperCase();
      final isTomb = allTombstones.contains(e.id) || 
          (iNo.isNotEmpty && (allTombstones.contains(iNo) || upperTombstones.contains(iNo))) ||
          (bNo.isNotEmpty && (allTombstones.contains(bNo) || upperTombstones.contains(bNo)));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = registry[e.id] ?? 
            (iNo.isNotEmpty ? registry[iNo] : null) ?? 
            (bNo.isNotEmpty ? registry[bNo] : null);
        if (delTime != null) return delTime >= (e.toMap()['updatedAt'] ?? 0);
      }
      return true;
    });

    ph.saleReturns.removeWhere((e) {
      final bNo = e.billNo.trim().toUpperCase();
      final isTomb = allTombstones.contains(e.id) || (bNo.isNotEmpty && (allTombstones.contains(bNo) || upperTombstones.contains(bNo)));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = registry[e.id] ?? (bNo.isNotEmpty ? registry[bNo] : null);
        if (delTime != null) return delTime >= (e.toMap()['updatedAt'] ?? 0);
      }
      return true;
    });

    ph.purchaseReturns.removeWhere((e) {
      final bNo = e.billNo.trim().toUpperCase();
      final isTomb = allTombstones.contains(e.id) || (bNo.isNotEmpty && (allTombstones.contains(bNo) || upperTombstones.contains(bNo)));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = registry[e.id] ?? (bNo.isNotEmpty ? registry[bNo] : null);
        if (delTime != null) return delTime >= (e.toMap()['updatedAt'] ?? 0);
      }
      return true;
    });

    ph.vouchers.removeWhere((e) {
      final vNo = e.voucherNo.trim().toUpperCase();
      final isTomb = allTombstones.contains(e.id) || (vNo.isNotEmpty && (allTombstones.contains(vNo) || upperTombstones.contains(vNo)));
      if (!isTomb) return false;
      if (registry != null) {
        final delTime = registry[e.id] ?? (vNo.isNotEmpty ? registry[vNo] : null);
        if (delTime != null) return delTime >= (e.toMap()['updatedAt'] ?? 0);
      }
      return true;
    });
  }
}
