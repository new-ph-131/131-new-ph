// FILE: lib/web_live_sync/sync_protocol/snapshot_watcher.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../pharoah_manager.dart';

class SnapshotWatcher {
  /// Detects records deleted from the mobile app by comparing current state with the last snapshot.
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

  /// Takes a snapshot of all active IDs to serve as a baseline for the next sync.
  static Future<void> takeSnapshot(PharoahManager ph) async {
    final prefs = await SharedPreferences.getInstance();
    String companyId = ph.activeCompany?.id ?? "unknown";
    String snapshotKey = 'sync_snapshot_$companyId';

    Map<String, List<String>> snapshot = {
      'sales': ph.sales.map((e) => e.id).toList(),
      'purchases': ph.purchases.map((e) => e.id).toList(),
      'saleChallans': ph.saleChallans.map((e) => e.id).toList(),
      'purchaseChallans': ph.purchaseChallans.map((e) => e.id).toList(),
      'saleReturns': ph.saleReturns.map((e) => e.id).toList(),
      'purchaseReturns': ph.purchaseReturns.map((e) => e.id).toList(),
      'vouchers': ph.vouchers.map((e) => e.id).toList(),
    };

    await prefs.setString(snapshotKey, jsonEncode(snapshot));
  }
}
