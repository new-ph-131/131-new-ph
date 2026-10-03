import re
import subprocess
import sys

print("🏷️ Step 1/3: Updating Live Tag to #PH-REV-624 (SYNC-ENGINE-INTEGRATION)...")
tb_path = "lib/web_live_sync/components/web_top_bar.dart"
with open(tb_path, "r", encoding="utf-8") as f:
    tb = f.read()

new_rev = "#PH-REV-624 (SYNC-ENGINE-INTEGRATION)"
tb = re.sub(r"#PH-REV-\d+[^\"]*", new_rev, tb)
with open(tb_path, "w", encoding="utf-8") as f:
    f.write(tb)
print(f"✔ Tag Updated: {new_rev}")

print("⚡ Step 2/3: Rewriting app_sync_engine.dart to use 1000-IQ Protocol...")
sync_path = "lib/web_live_sync/app_sync_engine.dart"
sync_code = r'''// FILE: lib/web_live_sync/app_sync_engine.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../pharoah_manager.dart';
import '../inventory_logic_center.dart';
import 'weblivetoken.dart';
import 'web_cloud_config.dart';
import 'sync_protocol/snapshot_watcher.dart';
import 'sync_protocol/tombstone_engine.dart';
import 'sync_protocol/delta_merge_engine.dart';

class AppSyncEngine {
  static const List<String> _coreFiles = [
    'meds.json', 'parts.json', 'sales.json', 'purc.json',
    'bats.json', 'vouc.json', 's_challan.json', 'p_challan.json',
    's_return.json', 'p_return.json', 'banks.json', 'config.json',
    'series.json', 'shortage.json', 'routs.json', 'comps.json', 'salts.json'
  ];

  /// 🔄 1000-IQ BULLETPROOF 2-WAY SYNC ENGINE (STATE SNAPSHOT DIFFING & TOMBSTONE PROTOCOL)
  static Future<bool> pushStoreData(PharoahManager ph) async {
    try {
      if (ph.activeCompany == null || ph.currentFY.isEmpty) return false;
      final workingDir = await ph.getWorkingPath();
      if (workingDir.isEmpty) return false;

      final prefs = await SharedPreferences.getInstance();
      final companyId = ph.activeCompany!.id;
      final storeToken = await WebLiveToken.getOrCreateToken(companyId);

      // =======================================================================
      // STEP 1: SNAP & DETECT (The Spy) - Catch Mobile Local Deletions
      // =======================================================================
      Set<String> localTombstones = await TombstoneEngine.getLocalTombstones(companyId);
      List<String> newlyDeleted = await SnapshotWatcher.detectLocalDeletions(ph);
      if (newlyDeleted.isNotEmpty) {
        localTombstones.addAll(newlyDeleted);
      }

      // =======================================================================
      // STEP 2: PULL CLOUD DATA
      // =======================================================================
      final pullUri = Uri.parse(
        "${WebCloudConfig.cloudRelayEndpoint}?action=PULL_STORE_DATA"
        "&storeToken=${Uri.encodeComponent(storeToken)}"
        "&username=${Uri.encodeComponent(ph.activeCompany!.adminUser.toLowerCase())}"
        "&password=${Uri.encodeComponent(ph.activeCompany!.password)}"
      );

      final pullRes = await http.get(pullUri).timeout(const Duration(seconds: 15));
      if (pullRes.statusCode == 200 && !pullRes.body.contains("ERROR")) {
        final Map<String, dynamic> cloudData = jsonDecode(pullRes.body);
        if (cloudData['status'] == 'SUCCESS' && cloudData['files'] != null) {
          final Map<String, dynamic> cloudFiles = cloudData['files'];

          // Extract Cloud Tombstones (Web Deletions)
          if (cloudFiles.containsKey('tombstones.json') && cloudFiles['tombstones.json'] != null) {
            try {
              List<dynamic> cloudT = jsonDecode(cloudFiles['tombstones.json']);
              localTombstones.addAll(cloudT.map((e) => e.toString()));
            } catch (_) {}
          }

          // ===================================================================
          // STEP 3: EXECUTE DEATH (The Graveyard) - Purge Zombie Records
          // ===================================================================
          TombstoneEngine.purgeDeletedRecords(ph, localTombstones);

          // ===================================================================
          // STEP 4: DELTA MERGE (The Updater) - Add & Edit Sync
          // ===================================================================
          bool hasChanges = DeltaMergeEngine.processCloudData(ph, cloudFiles, localTombstones);

          // REBUILD INVENTORY ONLY IF SOMETHING ADDED/EDITED/DELETED
          if (hasChanges || newlyDeleted.isNotEmpty || localTombstones.isNotEmpty) {
            InventoryLogicCenter.rebuildAllInventory(
              medicines: ph.medicines,
              batchHistory: ph.batchHistory,
              purchases: ph.purchases,
              sales: ph.sales,
              saleReturns: ph.saleReturns,
              purchaseReturns: ph.purchaseReturns,
            );
            await ph.save();
          }
        }
      }

      // Save latest merged tombstones to local memory
      await TombstoneEngine.saveLocalTombstones(companyId, localTombstones);

      // TAKE FRESH SNAPSHOT BEFORE PUSHING TO CLOUD
      await SnapshotWatcher.takeSnapshot(ph);

      // =======================================================================
      // STEP 5: PUSH TO CLOUD (The Rebirth)
      // =======================================================================
      Map<String, String> filesPayload = {};
      for (var name in _coreFiles) {
        final file = File('$workingDir/$name');
        if (await file.exists()) {
          filesPayload[name] = await file.readAsString();
        }
      }
      
      // Send the universal tombstone list to cloud
      filesPayload['tombstones.json'] = jsonEncode(localTombstones.toList());

      final payload = {
        "action": WebCloudConfig.actionPushStore,
        "storeToken": storeToken,
        "companyId": ph.activeCompany!.id,
        "companyName": ph.activeCompany!.name,
        "adminUser": ph.activeCompany!.adminUser,
        "adminPassword": ph.activeCompany!.password,
        "fy": ph.currentFY,
        "registryProfile": ph.activeCompany!.toMap(),
        "files": filesPayload,
        "syncedAt": DateTime.now().toIso8601String(),
      };

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(WebCloudConfig.cloudRelayEndpoint))
        ..headers.addAll(WebCloudConfig.standardHeaders)
        ..body = jsonEncode(payload)
        ..followRedirects = true;

      final streamedResponse = await client.send(request).timeout(WebCloudConfig.networkTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 400) {
        await prefs.setString('last_cloud_sync_time', DateTime.now().toIso8601String());
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("AppSyncEngine Error: $e");
      return false;
    }
  }

  static Future<String> getLastSyncFormattedTime() async {
    final prefs = await SharedPreferences.getInstance();
    String? timeStr = prefs.getString('last_cloud_sync_time');
    if (timeStr == null || timeStr.isEmpty) return "Never";
    try {
      DateTime dt = DateTime.parse(timeStr);
      String pad(int n) => n.toString().padLeft(2, '0');
      return "${pad(dt.day)}/${pad(dt.month)}/${dt.year} at ${pad(dt.hour)}:${pad(dt.minute)}";
    } catch (_) {
      return "Never";
    }
  }
}
'''
with open(sync_path, "w", encoding="utf-8") as f:
    f.write(sync_code)
print("✔ Core Engine Upgraded!")

print("\n🔍 Step 3/3: Running Flutter Analyze on web_live_sync...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], text=True)
if res.returncode != 0:
    print("❌ Analyze output:")
    print(res.stdout)
    sys.exit(1)
print("✅ 0 ISSUES FOUND! Analyzer is 100% clean.")
