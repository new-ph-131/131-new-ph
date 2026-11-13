// FILE: lib/sync_core/multi_fy_cloud_vault.dart
// Revision: #PH-REV-803 (MULTI-FY-LWW-MERGE-AND-CROSS-FY-EDGE-CASCADE)

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../app_date_logic.dart';
import '../gateway/company_registry_model.dart';
import '../inventory_logic_center.dart';
import '../models.dart';
import '../pharoah_manager.dart';
import 'd1_sales_ledger_service.dart';
import 'modules/batch_delta_merge_module.dart';

class MultiFyCloudVault {
  static const List<String> vaultFileKeys = [
    'meds.json',
    'parts.json',
    'sales.json',
    'purc.json',
    'bats.json',
    'vouc.json',
    's_challan.json',
    'p_challan.json',
    's_return.json',
    'p_return.json',
    'banks.json',
    'config.json',
    'series.json',
    'shortage.json',
    'routs.json',
    'comps.json',
    'salts.json',
    'dtypes.json',
    'pending_invoices.json',
    'gst_sessions.json',
  ];

  static const Set<String> _lwwRecordListFiles = {
    'sales.json',
    'purc.json',
    'vouc.json',
    's_challan.json',
    'p_challan.json',
    's_return.json',
    'p_return.json',
    'parts.json',
    'meds.json',
    'banks.json',
    'routs.json',
    'comps.json',
    'salts.json',
    'gst_sessions.json',
  };

  static const Set<String> _cascadeImpactFiles = {
    'sales.json',
    'purc.json',
    'vouc.json',
    's_return.json',
    'p_return.json',
    's_challan.json',
    'p_challan.json',
    'bats.json',
    'parts.json',
  };

  /// Decodes `fy_vault.json` from either outer `cloudData` response or inner `files` map.
  /// Also incorporates top-level `fy` files from `cloudData` when present.
  static Map<String, Map<String, String>> parseFyVault(Map<String, dynamic> inputMap) {
    final Map<String, dynamic> cloudFiles = (inputMap['files'] is Map)
        ? Map<String, dynamic>.from(inputMap['files'])
        : inputMap;
    final Map<String, Map<String, String>> result = {};
    final rawVault = cloudFiles['fy_vault.json'];
    if (rawVault != null) {
      try {
        final decoded = rawVault is String ? jsonDecode(rawVault) : rawVault;
        if (decoded is Map) {
          decoded.forEach((fyKey, fyFiles) {
            final cleanFy = fyKey.toString().trim();
            if (cleanFy.isNotEmpty && fyFiles is Map) {
              final Map<String, String> fileMap = {};
              fyFiles.forEach((fName, fContent) {
                if (fContent != null) {
                  fileMap[fName.toString()] = fContent is String ? fContent : jsonEncode(fContent);
                }
              });
              result[cleanFy] = fileMap;
            }
          });
        }
      } catch (e) {
        debugPrint("⚠ [MultiFyCloudVault] parseFyVault error: $e");
      }
    }
    final String cloudTopFy = (inputMap['fy'] ?? '').toString().trim();
    if (cloudTopFy.isNotEmpty) {
      final Map<String, String> topMap = result[cloudTopFy] ?? {};
      cloudFiles.forEach((k, v) {
        if (vaultFileKeys.contains(k) && v != null && !topMap.containsKey(k)) {
          topMap[k] = v is String ? v : jsonEncode(v);
        }
      });
      if (topMap.isNotEmpty) {
        result[cloudTopFy] = topMap;
      }
    }
    return result;
  }

  /// Extracts the exact cloud files map for `targetFy`.
  /// Returns null if the cloud payload belongs to a different FY and `fy_vault.json` does not have `targetFy` yet,
  /// preventing cross-year data pollution!
  static Map<String, dynamic>? extractFyFilesForTargetYear({
    required Map<String, dynamic> cloudData,
    required String targetFy,
  }) {
    final cleanTargetFy = targetFy.trim();
    if (cleanTargetFy.isEmpty) return null;

    final Map<String, dynamic> rawCloudFiles =
        (cloudData['files'] is Map) ? Map<String, dynamic>.from(cloudData['files']) : {};
    if (rawCloudFiles.isEmpty) return null;

    final Map<String, Map<String, String>> vault = parseFyVault(rawCloudFiles);
    if (vault.containsKey(cleanTargetFy) && vault[cleanTargetFy]!.isNotEmpty) {
      final Map<String, dynamic> scoped = Map<String, dynamic>.from(vault[cleanTargetFy]!);
      if (rawCloudFiles.containsKey('tombstones.json')) {
        scoped['tombstones.json'] = rawCloudFiles['tombstones.json'];
      }
      if (rawCloudFiles.containsKey('tombstone_registry.json')) {
        scoped['tombstone_registry.json'] = rawCloudFiles['tombstone_registry.json'];
      }
      return scoped;
    }

    final String cloudTopFy = (cloudData['fy'] ?? '').toString().trim();
    if (cloudTopFy.isEmpty || cloudTopFy == cleanTargetFy) {
      return rawCloudFiles;
    }

    // Cloud top-level files belong to a DIFFERENT Financial Year and vault doesn't have targetFy yet:
    // Block cross-year merge!
    debugPrint("🛡️ [MultiFyCloudVault] Blocked cross-FY merge: Cloud top FY is $cloudTopFy, local active FY is $cleanTargetFy.");
    return null;
  }

  static String _recordKeyForMap(String fileName, Map<String, dynamic> m) {
    final String id = (m['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return id;
    if (fileName == 'purc.json' || fileName == 'p_challan.json') {
      final String intNo = (m['internalNo'] ?? '').toString().trim().toUpperCase();
      if (intNo.isNotEmpty) return intNo;
    }
    if (fileName == 'sales.json' ||
        fileName == 's_challan.json' ||
        fileName == 's_return.json' ||
        fileName == 'p_return.json') {
      final String bNo = (m['billNo'] ?? '').toString().trim().toUpperCase();
      if (bNo.isNotEmpty) return bNo;
    }
    if (fileName == 'vouc.json') {
      final String vNo = (m['voucherNo'] ?? '').toString().trim().toUpperCase();
      if (vNo.isNotEmpty) return vNo;
    }
    if (fileName == 'meds.json') {
      final String name = (m['name'] ?? '').toString().trim().toUpperCase();
      final String pack = (m['pack'] ?? '').toString().trim().toUpperCase();
      if (name.isNotEmpty) return '${name}_$pack';
    }
    final String name = (m['name'] ?? '').toString().trim().toUpperCase();
    return name;
  }

  static String _secondarySeriesKeyForMap(String fileName, Map<String, dynamic> m) {
    if (fileName == 'purc.json' || fileName == 'p_challan.json') {
      return (m['internalNo'] ?? '').toString().trim().toUpperCase();
    }
    if (fileName == 'sales.json' ||
        fileName == 's_challan.json' ||
        fileName == 's_return.json' ||
        fileName == 'p_return.json') {
      return (m['billNo'] ?? '').toString().trim().toUpperCase();
    }
    if (fileName == 'vouc.json') {
      return (m['voucherNo'] ?? '').toString().trim().toUpperCase();
    }
    return '';
  }

  static bool _isRecordDeletedInFy(
    String fileName,
    Map<String, dynamic> m,
    String fy, {
    Set<String>? localTombstones,
    Map<String, int>? localRegistry,
  }) {
    final int isDel = int.tryParse((m['isDeleted'] ?? m['is_deleted'] ?? '0').toString()) ?? 0;
    if (isDel == 1) return true;
    final String id = (m['id'] ?? '').toString().trim();
    final String sec = _secondarySeriesKeyForMap(fileName, m);
    final int recUpd = int.tryParse((m['updatedAt'] ?? m['updated_at'] ?? '0').toString()) ?? 0;

    bool checkKeyTombstone(String key, {bool preserveCase = false}) {
      if (key.isEmpty) return false;
      final bool exactOnly = preserveCase || key.contains('_');
      if (localRegistry != null) {
        final int? delTs = exactOnly
            ? localRegistry[key]
            : (localRegistry[key] ?? localRegistry[key.toUpperCase()]);
        if (delTs != null) {
          return recUpd == 0 || delTs >= recUpd;
        }
      }
      if (localTombstones != null) {
        if (localTombstones.contains(key) || (!exactOnly && localTombstones.contains(key.toUpperCase()))) {
          return true;
        }
      }
      return false;
    }

    if (id.isNotEmpty && !D1SalesLedgerService.isUnscopedSeriesKey(id)) {
      if (checkKeyTombstone(id)) return true;
    }

    final String scopedSec = D1SalesLedgerService.scopeSecondaryKey(sec, fy);
    if (scopedSec.isNotEmpty && checkKeyTombstone(scopedSec)) {
      return true;
    }

    if (fileName == 'purc.json' || fileName == 'p_challan.json') {
      final String pId = (m['partyId'] ?? '').toString().trim().toUpperCase();
      final String bNo = (m['billNo'] ?? '').toString().trim();
      if (pId.isNotEmpty && bNo.isNotEmpty) {
        final String comp2 = D1SalesLedgerService.scopeSecondaryKey('${pId}_$bNo', fy, true);
        if (checkKeyTombstone(comp2, preserveCase: true)) return true;
        if (sec.isNotEmpty) {
          final String comp3 = D1SalesLedgerService.scopeSecondaryKey('${pId}_${bNo}_$sec', fy, true);
          if (checkKeyTombstone(comp3, preserveCase: true)) return true;
        }
      }
      return D1SalesLedgerService.isPurchaseDeleted(id, pId, bNo, sec, fy);
    }
    if (id.isNotEmpty || sec.isNotEmpty) {
      return D1SalesLedgerService.isBillDeleted(id, sec, "", fy);
    }
    return false;
  }

  static int? _findMatchingRecordIndex(
    String fileName,
    List<Map<String, dynamic>> mergedList,
    Map<String, dynamic> candidate,
    Map<String, int> keyToIdx,
    Map<String, int> secKeyToIdx,
  ) {
    final String k = _recordKeyForMap(fileName, candidate);
    final String sec = _secondarySeriesKeyForMap(fileName, candidate);

    if (fileName == 'purc.json' || fileName == 'p_challan.json') {
      final String candId = (candidate['id'] ?? '').toString().trim();
      final String candInt = (candidate['internalNo'] ?? '').toString().trim().toUpperCase();
      final String candParty = (candidate['partyId'] ?? '').toString().trim().toUpperCase();
      final String candBill = (candidate['billNo'] ?? '').toString().trim();

      if (candId.isNotEmpty && keyToIdx.containsKey(candId)) {
        final int idx = keyToIdx[candId]!;
        if (idx >= 0 && idx < mergedList.length && mergedList[idx]['_remove'] != true) {
          return idx;
        }
      }

      for (int i = 0; i < mergedList.length; i++) {
        final existing = mergedList[i];
        if (existing['_remove'] == true) continue;
        final String exId = (existing['id'] ?? '').toString().trim();
        final String exInt = (existing['internalNo'] ?? '').toString().trim().toUpperCase();
        final String exParty = (existing['partyId'] ?? '').toString().trim().toUpperCase();
        final String exBill = (existing['billNo'] ?? '').toString().trim();

        if (candId.isNotEmpty && exId.isNotEmpty) {
          if (candId == exId) return i;
          // Distinct non-empty IDs: ONLY match if exact duplicate identity of same (partyId, billNo, internalNo)
          if (candInt.isNotEmpty &&
              candInt == exInt &&
              candParty.isNotEmpty &&
              candParty == exParty &&
              candBill.isNotEmpty &&
              candBill == exBill) {
            return i;
          }
          continue;
        }

        // Legacy fallback when at least one side has an empty ID
        if (candInt.isNotEmpty && exInt.isNotEmpty) {
          if (candInt == exInt) {
            if (candParty.isNotEmpty && candBill.isNotEmpty && exParty.isNotEmpty && exBill.isNotEmpty) {
              if (candParty == exParty && candBill == exBill) return i;
            } else {
              return i;
            }
          }
        } else if (candParty.isNotEmpty &&
            candBill.isNotEmpty &&
            candParty == exParty &&
            candBill == exBill) {
          return i;
        }
      }
      return null;
    }

    return (k.isNotEmpty ? keyToIdx[k] : null) ?? (sec.isNotEmpty ? secKeyToIdx[sec] : null);
  }

  /// Record-level LWW merge between existing local JSON list and incoming cloud JSON list for an FY.
  /// Guarantees that unpushed or newer local edits and remote inactive-FY records are safely reconciled.
  static ({String mergedJson, bool changed}) mergeJsonListLww({
    required String fileName,
    required String localRaw,
    required String cloudRaw,
    required String fy,
    Set<String>? localTombstones,
    Map<String, int>? localRegistry,
  }) =>
      _mergeJsonListLww(
        fileName: fileName,
        localRaw: localRaw,
        cloudRaw: cloudRaw,
        fy: fy,
        localTombstones: localTombstones,
        localRegistry: localRegistry,
      );

  static ({String mergedJson, bool changed}) _mergeJsonListLww({
    required String fileName,
    required String localRaw,
    required String cloudRaw,
    required String fy,
    Set<String>? localTombstones,
    Map<String, int>? localRegistry,
  }) {
    final dynamic localDec = jsonDecode(localRaw);
    final dynamic cloudDec = jsonDecode(cloudRaw);
    if (localDec is! List || cloudDec is! List) {
      return (mergedJson: localRaw, changed: false);
    }

    final List<Map<String, dynamic>> mergedList = [];
    final Map<String, int> keyToIdx = {};
    final Map<String, int> secKeyToIdx = {};
    bool changed = false;

    void upsertCandidate(Map<String, dynamic> candidate, {required bool isCloud}) {
      final String k = _recordKeyForMap(fileName, candidate);
      final String sec = _secondarySeriesKeyForMap(fileName, candidate);
      if (k.isEmpty && sec.isEmpty) return;

      final int? existingIdx = _findMatchingRecordIndex(
        fileName,
        mergedList,
        candidate,
        keyToIdx,
        secKeyToIdx,
      );

      if (_isRecordDeletedInFy(
        fileName,
        candidate,
        fy,
        localTombstones: localTombstones,
        localRegistry: localRegistry,
      )) {
        if (existingIdx != null && existingIdx >= 0 && existingIdx < mergedList.length) {
          final locMap = mergedList[existingIdx];
          final int locUpd = int.tryParse((locMap['updatedAt'] ?? locMap['updated_at'] ?? '0').toString()) ?? 0;
          final int cldUpd = int.tryParse((candidate['updatedAt'] ?? candidate['updated_at'] ?? '0').toString()) ?? 0;
          final String locId = (locMap['id'] ?? '').toString().trim();
          final String cldId = (candidate['id'] ?? '').toString().trim();
          if (locId == cldId || cldUpd == 0 || cldUpd >= locUpd) {
            mergedList[existingIdx]['_remove'] = true;
            changed = true;
          }
        } else if (!isCloud) {
          changed = true;
        }
        return;
      }

      if (existingIdx != null && existingIdx >= 0 && existingIdx < mergedList.length) {
        final locMap = mergedList[existingIdx];
        if (locMap['_remove'] == true) return;
        final int locVer = int.tryParse((locMap['version'] ?? '1').toString()) ?? 1;
        final int cldVer = int.tryParse((candidate['version'] ?? '1').toString()) ?? 1;
        final int locUpd = int.tryParse((locMap['updatedAt'] ?? locMap['updated_at'] ?? '0').toString()) ?? 0;
        final int cldUpd = int.tryParse((candidate['updatedAt'] ?? candidate['updated_at'] ?? '0').toString()) ?? 0;

        final String locId = (locMap['id'] ?? '').toString().trim();
        final String candId = (candidate['id'] ?? '').toString().trim();

        if (cldVer > locVer || (cldVer == locVer && cldUpd > locUpd)) {
          if (fileName == "parts.json" && locMap["opBal"] != null && locUpd >= cldUpd) {
            candidate["opBal"] = locMap["opBal"];
          }
          if (candId.isEmpty && locId.isNotEmpty) {
            candidate["id"] = locId;
          }
          mergedList[existingIdx] = candidate;
          final String newK = _recordKeyForMap(fileName, candidate);
          if (newK.isNotEmpty) keyToIdx[newK] = existingIdx;
          if (sec.isNotEmpty) secKeyToIdx[sec] = existingIdx;
          changed = true;
        } else {
          if (locId.isEmpty && candId.isNotEmpty) {
            locMap["id"] = candId;
            keyToIdx[candId] = existingIdx;
            changed = true;
          }
          if (!isCloud) {
            changed = true;
          }
        }
      } else {
        final int idx = mergedList.length;
        mergedList.add(candidate);
        if (k.isNotEmpty) keyToIdx[k] = idx;
        if (sec.isNotEmpty) secKeyToIdx[sec] = idx;
        if (isCloud) changed = true;
      }
    }

    for (final item in localDec) {
      if (item is! Map) continue;
      upsertCandidate(Map<String, dynamic>.from(item), isCloud: false);
    }

    for (final item in cloudDec) {
      if (item is! Map) continue;
      upsertCandidate(Map<String, dynamic>.from(item), isCloud: true);
    }

    mergedList.removeWhere((m) => m['_remove'] == true);
    if (!changed) {
      return (mergedJson: localRaw, changed: false);
    }
    return (mergedJson: jsonEncode(mergedList), changed: true);
  }

  /// Syncs any other Financial Years present in `cloudData` (e.g. created or edited on Web) to App local disk folders
  /// using Record-Level LWW Merge, and triggers carry-forward cascade if any prior FY was updated.
  static Future<bool> syncVaultYearsToLocalDisk({
    required PharoahManager ph,
    required Map<String, dynamic> cloudData,
    Set<String>? localTombstones,
    Map<String, int>? localRegistry,
    Directory? rootDirOverride,
  }) async {
    if (ph.activeCompany == null) return false;
    bool registryChanged = false;
    final Set<String> mutatedHistoricalFys = {};
    try {
      final root = rootDirOverride ?? await getApplicationDocumentsDirectory();
      final comp = ph.activeCompany!;
      final Map<String, dynamic> rawCloudFiles =
          (cloudData['files'] is Map) ? Map<String, dynamic>.from(cloudData['files']) : {};
      final Map<String, Map<String, String>> vault = parseFyVault(rawCloudFiles);

      final Set<String> allKnownFys = Set<String>.from(comp.fYears);
      if (cloudData['registryProfile'] is Map && cloudData['registryProfile']['fYears'] is List) {
        for (final y in (cloudData['registryProfile']['fYears'] as List)) {
          final cy = y.toString().trim();
          if (cy.isNotEmpty) allKnownFys.add(cy);
        }
      }
      if (rawCloudFiles.containsKey('registered_fyears.json')) {
        try {
          final rawRf = rawCloudFiles['registered_fyears.json'];
          final rfList = rawRf is String ? jsonDecode(rawRf) : rawRf;
          if (rfList is List) {
            for (final y in rfList) {
              final cy = y.toString().trim();
              if (cy.isNotEmpty) allKnownFys.add(cy);
            }
          }
        } catch (_) {}
      }
      for (final vy in vault.keys) {
        if (vy.trim().isNotEmpty) allKnownFys.add(vy.trim());
      }
      final String cloudTopFy = (cloudData['fy'] ?? '').toString().trim();
      if (cloudTopFy.isNotEmpty) allKnownFys.add(cloudTopFy);

      // If Cloud top-level files belong to a non-active FY that is not in vault, include it in vault map
      if (cloudTopFy.isNotEmpty && cloudTopFy != ph.currentFY && !vault.containsKey(cloudTopFy)) {
        final Map<String, String> topMap = {};
        rawCloudFiles.forEach((k, v) {
          if (vaultFileKeys.contains(k) && v != null) {
            topMap[k] = v is String ? v : jsonEncode(v);
          }
        });
        if (topMap.isNotEmpty) {
          vault[cloudTopFy] = topMap;
        }
      }

      final List<String> sortedFys = AppDateLogic.sortFYList(allKnownFys);
      if (sortedFys.length != comp.fYears.length ||
          !sortedFys.every((y) => comp.fYears.contains(y))) {
        final int idx = ph.companiesRegistry.indexWhere((c) => c.id == comp.id);
        final updatedProfile = CompanyProfile(
          id: comp.id,
          name: comp.name,
          businessType: comp.businessType,
          createdAt: comp.createdAt,
          password: comp.password,
          adminUser: comp.adminUser,
          address: comp.address,
          state: comp.state,
          gstin: comp.gstin,
          dlNo: comp.dlNo,
          phone: comp.phone,
          email: comp.email,
          isBiometricEnabled: comp.isBiometricEnabled,
          recoveryKey: comp.recoveryKey,
          autoLockMinutes: comp.autoLockMinutes,
          fYears: sortedFys,
        );
        if (idx != -1) {
          ph.companiesRegistry[idx] = updatedProfile;
        }
        ph.activeCompany = updatedProfile;
        await ph.saveRegistry();
        registryChanged = true;
      }

      // Merge non-active FY files from vault into their respective disk directories using Record-Level LWW
      for (final entry in vault.entries) {
        final String fy = entry.key;
        if (fy == ph.currentFY) continue; // Active FY is handled by DeltaMergeEngine in memory
        final String fyDirPath = '${root.path}/Pharoah_Data/${comp.id}/${comp.businessType}/$fy';
        final Directory fyDir = Directory(fyDirPath);
        if (!await fyDir.exists()) {
          await fyDir.create(recursive: true);
        }
        bool fyHadTransactionMutation = false;
        for (final fEntry in entry.value.entries) {
          final String fileName = fEntry.key;
          if (fileName == 'fy_vault.json') continue;
          final targetFile = File('$fyDirPath/$fileName');
          final String cloudTrim = fEntry.value.trim();

          if (await targetFile.exists()) {
            try {
              final existingContent = await targetFile.readAsString();
              if (existingContent == fEntry.value) continue;
              final existingTrim = existingContent.trim();
              if (existingTrim.length > 10 && (cloudTrim.length <= 4 || cloudTrim == '[]' || cloudTrim == '{}')) {
                debugPrint('🛡️ [MultiFyCloudVault] Shielded local $targetFile (${existingTrim.length} bytes) against empty cloud payload!');
                continue;
              }

              if (_lwwRecordListFiles.contains(fileName)) {
                final mergedRes = _mergeJsonListLww(
                  fileName: fileName,
                  localRaw: existingContent,
                  cloudRaw: fEntry.value,
                  fy: fy,
                  localTombstones: localTombstones,
                  localRegistry: localRegistry,
                );
                if (mergedRes.changed) {
                  await targetFile.writeAsString(mergedRes.mergedJson);
                  if (_cascadeImpactFiles.contains(fileName)) {
                    fyHadTransactionMutation = true;
                  }
                }
                continue;
              } else if (fileName == 'bats.json') {
                final dynamic locMapRaw = jsonDecode(existingContent);
                final dynamic cldMapRaw = jsonDecode(fEntry.value);
                if (locMapRaw is Map && cldMapRaw is Map) {
                  final Map<String, List<BatchInfo>> locBatches = {};
                  locMapRaw.forEach((k, v) {
                    if (v is List) {
                      locBatches[k.toString()] = v
                          .map((b) => BatchInfo.fromMap(Map<String, dynamic>.from(b as Map)))
                          .toList();
                    }
                  });
                  final bool batsChanged = BatchDeltaMergeModule.mergeBatchHistoryFromCloudJson(
                    targetBatchHistory: locBatches,
                    incomingJson: cldMapRaw,
                  );
                  if (batsChanged) {
                    await targetFile.writeAsString(
                      jsonEncode(locBatches.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList()))),
                    );
                    fyHadTransactionMutation = true;
                  }
                  continue;
                }
              }
            } catch (e) {
              debugPrint("⚠ [MultiFyCloudVault] LWW merge fallback for $fy/$fileName: $e");
            }
          }

          if (_lwwRecordListFiles.contains(fileName)) {
            try {
              final mergedRes = _mergeJsonListLww(
                fileName: fileName,
                localRaw: '[]',
                cloudRaw: fEntry.value,
                fy: fy,
                localTombstones: localTombstones,
                localRegistry: localRegistry,
              );
              await targetFile.writeAsString(mergedRes.mergedJson);
            } catch (_) {
              await targetFile.writeAsString(fEntry.value);
            }
          } else {
            await targetFile.writeAsString(fEntry.value);
          }
          if (_cascadeImpactFiles.contains(fileName)) {
            fyHadTransactionMutation = true;
          }
        }

        if (fyHadTransactionMutation) {
          mutatedHistoricalFys.add(fy);
          await _rebuildDiskFyInventory(fyDirPath);
        }
      }

      // If any historical FY earlier than active FY was mutated, cascade opening balances & stock forward!
      if (mutatedHistoricalFys.isNotEmpty && ph.currentFY.isNotEmpty) {
        final List<String> orderedMutated = AppDateLogic.sortFYList(mutatedHistoricalFys);
        final String earliestFy = orderedMutated.first;
        final int earliestIdx = sortedFys.indexOf(earliestFy);
        if (earliestIdx != -1 && earliestIdx < sortedFys.length - 1) {
          debugPrint("🔄 [MultiFyCloudVault] Cascading opening balances & batch stock from mutated vault FY $earliestFy...");
          await ph.syncOpeningBalancesFromPreviousYear(
            startYear: earliestFy,
            onStepProgress: (_, __) {},
            reloadActiveYearAtEnd: true,
          );
          registryChanged = true;
        }
      }
      // 🏛️ CRITICAL BACK-YEAR CASCADE GUARD:
      // If the user active year is a historical/back year (e.g. 2025-26), vault sync from cloud
      // could have merged older future year files. We MUST unconditionally re-cascade forward from
      // ph.currentFY so that the local back-year closing balances (Party opBal, Bank balances, Batch stock)
      // remain strictly authoritative in all future years!
      final int activeBackFyIdx = ph.currentFY.isNotEmpty ? sortedFys.indexOf(ph.currentFY) : -1;
      if (activeBackFyIdx != -1 && activeBackFyIdx < sortedFys.length - 1) {
        debugPrint("🔄 [MultiFyCloudVault] Active FY is back-year ${ph.currentFY}. Cascading forward to newer years...");
        await ph.syncOpeningBalancesFromPreviousYear(
          startYear: ph.currentFY,
          onStepProgress: (_, __) {},
          reloadActiveYearAtEnd: false,
        );
      }
    } catch (e) {
      debugPrint("⚠ [MultiFyCloudVault] syncVaultYearsToLocalDisk error: $e");
    }
    return registryChanged;
  }

  /// Applies cross-FY D1 edge events (`eventFy != ph.currentFY`) directly to their respective FY folder on App local disk
  /// and cascades Opening Balances & Batch Stock forward into newer FYs!
  static Future<bool> applyCrossFyEdgeEventsToLocalDisk({
    required PharoahManager ph,
    required List<Map<String, dynamic>> edgeEvents,
  }) async {
    if (ph.activeCompany == null || edgeEvents.isEmpty) return false;
    final comp = ph.activeCompany!;
    final List<String> knownFys = AppDateLogic.sortFYList(
      comp.fYears.isNotEmpty ? comp.fYears : (ph.currentFY.isNotEmpty ? [ph.currentFY] : []),
    );
    if (knownFys.isEmpty) return false;

    final Map<String, List<Map<String, dynamic>>> eventsByFy = {};
    for (final ev in edgeEvents) {
      final dynamic rawData = ev['sale_data'];
      if (rawData is! Map) continue;
      String evFy = (rawData['fy'] ?? ev['fy'] ?? '').toString().trim();
      if (evFy.isEmpty) {
        final rawDate = rawData['date'] ?? rawData['billDate'] ?? rawData['fromDate'];
        if (rawDate != null) {
          final dt = DateTime.tryParse(rawDate.toString());
          if (dt != null) {
            evFy = AppDateLogic.getFYForDate(dt);
          }
        }
      }
      if (evFy.isEmpty || evFy == ph.currentFY || !knownFys.contains(evFy)) continue;
      eventsByFy.putIfAbsent(evFy, () => []).add(ev);
    }

    if (eventsByFy.isEmpty) return false;

    bool anyMutated = false;
    final Set<String> mutatedFys = {};
    try {
      final root = await getApplicationDocumentsDirectory();
      for (final entry in eventsByFy.entries) {
        final String targetFy = entry.key;
        final List<Map<String, dynamic>> fyEvents = entry.value;
        final String fyDirPath = '${root.path}/Pharoah_Data/${comp.id}/${comp.businessType}/$targetFy';
        final Directory fyDir = Directory(fyDirPath);
        if (!await fyDir.exists()) {
          await fyDir.create(recursive: true);
        }

        final File salesFile = File('$fyDirPath/sales.json');
        final File purcFile = File('$fyDirPath/purc.json');

        List<Sale> fySales = [];
        if (await salesFile.exists()) {
          try {
            final raw = jsonDecode(await salesFile.readAsString());
            if (raw is List) {
              fySales = raw.map((e) => Sale.fromMap(Map<String, dynamic>.from(e as Map))).toList();
            }
          } catch (_) {}
        }

        List<Purchase> fyPurc = [];
        if (await purcFile.exists()) {
          try {
            final raw = jsonDecode(await purcFile.readAsString());
            if (raw is List) {
              fyPurc = raw.map((e) => Purchase.fromMap(Map<String, dynamic>.from(e as Map))).toList();
            }
          } catch (_) {}
        }

        final bool sChanged = D1SalesLedgerService.applyEventsToLocalSales(fySales, fyEvents, targetFy);
        final bool pChanged = D1SalesLedgerService.applyEventsToLocalPurchases(fyPurc, fyEvents, targetFy);

        if (sChanged) {
          await salesFile.writeAsString(jsonEncode(fySales.map((e) => e.toMap()).toList()));
        }
        if (pChanged) {
          await purcFile.writeAsString(jsonEncode(fyPurc.map((e) => e.toMap()).toList()));
        }
        if (sChanged || pChanged) {
          anyMutated = true;
          mutatedFys.add(targetFy);
          await _rebuildDiskFyInventory(fyDirPath);
        }
      }

      if (mutatedFys.isNotEmpty) {
        final List<String> orderedMutated = AppDateLogic.sortFYList(mutatedFys);
        final String earliestFy = orderedMutated.first;
        debugPrint("🔄 [MultiFyCloudVault] Cross-FY D1 edge events applied to $orderedMutated. Cascading from $earliestFy...");
        await ph.syncOpeningBalancesFromPreviousYear(
          startYear: earliestFy,
          onStepProgress: (_, __) {},
          reloadActiveYearAtEnd: ph.currentFY.isNotEmpty,
        );
      }
    } catch (e) {
      debugPrint("⚠ [MultiFyCloudVault] applyCrossFyEdgeEventsToLocalDisk error: $e");
    }
    return anyMutated;
  }

  static Future<void> _rebuildDiskFyInventory(String fyDirPath) async {
    try {
      Future<List<dynamic>> readList(String name) async {
        final f = File('$fyDirPath/$name');
        if (!await f.exists()) return [];
        final dec = jsonDecode(await f.readAsString());
        return dec is List ? dec : [];
      }

      final List<Medicine> meds = (await readList('meds.json'))
          .map((e) => Medicine.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      final List<Sale> sales = (await readList('sales.json'))
          .map((e) => Sale.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      final List<Purchase> purc = (await readList('purc.json'))
          .map((e) => Purchase.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      final List<SaleReturn> sRet = (await readList('s_return.json'))
          .map((e) => SaleReturn.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      final List<PurchaseReturn> pRet = (await readList('p_return.json'))
          .map((e) => PurchaseReturn.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      final Map<String, List<BatchInfo>> bats = {};
      final File batsFile = File('$fyDirPath/bats.json');
      if (await batsFile.exists()) {
        final dec = jsonDecode(await batsFile.readAsString());
        if (dec is Map) {
          dec.forEach((k, v) {
            if (v is List) {
              bats[k.toString()] = v
                  .map((b) => BatchInfo.fromMap(Map<String, dynamic>.from(b as Map)))
                  .toList();
            }
          });
        }
      }

      InventoryLogicCenter.rebuildAllInventory(
        medicines: meds,
        batchHistory: bats,
        purchases: purc,
        sales: sales,
        saleReturns: sRet,
        purchaseReturns: pRet,
      );

      await File('$fyDirPath/meds.json').writeAsString(
        jsonEncode(meds.map((m) => m.toMap()).toList()),
      );
      await batsFile.writeAsString(
        jsonEncode(bats.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList()))),
      );
    } catch (e) {
      debugPrint("⚠ [MultiFyCloudVault] _rebuildDiskFyInventory error: $e");
    }
  }

  /// Builds the complete Multi-FY `filesPayload` for Google Drive Relay.
  /// Always keeps `primaryFy` in top-level `filesPayload` AND embeds all FYs in `fy_vault.json`,
  /// reconciling local disk FY folders with `remoteCloudFiles` so missing/partial local folders
  /// never erase remote inactive-FY records.
  static Future<({String primaryFy, Map<String, String> filesPayload})> buildMultiFyCloudPayload({
    required PharoahManager ph,
    required List<String> coreFiles,
    required Set<String> localTombstones,
    required Map<String, int> localRegistry,
    String? targetFyOverride,
    Map<String, dynamic>? remoteCloudFiles,
    Directory? rootDirOverride,
  }) async {
    final root = rootDirOverride ?? await getApplicationDocumentsDirectory();
    final comp = ph.activeCompany!;
    final Map<String, Map<String, String>> remoteVault =
        remoteCloudFiles != null ? parseFyVault(remoteCloudFiles) : {};

    final Set<String> allFys = {
      ...comp.fYears.map((e) => e.trim()).where((e) => e.isNotEmpty),
      if (ph.currentFY.trim().isNotEmpty) ph.currentFY.trim(),
      if (targetFyOverride != null && targetFyOverride.trim().isNotEmpty) targetFyOverride.trim(),
      ...remoteVault.keys.map((e) => e.trim()).where((e) => e.isNotEmpty),
    };
    if (remoteCloudFiles != null) {
      final Map<String, dynamic> innerFiles = (remoteCloudFiles['files'] is Map)
          ? Map<String, dynamic>.from(remoteCloudFiles['files'])
          : remoteCloudFiles;
      final rawRf = innerFiles['registered_fyears.json'];
      if (rawRf != null) {
        try {
          final rfList = rawRf is String ? jsonDecode(rawRf) : rawRf;
          if (rfList is List) {
            for (final y in rfList) {
              final cy = y.toString().trim();
              if (cy.isNotEmpty) allFys.add(cy);
            }
          }
        } catch (_) {}
      }
    }

    final List<String> sortedFys = AppDateLogic.sortFYList(allFys);
    final String latestFy = sortedFys.isNotEmpty ? sortedFys.last : ph.currentFY;
    // 🛡️ ACTIVE FY PRIORITY: Use explicitly passed targetFyOverride to protect against async suspensions
    final String primaryFy = (targetFyOverride != null && targetFyOverride.trim().isNotEmpty)
        ? targetFyOverride.trim()
        : (ph.currentFY.isNotEmpty ? ph.currentFY : latestFy);

    final Map<String, Map<String, String>> fyVault = {};
    for (final fy in sortedFys) {
      final String fyDirPath = '${root.path}/Pharoah_Data/${comp.id}/${comp.businessType}/$fy';
      final Directory fyDir = Directory(fyDirPath);

      final Map<String, String> singleFyMap = {};
      if (await fyDir.exists()) {
        for (final name in vaultFileKeys) {
          final f = File('$fyDirPath/$name');
          if (await f.exists()) {
            singleFyMap[name] = await f.readAsString();
          }
        }
      }

      // 🛡️ RC-2 REMOTE VAULT RECONCILIATION & SYMMETRIC MERGE:
      // Merge local disk and remote vault per file & per record with tombstone enforcement
      // so missing/partial/empty local folders never wipe out Web-created inactive FY records,
      // while local newer edits and cascaded opening balances remain authoritative.
      final Map<String, String> remoteFyMap = remoteVault[fy] ?? {};
      final Set<String> allFileNames = {...remoteFyMap.keys, ...singleFyMap.keys};
      final Map<String, String> mergedFyMap = {};

      for (final fileName in allFileNames) {
        if (fileName == 'fy_vault.json') continue;
        final String? localContent = singleFyMap[fileName];
        final String? remoteContent = remoteFyMap[fileName];

        if (_lwwRecordListFiles.contains(fileName)) {
          final String safeLocal = (localContent != null && localContent.trim().isNotEmpty)
              ? localContent
              : '[]';
          final String safeRemote = (remoteContent != null && remoteContent.trim().isNotEmpty)
              ? remoteContent
              : '[]';
          try {
            final mergedRes = _mergeJsonListLww(
              fileName: fileName,
              localRaw: safeLocal,
              cloudRaw: safeRemote,
              fy: fy,
              localTombstones: localTombstones,
              localRegistry: localRegistry,
            );
            mergedFyMap[fileName] = mergedRes.mergedJson;
          } catch (_) {
            mergedFyMap[fileName] = localContent ?? remoteContent ?? '[]';
          }
        } else if (fileName == 'bats.json' && localContent != null && remoteContent != null) {
          try {
            final dynamic locMapRaw = jsonDecode(localContent);
            final dynamic cldMapRaw = jsonDecode(remoteContent);
            if (locMapRaw is Map && cldMapRaw is Map) {
              final Map<String, List<BatchInfo>> locBatches = {};
              locMapRaw.forEach((k, v) {
                if (v is List) {
                  locBatches[k.toString()] =
                      v.map((b) => BatchInfo.fromMap(Map<String, dynamic>.from(b as Map))).toList();
                }
              });
              BatchDeltaMergeModule.mergeBatchHistoryFromCloudJson(
                targetBatchHistory: locBatches,
                incomingJson: cldMapRaw,
              );
              mergedFyMap[fileName] = jsonEncode(
                locBatches.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList())),
              );
            } else {
              mergedFyMap[fileName] = localContent;
            }
          } catch (_) {
            mergedFyMap[fileName] = localContent;
          }
        } else {
          mergedFyMap[fileName] = localContent ?? remoteContent!;
        }
      }

      if (mergedFyMap.isNotEmpty) {
        fyVault[fy] = mergedFyMap;
      }
    }

    // Primary top-level files come from `primaryFy` (active year) falling back to `latestFy`
    final Map<String, String> filesPayload = {};
    final Map<String, String> topSource = fyVault[primaryFy] ?? fyVault[latestFy] ?? fyVault[ph.currentFY] ?? {};
    for (final name in coreFiles) {
      if (topSource.containsKey(name)) {
        filesPayload[name] = topSource[name]!;
      }
    }

    filesPayload['fy_vault.json'] = jsonEncode(fyVault);
    filesPayload['registered_fyears.json'] = jsonEncode(sortedFys);
    filesPayload['tombstones.json'] = jsonEncode(localTombstones.where((k) => !k.contains('/')).toList());
    filesPayload['tombstone_registry.json'] = jsonEncode(localRegistry);

    return (primaryFy: primaryFy, filesPayload: filesPayload);
  }
}
