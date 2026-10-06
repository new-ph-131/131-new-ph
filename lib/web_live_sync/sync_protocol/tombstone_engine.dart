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

  /// Removes any record from the app's memory that exists in the tombstone list.
  static void purgeDeletedRecords(PharoahManager ph, Set<String> allTombstones) {
    if (allTombstones.isEmpty) return;
    ph.sales.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.billNo));
    ph.purchases.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.internalNo) || allTombstones.contains(e.billNo));
    ph.saleChallans.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.billNo));
    ph.purchaseChallans.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.internalNo));
    ph.saleReturns.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.billNo));
    ph.purchaseReturns.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.billNo));
    ph.vouchers.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.voucherNo));
  }
}
