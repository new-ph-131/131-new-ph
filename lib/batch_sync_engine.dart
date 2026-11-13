// FILE: lib/batch_sync_engine.dart
// Revision: #PH-REV-810 (SUPPORT-ALL-4-BATCH-EXPIRY-CONFIGS)

import 'models.dart';
import 'expiry_master.dart';
import 'inventory_logic_center.dart';
import 'sync_core/modules/batch_sync_module.dart';

class BatchSyncEngine {
  /// 1. REGISTER OR UPDATE BATCH FROM BILLING (Purchase, Sale, Challans, Returns)
  static void registerBatchActivity({
    required Map<String, List<BatchInfo>> batchHistory,
    required List<Medicine> medicines,
    required String productKey,
    required String batchNo,
    required String exp,
    required String packing,
    required double mrp,
    required double rate, // Purchase Rate (or Selling Rate when isPurchaseRate == false)
    double rateA = 0.0,
    double rateB = 0.0,
    double rateC = 0.0,
    double rateCFormula = 0.0,
    String appliedRateType = "A",
    String storeToken = "",
    bool isPurchaseRate = true,
  }) {
    String resolvedKey = productKey;
    try {
      final med = medicines.firstWhere(
        (m) => m.id == productKey || m.identityKey == productKey || m.name.trim().toUpperCase() == productKey.trim().toUpperCase(),
      );
      resolvedKey = med.identityKey;
    } catch (_) {}

    if (!batchHistory.containsKey(resolvedKey)) {
      batchHistory[resolvedKey] = [];
    }

    List<BatchInfo> history = batchHistory[resolvedKey]!;
    String cleanBatch = batchNo.trim().toUpperCase();

    int idx = InventoryLogicCenter.findMatchingBatchIndex(
      history,
      batchNo: cleanBatch,
      exp: exp,
      mrp: mrp,
      purRate: isPurchaseRate ? rate : 0.0,
      preferPositiveStock: !isPurchaseRate,
      exactEmptyBatchLot: isPurchaseRate,
    );

    double finalRateA = rateA > 0 ? rateA : (mrp > 0 ? mrp : rate);
    double finalRateB = rateB > 0 ? rateB : (finalRateA * 0.95);
    double finalRateC = rateC > 0 ? rateC : (finalRateA * 0.92);
    if (rateCFormula > 0 && rate > 0) {
      finalRateC = rate + (rate * (rateCFormula / 100));
    }

    final int nowTs = DateTime.now().millisecondsSinceEpoch;
    late BatchInfo syncedBatch;

    if (idx != -1) {
      var target = history[idx];
      if (exp.trim().isNotEmpty || isPurchaseRate) {
        if (exp.trim().isNotEmpty) target.exp = exp.trim();
      }
      if (packing.trim().isNotEmpty) target.packing = packing;
      if (mrp > 0) target.mrp = mrp;
      if (isPurchaseRate && rate > 0) {
        target.rate = rate;
        target.purRate = rate;
      } else if (target.purRate <= 0 && target.rate <= 0 && rate > 0) {
        target.rate = rate;
        target.purRate = rate;
      }
      if (rateA > 0) target.rateA = finalRateA;
      if (rateB > 0) target.rateB = finalRateB;
      if (rateC > 0 || rateCFormula > 0) target.rateC = finalRateC;
      if (rateCFormula > 0) target.rateCFormula = rateCFormula;
      target.appliedRateType = appliedRateType;
      target.isShell = false;
      target.version += 1;
      target.updatedAt = nowTs;
      syncedBatch = target;
    } else {
      syncedBatch = BatchInfo(
        batch: cleanBatch,
        exp: exp.trim(),
        packing: packing,
        mrp: mrp,
        rate: rate,
        purRate: rate,
        rateA: finalRateA,
        rateB: finalRateB,
        rateC: finalRateC,
        rateCFormula: rateCFormula,
        appliedRateType: appliedRateType,
        qty: 0.0,
        isShell: false,
        status: "Active",
        updatedAt: nowTs,
        version: 1,
      );
      history.add(syncedBatch);
    }

    if (storeToken.trim().isNotEmpty) {
      BatchSyncModule.onBatchSaved(
        batch: syncedBatch,
        medIdentityKey: resolvedKey,
        storeToken: storeToken,
        isDelete: false,
      );
    }

    _syncLatestToMedicineMaster(
      medicines,
      resolvedKey,
      mrp,
      isPurchaseRate ? rate : syncedBatch.purRate,
      finalRateA,
      finalRateB,
      finalRateC,
      storeToken: storeToken,
    );
  }

  static void _syncLatestToMedicineMaster(
    List<Medicine> medicines,
    String medId,
    double mrp,
    double purRate,
    double rA,
    double rB,
    double rC, {
    String storeToken = "",
  }) {
    try {
      var med = medicines.firstWhere((m) => m.identityKey == medId || m.id == medId);
      if (mrp > 0) med.mrp = mrp;
      if (purRate > 0) med.purRate = purRate;
      if (rA > 0) med.rateA = rA;
      if (rB > 0) med.rateB = rB;
      if (rC > 0) med.rateC = rC;
      med.version += 1;
      med.updatedAt = DateTime.now().millisecondsSinceEpoch;
    } catch (e) {}
  }

  /// 2. AUTO-PICK BEST BATCH FOR BILLING (Supports both dated and non-expiry / non-batch lots)
  static BatchInfo? findBestAvailableBatch(
    Map<String, List<BatchInfo>> batchHistory,
    String productKey,
  ) {
    if (!batchHistory.containsKey(productKey)) return null;
    List<BatchInfo> list = batchHistory[productKey]!;
    if (list.isEmpty) return null;

    List<BatchInfo> validBatches = list.where((b) {
      if (b.qty <= 0 || b.status == "Blocked") return false;
      return ExpiryMaster.isSaleAllowed(b.exp);
    }).toList();

    if (validBatches.isEmpty) return null;

    validBatches.sort((a, b) {
      final bool aNonExp = ExpiryMaster.isNonExpiryValue(a.exp);
      final bool bNonExp = ExpiryMaster.isNonExpiryValue(b.exp);
      if (aNonExp && bNonExp) return 0;
      if (aNonExp) return 1;
      if (bNonExp) return -1;
      try {
        var pA = a.exp.split('/');
        var pB = b.exp.split('/');
        DateTime dA = DateTime(2000 + int.parse(pA[1]), int.parse(pA[0]));
        DateTime dB = DateTime(2000 + int.parse(pB[1]), int.parse(pB[0]));
        return dA.compareTo(dB);
      } catch (e) {
        return 0;
      }
    });

    return validBatches.first;
  }
}
