import os
import re
import subprocess

print("🏷️ Updating Live Tag to #PH-REV-623 (SYNC-PROTOCOL-ENGINES)...")
tb_path = "lib/web_live_sync/components/web_top_bar.dart"
with open(tb_path, "r", encoding="utf-8") as f:
    tb = f.read()

new_rev = "#PH-REV-623 (SYNC-PROTOCOL-ENGINES)"
tb = re.sub(r"#PH-REV-\d+[^\"]*", new_rev, tb)
with open(tb_path, "w", encoding="utf-8") as f:
    f.write(tb)

print("📁 Creating sync_protocol directory...")
os.makedirs("lib/web_live_sync/sync_protocol", exist_ok=True)

# ==============================================================================
# 1. SNAPSHOT WATCHER (The Spy)
# ==============================================================================
sw_path = "lib/web_live_sync/sync_protocol/snapshot_watcher.dart"
sw_code = r'''// FILE: lib/web_live_sync/sync_protocol/snapshot_watcher.dart

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
'''
with open(sw_path, "w", encoding="utf-8") as f:
    f.write(sw_code)
print("✔ Created: " + sw_path)


# ==============================================================================
# 2. TOMBSTONE ENGINE (The Graveyard)
# ==============================================================================
te_path = "lib/web_live_sync/sync_protocol/tombstone_engine.dart"
te_code = r'''// FILE: lib/web_live_sync/sync_protocol/tombstone_engine.dart

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
'''
with open(te_path, "w", encoding="utf-8") as f:
    f.write(te_code)
print("✔ Created: " + te_path)


# ==============================================================================
# 3. DELTA MERGE ENGINE (The Updater - Edit Sync)
# ==============================================================================
dm_path = "lib/web_live_sync/sync_protocol/delta_merge_engine.dart"
dm_code = r'''// FILE: lib/web_live_sync/sync_protocol/delta_merge_engine.dart

import 'dart:convert';
import '../../../pharoah_manager.dart';
import '../../../models.dart';

class DeltaMergeEngine {
  /// Smartly merges cloud data. If a record exists locally but was modified on the web, it overwrites it.
  static bool processCloudData(PharoahManager ph, Map<String, dynamic> cloudFiles, Set<String> tombstones) {
    bool hasChanges = false;

    dynamic decodeJson(String fileName) {
      if (cloudFiles.containsKey(fileName) && cloudFiles[fileName] != null) {
        try { return jsonDecode(cloudFiles[fileName]); } catch (_) {}
      }
      return null;
    }

    // Advanced Deep-Compare Merge Function
    bool mergeList<T>(
      List<dynamic>? cloudList,
      List<T> localList,
      String Function(T) getId,
      T Function(Map<String, dynamic>) fromMap,
      Map<String, dynamic> Function(T) toMap,
    ) {
      if (cloudList == null) return false;
      bool changed = false;

      for (var rawMap in cloudList) {
        final cloudMap = rawMap as Map<String, dynamic>;
        String id = cloudMap['id'] ?? '';
        
        // Skip if deleted
        if (id.isEmpty || tombstones.contains(id)) continue;

        int idx = localList.indexWhere((e) => getId(e) == id);
        
        if (idx == -1) {
          // ADD NEW RECORD
          localList.add(fromMap(cloudMap));
          changed = true;
        } else {
          // MODIFY EXISTING RECORD (Deep JSON String Comparison)
          String localJson = jsonEncode(toMap(localList[idx]));
          String cloudJson = jsonEncode(cloudMap);
          
          if (localJson != cloudJson) {
            localList[idx] = fromMap(cloudMap);
            changed = true;
          }
        }
      }
      return changed;
    }

    bool cSales = mergeList<Sale>(decodeJson('sales.json'), ph.sales, (e) => e.id, (m) => Sale.fromMap(m), (e) => e.toMap());
    bool cPurc  = mergeList<Purchase>(decodeJson('purc.json'), ph.purchases, (e) => e.id, (m) => Purchase.fromMap(m), (e) => e.toMap());
    bool cVouc  = mergeList<Voucher>(decodeJson('vouc.json'), ph.vouchers, (e) => e.id, (m) => Voucher.fromMap(m), (e) => e.toMap());
    bool cSCh   = mergeList<SaleChallan>(decodeJson('s_challan.json'), ph.saleChallans, (e) => e.id, (m) => SaleChallan.fromMap(m), (e) => e.toMap());
    bool cPCh   = mergeList<PurchaseChallan>(decodeJson('p_challan.json'), ph.purchaseChallans, (e) => e.id, (m) => PurchaseChallan.fromMap(m), (e) => e.toMap());
    bool cSRet  = mergeList<SaleReturn>(decodeJson('s_return.json'), ph.saleReturns, (e) => e.id, (m) => SaleReturn.fromMap(m), (e) => e.toMap());
    bool cPRet  = mergeList<PurchaseReturn>(decodeJson('p_return.json'), ph.purchaseReturns, (e) => e.id, (m) => PurchaseReturn.fromMap(m), (e) => e.toMap());

    // Party Deduplication Merge Logic
    var rawParts = decodeJson('parts.json') as List?;
    if (rawParts != null) {
      for (var rawPart in rawParts) {
        final partMap = rawPart as Map<String, dynamic>;
        String cleanName = (partMap['name'] ?? '').toString().replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
        String pGst = (partMap['gst'] ?? '').toString().toUpperCase().trim();
        if (cleanName.isEmpty) continue;

        int existingIdx = ph.parties.indexWhere((p) {
          if (pGst.isNotEmpty && pGst != 'N/A' && p.gst.toUpperCase().trim() == pGst) return true;
          return p.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase() == cleanName;
        });

        if (existingIdx != -1) {
          final oldP = ph.parties[existingIdx];
          final incoming = Party.fromMap(partMap);
          ph.parties[existingIdx] = Party(
            id: oldP.id, name: oldP.name, group: incoming.group,
            phone: incoming.phone.isNotEmpty ? incoming.phone : oldP.phone,
            email: incoming.email.isNotEmpty ? incoming.email : oldP.email,
            address: incoming.address.isNotEmpty ? incoming.address : oldP.address,
            city: incoming.city.isNotEmpty ? incoming.city : oldP.city,
            state: incoming.state,
            gst: incoming.gst.isNotEmpty && incoming.gst != 'N/A' ? incoming.gst : oldP.gst,
            dl: incoming.dl.isNotEmpty && incoming.dl != 'N/A' ? incoming.dl : oldP.dl,
            pan: incoming.pan.isNotEmpty ? incoming.pan : oldP.pan,
            opBal: incoming.opBal != 0.0 ? incoming.opBal : oldP.opBal,
          );
        } else {
          ph.parties.add(Party.fromMap(partMap));
          hasChanges = true;
        }
      }
    }

    // Medicine Deduplication Merge Logic
    var rawMeds = decodeJson('meds.json') as List?;
    if (rawMeds != null) {
      for (var rawMed in rawMeds) {
        final medMap = rawMed as Map<String, dynamic>;
        String cleanName = (medMap['name'] ?? '').toString().replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
        if (cleanName.isEmpty) continue;

        int existingIdx = ph.medicines.indexWhere((m) {
          return m.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase() == cleanName;
        });

        if (existingIdx != -1) {
          final oldM = ph.medicines[existingIdx];
          final incoming = Medicine.fromMap(medMap);
          ph.medicines[existingIdx] = Medicine(
            id: oldM.id,
            systemId: oldM.systemId.isNotEmpty ? oldM.systemId : incoming.systemId,
            name: oldM.name,
            packing: incoming.packing.isNotEmpty ? incoming.packing : oldM.packing,
            companyId: incoming.companyId.isNotEmpty ? incoming.companyId : oldM.companyId,
            saltId: incoming.saltId.isNotEmpty ? incoming.saltId : oldM.saltId,
            hsnCode: incoming.hsnCode.isNotEmpty ? incoming.hsnCode : oldM.hsnCode,
            gst: incoming.gst,
            mrp: incoming.mrp > 0 ? incoming.mrp : oldM.mrp,
            purRate: incoming.purRate > 0 ? incoming.purRate : oldM.purRate,
            rateA: incoming.rateA > 0 ? incoming.rateA : oldM.rateA,
            rateB: incoming.rateB > 0 ? incoming.rateB : oldM.rateB,
            rateC: incoming.rateC > 0 ? incoming.rateC : oldM.rateC,
            stock: oldM.stock > 0 ? oldM.stock : incoming.stock,
            drugForm: incoming.drugForm,
          );
        } else {
          ph.medicines.add(Medicine.fromMap(medMap));
          hasChanges = true;
        }
      }
    }

    return hasChanges || cSales || cPurc || cVouc || cSCh || cPCh || cSRet || cPRet;
  }
}
'''
with open(dm_path, "w", encoding="utf-8") as f:
    f.write(dm_code)
print("✔ Created: " + dm_path)

print("\n🔍 Running Flutter Analyze on sync_protocol engines...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/sync_protocol/"], text=True)
if res.returncode != 0:
    print("❌ Analyze output:")
    print(res.stdout)
    sys.exit(1)
print("✅ 0 ISSUES FOUND! Engines created successfully.")
