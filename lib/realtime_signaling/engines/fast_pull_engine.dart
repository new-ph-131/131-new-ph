// FILE: lib/realtime_signaling/engines/fast_pull_engine.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../pharoah_manager.dart';
import '../../inventory_logic_center.dart';
import '../../web_live_sync/weblivetoken.dart';
import '../../web_live_sync/web_cloud_config.dart';
import '../../web_live_sync/sync_protocol/snapshot_watcher.dart';
import '../../web_live_sync/sync_protocol/tombstone_engine.dart';
import '../../web_live_sync/sync_protocol/delta_merge_engine.dart';

/// FastPullEngine: Dedicated high-speed pull & merge engine.
/// Pulls cloud changes from Web and immediately updates App memory,
/// disk storage, and UI listeners in < 300ms without circular re-push.
class FastPullEngine {
  static bool _isPulling = false;

  static Future<bool> pullAndMerge(PharoahManager ph) async {
    if (_isPulling) return false;
    if (ph.activeCompany == null || ph.currentFY.isEmpty) return false;

    _isPulling = true;
    try {
      final workingDir = await ph.getWorkingPath();
      if (workingDir.isEmpty) return false;

      final companyId = ph.activeCompany!.id;
      final storeToken = await WebLiveToken.getOrCreateToken(companyId);

      // 1. Fetch Local Tombstones & Hashes
      Set<String> localTombstones = await TombstoneEngine.getLocalTombstones(companyId);
      Map<String, String> localHashes = await SnapshotWatcher.getLocalHashes(companyId);

      // 2. Ultra-Fast Pull from Cloud Relay
      final pullUri = Uri.parse(
        "${WebCloudConfig.cloudRelayEndpoint}?action=PULL_STORE_DATA"
        "&storeToken=${Uri.encodeComponent(storeToken)}"
        "&username=${Uri.encodeComponent(ph.activeCompany!.adminUser.toLowerCase())}"
        "&password=${Uri.encodeComponent(ph.activeCompany!.password)}"
      );

      final response = await http.get(pullUri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.body.contains("ERROR")) {
        return false;
      }

      final Map<String, dynamic> cloudData = jsonDecode(response.body);
      if (cloudData['status'] != 'SUCCESS' || cloudData['files'] == null) {
        return false;
      }

      final Map<String, dynamic> cloudFiles = cloudData['files'];

      // 3. Process Cloud Tombstones
      if (cloudFiles.containsKey('tombstones.json') && cloudFiles['tombstones.json'] != null) {
        try {
          List<dynamic> cloudT = jsonDecode(cloudFiles['tombstones.json']);
          final sanitizedCloudT = await TombstoneEngine.sanitizeCloudTombstones(
            companyId,
            cloudT.map((e) => e.toString()),
          );
          localTombstones.addAll(sanitizedCloudT);
        } catch (_) {}
      }
      localTombstones = await TombstoneEngine.sanitizeCloudTombstones(companyId, localTombstones);

      // 4. Purge Deleted
      TombstoneEngine.purgeDeletedRecords(ph, localTombstones);

      // 5. Delta Merge Cloud Data into Memory
      bool hasChanges = DeltaMergeEngine.processCloudData(ph, cloudFiles, localTombstones, localHashes);

      if (hasChanges) {
        // Rebuild stock & batches
        InventoryLogicCenter.rebuildAllInventory(
          medicines: ph.medicines,
          batchHistory: ph.batchHistory,
          purchases: ph.purchases,
          sales: ph.sales,
          saleReturns: ph.saleReturns,
          purchaseReturns: ph.purchaseReturns,
        );

        // Save directly to local disk files
        Future _w(String n, List data) async =>
            await File('$workingDir/$n').writeAsString(jsonEncode(data.map((e) => e.toMap()).toList()));

        await _w('meds.json', ph.medicines);
        await _w('parts.json', ph.parties);
        await _w('sales.json', ph.sales);
        await _w('purc.json', ph.purchases);
        await _w('vouc.json', ph.vouchers);
        await _w('s_challan.json', ph.saleChallans);
        await _w('p_challan.json', ph.purchaseChallans);
        await _w('s_return.json', ph.saleReturns);
        await _w('p_return.json', ph.purchaseReturns);
        await File('$workingDir/bats.json').writeAsString(
          jsonEncode(ph.batchHistory.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList()))),
        );

        await TombstoneEngine.saveLocalTombstones(companyId, localTombstones);
        await SnapshotWatcher.takeSnapshot(ph);

        // 🔥 INSTANT REACTIVE NOTIFICATION TO RE-RENDER ACTIVE APP SCREENS
        ph.notifyListeners();
        debugPrint("⚡ [FastPullEngine] Successfully pulled & merged latest cloud records!");
        return true;
      }

      return false;
    } catch (e) {
      debugPrint("⚠ [FastPullEngine] Pull error: $e");
      return false;
    } finally {
      _isPulling = false;
    }
  }
}
