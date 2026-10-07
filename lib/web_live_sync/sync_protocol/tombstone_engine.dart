// FILE: lib/web_live_sync/sync_protocol/tombstone_engine.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../pharoah_manager.dart';

/// 🛡️ RE-USABLE SEQUENCE SYNC & TOMBSTONE RECONCILER ENGINE
/// Architectural Mandate: NEVER blacklist or purge by human-readable billNo.
/// Only immutable system hashes ('sync_id' / UUID) with monotonic clock auditing.
class TombstoneEngine {
  /// 🛡️ Persistent high-precision Timestamp-backed Tombstone Registry: { "sync_id": epoch_millis }
  static Future<Map<String, int>> getTombstoneRegistry(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tombstone_registry_$companyId');
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, int>{};
      decoded.forEach((k, v) {
        final cleanK = k.toString().trim();
        // Mandatory Shield: Drop human-readable sequence numbers
        if (cleanK.isNotEmpty && !cleanK.contains('/')) {
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
    // Sanitize: strip out any bill numbers
    final sanitized = Map<String, int>.from(registry);
    sanitized.removeWhere((k, _) => k.contains('/'));
    await prefs.setString('tombstone_registry_$companyId', jsonEncode(sanitized));
  }

  /// Records a deletion with high-precision timestamp into registry (ID ONLY)
  static Future<void> recordTombstoneWithTimestamp(
    String companyId, {
    required String id,
    String? secondaryKey,
    int? timestamp,
  }) async {
    final registry = await getTombstoneRegistry(companyId);
    final int ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final cleanId = id.trim();
    if (cleanId.isNotEmpty && !cleanId.contains('/')) {
      registry[cleanId] = ts;
    }
    await saveTombstoneRegistry(companyId, registry);
    await recordTombstone(companyId, id: cleanId);
  }

  /// Unmarks a tombstone when a bill is explicitly re-created with a newer timestamp
  static Future<void> unmarkTombstoneWithTimestamp(String companyId, {required String id, String? secondaryKey}) async {
    final registry = await getTombstoneRegistry(companyId);
    final cleanId = id.trim();
    if (cleanId.isNotEmpty) {
      registry.remove(cleanId);
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      registry.remove(secondaryKey.trim());
    }
    await saveTombstoneRegistry(companyId, registry);
    await unmarkTombstone(companyId, id: cleanId, secondaryKey: secondaryKey);
  }

  // --- Legacy Set-based APIs (Kept for Full Compatibility, Sanitized against billNo) ---
  static Future<Set<String>> getLocalTombstones(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('tombstones_$companyId') ?? [];
    return list.where((k) => !k.contains('/')).toSet();
  }

  static Future<void> saveLocalTombstones(String companyId, Set<String> tombstones) async {
    final prefs = await SharedPreferences.getInstance();
    final sanitized = tombstones.where((k) => !k.contains('/')).toList();
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
      unmarked.add(cleanId);
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      final cleanSec = secondaryKey.trim();
      tombstones.remove(cleanSec);
      unmarked.add(cleanSec);
    }
    await saveLocalTombstones(companyId, tombstones);
    await saveUnmarkedKeys(companyId, unmarked);
  }

  static Future<Set<String>> recordTombstone(String companyId, {required String id, String? secondaryKey}) async {
    final tombstones = await getLocalTombstones(companyId);
    final unmarked = await getUnmarkedKeys(companyId);
    final cleanId = id.trim();
    if (cleanId.isNotEmpty && !cleanId.contains('/')) {
      tombstones.add(cleanId);
      unmarked.remove(cleanId);
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
      // Drop human-readable sequence numbers
      if (cleanK.isNotEmpty && !cleanK.contains('/')) {
        registry[cleanK] = ts;
        tombstones.add(cleanK);
        unmarked.remove(cleanK);
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
      if (cleanK.isNotEmpty && !cleanK.contains('/') && !unmarked.contains(cleanK)) {
        sanitized.add(cleanK);
      }
    }
    return sanitized;
  }

  /// 🛡️ Chronological Anti-Zombie Registry Purge:
  /// Evaluates ID ONLY and checks deleteTimestamp >= recordTimestamp before purging.
  static void purgeDeletedRecordsWithRegistry(PharoahManager ph, Map<String, int> registry) {
    if (registry.isEmpty) return;
    ph.sales.removeWhere((e) {
      final delTime = registry[e.id];
      return delTime != null && delTime >= e.updatedAt;
    });
    ph.purchases.removeWhere((e) {
      final delTime = registry[e.id];
      return delTime != null && delTime >= e.updatedAt;
    });
    ph.saleChallans.removeWhere((e) {
      final delTime = registry[e.id];
      return delTime != null && delTime >= (e.toMap()['updatedAt'] ?? 0);
    });
    ph.purchaseChallans.removeWhere((e) {
      final delTime = registry[e.id];
      return delTime != null && delTime >= (e.toMap()['updatedAt'] ?? 0);
    });
    ph.saleReturns.removeWhere((e) {
      final delTime = registry[e.id];
      return delTime != null && delTime >= (e.toMap()['updatedAt'] ?? 0);
    });
    ph.purchaseReturns.removeWhere((e) {
      final delTime = registry[e.id];
      return delTime != null && delTime >= (e.toMap()['updatedAt'] ?? 0);
    });
    ph.vouchers.removeWhere((e) {
      final delTime = registry[e.id];
      return delTime != null && delTime >= (e.toMap()['updatedAt'] ?? 0);
    });
  }

  /// 🛡️ ID-ONLY Purge (Never purges by billNo, respects Monotonic Clock Registry)
  static void purgeDeletedRecords(PharoahManager ph, Set<String> allTombstones, [Map<String, int>? registry]) {
    if (allTombstones.isEmpty) return;
    ph.sales.removeWhere((e) {
      if (!allTombstones.contains(e.id)) return false;
      if (registry != null && registry.containsKey(e.id)) {
        return registry[e.id]! >= e.updatedAt;
      }
      return true;
    });
    ph.purchases.removeWhere((e) {
      if (!allTombstones.contains(e.id)) return false;
      if (registry != null && registry.containsKey(e.id)) {
        return registry[e.id]! >= e.updatedAt;
      }
      return true;
    });
    ph.saleChallans.removeWhere((e) {
      if (!allTombstones.contains(e.id)) return false;
      if (registry != null && registry.containsKey(e.id)) {
        return registry[e.id]! >= (e.toMap()['updatedAt'] ?? 0);
      }
      return true;
    });
    ph.purchaseChallans.removeWhere((e) {
      if (!allTombstones.contains(e.id)) return false;
      if (registry != null && registry.containsKey(e.id)) {
        return registry[e.id]! >= (e.toMap()['updatedAt'] ?? 0);
      }
      return true;
    });
    ph.saleReturns.removeWhere((e) {
      if (!allTombstones.contains(e.id)) return false;
      if (registry != null && registry.containsKey(e.id)) {
        return registry[e.id]! >= (e.toMap()['updatedAt'] ?? 0);
      }
      return true;
    });
    ph.purchaseReturns.removeWhere((e) {
      if (!allTombstones.contains(e.id)) return false;
      if (registry != null && registry.containsKey(e.id)) {
        return registry[e.id]! >= (e.toMap()['updatedAt'] ?? 0);
      }
      return true;
    });
    ph.vouchers.removeWhere((e) {
      if (!allTombstones.contains(e.id)) return false;
      if (registry != null && registry.containsKey(e.id)) {
        return registry[e.id]! >= (e.toMap()['updatedAt'] ?? 0);
      }
      return true;
    });
  }
}
