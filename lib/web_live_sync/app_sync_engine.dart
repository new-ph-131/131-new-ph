import "../sync_core/d1_sales_ledger_service.dart";
// FILE: lib/web_live_sync/app_sync_engine.dart

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

      // STEP 1: SNAP & DETECT (The Spy)
      Set<String> localTombstones = await TombstoneEngine.getLocalTombstones(companyId);
      Map<String, int> localRegistry = await TombstoneEngine.getTombstoneRegistry(companyId);
      Map<String, String> localHashes = await SnapshotWatcher.getLocalHashes(companyId);
      List<String> newlyDeleted = await SnapshotWatcher.detectLocalDeletions(ph);
      if (newlyDeleted.isNotEmpty) {
        final nowTs = DateTime.now().millisecondsSinceEpoch;
        for (var id in newlyDeleted) {
          localRegistry[id] = nowTs;
        }
        localTombstones.addAll(newlyDeleted.where((k) => !k.contains('/')));
      }

      // STEP 2: PULL CLOUD DATA
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

          if (cloudFiles.containsKey('tombstones.json') && cloudFiles['tombstones.json'] != null) {
            try {
              List<dynamic> cloudT = jsonDecode(cloudFiles['tombstones.json']);
              final sanitizedCloudT = await TombstoneEngine.sanitizeCloudTombstones(
                companyId,
                cloudT.map((e) => e.toString()),
              );
              localTombstones.addAll(sanitizedCloudT);
              for (final tk in sanitizedCloudT) {
                localRegistry.putIfAbsent(tk, () => DateTime.now().millisecondsSinceEpoch);
                localRegistry.putIfAbsent(tk.toUpperCase(), () => DateTime.now().millisecondsSinceEpoch);
              }
            } catch (_) {}
          }
          if (cloudFiles.containsKey('tombstone_registry.json') && cloudFiles['tombstone_registry.json'] != null) {
            try {
              dynamic rawReg = jsonDecode(cloudFiles['tombstone_registry.json']);
              if (rawReg is Map) {
                final unmarkedKeys = await TombstoneEngine.getUnmarkedKeys(companyId);
                rawReg.forEach((k, v) {
                  final cleanK = k.toString().trim();
                  if (cleanK.isNotEmpty && !unmarkedKeys.contains(cleanK) && !unmarkedKeys.contains(cleanK.toUpperCase())) {
                    final cTs = int.tryParse(v.toString()) ?? 0;
                    final lTs = localRegistry[cleanK] ?? 0;
                    if (cTs > lTs) {
                      localRegistry[cleanK] = cTs;
                      localRegistry[cleanK.toUpperCase()] = cTs;
                    }
                    localTombstones.add(cleanK);
                    localTombstones.add(cleanK.toUpperCase());
                  }
                });
              }
            } catch (_) {}
          }
          localTombstones = await TombstoneEngine.sanitizeCloudTombstones(companyId, localTombstones);

          // 🚀 STEP 2.5: EDGE D1 REAL-TIME SALES & PURCHASES DELTA HARVEST BEFORE CLOUD MERGE
          bool d1HasChanges = false;
          if (D1SalesLedgerService.USE_D1_EDGE_LEDGER) {
            try {
              final edgeEvents = await D1SalesLedgerService.fetchSaleDeltas(storeToken);
              if (edgeEvents.isNotEmpty) {
                bool d1Sales = D1SalesLedgerService.applyEventsToLocalSales(ph.sales, edgeEvents);
                bool d1Purc = D1SalesLedgerService.applyEventsToLocalPurchases(ph.purchases, edgeEvents);
                if (d1Sales || d1Purc) d1HasChanges = true;
                final nowTs = DateTime.now().millisecondsSinceEpoch;
                for (final ev in edgeEvents) {
                  if ((ev["action"] ?? "").toString().toUpperCase() == "DELETE") {
                    final String bId = (ev["bill_id"] ?? "").toString().trim();
                    final String bNo = (ev["bill_no"] ?? "").toString().trim().toUpperCase();
                    if (bId.isNotEmpty) {
                      localRegistry[bId] = nowTs;
                      localRegistry[bId.toUpperCase()] = nowTs;
                      localTombstones.add(bId);
                    }
                    if (bNo.isNotEmpty) {
                      localRegistry[bNo] = nowTs;
                      localTombstones.add(bNo);
                    }
                  }
                }
              }
            } catch (_) {}
          }

          // STEP 3: EXECUTE DEATH (The Graveyard - Monotonic Anti-Zombie & Multi-Key)
          TombstoneEngine.purgeDeletedRecordsWithRegistry(ph, localRegistry);
          TombstoneEngine.purgeDeletedRecords(ph, localTombstones, localRegistry);

          // STEP 4: DELTA MERGE (The Updater)
          bool hasChanges = DeltaMergeEngine.processCloudData(ph, cloudFiles, localRegistry, localHashes) || d1HasChanges;

          // Final post-merge tombstone sweep so nothing slips through
          TombstoneEngine.purgeDeletedRecordsWithRegistry(ph, localRegistry);
          TombstoneEngine.purgeDeletedRecords(ph, localTombstones, localRegistry);

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
            ph.notifyListeners();
          }
        }
      }

      await TombstoneEngine.saveTombstoneRegistry(companyId, localRegistry);
      await TombstoneEngine.saveLocalTombstones(companyId, localTombstones);
      await SnapshotWatcher.takeSnapshot(ph);

      // 🛡️ Ensure ALL core disk files strictly match in-memory state before pushing to Cloud Relay
      try {
        await File('$workingDir/sales.json').writeAsString(jsonEncode(ph.sales.map((e) => e.toMap()).toList()));
        await File('$workingDir/purc.json').writeAsString(jsonEncode(ph.purchases.map((e) => e.toMap()).toList()));
        await File('$workingDir/parts.json').writeAsString(jsonEncode(ph.parties.map((e) => e.toMap()).toList()));
        await File('$workingDir/meds.json').writeAsString(jsonEncode(ph.medicines.map((e) => e.toMap()).toList()));
        await File('$workingDir/vouc.json').writeAsString(jsonEncode(ph.vouchers.map((e) => e.toMap()).toList()));
        await File('$workingDir/s_challan.json').writeAsString(jsonEncode(ph.saleChallans.map((e) => e.toMap()).toList()));
        await File('$workingDir/p_challan.json').writeAsString(jsonEncode(ph.purchaseChallans.map((e) => e.toMap()).toList()));
        await File('$workingDir/s_return.json').writeAsString(jsonEncode(ph.saleReturns.map((e) => e.toMap()).toList()));
        await File('$workingDir/p_return.json').writeAsString(jsonEncode(ph.purchaseReturns.map((e) => e.toMap()).toList()));
        await File('$workingDir/banks.json').writeAsString(jsonEncode(ph.bankTransactions.map((e) => e.toMap()).toList()));
        await File('$workingDir/series.json').writeAsString(jsonEncode(ph.numberingSeries.map((e) => e.toMap()).toList()));
      } catch (e) {
        debugPrint("Error flushing core sync files to disk: $e");
      }

      // STEP 5: PUSH TO CLOUD (The Rebirth)
      Map<String, String> filesPayload = {};
      for (var name in _coreFiles) {
        final file = File('$workingDir/$name');
        if (await file.exists()) {
          filesPayload[name] = await file.readAsString();
        }
      }
      
      filesPayload['tombstones.json'] = jsonEncode(localTombstones.where((k) => !k.contains('/')).toList());
      filesPayload['tombstone_registry.json'] = jsonEncode(localRegistry);

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
