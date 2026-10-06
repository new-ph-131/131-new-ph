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

  /// Atomically unmarks a tombstone when a record is newly imported or revived
  static Future<void> unmarkTombstone(String companyId, {required String id, String? secondaryKey}) async {
    final tombstones = await getLocalTombstones(companyId);
    if (id.trim().isNotEmpty) tombstones.remove(id.trim());
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) tombstones.remove(secondaryKey.trim());
    await saveLocalTombstones(companyId, tombstones);
  }

  /// Atomically registers a deleted record with its ID and optional secondary key (e.g. BillNo)
  static Future<Set<String>> recordTombstone(String companyId, {required String id, String? secondaryKey}) async {
    final tombstones = await getLocalTombstones(companyId);
    if (id.trim().isNotEmpty) tombstones.add(id.trim());
    if (secondaryKey != null && secondaryKey.trim().isNotEmpty) tombstones.add(secondaryKey.trim());
    await saveLocalTombstones(companyId, tombstones);
    return tombstones;
  }

  /// Atomically registers a batch of deleted records for high-speed bulk deletion
  static Future<Set<String>> recordBatchTombstones(String companyId, Iterable<String> keys) async {
    final tombstones = await getLocalTombstones(companyId);
    for (var k in keys) {
      if (k.trim().isNotEmpty) tombstones.add(k.trim());
    }
    await saveLocalTombstones(companyId, tombstones);
    return tombstones;
  }

  /// Removes any record from the app's memory that exists in the tombstone list.
  /// Protects freshly imported/created records from accidental tombstone purge.
  static void purgeDeletedRecords(PharoahManager ph, Set<String> allTombstones) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int protectWindow = 120000; // Protect records created/updated in last 2 mins

    // Un-tombstone any active records that were freshly imported/modified
    for (var s in ph.sales) {
      if (now - s.updatedAt < protectWindow) {
        allTombstones.remove(s.id);
        if (s.billNo.isNotEmpty) allTombstones.remove(s.billNo);
      }
    }
    for (var p in ph.purchases) {
      if (now - p.updatedAt < protectWindow) {
        allTombstones.remove(p.id);
        if (p.internalNo.isNotEmpty) allTombstones.remove(p.internalNo);
        if (p.billNo.isNotEmpty) allTombstones.remove(p.billNo);
      }
    }

    ph.sales.removeWhere((e) => (now - e.updatedAt >= protectWindow) && (allTombstones.contains(e.id) || allTombstones.contains(e.billNo)));
    ph.purchases.removeWhere((e) => (now - e.updatedAt >= protectWindow) && (allTombstones.contains(e.id) || allTombstones.contains(e.internalNo) || allTombstones.contains(e.billNo)));
    ph.saleChallans.removeWhere((e) => (now - e.updatedAt >= protectWindow) && (allTombstones.contains(e.id) || allTombstones.contains(e.billNo)));
    ph.purchaseChallans.removeWhere((e) => (now - e.updatedAt >= protectWindow) && (allTombstones.contains(e.id) || allTombstones.contains(e.internalNo)));
    ph.saleReturns.removeWhere((e) => (now - e.updatedAt >= protectWindow) && (allTombstones.contains(e.id) || allTombstones.contains(e.billNo)));
    ph.purchaseReturns.removeWhere((e) => (now - e.updatedAt >= protectWindow) && (allTombstones.contains(e.id) || allTombstones.contains(e.billNo)));
    ph.vouchers.removeWhere((e) => (now - e.updatedAt >= protectWindow) && (allTombstones.contains(e.id) || allTombstones.contains(e.voucherNo)));
  }
}
