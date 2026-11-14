// FILE: lib/sync_core/modules/batch_delta_merge_module.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../inventory_logic_center.dart';
import '../../models.dart';
import '../d1_sales_ledger_service.dart';
import 'batch_sync_module.dart';

/// 🛡️ BATCH DELTA MERGE & ANTI-ZOMBIE SUPPRESSION MODULE (#PH-REV-762)
/// Complies with strict Enterprise File Separation Architecture.
/// Guarantees:
/// 1. Deleted/Tombstoned batches NEVER resurrect during transaction hydration or cloud pull.
/// 2. LWW updates to existing batches without wiping in-memory state.
/// 3. Deep synchronization between Flutter Mobile App and Cloudflare Web Portal.
class BatchDeltaMergeModule {
  /// Checks whether a specific batch for a product has been marked deleted or tombstoned.
  static bool isBatchTombstoned({
    required String productKey,
    required String batchNo,
    String exp = '',
    double mrp = 0.0,
    double purRate = 0.0,
    Iterable<String>? tombstones,
    Map<String, int>? registry,
  }) {
    final cleanMed = productKey.trim();
    final cleanBatch = batchNo.trim().toUpperCase();
    if (cleanMed.isEmpty) return false;

    final syncId = BatchSyncModule.getBatchSyncId(
      cleanMed,
      cleanBatch,
      exp: exp,
      mrp: mrp,
      purRate: purRate,
    );
    final upperSyncId = syncId.toUpperCase();

    // 1. D1 Sales Ledger Edge Gravestones
    if (D1SalesLedgerService.isBillDeleted(syncId, cleanBatch, cleanMed)) {
      return true;
    }

    // 2. High-precision Epoch Tombstone Registry
    if (registry != null) {
      if (registry.containsKey(syncId) ||
          registry.containsKey(upperSyncId) ||
          (cleanBatch.isNotEmpty && registry.containsKey(cleanBatch))) {
        return true;
      }
    }

    // 3. Flat Tombstone Set
    if (tombstones != null) {
      for (final t in tombstones) {
        final upperT = t.trim().toUpperCase();
        if (upperT == upperSyncId || (cleanBatch.isNotEmpty && upperT == cleanBatch)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Purges any tombstoned/deleted batches currently residing in [batchHistory].
  static int purgeTombstonedBatches(
    Map<String, List<BatchInfo>> batchHistory, {
    Iterable<String>? tombstones,
    Map<String, int>? registry,
  }) {
    int purgedCount = 0;
    final keysToRemove = <String>[];

    batchHistory.forEach((medKey, list) {
      final beforeLen = list.length;
      list.removeWhere((b) {
        final bPur = b.purRate > 0 ? b.purRate : b.rate;
        return isBatchTombstoned(
          productKey: medKey,
          batchNo: b.batch,
          exp: b.exp,
          mrp: b.mrp,
          purRate: bPur,
          tombstones: tombstones,
          registry: registry,
        );
      });
      purgedCount += (beforeLen - list.length);
      if (list.isEmpty) {
        keysToRemove.add(medKey);
      }
    });

    for (final k in keysToRemove) {
      batchHistory.remove(k);
    }

    if (purgedCount > 0) {
      debugPrint("🛡️ [BatchDeltaMergeModule] Purged $purgedCount tombstoned/deleted batch(es).");
    }
    return purgedCount;
  }

  /// Merges incoming cloud batch JSON (from bats.json payload) into memory [batchHistory]
  /// with LWW conflict resolution and tombstone suppression.
  static bool mergeBatchHistoryFromCloudJson({
    required Map<String, List<BatchInfo>> targetBatchHistory,
    required dynamic incomingJson,
    Iterable<String>? tombstones,
    Map<String, int>? registry,
  }) {
    if (incomingJson == null) return false;

    Map<String, dynamic> rawMap = {};
    if (incomingJson is String) {
      try {
        final d = jsonDecode(incomingJson);
        if (d is Map) rawMap = Map<String, dynamic>.from(d);
      } catch (_) {
        return false;
      }
    } else if (incomingJson is Map) {
      rawMap = Map<String, dynamic>.from(incomingJson);
    } else {
      return false;
    }

    if (rawMap.isEmpty) return false;

    bool hasChanged = false;

    // First: purge any local tombstoned batches
    purgeTombstonedBatches(
      targetBatchHistory,
      tombstones: tombstones,
      registry: registry,
    );

    rawMap.forEach((medKey, rawList) {
      final cleanMedKey = medKey.toString().trim();
      if (cleanMedKey.isEmpty || rawList is! List) return;

      if (!targetBatchHistory.containsKey(cleanMedKey)) {
        targetBatchHistory[cleanMedKey] = [];
      }
      final existingList = targetBatchHistory[cleanMedKey]!;

      for (final rawItem in rawList) {
        if (rawItem is! Map) continue;
        final itemMap = Map<String, dynamic>.from(rawItem);
        final batchNo = (itemMap['batch'] ?? "").toString().trim().toUpperCase();
        final incomingBatch = BatchInfo.fromMap(itemMap);
        final double incPur = incomingBatch.purRate > 0 ? incomingBatch.purRate : incomingBatch.rate;

        // 🛡️ Tombstone Guard: Do NOT resurrect deleted batches (named or distinct empty-batch lots)!
        if (isBatchTombstoned(
          productKey: cleanMedKey,
          batchNo: batchNo,
          exp: incomingBatch.exp,
          mrp: incomingBatch.mrp,
          purRate: incPur,
          tombstones: tombstones,
          registry: registry,
        )) {
          if (batchNo.isNotEmpty) {
            existingList.removeWhere((b) => b.batch.trim().toUpperCase() == batchNo);
          } else {
            final idxToDel = InventoryLogicCenter.findMatchingBatchIndex(
              existingList,
              batchNo: '',
              exp: incomingBatch.exp,
              mrp: incomingBatch.mrp,
              purRate: incPur,
              exactEmptyBatchLot: true,
            );
            if (idxToDel != -1) existingList.removeAt(idxToDel);
          }
          continue;
        }
        final idx = InventoryLogicCenter.findMatchingBatchIndex(
          existingList,
          batchNo: batchNo,
          exp: incomingBatch.exp,
          mrp: incomingBatch.mrp,
          purRate: incPur,
          exactEmptyBatchLot: true,
        );

        if (idx != -1) {
          // Merge metadata
          final existing = existingList[idx];
          // 🛡️ LWW Version Guard: If local has in-flight edits with higher version/timestamp, do NOT overwrite!
          if (existing.version > incomingBatch.version && existing.version > 1) {
            continue;
          }
          if (existing.version == incomingBatch.version && existing.updatedAt > incomingBatch.updatedAt && existing.updatedAt > 0) {
            continue;
          }
          bool fieldChanged = false;

          if (incomingBatch.exp.isNotEmpty && existing.exp != incomingBatch.exp) {
            existing.exp = incomingBatch.exp;
            fieldChanged = true;
          }
          if (incomingBatch.mrp > 0 && existing.mrp != incomingBatch.mrp) {
            existing.mrp = incomingBatch.mrp;
            fieldChanged = true;
          }
          if (incomingBatch.purRate > 0 && existing.purRate != incomingBatch.purRate) {
            existing.purRate = incomingBatch.purRate;
            existing.rate = incomingBatch.purRate;
            fieldChanged = true;
          }
          if (incomingBatch.rateA > 0 && existing.rateA != incomingBatch.rateA) {
            existing.rateA = incomingBatch.rateA;
            fieldChanged = true;
          }
          if (incomingBatch.rateB > 0 && existing.rateB != incomingBatch.rateB) {
            existing.rateB = incomingBatch.rateB;
            fieldChanged = true;
          }
          if (incomingBatch.rateC > 0 && existing.rateC != incomingBatch.rateC) {
            existing.rateC = incomingBatch.rateC;
            fieldChanged = true;
          }
          if (incomingBatch.rateCFormula > 0 && existing.rateCFormula != incomingBatch.rateCFormula) {
            existing.rateCFormula = incomingBatch.rateCFormula;
            fieldChanged = true;
          }
          if (incomingBatch.appliedRateType.isNotEmpty && existing.appliedRateType != incomingBatch.appliedRateType) {
            existing.appliedRateType = incomingBatch.appliedRateType;
            fieldChanged = true;
          }
          if (incomingBatch.status.isNotEmpty && existing.status != incomingBatch.status) {
            existing.status = incomingBatch.status;
            fieldChanged = true;
          }
          final bool isIncomingNewerOrEqual = incomingBatch.version > existing.version ||
              (incomingBatch.version == existing.version && incomingBatch.updatedAt >= existing.updatedAt);
          if (existing.openingQty != incomingBatch.openingQty &&
              (isIncomingNewerOrEqual || (incomingBatch.openingQty != 0.0 && existing.openingQty == 0.0))) {
            existing.openingQty = incomingBatch.openingQty;
            fieldChanged = true;
          }
          if (isIncomingNewerOrEqual) {
            if (existing.adjustmentQty != incomingBatch.adjustmentQty ||
                existing.adjReason != incomingBatch.adjReason) {
              existing.adjustmentQty = incomingBatch.adjustmentQty;
              existing.adjReason = incomingBatch.adjReason;
              fieldChanged = true;
            }
            if (existing.adjustmentHistory.length != incomingBatch.adjustmentHistory.length ||
                incomingBatch.version > existing.version ||
                incomingBatch.updatedAt > existing.updatedAt) {
              existing.adjustmentHistory = List<BatchAdjustmentRecord>.from(incomingBatch.adjustmentHistory);
              fieldChanged = true;
            }
            if (incomingBatch.version > existing.version) {
              existing.version = incomingBatch.version;
              fieldChanged = true;
            }
            if (incomingBatch.updatedAt > existing.updatedAt) {
              existing.updatedAt = incomingBatch.updatedAt;
              fieldChanged = true;
            }
          } else if (incomingBatch.adjustmentQty != 0.0 && existing.adjustmentQty != incomingBatch.adjustmentQty) {
            existing.adjustmentQty = incomingBatch.adjustmentQty;
            existing.adjReason = incomingBatch.adjReason;
            if (existing.adjustmentHistory.isEmpty && incomingBatch.adjustmentHistory.isNotEmpty) {
              existing.adjustmentHistory = List<BatchAdjustmentRecord>.from(incomingBatch.adjustmentHistory);
            }
            fieldChanged = true;
          }

          if (fieldChanged) hasChanged = true;
        } else {
          // Insert new batch
          existingList.add(incomingBatch);
          hasChanged = true;
        }
      }
    });

    return hasChanged;
  }

  /// Sanitizes a raw JSON string of bats.json before cloud storage or disk write,
  /// removing any tombstoned entries.
  static String filterTombstonedBatchJson(
    String rawBatsJson, {
    Iterable<String>? tombstones,
    Map<String, int>? registry,
  }) {
    if (rawBatsJson.trim().isEmpty) return "{}";
    try {
      final decoded = jsonDecode(rawBatsJson);
      if (decoded is! Map) return rawBatsJson;

      final sanitized = <String, List<dynamic>>{};
      decoded.forEach((medKey, list) {
        final cleanMedKey = medKey.toString().trim();
        if (cleanMedKey.isEmpty || list is! List) return;

        final validBatches = <dynamic>[];
        for (final item in list) {
          if (item is Map) {
            final batchNo = (item['batch'] ?? "").toString().trim().toUpperCase();
            final itemMap = Map<String, dynamic>.from(item);
            final parsed = BatchInfo.fromMap(itemMap);
            final double pPur = parsed.purRate > 0 ? parsed.purRate : parsed.rate;
            if (isBatchTombstoned(
              productKey: cleanMedKey,
              batchNo: batchNo,
              exp: parsed.exp,
              mrp: parsed.mrp,
              purRate: pPur,
              tombstones: tombstones,
              registry: registry,
            )) {
              continue; // Drop tombstoned batch or specific empty-batch lot
            }
            validBatches.add(item);
          }
        }
        if (validBatches.isNotEmpty) {
          sanitized[cleanMedKey] = validBatches;
        }
      });

      return jsonEncode(sanitized);
    } catch (_) {
      return rawBatsJson;
    }
  }
}

// fix trigger
