// FILE: lib/web_live_sync/sync_protocol/tombstone_engine.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../../../pharoah_manager.dart';

class TombstoneEngine {
  static Future<Set<String>> getLocalTombstones(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('tombstones_$companyId') ?? []).toSet();
  }

  static Future<void> saveLocalTombstones(String companyId, Set<String> tombstones) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('tombstones_$companyId', tombstones.toList());
  }

  /// Persistent registry of keys that were explicitly unmarked / revived by user import/action
  static Future<Set<String>> getUnmarkedKeys(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('unmarked_tombstones_$companyId') ?? []).toSet();
  }

  static Future<void> saveUnmarkedKeys(String companyId, Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('unmarked_tombstones_$companyId', keys.toList());
  }

  /// Atomically unmarks a tombstone when a record is newly imported or explicitly recreated.
  /// Also registers key in unmarked registry to shield against incoming cloud tombstones.
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

  /// Atomically registers a deleted record with its ID and optional secondary key (e.g. BillNo).
  /// Removes any previous unmark shield for these keys.
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

  /// Atomically registers a batch of deleted records for high-speed bulk deletion.
  static Future<Set<String>> recordBatchTombstones(String companyId, Iterable<String> keys) async {
    final tombstones = await getLocalTombstones(companyId);
    final unmarked = await getUnmarkedKeys(companyId);

    for (var k in keys) {
      final cleanK = k.trim();
      if (cleanK.isNotEmpty) {
        tombstones.add(cleanK);
        unmarked.remove(cleanK);
      }
    }

    await saveLocalTombstones(companyId, tombstones);
    await saveUnmarkedKeys(companyId, unmarked);
    return tombstones;
  }

  /// 🛡️ Filters incoming cloud tombstones against explicitly unmarked keys
  /// so old deletions stored on Cloud can NEVER kill a newly imported/revived record!
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

  /// Removes deleted records while auto-reviving newly imported/active bills
  static void purgeDeletedRecords(PharoahManager ph, Set<String> allTombstones) {
    if (allTombstones.isEmpty) return;

    // 1. Sales: Exact ID deletion only; revive active bill numbers
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

    // 2. Purchases: Exact ID deletion only; revive active bills/internal numbers
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

    // 3. Challans, Returns, Vouchers: Exact ID deletion with revival
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
