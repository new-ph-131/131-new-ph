// FILE: lib/web_live_sync/sync_protocol/snapshot_watcher.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../pharoah_manager.dart';

class SnapshotWatcher {
  /// Detects records deleted from the mobile app.
  static Future<List<String>> detectLocalDeletions(PharoahManager ph) async {
    final prefs = await SharedPreferences.getInstance();
    String companyId = ph.activeCompany?.id ?? "unknown";
    String snapshotKey = 'sync_snapshot_$companyId';

    String? snapStr = prefs.getString(snapshotKey);
    if (snapStr == null || snapStr.isEmpty) return [];

    Map<String, dynamic> snapshot = jsonDecode(snapStr);
    List<String> newlyDeletedIds = [];

    void checkDeletions(String key, List<dynamic> currentList) {
      List<String> snapIds = List<String>.from(snapshot[key] ?? []);
      Set<String> currentIds = currentList.map((e) => e.id.toString()).toSet();
      for (String oldId in snapIds) {
        if (!currentIds.contains(oldId)) {
          newlyDeletedIds.add(oldId);
        }
      }
    }

    checkDeletions('sales', ph.sales);
    checkDeletions('purchases', ph.purchases);
    checkDeletions('saleChallans', ph.saleChallans);
    checkDeletions('purchaseChallans', ph.purchaseChallans);
    checkDeletions('saleReturns', ph.saleReturns);
    checkDeletions('purchaseReturns', ph.purchaseReturns);
    checkDeletions('vouchers', ph.vouchers);

    return newlyDeletedIds;
  }

  /// Extracts baseline hashes of local objects to detect offline edits
  static Future<Map<String, String>> getLocalHashes(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    String snapStr = prefs.getString('sync_hashes_$companyId') ?? '{}';
    return Map<String, String>.from(jsonDecode(snapStr));
  }

  /// Takes a snapshot of all active IDs and their Content Hashes.
  static Future<void> takeSnapshot(PharoahManager ph) async {
    final prefs = await SharedPreferences.getInstance();
    String companyId = ph.activeCompany?.id ?? "unknown";
    
    Map<String, List<String>> snapshot = {
      'sales': ph.sales.map((e) => e.id).toList(),
      'purchases': ph.purchases.map((e) => e.id).toList(),
      'saleChallans': ph.saleChallans.map((e) => e.id).toList(),
      'purchaseChallans': ph.purchaseChallans.map((e) => e.id).toList(),
      'saleReturns': ph.saleReturns.map((e) => e.id).toList(),
      'purchaseReturns': ph.purchaseReturns.map((e) => e.id).toList(),
      'vouchers': ph.vouchers.map((e) => e.id).toList(),
    };
    await prefs.setString('sync_snapshot_$companyId', jsonEncode(snapshot));

    // SMART HASH ENGINE: Saves exact JSON footprint of every transaction
    Map<String, String> hashes = {};
    for (var s in ph.sales) hashes[s.id] = jsonEncode(s.toMap()).hashCode.toString();
    for (var p in ph.purchases) hashes[p.id] = jsonEncode(p.toMap()).hashCode.toString();
    for (var c in ph.saleChallans) hashes[c.id] = jsonEncode(c.toMap()).hashCode.toString();
    for (var c in ph.purchaseChallans) hashes[c.id] = jsonEncode(c.toMap()).hashCode.toString();
    for (var r in ph.saleReturns) hashes[r.id] = jsonEncode(r.toMap()).hashCode.toString();
    for (var r in ph.purchaseReturns) hashes[r.id] = jsonEncode(r.toMap()).hashCode.toString();
    for (var v in ph.vouchers) hashes[v.id] = jsonEncode(v.toMap()).hashCode.toString();
    await prefs.setString('sync_hashes_$companyId', jsonEncode(hashes));
  }
}
