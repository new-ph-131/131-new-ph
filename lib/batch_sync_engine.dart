// FILE: lib/batch_sync_engine.dart
// Revision: #PH-REV-810 (SUPPORT-ALL-4-BATCH-EXPIRY-CONFIGS)

import "models.dart";
import "pharoah_manager.dart";
import "expiry_master.dart";
import "inventory_logic_center.dart";
import "sync_core/modules/batch_sync_module.dart";

class BatchSyncEngine {
  static void registerBatchActivity({
    PharoahManager? ph,
    Map<String, List<BatchInfo>>? batchHistory,
    List<Medicine>? medicines,
    required String productKey,
    required String batchNo,
    required String exp,
    required String packing,
    required double mrp,
    required double rate,
    double rateA = 0.0,
    double rateB = 0.0,
    double rateC = 0.0,
    double rateCFormula = 0.0,
    String appliedRateType = "A",
    double qtyChange = 0.0,
    String status = "Active",
    String storeToken = "",
    bool isPurchaseRate = true,
  }) {
    if (ph != null && ph.activeCompany == null && batchHistory == null) return;
    final Map<String, List<BatchInfo>> targetHistory = batchHistory ?? ph!.batchHistory;
    final List<Medicine> targetMeds = medicines ?? ph?.medicines ?? const <Medicine>[];

    String resolvedKey = productKey;
    try {
      final med = targetMeds.firstWhere(
        (m) => m.id == productKey || m.identityKey == productKey || m.name.trim().toUpperCase() == productKey.trim().toUpperCase(),
      );
      resolvedKey = med.identityKey;
    } catch (_) {}

    if (!targetHistory.containsKey(resolvedKey)) {
      targetHistory[resolvedKey] = [];
    }

    List<BatchInfo> history = targetHistory[resolvedKey]!;
    int existingIdx = InventoryLogicCenter.findMatchingBatchIndex(
      history,
      batchNo: batchNo,
      exp: exp,
      mrp: mrp,
      purRate: isPurchaseRate ? rate : 0.0,
      exactEmptyBatchLot: isPurchaseRate,
    );

    double finalRateA = rateA == 0.0 ? mrp : rateA;
    double finalRateB = rateB == 0.0 ? (rateA == 0.0 ? mrp * 0.95 : rateA * 0.95) : rateB;
    double finalRateC = rateC == 0.0 ? (rateA == 0.0 ? mrp * 0.92 : rateA * 0.92) : rateC;

    if (existingIdx != -1) {
      final existing = history[existingIdx];
      if (existing.version <= 1) {
        if (exp.trim().isNotEmpty) existing.exp = exp;
        if (mrp > 0) existing.mrp = mrp;
        if (packing.trim().isNotEmpty) existing.packing = packing;
        if (isPurchaseRate && rate > 0) {
          existing.rate = rate;
          existing.purRate = rate;
        }
        if (finalRateA > 0) existing.rateA = finalRateA;
        if (finalRateB > 0) existing.rateB = finalRateB;
        if (finalRateC > 0) existing.rateC = finalRateC;
        existing.rateCFormula = rateCFormula;
        existing.appliedRateType = appliedRateType;
        existing.status = status;
      }
      if (qtyChange != 0.0) {
        existing.qty += qtyChange;
      }
    } else {
      history.add(BatchInfo(
        batch: batchNo.trim(),
        exp: exp,
        packing: packing,
        mrp: mrp,
        rate: isPurchaseRate ? rate : 0.0,
        qty: qtyChange,
        openingQty: qtyChange,
        isShell: false,
        purRate: isPurchaseRate ? rate : 0.0,
        rateA: finalRateA,
        rateB: finalRateB,
        rateC: finalRateC,
        rateCFormula: rateCFormula,
        appliedRateType: appliedRateType,
        status: status,
      ));
    }

    if (ph != null) {
      ph.save();
    }
    final String effectiveToken = storeToken.trim().isNotEmpty
        ? storeToken.trim()
        : (ph?.activeCompany?.id ?? "");
    if (effectiveToken.isNotEmpty) {
      final savedBatch = history[existingIdx != -1 ? existingIdx : history.length - 1];
      BatchSyncModule.onBatchSaved(
        batch: savedBatch,
        medIdentityKey: resolvedKey,
        storeToken: effectiveToken,
        isDelete: false,
      );
    }
  }

  static List<BatchInfo> getFilteredBatches({
    required PharoahManager ph,
    required String productKey,
    bool hideExpired = false,
  }) {
    if (ph.activeCompany == null) return [];
    if (!ph.batchHistory.containsKey(productKey)) return [];
    List<BatchInfo> allBatches = ph.batchHistory[productKey]!;
    if (hideExpired) {
      return allBatches.where((b) => ExpiryMaster.isSaleAllowed(b.exp)).toList();
    }
    return allBatches;
  }

  static BatchInfo? findBestAvailableBatch({
    required Map<String, List<BatchInfo>> batchHistory,
    required Medicine med,
  }) {
    final key = med.identityKey;
    final list = batchHistory[key] ?? batchHistory[med.id] ?? [];
    final available = list
        .where((b) => b.qty > 0 && b.status != "Blocked" && ExpiryMaster.isSaleAllowed(b.exp))
        .toList();
    if (available.isEmpty) return null;
    available.sort((a, b) {
      final bool aNonExp = ExpiryMaster.isNonExpiryValue(a.exp);
      final bool bNonExp = ExpiryMaster.isNonExpiryValue(b.exp);
      if (!aNonExp && bNonExp) return -1;
      if (aNonExp && !bNonExp) return 1;
      return ExpiryMaster.parseToEndOfMonth(a.exp).compareTo(ExpiryMaster.parseToEndOfMonth(b.exp));
    });
    return available.first;
  }
}
