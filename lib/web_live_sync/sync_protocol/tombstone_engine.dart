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
  static void purgeDeletedRecords(PharoahManager ph, Set<String> allTombstones) {
    ph.sales.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.billNo));
    ph.purchases.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.internalNo) || allTombstones.contains(e.billNo));
    ph.saleChallans.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.billNo));
    ph.purchaseChallans.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.internalNo));
    ph.saleReturns.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.billNo));
    ph.purchaseReturns.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.billNo));
    ph.vouchers.removeWhere((e) => allTombstones.contains(e.id) || allTombstones.contains(e.voucherNo));
  }
}
