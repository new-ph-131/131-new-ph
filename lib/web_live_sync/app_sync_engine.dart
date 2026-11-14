import '../app_date_logic.dart';
import '../sync_core/modules/settings_sync_module.dart';
import "sub_views/web_accounts/services/web_voucher_d1_sync_service.dart";
import "../gst/gst_diary/services/gst_diary_d1_sync_service.dart";
import "../sync_core/d1_sales_ledger_service.dart";
// FILE: lib/web_live_sync/app_sync_engine.dart

import 'dart:async';
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
import '../sync_core/multi_fy_cloud_vault.dart';
import 'package:path_provider/path_provider.dart';

class AppSyncEngine {
  static const List<String> _coreFiles = [
    'meds.json', 'parts.json', 'sales.json', 'purc.json',
    'bats.json', 'vouc.json', 's_challan.json', 'p_challan.json',
    's_return.json', 'p_return.json', 'banks.json', 'config.json',
    'series.json', 'shortage.json', 'routs.json', 'comps.json', 'salts.json',
    'gst_sessions.json'
  ];

  static Completer<void>? _activePushLock;

  /// 🔄 1000-IQ BULLETPROOF 2-WAY SYNC ENGINE (STATE SNAPSHOT DIFFING & TOMBSTONE PROTOCOL)
  static Future<bool> pushStoreData(PharoahManager ph, [String? targetFyOverride]) async {
    while (_activePushLock != null) {
      try {
        await _activePushLock!.future;
      } catch (_) {}
    }
    final lock = Completer<void>();
    _activePushLock = lock;
    try {
      if (ph.activeCompany == null) return false;
      final String effectiveFy = (targetFyOverride != null && targetFyOverride.trim().isNotEmpty)
          ? targetFyOverride.trim()
          : (ph.currentFY.isNotEmpty
              ? ph.currentFY
              : (ph.activeCompany!.fYears.isNotEmpty ? ph.activeCompany!.fYears.last : ""));
      if (effectiveFy.isEmpty) return false;
      int pendingD1MaxSeq = 0;

      final root = await getApplicationDocumentsDirectory();
      final String workingDir = '${root.path}/Pharoah_Data/${ph.activeCompany!.id}/${ph.activeCompany!.businessType}/$effectiveFy';
      final d = Directory(workingDir);
      if (!await d.exists()) await d.create(recursive: true);

      final prefs = await SharedPreferences.getInstance();
      final companyId = ph.activeCompany!.id;
      final storeToken = await WebLiveToken.getOrCreateToken(companyId);

      // STEP 1: SNAP & DETECT (The Spy)
      Set<String> localTombstones = await TombstoneEngine.getLocalTombstones(companyId);
      Map<String, int> localRegistry = await TombstoneEngine.getTombstoneRegistry(companyId);
      Map<String, String> localHashes = await SnapshotWatcher.getLocalHashes(companyId, effectiveFy);
      D1SalesLedgerService.activeFinancialYear = effectiveFy;
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

      Map<String, dynamic>? pulledCloudData;
      String initialRemoteSyncedAt = "";
      final pullRes = await http.get(pullUri).timeout(const Duration(seconds: 15));
      if (pullRes.statusCode != 200) {
        debugPrint("AppSyncEngine Notice: Aborting push because pre-push PULL returned HTTP ${pullRes.statusCode}");
        return false;
      }
      if (pullRes.statusCode == 200 && !pullRes.body.contains("ERROR")) {
        final Map<String, dynamic> cloudData = jsonDecode(pullRes.body);
        if (cloudData['status'] == 'SUCCESS' && cloudData['files'] != null) {
          pulledCloudData = cloudData;
          initialRemoteSyncedAt = (cloudData['syncedAt'] ?? '').toString().trim();
          final Map<String, dynamic> cloudFiles = Map<String, dynamic>.from(cloudData['files'] as Map);

          final Map<String, int> unmarkedRegistry = await TombstoneEngine.getUnmarkedRegistry(companyId);
          final unmarkedKeys = await TombstoneEngine.getUnmarkedKeys(companyId);
          final List<String> cloudOverridesUnmark = [];
          if (cloudFiles.containsKey('tombstone_registry.json') && cloudFiles['tombstone_registry.json'] != null) {
            try {
              dynamic rawReg = jsonDecode(cloudFiles['tombstone_registry.json']);
              if (rawReg is Map) {
                rawReg.forEach((k, v) {
                  final cleanK = k.toString().trim();
                  if (cleanK.isEmpty || D1SalesLedgerService.isUnscopedSeriesKey(cleanK)) return;
                  final bool keepCase = cleanK.contains('_');
                  final cTs = int.tryParse(v.toString()) ?? 0;
                  final bool isUnmarked = unmarkedKeys.contains(cleanK) || (!keepCase && unmarkedKeys.contains(cleanK.toUpperCase()));
                  final int uTs = unmarkedRegistry[cleanK] ?? (!keepCase ? (unmarkedRegistry[cleanK.toUpperCase()] ?? 0) : 0);
                  if (!isUnmarked || (cTs > 0 && cTs >= uTs)) {
                    final lTs = localRegistry[cleanK] ?? 0;
                    if (cTs > lTs) {
                      localRegistry[cleanK] = cTs;
                      if (!keepCase) localRegistry[cleanK.toUpperCase()] = cTs;
                    }
                    localTombstones.add(cleanK);
                    if (!keepCase) localTombstones.add(cleanK.toUpperCase());
                    if (isUnmarked) cloudOverridesUnmark.add(cleanK);
                  }
                });
              }
            } catch (_) {}
          }
          if (cloudOverridesUnmark.isNotEmpty) {
            await TombstoneEngine.clearUnmarkedForDeletedKeys(companyId, cloudOverridesUnmark);
          }
          if (cloudFiles.containsKey('tombstones.json') && cloudFiles['tombstones.json'] != null) {
            try {
              List<dynamic> cloudT = jsonDecode(cloudFiles['tombstones.json']);
              final sanitizedCloudT = await TombstoneEngine.sanitizeCloudTombstones(
                companyId,
                cloudT.map((e) => e.toString()),
                cloudRegistry: localRegistry,
              );
              // Never poison localRegistry with DateTime.now() on flat legacy tombstones
              localTombstones.addAll(sanitizedCloudT);
            } catch (_) {}
          }
          localTombstones = await TombstoneEngine.sanitizeCloudTombstones(
            companyId,
            localTombstones,
            cloudRegistry: localRegistry,
          );

          // 🚀 STEP 2.5: EDGE D1 REAL-TIME SALES & PURCHASES DELTA HARVEST BEFORE CLOUD MERGE
          bool d1HasChanges = false;
          
          
          final bool stillInEffectiveFy = ph.activeCompany != null &&
              ph.activeCompany!.id == companyId &&
              ph.currentFY == effectiveFy;
          if (D1SalesLedgerService.USE_D1_EDGE_LEDGER) {
            try {
              final deltaRes = await D1SalesLedgerService.fetchSaleDeltasWithCursor(storeToken);
              final edgeEvents = deltaRes.events;
              pendingD1MaxSeq = deltaRes.maxSeq;
              if (edgeEvents.isNotEmpty) {
                if (stillInEffectiveFy) {
                  bool d1Sales = D1SalesLedgerService.applyEventsToLocalSales(ph.sales, edgeEvents, effectiveFy);
                  bool d1Purc = D1SalesLedgerService.applyEventsToLocalPurchases(ph.purchases, edgeEvents, effectiveFy);
                  bool d1SRet = D1SalesLedgerService.applyEventsToLocalSaleReturns(ph.saleReturns, edgeEvents, effectiveFy);
                  bool d1PRet = D1SalesLedgerService.applyEventsToLocalPurchaseReturns(ph.purchaseReturns, edgeEvents, effectiveFy);
                  bool d1Vouc = WebVoucherD1SyncService.applyEdgeEventsToLocalVouchers(ph.vouchers, edgeEvents);
                  bool d1Gst = GstDiaryD1SyncService.applyEdgeEventsToLocalSessions(ph.gstDiarySessions, edgeEvents);
                  bool d1Cfg = GstDiaryD1SyncService.applyEdgeEventsToLocalConfig(
                    currentConfig: ph.config,
                    edgeEvents: edgeEvents,
                    onConfigMutated: (cfg) => ph.config = cfg,
                  );
                  bool d1Series = SettingsSyncModule.applyEdgeEventsToLocalSeries(
                    currentSeries: ph.numberingSeries,
                    edgeEvents: edgeEvents,
                    onSeriesMutated: (updated) => ph.numberingSeries = updated,
                  );
                  if (d1Sales || d1Purc || d1SRet || d1PRet || d1Vouc || d1Gst || d1Cfg || d1Series) d1HasChanges = true;
                }
                await MultiFyCloudVault.applyCrossFyEdgeEventsToLocalDisk(
                  ph: ph,
                  edgeEvents: edgeEvents,
                );
                for (final ev in edgeEvents) {
                  final String action = (ev["action"] ?? "").toString().toUpperCase();
                  final String bId = (ev["bill_id"] ?? "").toString().trim();
                  final String bNo = (ev["bill_no"] ?? "").toString().trim().toUpperCase();
                  final int evTs = int.tryParse((ev["updated_at"] ?? ev["created_at"] ?? "1").toString()) ?? DateTime.now().millisecondsSinceEpoch;
                  final dynamic rawPayload = ev["sale_data"];
                  final String evFy = (ev["fy"] ?? (rawPayload is Map ? rawPayload["fy"] : "") ?? "").toString().trim();
                  DateTime? evDate;
                  if (rawPayload is Map && rawPayload["date"] != null) {
                    evDate = DateTime.tryParse(rawPayload["date"].toString());
                  }
                  if (evFy.isNotEmpty && evFy != effectiveFy) {
                    continue;
                  }
                  if (evDate != null && !D1SalesLedgerService.doesEventBelongToActiveFY(rawPayload, evDate, effectiveFy)) {
                    continue;
                  }
                  final bool isPurc = rawPayload is Map &&
                      (rawPayload["doc_type"] == "PURCHASE" ||
                       rawPayload.containsKey("distributorName") ||
                       rawPayload.containsKey("internalNo"));
                  final bool payloadDel = rawPayload is Map &&
                      ((int.tryParse(rawPayload["is_deleted"]?.toString() ?? rawPayload["isDeleted"]?.toString() ?? "0") ?? 0) == 1 ||
                       rawPayload["status"] == "Deleted");
                  final String scopedBNo = D1SalesLedgerService.scopeSecondaryKey(bNo, effectiveFy);
                  if (action == "DELETE" || action.startsWith("DELETE_") || payloadDel) {
                    if (bId.isNotEmpty) {
                      localRegistry[bId] = evTs;
                      localRegistry[bId.toUpperCase()] = evTs;
                      localTombstones.add(bId);
                    }
                    if (!isPurc && scopedBNo.isNotEmpty) {
                      localRegistry[scopedBNo] = evTs;
                      localTombstones.add(scopedBNo);
                    }
                    if (rawPayload is Map) {
                      final String pId = (rawPayload["partyId"] ?? "").toString().trim().toUpperCase();
                      final String pBill = (rawPayload["billNo"] ?? "").toString().trim();
                      final String iNo = (rawPayload["internalNo"] ?? "").toString().trim().toUpperCase();
                      final String scopedINo = D1SalesLedgerService.scopeSecondaryKey(iNo, effectiveFy);
                      if (scopedINo.isNotEmpty) {
                        localRegistry[scopedINo] = evTs;
                        localTombstones.add(scopedINo);
                      }
                      if (pId.isNotEmpty && pBill.isNotEmpty) {
                        final c2 = D1SalesLedgerService.scopeSecondaryKey("${pId}_$pBill", effectiveFy, true);
                        localRegistry[c2] = evTs;
                        localTombstones.add(c2);
                        if (iNo.isNotEmpty) {
                          final c3 = D1SalesLedgerService.scopeSecondaryKey("${pId}_${pBill}_$iNo", effectiveFy, true);
                          localRegistry[c3] = evTs;
                          localTombstones.add(c3);
                        }
                      }
                    }
                  } else {
                    final bool alreadyDel = bId.isNotEmpty && D1SalesLedgerService.isBillDeleted(bId, "", "", effectiveFy);
                    if (alreadyDel) continue;
                    if (rawPayload is Map && isPurc) {
                      final String pId = (rawPayload["partyId"] ?? "").toString().trim().toUpperCase();
                      final String pBill = (rawPayload["billNo"] ?? "").toString().trim();
                      final String iNo = (rawPayload["internalNo"] ?? "").toString().trim().toUpperCase();
                      final bool blocked = bId.isNotEmpty
                          ? D1SalesLedgerService.isPurchaseIdDeleted(bId, effectiveFy)
                          : D1SalesLedgerService.isPurchaseDeleted(bId, pId, pBill, iNo, effectiveFy);
                      if (blocked) {
                        continue;
                      }
                      D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(bId, pId, pBill, iNo, effectiveFy);
                    }
                    if (bId.isNotEmpty) {
                      localRegistry.remove(bId);
                      localRegistry.remove(bId.toUpperCase());
                      localTombstones.remove(bId);
                      localTombstones.remove(bId.toUpperCase());
                    }
                    if (!isPurc && scopedBNo.isNotEmpty) {
                      localRegistry.remove(scopedBNo);
                      localTombstones.remove(scopedBNo);
                    }
                    if (rawPayload is Map) {
                      final String pId = (rawPayload["partyId"] ?? "").toString().trim().toUpperCase();
                      final String pBill = (rawPayload["billNo"] ?? "").toString().trim();
                      final String iNo = (rawPayload["internalNo"] ?? "").toString().trim().toUpperCase();
                      final String scopedINo = D1SalesLedgerService.scopeSecondaryKey(iNo, effectiveFy);
                      final String scopedPBill = D1SalesLedgerService.scopeSecondaryKey(pBill, effectiveFy);
                      if (scopedINo.isNotEmpty) {
                        localRegistry.remove(scopedINo);
                        localTombstones.remove(scopedINo);
                      }
                      if (!isPurc && scopedPBill.isNotEmpty) {
                        localRegistry.remove(scopedPBill);
                        localTombstones.remove(scopedPBill);
                      }
                      if (pId.isNotEmpty && pBill.isNotEmpty) {
                        final c2 = D1SalesLedgerService.scopeSecondaryKey("${pId}_$pBill", effectiveFy, true);
                        localRegistry.remove(c2);
                        localTombstones.remove(c2);
                        if (iNo.isNotEmpty) {
                          final c3 = D1SalesLedgerService.scopeSecondaryKey("${pId}_${pBill}_$iNo", effectiveFy, true);
                          localRegistry.remove(c3);
                          localTombstones.remove(c3);
                        }
                      }
                    }
                  }
                }
              }
            } catch (_) {}
          }

          // STEP 3.5: SYNC OTHER FINANCIAL YEARS FROM CLOUD VAULT TO DISK & EXTRACT CURRENT FY FILES
          await MultiFyCloudVault.syncVaultYearsToLocalDisk(
            ph: ph,
            cloudData: cloudData,
            localTombstones: localTombstones,
            localRegistry: localRegistry,
          );

          if (ph.activeCompany != null && ph.activeCompany!.id == companyId && ph.currentFY == effectiveFy) {
            // STEP 3: EXECUTE DEATH (The Graveyard - Monotonic Anti-Zombie & Multi-Key)
            TombstoneEngine.purgeDeletedRecordsWithRegistry(ph, localRegistry);
            TombstoneEngine.purgeDeletedRecords(ph, localTombstones, localRegistry);

            final Map<String, dynamic>? currentFyCloudFiles = MultiFyCloudVault.extractFyFilesForTargetYear(
              cloudData: cloudData,
              targetFy: effectiveFy,
            );

            // STEP 4: DELTA MERGE (The Updater - Strictly Scoped to ph.currentFY)
            bool hasChanges = (currentFyCloudFiles != null
                    ? DeltaMergeEngine.processCloudData(ph, currentFyCloudFiles, localRegistry, localHashes)
                    : false) ||
                d1HasChanges;

            // Final post-merge tombstone sweep so nothing slips through
            TombstoneEngine.purgeDeletedRecordsWithRegistry(ph, localRegistry);
            TombstoneEngine.purgeDeletedRecords(ph, localTombstones, localRegistry);

            if (hasChanges || newlyDeleted.isNotEmpty) {
              InventoryLogicCenter.rebuildAllInventory(
                medicines: ph.medicines,
                batchHistory: ph.batchHistory,
                purchases: ph.purchases,
                sales: ph.sales,
                saleReturns: ph.saleReturns,
                purchaseReturns: ph.purchaseReturns,
              );
              if (hasChanges &&
                  ph.activeCompany != null &&
                  ph.activeCompany!.fYears.length > 1 &&
                  ph.currentFY.isNotEmpty &&
                  ph.currentFY != ph.activeCompany!.fYears.last) {
                await ph.syncOpeningBalancesFromPreviousYear(
                  startYear: ph.currentFY,
                  onStepProgress: (_, __) {},
                  reloadActiveYearAtEnd: false,
                );
              }
              ph.notifyListeners();
            }
          }
        }
      }

      await TombstoneEngine.saveTombstoneRegistry(companyId, localRegistry);
      await TombstoneEngine.saveLocalTombstones(companyId, localTombstones);
      if (pendingD1MaxSeq > 0) {
        await D1SalesLedgerService.commitSaleDeltaSeq(storeToken, pendingD1MaxSeq);
      }
      if (ph.activeCompany != null && ph.activeCompany!.id == companyId && ph.currentFY == effectiveFy) {
        await SnapshotWatcher.takeSnapshot(ph);

        // 🛡️ Ensure ALL core disk files strictly match in-memory state before pushing to Cloud Relay
        try {
          await File('$workingDir/sales.json').writeAsString(jsonEncode(ph.sales.map((e) => e.toMap()).toList()));
          await File('$workingDir/purc.json').writeAsString(jsonEncode(ph.purchases.map((e) => e.toMap()).toList()));
          await File('$workingDir/parts.json').writeAsString(jsonEncode(ph.parties.map((e) => e.toMap()).toList()));
          await File('$workingDir/meds.json').writeAsString(jsonEncode(ph.medicines.map((e) => e.toMap()).toList()));
          await File('$workingDir/comps.json').writeAsString(jsonEncode(ph.companies.map((e) => e.toMap()).toList()));
          await File('$workingDir/salts.json').writeAsString(jsonEncode(ph.salts.map((e) => e.toMap()).toList()));
          await File('$workingDir/routs.json').writeAsString(jsonEncode(ph.routes.map((e) => e.toMap()).toList()));
          await File('$workingDir/shortage.json').writeAsString(jsonEncode(ph.shortages.map((e) => e.toMap()).toList()));
          await File('$workingDir/vouc.json').writeAsString(jsonEncode(ph.vouchers.map((e) => e.toMap()).toList()));
          await File('$workingDir/s_challan.json').writeAsString(jsonEncode(ph.saleChallans.map((e) => e.toMap()).toList()));
          await File('$workingDir/p_challan.json').writeAsString(jsonEncode(ph.purchaseChallans.map((e) => e.toMap()).toList()));
          await File('$workingDir/s_return.json').writeAsString(jsonEncode(ph.saleReturns.map((e) => e.toMap()).toList()));
          await File('$workingDir/p_return.json').writeAsString(jsonEncode(ph.purchaseReturns.map((e) => e.toMap()).toList()));
          await File('$workingDir/banks.json').writeAsString(jsonEncode(ph.banks.map((e) => e.toMap()).toList()));
          await File('$workingDir/series.json').writeAsString(jsonEncode(ph.numberingSeries.map((e) => e.toMap()).toList()));
          await File('$workingDir/bats.json').writeAsString(jsonEncode(ph.batchHistory.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList()))));
          await File('$workingDir/gst_sessions.json').writeAsString(jsonEncode(ph.gstDiarySessions.map((e) => e.toMap()).toList()));
          await File('$workingDir/config.json').writeAsString(jsonEncode(ph.config.toMap()));
        } catch (e) {
          debugPrint("Error flushing core sync files to disk: $e");
          return false;
        }
      }

      // 🏛️ FINAL BACK-YEAR CARRY-FORWARD ENFORCER BEFORE CLOUD BUNDLE:
      // If active year is a historical year, re-cascade forward to guarantee that
      // all newer FY folders on disk contain authoritative opening balances and stock
      // before building the multi-FY cloud vault payload!
      if (ph.activeCompany != null &&
          ph.activeCompany!.fYears.length > 1) {
        final sortedFys = AppDateLogic.sortFYList(ph.activeCompany!.fYears);
        if (sortedFys.length > 1) {
          final bool cascadeOk = await ph.syncOpeningBalancesFromPreviousYear(
            startYear: sortedFys.first,
            onStepProgress: (_, __) {},
            reloadActiveYearAtEnd: ph.currentFY.isNotEmpty,
          );
          if (!cascadeOk) {
            debugPrint("AppSyncEngine Notice: Aborting push because multi-year carry-forward cascade failed.");
            return false;
          }
        }
      }

      // 🛡️ PRE-PUSH OPTIMISTIC CONCURRENCY CHECK:
      // Verify whether another device updated the remote vault while local merges/cascades were executing.
      if (pulledCloudData != null) {
        try {
          final verifyRes = await http.get(pullUri).timeout(const Duration(seconds: 10));
          if (verifyRes.statusCode == 200 && !verifyRes.body.contains("ERROR")) {
            final Map<String, dynamic> latestCloudData = jsonDecode(verifyRes.body);
            if (latestCloudData['status'] == 'SUCCESS' && latestCloudData['files'] != null) {
              final String latestSyncedAt = (latestCloudData['syncedAt'] ?? '').toString().trim();
              if (latestSyncedAt.isNotEmpty && latestSyncedAt != initialRemoteSyncedAt) {
                debugPrint("🔄 [AppSyncEngine] Concurrent remote push detected ($initialRemoteSyncedAt -> $latestSyncedAt). Re-reconciling before upload...");
                pulledCloudData = latestCloudData;
                initialRemoteSyncedAt = latestSyncedAt;
                await MultiFyCloudVault.syncVaultYearsToLocalDisk(
                  ph: ph,
                  cloudData: latestCloudData,
                  localTombstones: localTombstones,
                  localRegistry: localRegistry,
                );
              }
            }
          }
        } catch (_) {}
      }

      // STEP 5: PUSH TO CLOUD (Multi-FY Cloud Vault — All Financial Years Preserved!)
      final vaultBundle = await MultiFyCloudVault.buildMultiFyCloudPayload(
        ph: ph,
        coreFiles: _coreFiles,
        localTombstones: localTombstones,
        localRegistry: localRegistry,
        targetFyOverride: effectiveFy,
        remoteCloudFiles: pulledCloudData,
      );

      final payload = {
        "action": WebCloudConfig.actionPushStore,
        "storeToken": storeToken,
        "companyId": ph.activeCompany!.id,
        "companyName": ph.activeCompany!.name,
        "adminUser": ph.activeCompany!.adminUser,
        "adminPassword": ph.activeCompany!.password,
        "fy": vaultBundle.primaryFy,
        "activeFy": effectiveFy,
        "baseSyncedAt": initialRemoteSyncedAt,
        "registryProfile": ph.activeCompany!.toMap(),
        "files": vaultBundle.filesPayload,
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
    } finally {
      if (identical(_activePushLock, lock)) {
        _activePushLock = null;
      }
      if (!lock.isCompleted) {
        lock.complete();
      }
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
