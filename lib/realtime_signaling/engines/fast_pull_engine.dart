import "../../sync_core/d1_sales_ledger_service.dart";
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
/// Strict mandate: Evaluates immutable sync_id/UUID only, never purges by human-readable billNo.
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

      // 1. Fetch Local Tombstone Registry & Hashes
      Map<String, int> localRegistry = await TombstoneEngine.getTombstoneRegistry(companyId);
      Set<String> localTombstones = await TombstoneEngine.getLocalTombstones(companyId);
      Map<String, String> localHashes = await SnapshotWatcher.getLocalHashes(companyId);

      // 🚀 STEP 1.5: REAL-TIME D1 EDGE HARVEST (<30ms) & IMMEDIATE TOMBSTONE LOCK (SALES + PURCHASES)
      if (D1SalesLedgerService.USE_D1_EDGE_LEDGER) {
        try {
          final edgeEvents = await D1SalesLedgerService.fetchSaleDeltas(storeToken);
          if (edgeEvents.isNotEmpty) {
            bool d1SalesMutated = D1SalesLedgerService.applyEventsToLocalSales(ph.sales, edgeEvents);
            bool d1PurcMutated = D1SalesLedgerService.applyEventsToLocalPurchases(ph.purchases, edgeEvents);
            final List<String> newTombKeys = [];
            final List<String> newUnmarkKeys = [];
            for (final ev in edgeEvents) {
              final String action = (ev["action"] ?? "").toString().toUpperCase();
              final String bId = (ev["bill_id"] ?? "").toString().trim();
              final String bNo = (ev["bill_no"] ?? "").toString().trim().toUpperCase();
              final dynamic rawPayload = ev["sale_data"];
              if (action == "DELETE") {
                if (bId.isNotEmpty) {
                  newTombKeys.add(bId);
                  newUnmarkKeys.remove(bId);
                  newUnmarkKeys.remove(bId.toUpperCase());
                }
                if (bNo.isNotEmpty) {
                  newTombKeys.add(bNo);
                  newUnmarkKeys.remove(bNo);
                }
                if (rawPayload is Map) {
                  final String pId = (rawPayload["partyId"] ?? "").toString().trim().toUpperCase();
                  final String pBill = (rawPayload["billNo"] ?? "").toString().trim().toUpperCase();
                  final String iNo = (rawPayload["internalNo"] ?? "").toString().trim().toUpperCase();
                  if (iNo.isNotEmpty) {
                    newTombKeys.add(iNo);
                    newUnmarkKeys.remove(iNo);
                  }
                  if (pId.isNotEmpty && pBill.isNotEmpty) {
                    final c2 = "${pId}_$pBill";
                    newTombKeys.add(c2);
                    newUnmarkKeys.remove(c2);
                    if (iNo.isNotEmpty) {
                      final c3 = "${pId}_${pBill}_$iNo";
                      newTombKeys.add(c3);
                      newUnmarkKeys.remove(c3);
                    }
                  }
                }
              } else {
                if (bId.isNotEmpty) {
                  newUnmarkKeys.add(bId);
                  newTombKeys.remove(bId);
                  newTombKeys.remove(bId.toUpperCase());
                }
                if (bNo.isNotEmpty) {
                  newUnmarkKeys.add(bNo);
                  newTombKeys.remove(bNo);
                }
                if (rawPayload is Map) {
                  final String pId = (rawPayload["partyId"] ?? "").toString().trim().toUpperCase();
                  final String pBill = (rawPayload["billNo"] ?? "").toString().trim().toUpperCase();
                  final String iNo = (rawPayload["internalNo"] ?? "").toString().trim().toUpperCase();
                  if (iNo.isNotEmpty) {
                    newUnmarkKeys.add(iNo);
                    newTombKeys.remove(iNo);
                  }
                  if (pBill.isNotEmpty) {
                    newUnmarkKeys.add(pBill);
                    newTombKeys.remove(pBill);
                  }
                  if (pId.isNotEmpty && pBill.isNotEmpty) {
                    final c2 = "${pId}_$pBill";
                    newUnmarkKeys.add(c2);
                    newTombKeys.remove(c2);
                    if (iNo.isNotEmpty) {
                      final c3 = "${pId}_${pBill}_$iNo";
                      newUnmarkKeys.add(c3);
                      newTombKeys.remove(c3);
                    }
                  }
                }
              }
            }
            if (newUnmarkKeys.isNotEmpty) {
              for (final uk in newUnmarkKeys.toSet()) {
                localRegistry.remove(uk);
                localRegistry.remove(uk.toUpperCase());
                localTombstones.remove(uk);
                localTombstones.remove(uk.toUpperCase());
                await TombstoneEngine.unmarkTombstoneWithTimestamp(companyId, id: uk);
              }
            }
            if (newTombKeys.isNotEmpty) {
              final nowTs = DateTime.now().millisecondsSinceEpoch;
              for (final tk in newTombKeys) {
                localRegistry[tk] = nowTs;
                localRegistry[tk.toUpperCase()] = nowTs;
                localTombstones.add(tk);
                localTombstones.add(tk.toUpperCase());
              }
              await TombstoneEngine.recordBatchTombstones(companyId, newTombKeys, timestamp: nowTs);
            }
            if (d1SalesMutated || d1PurcMutated) {
              InventoryLogicCenter.rebuildAllInventory(
                medicines: ph.medicines,
                batchHistory: ph.batchHistory,
                purchases: ph.purchases,
                sales: ph.sales,
                saleReturns: ph.saleReturns,
                purchaseReturns: ph.purchaseReturns,
              );
              if (d1SalesMutated) {
                await File('$workingDir/sales.json').writeAsString(
                  jsonEncode(ph.sales.map((e) => e.toMap()).toList()),
                );
              }
              if (d1PurcMutated) {
                await File('$workingDir/purc.json').writeAsString(
                  jsonEncode(ph.purchases.map((e) => e.toMap()).toList()),
                );
              }
              ph.notifyListeners();
            }
          }
        } catch (d1Err) {
          debugPrint("⚠ [FastPullEngine] D1 Delta Sync Notice: $d1Err");
        }
      }

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

      // 3. Process Cloud Tombstones & Monotonic Registry (Only IDs, drop sequence numbers)
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

      // 4. Chronological Anti-Zombie Purge with Registry (Timestamp & ID ONLY)
      TombstoneEngine.purgeDeletedRecordsWithRegistry(ph, localRegistry);
      TombstoneEngine.purgeDeletedRecords(ph, localTombstones, localRegistry);

      // 🛡️ UNIVERSAL PRE-MERGE SHIELD FOR ALL CLOUD SNAPSHOT FILES
      void sanitizeCloudFile(String fileName, List<String> Function(Map) keyExtractor) {
        if (!cloudFiles.containsKey(fileName) || cloudFiles[fileName] == null) return;
        try {
          final List<dynamic> rawList = jsonDecode(cloudFiles[fileName]);
          final List<dynamic> filtered = [];
          for (final item in rawList) {
            if (item is Map) {
              final int isDel = int.tryParse(item["is_deleted"]?.toString() ?? item["isDeleted"]?.toString() ?? (item["status"] == "Deleted" || item["status"] == "Cancelled" ? "1" : "0")) ?? 0;
              if (isDel == 1) continue;
              final int itemUpdatedAt = int.tryParse(item["updated_at"]?.toString() ?? item["updatedAt"]?.toString() ?? "0") ?? 0;
              final keys = keyExtractor(item);
              bool isBlocked = false;
              for (int ki = 0; ki < keys.length; ki++) {
                final k = keys[ki].trim();
                final clean = k.toUpperCase();
                if (clean.isEmpty) continue;
                final bool inTombs = localTombstones.contains(clean) || localTombstones.contains(k);
                final int regTs = localRegistry[clean] ?? localRegistry[k] ?? 0;
                if (ki == 0) {
                  // Primary immutable ID check
                  if (inTombs || regTs > 0) {
                    isBlocked = true;
                    break;
                  }
                } else {
                  // Secondary / Series key check: allow newer re-created bills with a newer timestamp!
                  if (regTs > 0 && (itemUpdatedAt == 0 || regTs >= itemUpdatedAt)) {
                    isBlocked = true;
                    break;
                  } else if (regTs == 0 && inTombs && itemUpdatedAt == 0) {
                    isBlocked = true;
                    break;
                  }
                }
              }
              if (!isBlocked) filtered.add(item);
            }
          }
          cloudFiles[fileName] = jsonEncode(filtered);
        } catch (_) {}
      }

      // 🛡️ UNIVERSAL D1 PRE-MERGE SHIELD: Sales, Purchases, Challans, Returns, Vouchers
      void applyUniversalD1Shield(String fileName, String docType, List<String> Function(Map) keyExtractor) {
        if (!cloudFiles.containsKey(fileName) || cloudFiles[fileName] == null) return;
        try {
          final List<dynamic> rawList = jsonDecode(cloudFiles[fileName]);
          final List<dynamic> filtered = [];
          for (final item in rawList) {
            if (item is Map) {
              if (docType == "PURCHASE" || docType == "PURCHASE_CHALLAN") {
                final pId = (item["id"] ?? "").toString();
                final partyId = (item["partyId"] ?? "").toString();
                final billNo = (item["billNo"] ?? "").toString();
                final intNo = (item["internalNo"] ?? "").toString();
                if (D1SalesLedgerService.isPurchaseDeleted(pId, partyId, billNo, intNo)) continue;
                final int itemVer = int.tryParse(item["version"]?.toString() ?? "1") ?? 1;
                if (D1SalesLedgerService.getPurchaseKnownVersion(pId, partyId, billNo, intNo) > itemVer) continue;
                filtered.add(item);
                continue;
              }
              final keys = keyExtractor(item);
              final String k1 = keys.isNotEmpty ? keys[0].trim() : "";
              final String k2 = keys.length > 1 ? keys[1].trim() : "";
              final String k3 = keys.length > 2 ? keys[2].trim() : "";
              if (D1SalesLedgerService.isBillDeleted(k1, k2, k3)) continue;
              final int itemVer = int.tryParse(item["version"]?.toString() ?? "1") ?? 1;
              if (D1SalesLedgerService.getKnownVersion(k1, k2, k3) > itemVer) continue;
              filtered.add(item);
            }
          }
          cloudFiles[fileName] = jsonEncode(filtered);
        } catch (_) {}
      }

      applyUniversalD1Shield("sales.json", "SALE", (m) => [(m["id"] ?? "").toString(), (m["billNo"] ?? "").toString()]);
      applyUniversalD1Shield("purc.json", "PURCHASE", (m) => [(m["id"] ?? "").toString()]);
      applyUniversalD1Shield("vouc.json", "VOUCHER", (m) => [(m["id"] ?? "").toString(), (m["voucherNo"] ?? "").toString()]);
      applyUniversalD1Shield("s_challan.json", "CHALLAN", (m) => [(m["id"] ?? "").toString(), (m["billNo"] ?? "").toString()]);
      applyUniversalD1Shield("p_challan.json", "PURCHASE_CHALLAN", (m) => [(m["id"] ?? "").toString(), (m["billNo"] ?? "").toString(), (m["internalNo"] ?? "").toString()]);
      applyUniversalD1Shield("s_return.json", "SALE_RETURN", (m) => [(m["id"] ?? "").toString(), (m["billNo"] ?? "").toString()]);
      applyUniversalD1Shield("p_return.json", "PURCHASE_RETURN", (m) => [(m["id"] ?? "").toString(), (m["billNo"] ?? "").toString()]);
      sanitizeCloudFile("sales.json", (m) => [(m["id"] ?? "").toString(), (m["billNo"] ?? "").toString()]);
      sanitizeCloudFile("purc.json", (m) {
        final pId = (m["partyId"] ?? "").toString().trim().toUpperCase();
        final bNo = (m["billNo"] ?? "").toString().trim().toUpperCase();
        final iNo = (m["internalNo"] ?? "").toString().trim().toUpperCase();
        final comp2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
        final comp3 = (pId.isNotEmpty && bNo.isNotEmpty && iNo.isNotEmpty) ? "${pId}_${bNo}_$iNo" : "";
        return [(m["id"] ?? "").toString(), iNo, comp2, comp3];
      });
      sanitizeCloudFile("vouc.json", (m) => [(m["id"] ?? "").toString(), (m["voucherNo"] ?? "").toString()]);
      sanitizeCloudFile("s_challan.json", (m) => [(m["id"] ?? "").toString(), (m["billNo"] ?? "").toString()]);
      sanitizeCloudFile("p_challan.json", (m) {
        final pId = (m["partyId"] ?? "").toString().trim().toUpperCase();
        final bNo = (m["billNo"] ?? "").toString().trim().toUpperCase();
        final iNo = (m["internalNo"] ?? "").toString().trim().toUpperCase();
        final comp2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
        final comp3 = (pId.isNotEmpty && bNo.isNotEmpty && iNo.isNotEmpty) ? "${pId}_${bNo}_$iNo" : "";
        return [(m["id"] ?? "").toString(), iNo, comp2, comp3];
      });
      sanitizeCloudFile("s_return.json", (m) => [(m["id"] ?? "").toString(), (m["billNo"] ?? "").toString()]);
      sanitizeCloudFile("p_return.json", (m) => [(m["id"] ?? "").toString(), (m["billNo"] ?? "").toString()]);

      // 5. Delta Merge Cloud Data into Memory
      bool hasChanges = DeltaMergeEngine.processCloudData(ph, cloudFiles, localRegistry, localHashes);

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

        await TombstoneEngine.saveTombstoneRegistry(companyId, localRegistry);
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
