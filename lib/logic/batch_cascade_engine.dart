// FILE: lib/logic/batch_cascade_engine.dart
import 'package:flutter/foundation.dart';
import '../models.dart';
import '../app_date_logic.dart';
import '../inventory_logic_center.dart';
import '../sync_core/modules/batch_sync_module.dart';
import '../web_live_sync/sync_protocol/tombstone_engine.dart';
import 'product_integrity_service.dart';

class BatchUsageAuditRecord {
  final String documentType;
  final String billNo;
  final DateTime date;
  final String partyName;
  final double qty;
  final double rate;

  BatchUsageAuditRecord({
    required this.documentType,
    required this.billNo,
    required this.date,
    required this.partyName,
    required this.qty,
    required this.rate,
  });
}

class BatchCascadeEngine {
  static String clean(String s) => ProductIntegrityService.cleanString(s);

  static bool _matchesMedicine(String itMedId, String itName, Medicine med) {
    final cleanMedId = med.id.trim();
    final cleanSysId = med.systemId.trim().toUpperCase();
    final cleanMedName = clean(med.name);

    if (cleanMedId.isNotEmpty && itMedId.trim() == cleanMedId) return true;
    if (cleanSysId.isNotEmpty && itMedId.trim().toUpperCase() == cleanSysId) return true;
    final cName = clean(itName);
    if (cName.isNotEmpty && cName == cleanMedName) return true;
    return false;
  }

  /// 🔍 1. CHECK USAGE IN ACTIVE FINANCIAL YEAR
  static List<BatchUsageAuditRecord> checkActiveFYUsage({
    required Medicine medicine,
    required String batchNo,
    required String activeFY,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleChallan> saleChallans,
    required List<PurchaseChallan> purchaseChallans,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
  }) {
    final List<BatchUsageAuditRecord> records = [];
    final cleanBatch = batchNo.trim().toUpperCase();
    final currentFY = activeFY.isNotEmpty ? activeFY : AppDateLogic.getCurrentFYString();

    // A. Sales
    for (var s in sales.where((s) => s.status == "Active")) {
      if (!AppDateLogic.isValidInFY(s.date, currentFY)) continue;
      for (var it in s.items) {
        if (_matchesMedicine(it.medicineID, it.name, medicine) &&
            it.batch.trim().toUpperCase() == cleanBatch) {
          records.add(BatchUsageAuditRecord(
            documentType: "Sale Invoice",
            billNo: s.billNo,
            date: s.date,
            partyName: s.partyName,
            qty: it.qty + it.freeQty,
            rate: it.rate,
          ));
        }
      }
    }

    // B. Purchases
    for (var p in purchases.where((p) => p.isDeleted == 0)) {
      if (!AppDateLogic.isValidInFY(p.date, currentFY)) continue;
      for (var it in p.items) {
        if (_matchesMedicine(it.medicineID, it.name, medicine) &&
            it.batch.trim().toUpperCase() == cleanBatch) {
          records.add(BatchUsageAuditRecord(
            documentType: "Purchase Bill",
            billNo: p.billNo.isNotEmpty ? p.billNo : p.internalNo,
            date: p.date,
            partyName: p.distributorName,
            qty: it.qty + it.freeQty,
            rate: it.purchaseRate,
          ));
        }
      }
    }

    // C. Sale Challans
    for (var sc in saleChallans.where((c) => c.status == "Active")) {
      if (!AppDateLogic.isValidInFY(sc.date, currentFY)) continue;
      for (var it in sc.items) {
        if (_matchesMedicine(it.medicineID, it.name, medicine) &&
            it.batch.trim().toUpperCase() == cleanBatch) {
          records.add(BatchUsageAuditRecord(
            documentType: "Sale Challan",
            billNo: sc.billNo,
            date: sc.date,
            partyName: sc.partyName,
            qty: it.qty + it.freeQty,
            rate: it.rate,
          ));
        }
      }
    }

    // D. Purchase Challans
    for (var pc in purchaseChallans.where((c) => c.status == "Active")) {
      if (!AppDateLogic.isValidInFY(pc.date, currentFY)) continue;
      for (var it in pc.items) {
        if (_matchesMedicine(it.medicineID, it.name, medicine) &&
            it.batch.trim().toUpperCase() == cleanBatch) {
          records.add(BatchUsageAuditRecord(
            documentType: "Purchase Challan",
            billNo: pc.billNo.isNotEmpty ? pc.billNo : pc.internalNo,
            date: pc.date,
            partyName: pc.distributorName,
            qty: it.qty + it.freeQty,
            rate: it.purchaseRate,
          ));
        }
      }
    }

    // E. Sale Returns (Credit Notes)
    for (var sr in saleReturns.where((r) => r.status == "Active")) {
      if (!AppDateLogic.isValidInFY(sr.date, currentFY)) continue;
      for (var it in sr.items) {
        if (_matchesMedicine(it.medicineID, it.name, medicine) &&
            it.batch.trim().toUpperCase() == cleanBatch) {
          records.add(BatchUsageAuditRecord(
            documentType: "Credit Note",
            billNo: sr.billNo,
            date: sr.date,
            partyName: sr.partyName,
            qty: it.qty + it.freeQty,
            rate: it.rate,
          ));
        }
      }
    }

    // F. Purchase Returns (Debit Notes)
    for (var pr in purchaseReturns.where((r) => r.status == "Active")) {
      if (!AppDateLogic.isValidInFY(pr.date, currentFY)) continue;
      for (var it in pr.items) {
        if (_matchesMedicine(it.medicineID, it.name, medicine) &&
            it.batch.trim().toUpperCase() == cleanBatch) {
          records.add(BatchUsageAuditRecord(
            documentType: "Debit Note",
            billNo: pr.billNo,
            date: pr.date,
            partyName: pr.distributorName,
            qty: it.qty + it.freeQty,
            rate: it.purchaseRate,
          ));
        }
      }
    }

    return records;
  }

  /// 🔄 2. FULL CASCADE BATCH MODIFICATION (NAME, EXPIRY, RATES)
  static int cascadeBatchUpdate({
    required Medicine medicine,
    required String oldBatchNo,
    required String newBatchNo,
    required String newExp,
    required double newMrp,
    required double newPurRate,
    double newRateA = 0.0,
    double newRateB = 0.0,
    double newRateC = 0.0,
    required Map<String, List<BatchInfo>> batchHistory,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleChallan> saleChallans,
    required List<PurchaseChallan> purchaseChallans,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
    required List<Medicine> medicines,
    String storeToken = "",
    String companyId = "",
  }) {
    int mutatedCount = 0;
    final cleanOld = oldBatchNo.trim().toUpperCase();
    final cleanNew = newBatchNo.trim().toUpperCase();
    final medKey = medicine.identityKey;

    // A. Update in BatchHistory
    if (batchHistory.containsKey(medKey)) {
      final list = batchHistory[medKey]!;
      final idx = list.indexWhere((b) => b.batch.trim().toUpperCase() == cleanOld);
      if (idx != -1) {
        final b = list[idx];
        b.batch = cleanNew;
        b.exp = newExp.trim();
        b.mrp = newMrp;
        b.purRate = newPurRate;
        b.rate = newPurRate;
        b.rateA = newRateA > 0 ? newRateA : newMrp;
        b.rateB = newRateB > 0 ? newRateB : (b.rateA * 0.95);
        b.rateC = newRateC > 0 ? newRateC : (b.rateA * 0.92);
        b.version += 1;
        b.updatedAt = DateTime.now().millisecondsSinceEpoch;

        // If batch was renamed, tombstone old batch sync ID so it doesn't resurrect
        if (cleanOld != cleanNew) {
          if (companyId.isNotEmpty) {
            final oldSyncId = BatchSyncModule.getBatchSyncId(medKey, cleanOld);
            TombstoneEngine.recordBatchTombstones(companyId, [oldSyncId]);
          }
          if (storeToken.isNotEmpty) {
            final oldBatchShell = BatchInfo(
              batch: cleanOld,
              exp: b.exp,
              packing: b.packing,
              mrp: b.mrp,
              rate: b.rate,
            );
            BatchSyncModule.onBatchSaved(
              batch: oldBatchShell,
              medIdentityKey: medKey,
              storeToken: storeToken,
              isDelete: true,
            );
          }
        }

        // Enqueue new batch mutation to D1 Outbox
        if (storeToken.isNotEmpty) {
          BatchSyncModule.onBatchSaved(
            batch: b,
            medIdentityKey: medKey,
            storeToken: storeToken,
            isDelete: false,
          );
        }
      }
    }

    // B. Cascade across Sales
    for (var s in sales) {
      bool billMutated = false;
      for (var it in s.items) {
        if (_matchesMedicine(it.medicineID, it.name, medicine) &&
            it.batch.trim().toUpperCase() == cleanOld) {
          it.batch = cleanNew;
          it.exp = newExp.trim();
          it.mrp = newMrp;
          billMutated = true;
          mutatedCount++;
        }
      }
      if (billMutated) {
        s.updatedAt = DateTime.now().millisecondsSinceEpoch;
      }
    }

    // C. Cascade across Purchases
    for (var p in purchases) {
      bool billMutated = false;
      for (var it in p.items) {
        if (_matchesMedicine(it.medicineID, it.name, medicine) &&
            it.batch.trim().toUpperCase() == cleanOld) {
          it.batch = cleanNew;
          it.exp = newExp.trim();
          it.mrp = newMrp;
          it.purchaseRate = newPurRate;
          billMutated = true;
          mutatedCount++;
        }
      }
      if (billMutated) {
        p.updatedAt = DateTime.now().millisecondsSinceEpoch;
      }
    }

    // D. Cascade across Sale Challans
    for (var sc in saleChallans) {
      bool billMutated = false;
      for (var it in sc.items) {
        if (_matchesMedicine(it.medicineID, it.name, medicine) &&
            it.batch.trim().toUpperCase() == cleanOld) {
          it.batch = cleanNew;
          it.exp = newExp.trim();
          it.mrp = newMrp;
          billMutated = true;
          mutatedCount++;
        }
      }
      if (billMutated) {
        sc.updatedAt = DateTime.now().millisecondsSinceEpoch;
      }
    }

    // E. Cascade across Purchase Challans
    for (var pc in purchaseChallans) {
      bool billMutated = false;
      for (var it in pc.items) {
        if (_matchesMedicine(it.medicineID, it.name, medicine) &&
            it.batch.trim().toUpperCase() == cleanOld) {
          it.batch = cleanNew;
          it.exp = newExp.trim();
          it.mrp = newMrp;
          it.purchaseRate = newPurRate;
          billMutated = true;
          mutatedCount++;
        }
      }
      if (billMutated) {
        pc.updatedAt = DateTime.now().millisecondsSinceEpoch;
      }
    }

    // F. Cascade across Returns
    for (var sr in saleReturns) {
      for (var it in sr.items) {
        if (_matchesMedicine(it.medicineID, it.name, medicine) &&
            it.batch.trim().toUpperCase() == cleanOld) {
          it.batch = cleanNew;
          it.exp = newExp.trim();
          it.mrp = newMrp;
          mutatedCount++;
        }
      }
    }

    for (var pr in purchaseReturns) {
      for (var it in pr.items) {
        if (_matchesMedicine(it.medicineID, it.name, medicine) &&
            it.batch.trim().toUpperCase() == cleanOld) {
          it.batch = cleanNew;
          it.exp = newExp.trim();
          it.mrp = newMrp;
          it.purchaseRate = newPurRate;
          mutatedCount++;
        }
      }
    }

    // Rebuild inventory with new batch keys
    InventoryLogicCenter.rebuildAllInventory(
      medicines: medicines,
      batchHistory: batchHistory,
      purchases: purchases,
      sales: sales,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
    );

    return mutatedCount;
  }

  /// 🛡️ 3. SAFE BATCH DELETION WITH FINANCIAL YEAR INTEGRITY CHECK
  static ({bool success, String message, List<BatchUsageAuditRecord> lockingRecords}) deleteBatchSafe({
    required Medicine medicine,
    required String batchNo,
    required String activeFY,
    required Map<String, List<BatchInfo>> batchHistory,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleChallan> saleChallans,
    required List<PurchaseChallan> purchaseChallans,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
    required List<Medicine> medicines,
    String storeToken = "",
    String companyId = "",
  }) {
    final cleanBatch = batchNo.trim().toUpperCase();
    final medKey = medicine.identityKey;

    // Check active FY records
    final records = checkActiveFYUsage(
      medicine: medicine,
      batchNo: cleanBatch,
      activeFY: activeFY,
      sales: sales,
      purchases: purchases,
      saleChallans: saleChallans,
      purchaseChallans: purchaseChallans,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
    );

    if (records.isNotEmpty) {
      return (
        success: false,
        message: "Cannot delete batch '$cleanBatch': Found ${records.length} active transaction(s) in Financial Year $activeFY.",
        lockingRecords: records,
      );
    }

    // Zero active FY records: proceed with deletion!
    BatchInfo? removedBatch;
    if (batchHistory.containsKey(medKey)) {
      final list = batchHistory[medKey]!;
      final idx = list.indexWhere((b) => b.batch.trim().toUpperCase() == cleanBatch);
      if (idx != -1) {
        removedBatch = list.removeAt(idx);
      }
    }

    final syncId = BatchSyncModule.getBatchSyncId(medKey, cleanBatch);

    // Record tombstone
    if (companyId.isNotEmpty) {
      TombstoneEngine.recordBatchTombstones(companyId, [syncId, cleanBatch]);
    }

    // Enqueue deletion to Cloudflare D1
    if (storeToken.isNotEmpty && removedBatch != null) {
      BatchSyncModule.onBatchSaved(
        batch: removedBatch,
        medIdentityKey: medKey,
        storeToken: storeToken,
        isDelete: true,
      );
    }

    // Rebuild inventory
    InventoryLogicCenter.rebuildAllInventory(
      medicines: medicines,
      batchHistory: batchHistory,
      purchases: purchases,
      sales: sales,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
    );

    return (
      success: true,
      message: "Batch '$cleanBatch' deleted successfully and shielded with tombstone.",
      lockingRecords: <BatchUsageAuditRecord>[],
    );
  }
}
