// FILE: lib/sync_core/modules/batch_sync_module.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../inventory_logic_center.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';
import '../d1_sales_ledger_service.dart';

/// 🛡️ BATCH MASTER SYNC MODULE (#PH-REV-764)
/// Handles autonomous batch mirroring, LWW monotonic versioning,
/// D1 Outbox integration, and Tombstone deletion shielding across App & Web.
class BatchSyncModule {
  static String cleanString(String input) {
    return input.replaceAll(RegExp(r"[^A-Z0-9]"), "").toUpperCase();
  }

  /// Unique composite syncId for each batch
  static String getBatchSyncId(
    String medIdentityKey,
    String batchNo, {
    String exp = '',
    double mrp = 0.0,
    double purRate = 0.0,
  }) {
    final cMed = cleanString(medIdentityKey);
    final cBatch = cleanString(batchNo);
    if (cBatch.isNotEmpty) {
      return "BATCH_${cMed}_$cBatch";
    }
    return InventoryLogicCenter.makeSyncKey(
      medIdentityKey,
      '',
      exp: exp,
      mrp: mrp,
      purRate: purRate,
    );
  }

  /// 📤 1. D1 OUTBOX ENQUEUE: Push Batch Mutation directly to Cloudflare D1
  static void onBatchSaved({
    required BatchInfo batch,
    required String medIdentityKey,
    required String storeToken,
    bool isDelete = false,
  }) {
    if (storeToken.trim().isEmpty || medIdentityKey.trim().isEmpty) return;

    final double bPur = batch.purRate > 0 ? batch.purRate : batch.rate;
    final syncId = getBatchSyncId(
      medIdentityKey,
      batch.batch,
      exp: batch.exp,
      mrp: batch.mrp,
      purRate: bPur,
    );
    final int versionToPush = batch.version > 0 ? batch.version : 1;

    SyncQueueManager.enqueueMutation(
      syncId: syncId,
      storeToken: storeToken.trim().toUpperCase(),
      docType: 'BATCH',
      currentVersion: versionToPush,
      isDelete: isDelete,
      rawPayload: {
        'medKey': medIdentityKey.trim(),
        'batch': batch.toMap(),
        'fy': D1SalesLedgerService.activeFinancialYear,
        'isDeleted': isDelete ? 1 : 0,
      },
    );
  }

  /// 📥 2. MERGE INCOMING ENVELOPE FROM D1 BATCH WITH LWW MONOTONIC VERSIONING
  static bool mergeIncomingBatchEnvelope(
    Map<String, List<BatchInfo>> batchHistory,
    SyncEnvelope envelope, [
    Map<String, int>? tombstoneRegistry,
  ]) {
    final Map<String, dynamic> rawData = envelope.billData;
    final String medKey = (rawData['medKey'] ?? "").toString().trim();
    final dynamic rawBatch = rawData['batch'];

    if (medKey.isEmpty || rawBatch == null) return false;

    final Map<String, dynamic> batchMap = rawBatch is Map<String, dynamic>
        ? rawBatch
        : Map<String, dynamic>.from(rawBatch as Map);

    final String batchNo = (batchMap['batch'] ?? "").toString().trim();
    final incomingPreview = BatchInfo.fromMap(batchMap);
    final double incPur = incomingPreview.purRate > 0 ? incomingPreview.purRate : incomingPreview.rate;
    final syncId = getBatchSyncId(
      medKey,
      batchNo,
      exp: incomingPreview.exp,
      mrp: incomingPreview.mrp,
      purRate: incPur,
    );
    bool isDel = envelope.isDeleted == 1 || envelope.action == "DELETE";
    final int incomingVersion = envelope.version > 0 ? envelope.version : 1;
    final int incomingTimestamp = envelope.updatedAt > 0 ? envelope.updatedAt : DateTime.now().millisecondsSinceEpoch;
    final String envFy = (rawData['fy'] ?? batchMap['fy'] ?? '').toString().trim();
    final String activeFy = D1SalesLedgerService.activeFinancialYear.trim();
    final bool isCrossFy = envFy.isNotEmpty && activeFy.isNotEmpty && envFy != activeFy;

    if (isCrossFy && isDel) {
      return false;
    }

    // Check Permanent Tombstones
    if ((batchNo.isNotEmpty && D1SalesLedgerService.isBillDeleted(syncId, batchNo, medKey)) ||
        (tombstoneRegistry != null && tombstoneRegistry.containsKey(syncId))) {
      if (!isDel) {
        D1SalesLedgerService.unmarkPermanentlyDeleted(syncId, batchNo, medKey);
      } else {
        if (batchHistory.containsKey(medKey)) {
          final idxToRemove = InventoryLogicCenter.findMatchingBatchIndex(
            batchHistory[medKey]!,
            batchNo: batchNo,
            exp: incomingPreview.exp,
            mrp: incomingPreview.mrp,
            purRate: incPur,
            exactEmptyBatchLot: true,
          );
          if (idxToRemove != -1) {
            batchHistory[medKey]!.removeAt(idxToRemove);
            return true;
          }
        }
        return false;
      }
    }

    final existingList = batchHistory[medKey];
    final int preExistingIdx = existingList == null
        ? -1
        : InventoryLogicCenter.findMatchingBatchIndex(
            existingList,
            batchNo: batchNo,
            exp: incomingPreview.exp,
            mrp: incomingPreview.mrp,
            purRate: incPur,
            exactEmptyBatchLot: true,
          );

    if (preExistingIdx == -1 && isCrossFy) {
      return false;
    }

    if (!batchHistory.containsKey(medKey)) {
      batchHistory[medKey] = [];
    }

    final list = batchHistory[medKey]!;
    final existingIdx = InventoryLogicCenter.findMatchingBatchIndex(
      list,
      batchNo: batchNo,
      exp: incomingPreview.exp,
      mrp: incomingPreview.mrp,
      purRate: incPur,
      exactEmptyBatchLot: true,
    );

    if (isDel) {
      D1SalesLedgerService.markPermanentlyDeleted(syncId, batchNo, medKey);
      if (existingIdx != -1) {
        list.removeAt(existingIdx);
        return true;
      }
      return false;
    }

    final incomingBatch = BatchInfo.fromMap(batchMap);
    incomingBatch.version = incomingVersion;
    incomingBatch.updatedAt = incomingTimestamp;

    if (existingIdx != -1) {
      final existing = list[existingIdx];

      // LWW Conflict Resolution Guard: Ignore older mutations
      if (incomingVersion < existing.version) {
        return false;
      }
      if (incomingVersion == existing.version && incomingTimestamp < existing.updatedAt) {
        return false;
      }

      existing.exp = incomingBatch.exp;
      existing.mrp = incomingBatch.mrp;
      existing.rate = incomingBatch.rate;
      existing.purRate = incomingBatch.purRate;
      existing.rateA = incomingBatch.rateA;
      existing.rateB = incomingBatch.rateB;
      existing.rateC = incomingBatch.rateC;
      existing.rateCFormula = incomingBatch.rateCFormula;
      existing.appliedRateType = incomingBatch.appliedRateType;
      existing.status = incomingBatch.status;
      final bool isSameOrUnscopedFy = !isCrossFy;
      final bool isNewerVersion = incomingVersion >= existing.version;
      existing.version = incomingVersion;
      existing.updatedAt = incomingTimestamp;
      if (isSameOrUnscopedFy) {
        if (incomingBatch.openingQty != 0.0 || isNewerVersion) {
          existing.openingQty = incomingBatch.openingQty;
        }
        existing.adjustmentQty = incomingBatch.adjustmentQty;
        existing.adjReason = incomingBatch.adjReason;
        existing.adjustmentHistory = List<BatchAdjustmentRecord>.from(incomingBatch.adjustmentHistory);
      }
      return true;
    } else {
      list.add(incomingBatch);
      return true;
    }
  }
}
