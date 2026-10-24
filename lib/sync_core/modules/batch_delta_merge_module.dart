// FILE: lib/sync_core/modules/batch_delta_merge_module.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
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
    Iterable<String>? tombstones,
    Map<String, int>? registry,
  }) {
    final cleanMed = productKey.trim();
    final cleanBatch = batchNo.trim().toUpperCase();
    if (cleanMed.isEmpty || cleanBatch.isEmpty) return false;

    final syncId = BatchSyncModule.getBatchSyncId(cleanMed, cleanBatch);

    // 1. D1 Sales Ledger Edge Gravestones
    if (D1SalesLedgerService.isBillDeleted(syncId, cleanBatch, cleanMed)) {
      return true;
    }

    // 2. High-precision Epoch Tombstone Registry
    if (registry != null) {
      if (registry.containsKey(syncId) ||
          registry.containsKey(syncId.toUpperCase()) ||
          registry.containsKey(cleanBatch)) {
        return true;
      }
    }

    // 3. Flat Tombstone Set
    if (tombstones != null) {
      for (final t in tombstones) {
        final upperT = t.trim().toUpperCase();
        if (upperT == syncId || upperT == cleanBatch) {
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
      list.removeWhere((b) => isBatchTombstoned(
        productKey: medKey,
        batchNo: b.batch,
        tombstones: tombstones,
        registry: registry,
      ));
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
        if (batchNo.isEmpty) continue;

        // 🛡️ Tombstone Guard: Do NOT resurrect deleted batches!
        if (isBatchTombstoned(
          productKey: cleanMedKey,
          batchNo: batchNo,
          tombstones: tombstones,
          registry: registry,
        )) {
          // If it accidentally exists in memory, remove it immediately
          existingList.removeWhere((b) => b.batch.trim().toUpperCase() == batchNo);
          continue;
        }

        final incomingBatch = BatchInfo.fromMap(itemMap);
        final idx = existingList.indexWhere((b) => b.batch.trim().toUpperCase() == batchNo);

        if (idx != -1) {
          // Merge metadata
          final existing = existingList[idx];
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
          if (incomingBatch.openingQty != 0.0 && existing.openingQty != incomingBatch.openingQty) {
            existing.openingQty = incomingBatch.openingQty;
            fieldChanged = true;
          }
          if (incomingBatch.adjustmentQty != 0.0 && existing.adjustmentQty != incomingBatch.adjustmentQty) {
            existing.adjustmentQty = incomingBatch.adjustmentQty;
            existing.adjReason = incomingBatch.adjReason;
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
            if (batchNo.isEmpty) continue;
            if (isBatchTombstoned(
              productKey: cleanMedKey,
              batchNo: batchNo,
              tombstones: tombstones,
              registry: registry,
            )) {
              continue; // Drop tombstoned batch
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
