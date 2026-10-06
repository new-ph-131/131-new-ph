// FILE: lib/web_live_sync/sync_protocol/tombstone_engine.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../pharoah_manager.dart';

class TombstoneEngine {
  /// 🛡️ Persistent high-precision Timestamp-backed Tombstone Registry: { "sync_id": epoch_millis }
  static Future<Map<String, int>> getTombstoneRegistry(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tombstone_registry_$companyId');
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, int.tryParse(v.toString()) ?? 0));
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveTombstoneRegistry(String companyId, Map<String, int> registry) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tombstone_registry_$companyId', jsonEncode(registry));
  }

  /// Records a deletion with high-precision timestamp into registry
  static Future<void> recordTombstoneWithTimestamp(
    String companyId, {
    required String id,
    String? secondaryKey,
    int? timestamp,
  }) async {
    final registry = await getTombstoneRegistry(companyId);
    final int ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    if (id.trim().isNotEmpty) {
      registry[id.trim()] = ts;
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      registry[secondaryKey.trim()] = ts;
    }
    await saveTombstoneRegistry(companyId, registry);
    await recordTombstone(companyId, id: id, secondaryKey: secondaryKey);
  }

  /// Unmarks a tombstone when a bill is explicitly re-created with a newer timestamp
  static Future<void> unmarkTombstoneWithTimestamp(String companyId, {required String id, String? secondaryKey}) async {
    final registry = await getTombstoneRegistry(companyId);
    if (id.trim().isNotEmpty) {
      registry.remove(id.trim());
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      registry.remove(secondaryKey.trim());
    }
    await saveTombstoneRegistry(companyId, registry);
    await unmarkTombstone(companyId, id: id, secondaryKey: secondaryKey);
  }

  // --- Existing Legacy Set-based APIs (Kept for Full Compatibility) ---
  static Future<Set<String>> getLocalTombstones(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('tombstones_$companyId') ?? []).toSet();
  }

  static Future<void> saveLocalTombstones(String companyId, Set<String> tombstones) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('tombstones_$companyId', tombstones.toList());
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
    if (id.trim().isNotEmpty) {
      tombstones.remove(id.trim());
      unmarked.add(id.trim());
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      tombstones.remove(secondaryKey.trim());
      unmarked.add(secondaryKey.trim());
    }
    await saveLocalTombstones(companyId, tombstones);
    await saveUnmarkedKeys(companyId, unmarked);
  }

  static Future<Set<String>> recordTombstone(String companyId, {required String id, String? secondaryKey}) async {
    final tombstones = await getLocalTombstones(companyId);
    final unmarked = await getUnmarkedKeys(companyId);
    if (id.trim().isNotEmpty) {
      tombstones.add(id.trim());
      unmarked.remove(id.trim());
    }
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) {
      tombstones.add(secondaryKey.trim());
      unmarked.remove(secondaryKey.trim());
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
      if (cleanK.isNotEmpty && !unmarked.contains(cleanK)) {
        sanitized.add(cleanK);
      }
    }
    return sanitized;
  }

  static void purgeDeletedRecords(PharoahManager ph, Set<String> allTombstones) {
    if (allTombstones.isEmpty) return;
    final List<String> revivedSales = [];
    for (var s in ph.sales) {
      if (!allTombstones.contains(s.id)) {
        if (s.billNo.isNotEmpty && allTombstones.contains(s.billNo)) {
          revivedSales.add(s.billNo);
        }
      }
    }
    for (var b in revivedSales) allTombstones.remove(b);
    ph.sales.removeWhere((e) => allTombstones.contains(e.id));

    final List<String> revivedPurchases = [];
    for (var p in ph.purchases) {
      if (!allTombstones.contains(p.id)) {
        if (p.internalNo.isNotEmpty && allTombstones.contains(p.internalNo)) {
          revivedPurchases.add(p.internalNo);
        }
        if (p.billNo.isNotEmpty && allTombstones.contains(p.billNo)) {
          revivedPurchases.add(p.billNo);
        }
      }
    }
    for (var b in revivedPurchases) allTombstones.remove(b);
    ph.purchases.removeWhere((e) => allTombstones.contains(e.id));

    final List<String> otherRevivals = [];
    for (var c in ph.saleChallans) {
      if (!allTombstones.contains(c.id) && c.billNo.isNotEmpty && allTombstones.contains(c.billNo)) otherRevivals.add(c.billNo);
    }
    for (var c in ph.purchaseChallans) {
      if (!allTombstones.contains(c.id) && c.internalNo.isNotEmpty && allTombstones.contains(c.internalNo)) otherRevivals.add(c.internalNo);
    }
    for (var r in ph.saleReturns) {
      if (!allTombstones.contains(r.id) && r.billNo.isNotEmpty && allTombstones.contains(r.billNo)) otherRevivals.add(r.billNo);
    }
    for (var r in ph.purchaseReturns) {
      if (!allTombstones.contains(r.id) && r.billNo.isNotEmpty && allTombstones.contains(r.billNo)) otherRevivals.add(r.billNo);
    }
    for (var v in ph.vouchers) {
      if (!allTombstones.contains(v.id) && v.voucherNo.isNotEmpty && allTombstones.contains(v.voucherNo)) otherRevivals.add(v.voucherNo);
    }
    for (var b in otherRevivals) allTombstones.remove(b);
    ph.saleChallans.removeWhere((e) => allTombstones.contains(e.id));
    ph.purchaseChallans.removeWhere((e) => allTombstones.contains(e.id));
    ph.saleReturns.removeWhere((e) => allTombstones.contains(e.id));
    ph.purchaseReturns.removeWhere((e) => allTombstones.contains(e.id));
    ph.vouchers.removeWhere((e) => allTombstones.contains(e.id));
  }
}
