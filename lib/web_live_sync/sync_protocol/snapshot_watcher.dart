// FILE: lib/web_live_sync/sync_protocol/snapshot_watcher.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models.dart';
import '../../pharoah_manager.dart';

class SnapshotWatcher {
  /// Detects records deleted from the mobile app.
  static String _scopedKey(String prefix, String companyId, String fy) {
    final cleanFy = fy.trim();
    return cleanFy.isEmpty ? '${prefix}_$companyId' : '${prefix}_${companyId}_$cleanFy';
  }

  static bool isProtectedChallanSnapshotId(
    String id, {
    Set<String> billedIds = const {},
    Set<String> crossFyIds = const {},
  }) {
    final clean = id.trim();
    if (clean.isEmpty) return true;
    final up = clean.toUpperCase();
    // Never passively auto-tombstone Web Portal created challans or cross-FY / Billed challans
    // just because a snapshot list omitted them during an FY switch or partial pull.
    if (up.startsWith('SCH-WEB-') || up.startsWith('PCH-WEB-') || up.contains('-WEB-')) {
      return true;
    }
    if (billedIds.contains(clean) || crossFyIds.contains(clean)) {
      return true;
    }
    return false;
  }

  static List<String> detectDeletionsFromSnapshotMap({
    required Map<String, dynamic> snapshot,
    required List<String> currentSaleIds,
    required List<String> currentPurchaseIds,
    required List<String> currentSaleChallanIds,
    required List<String> currentPurchaseChallanIds,
    required List<String> currentSaleReturnIds,
    required List<String> currentPurchaseReturnIds,
    required List<String> currentVoucherIds,
    required List<String> currentGstSessionIds,
  }) {
    final List<String> newlyDeletedIds = [];
    final Set<String> billedIds = Set<String>.from(
      (snapshot['billedChallanIds'] as List? ?? const []).map((e) => e.toString().trim()),
    );
    final Set<String> crossFyIds = Set<String>.from(
      (snapshot['crossFyChallanIds'] as List? ?? const []).map((e) => e.toString().trim()),
    );

    void checkDeletions(String key, List<String> currentIdsList, {bool isChallan = false}) {
      final List<String> snapIds = List<String>.from(snapshot[key] ?? []);
      if (snapIds.isEmpty) return;
      final Set<String> currentIds = currentIdsList.map((e) => e.trim()).toSet();
      if (isChallan && currentIds.isEmpty) {
        return;
      }
      for (String oldId in snapIds) {
        final cleanOld = oldId.trim();
        if (cleanOld.isEmpty) continue;
        if (!currentIds.contains(cleanOld)) {
          if (isChallan &&
              isProtectedChallanSnapshotId(
                cleanOld,
                billedIds: billedIds,
                crossFyIds: crossFyIds,
              )) {
            continue;
          }
          newlyDeletedIds.add(cleanOld);
        }
      }
    }

    checkDeletions('sales', currentSaleIds);
    checkDeletions('purchases', currentPurchaseIds);
    checkDeletions('saleChallans', currentSaleChallanIds, isChallan: true);
    checkDeletions('purchaseChallans', currentPurchaseChallanIds, isChallan: true);
    checkDeletions('saleReturns', currentSaleReturnIds);
    checkDeletions('purchaseReturns', currentPurchaseReturnIds);
    checkDeletions('vouchers', currentVoucherIds);
    checkDeletions('gstDiarySessions', currentGstSessionIds);

    return newlyDeletedIds;
  }

  static Future<List<String>> detectLocalDeletions(PharoahManager ph) async {
    if (ph.currentFY.trim().isEmpty) return [];
    final prefs = await SharedPreferences.getInstance();
    String companyId = ph.activeCompany?.id ?? "unknown";
    String snapshotKey = _scopedKey('sync_snapshot', companyId, ph.currentFY);

    String? snapStr = prefs.getString(snapshotKey);
    if (snapStr == null || snapStr.isEmpty) return [];

    final Map<String, dynamic> snapshot = jsonDecode(snapStr);
    return detectDeletionsFromSnapshotMap(
      snapshot: snapshot,
      currentSaleIds: ph.sales.map((e) => e.id.toString()).toList(),
      currentPurchaseIds: ph.purchases.map((e) => e.id.toString()).toList(),
      currentSaleChallanIds: ph.saleChallans.map((e) => e.id.toString()).toList(),
      currentPurchaseChallanIds: ph.purchaseChallans.map((e) => e.id.toString()).toList(),
      currentSaleReturnIds: ph.saleReturns.map((e) => e.id.toString()).toList(),
      currentPurchaseReturnIds: ph.purchaseReturns.map((e) => e.id.toString()).toList(),
      currentVoucherIds: ph.vouchers.map((e) => e.id.toString()).toList(),
      currentGstSessionIds: ph.gstDiarySessions.map((e) => e.id.toString()).toList(),
    );
  }

  /// Extracts baseline hashes of local objects to detect offline edits
  static Future<Map<String, String>> getLocalHashes(String companyId, [String fy = ""]) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _scopedKey('sync_hashes', companyId, fy);
    String snapStr = prefs.getString(key) ?? prefs.getString('sync_hashes_$companyId') ?? '{}';
    try {
      return Map<String, String>.from(jsonDecode(snapStr));
    } catch (_) {
      return {};
    }
  }

  /// Takes a snapshot of all active IDs and their Content Hashes.
  static Future<void> takeSnapshot(PharoahManager ph) async {
    if (ph.currentFY.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    String companyId = ph.activeCompany?.id ?? "unknown";
    String snapshotKey = _scopedKey('sync_snapshot', companyId, ph.currentFY);
    String hashKey = _scopedKey('sync_hashes', companyId, ph.currentFY);

    final Set<String> billedChallanIds = {};
    final Set<String> crossFyChallanIds = {};
    for (final c in ph.saleChallans) {
      if (c.status.trim().toUpperCase() == 'BILLED') billedChallanIds.add(c.id);
      if (isStrictCarryForwardFy(c.effectiveOriginalFy, ph.currentFY) ||
          c.id.toUpperCase().contains('-WEB-')) {
        crossFyChallanIds.add(c.id);
      }
    }
    for (final c in ph.purchaseChallans) {
      if (c.status.trim().toUpperCase() == 'BILLED') billedChallanIds.add(c.id);
      if (isStrictCarryForwardFy(c.effectiveOriginalFy, ph.currentFY) ||
          c.id.toUpperCase().contains('-WEB-')) {
        crossFyChallanIds.add(c.id);
      }
    }

    Map<String, List<String>> snapshot = {
      'sales': ph.sales.map((e) => e.id).toList(),
      'purchases': ph.purchases.map((e) => e.id).toList(),
      'saleChallans': ph.saleChallans.map((e) => e.id).toList(),
      'purchaseChallans': ph.purchaseChallans.map((e) => e.id).toList(),
      'saleReturns': ph.saleReturns.map((e) => e.id).toList(),
      'purchaseReturns': ph.purchaseReturns.map((e) => e.id).toList(),
      'vouchers': ph.vouchers.map((e) => e.id).toList(),
      'gstDiarySessions': ph.gstDiarySessions.map((e) => e.id).toList(),
      'billedChallanIds': billedChallanIds.toList(),
      'crossFyChallanIds': crossFyChallanIds.toList(),
    };
    await prefs.setString(snapshotKey, jsonEncode(snapshot));

    // SMART HASH ENGINE: Saves exact JSON footprint of every transaction
    Map<String, String> hashes = {};
    for (var s in ph.sales) hashes[s.id] = jsonEncode(s.toMap()).hashCode.toString();
    for (var p in ph.purchases) hashes[p.id] = jsonEncode(p.toMap()).hashCode.toString();
    for (var c in ph.saleChallans) hashes[c.id] = jsonEncode(c.toMap()).hashCode.toString();
    for (var c in ph.purchaseChallans) hashes[c.id] = jsonEncode(c.toMap()).hashCode.toString();
    for (var r in ph.saleReturns) hashes[r.id] = jsonEncode(r.toMap()).hashCode.toString();
    for (var r in ph.purchaseReturns) hashes[r.id] = jsonEncode(r.toMap()).hashCode.toString();
    for (var v in ph.vouchers) hashes[v.id] = jsonEncode(v.toMap()).hashCode.toString();
    for (var gs in ph.gstDiarySessions) hashes[gs.id] = jsonEncode(gs.toMap()).hashCode.toString();
    await prefs.setString(hashKey, jsonEncode(hashes));
  }
}
