// FILE: lib/sync_core/modules/batch_sync_module.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';
import '../d1_sales_ledger_service.dart';

/// 🛡️ BATCH MASTER SYNC MODULE (#PH-REV-756)
/// Handles autonomous batch mirroring, LWW monotonic versioning,
/// D1 Outbox integration, and Tombstone deletion shielding across App & Web.
class BatchSyncModule {
  static String cleanString(String input) {
    return input.replaceAll(RegExp(r"[^A-Z0-9]"), "").toUpperCase();
  }

  /// Unique composite syncId for each batch
  static String getBatchSyncId(String medIdentityKey, String batchNo) {
    final cMed = cleanString(medIdentityKey);
    final cBatch = cleanString(batchNo);
    return "BATCH_${cMed}_$cBatch";
  }

  /// 📤 1. D1 OUTBOX ENQUEUE: Push Batch Mutation directly to Cloudflare D1
  static void onBatchSaved({
    required BatchInfo batch,
    required String medIdentityKey,
    required String storeToken,
    bool isDelete = false,
  }) {
    if (storeToken.trim().isEmpty || medIdentityKey.trim().isEmpty || batch.batch.trim().isEmpty) return;

    final syncId = getBatchSyncId(medIdentityKey, batch.batch);

    SyncQueueManager.enqueueMutation(
      syncId: syncId,
      storeToken: storeToken.trim().toUpperCase(),
      docType: 'BATCH',
      currentVersion: 1,
      isDelete: isDelete,
      rawPayload: {
        'medKey': medIdentityKey.trim(),
        'batch': batch.toMap(),
        'isDeleted': isDelete ? 1 : 0,
      },
    );
  }

  /// 📥 2. MERGE INCOMING ENVELOPE FROM D1 BATCH
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
    if (batchNo.isEmpty) return false;

    final syncId = getBatchSyncId(medKey, batchNo);
    bool isDel = envelope.isDeleted == 1 || envelope.action == "DELETE";

    // Check Permanent Tombstones
    if (D1SalesLedgerService.isBillDeleted(syncId, batchNo, medKey) ||
        (tombstoneRegistry != null && tombstoneRegistry.containsKey(syncId))) {
      if (!isDel) {
        D1SalesLedgerService.unmarkPermanentlyDeleted(syncId, batchNo, medKey);
      } else {
        if (batchHistory.containsKey(medKey)) {
          final beforeLen = batchHistory[medKey]!.length;
          batchHistory[medKey]!.removeWhere((b) => b.batch.trim().toUpperCase() == batchNo.toUpperCase());
          return batchHistory[medKey]!.length != beforeLen;
        }
        return false;
      }
    }

    if (!batchHistory.containsKey(medKey)) {
      batchHistory[medKey] = [];
    }

    final list = batchHistory[medKey]!;
    final existingIdx = list.indexWhere((b) => b.batch.trim().toUpperCase() == batchNo.toUpperCase());

    if (isDel) {
      D1SalesLedgerService.markPermanentlyDeleted(syncId, batchNo, medKey);
      if (existingIdx != -1) {
        list.removeAt(existingIdx);
        return true;
      }
      return false;
    }

    final incomingBatch = BatchInfo.fromMap(batchMap);
    if (existingIdx != -1) {
      final existing = list[existingIdx];
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
      if (incomingBatch.openingQty != 0.0) {
        existing.openingQty = incomingBatch.openingQty;
      }
      if (incomingBatch.adjustmentQty != 0.0) {
        existing.adjustmentQty = incomingBatch.adjustmentQty;
        existing.adjReason = incomingBatch.adjReason;
      }
      return true;
    } else {
      list.add(incomingBatch);
      return true;
    }
  }
}
