// FILE: lib/sync_core/multi_fy_cloud_vault.dart
// Revision: #PH-REV-787 (MULTI-FY-GOOGLE-DRIVE-CLOUD-VAULT)

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../app_date_logic.dart';
import '../gateway/company_registry_model.dart';
import '../models.dart';
import '../pharoah_manager.dart';

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

  /// Decodes `fy_vault.json` from cloud `files` map if present.
  static Map<String, Map<String, String>> parseFyVault(Map<String, dynamic> cloudFiles) {
    final Map<String, Map<String, String>> result = {};
    final rawVault = cloudFiles['fy_vault.json'];
    if (rawVault == null) return result;
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

  /// Syncs any other Financial Years present in `cloudData` (e.g. created or edited on Web) to App local disk folders
  /// and updates `ph.activeCompany.fYears` if a new Financial Year was created on Web.
  static Future<bool> syncVaultYearsToLocalDisk({
    required PharoahManager ph,
    required Map<String, dynamic> cloudData,
  }) async {
    if (ph.activeCompany == null) return false;
    bool registryChanged = false;
    try {
      final root = await getApplicationDocumentsDirectory();
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
      for (final vy in vault.keys) {
        if (vy.trim().isNotEmpty) allKnownFys.add(vy.trim());
      }
      final String cloudTopFy = (cloudData['fy'] ?? '').toString().trim();
      if (cloudTopFy.isNotEmpty) allKnownFys.add(cloudTopFy);

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

      // Write non-active FY files from vault to their respective disk directories
      for (final entry in vault.entries) {
        final String fy = entry.key;
        if (fy == ph.currentFY) continue; // Active FY is handled by DeltaMergeEngine in memory
        final String fyDirPath = '${root.path}/Pharoah_Data/${comp.id}/${comp.businessType}/$fy';
        final Directory fyDir = Directory(fyDirPath);
        if (!await fyDir.exists()) {
          await fyDir.create(recursive: true);
        }
        for (final fEntry in entry.value.entries) {
          if (fEntry.key == 'fy_vault.json') continue;
          final targetFile = File('$fyDirPath/${fEntry.key}');
          if (await targetFile.exists()) {
            try {
              final existingContent = await targetFile.readAsString();
              if (existingContent == fEntry.value) continue;
            } catch (_) {}
          }
          await targetFile.writeAsString(fEntry.value);
        }
      }
    } catch (e) {
      debugPrint("⚠ [MultiFyCloudVault] syncVaultYearsToLocalDisk error: $e");
    }
    return registryChanged;
  }

  /// Builds the complete Multi-FY `filesPayload` for Google Drive Relay.
  /// Always keeps `fYears.last` (latest FY) in top-level `filesPayload` AND embeds all FYs in `fy_vault.json`.
  static Future<({String primaryFy, Map<String, String> filesPayload})> buildMultiFyCloudPayload({
    required PharoahManager ph,
    required List<String> coreFiles,
    required Set<String> localTombstones,
    required Map<String, int> localRegistry,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final comp = ph.activeCompany!;
    final List<String> sortedFys = AppDateLogic.sortFYList(
      comp.fYears.isNotEmpty ? comp.fYears : [ph.currentFY],
    );
    final String latestFy = sortedFys.isNotEmpty ? sortedFys.last : ph.currentFY;

    final Map<String, Map<String, String>> fyVault = {};
    for (final fy in sortedFys) {
      final String fyDirPath = '${root.path}/Pharoah_Data/${comp.id}/${comp.businessType}/$fy';
      final Directory fyDir = Directory(fyDirPath);
      if (!await fyDir.exists()) continue;

      final Map<String, String> singleFyMap = {};
      for (final name in vaultFileKeys) {
        final f = File('$fyDirPath/$name');
        if (await f.exists()) {
          singleFyMap[name] = await f.readAsString();
        }
      }
      if (singleFyMap.isNotEmpty) {
        fyVault[fy] = singleFyMap;
      }
    }

    // Primary top-level files come from `latestFy` (or `ph.currentFY` if latestFy not in vault)
    final Map<String, String> filesPayload = {};
    final Map<String, String> topSource = fyVault[latestFy] ?? fyVault[ph.currentFY] ?? {};
    for (final name in coreFiles) {
      if (topSource.containsKey(name)) {
        filesPayload[name] = topSource[name]!;
      }
    }

    filesPayload['fy_vault.json'] = jsonEncode(fyVault);
    filesPayload['tombstones.json'] = jsonEncode(localTombstones.where((k) => !k.contains('/')).toList());
    filesPayload['tombstone_registry.json'] = jsonEncode(localRegistry);

    return (primaryFy: latestFy, filesPayload: filesPayload);
  }
}
