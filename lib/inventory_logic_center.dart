// FILE: lib/inventory_logic_center.dart (FULLY RESOLVED & COMPILE-SAFE)
import 'models.dart';

class InventoryLogicCenter {
  /// 1. DASHBOARD VALUATION ENGINE
  static double calculateTotalStockValue({
    required Map<String, List<BatchInfo>> batchHistory,
    required List<Medicine> medicines,
  }) {
    double grandTotal = 0;
    batchHistory.forEach((medKey, batches) {
      Medicine? parentMed;
      try {
        parentMed = medicines.firstWhere(
          (m) =>
              m.identityKey == medKey ||
              m.id == medKey ||
              m.name.trim().toUpperCase() == medKey.trim().toUpperCase(),
        );
      } catch (e) {
        parentMed = null;
      }

      double gstRate = parentMed?.gst ?? 12.0;
      for (var batch in batches) {
        if (batch.qty > 0) {
          double baseRate = batch.purRate > 0 ? batch.purRate : batch.rate;
          double taxableRate = baseRate / (1 + (gstRate / 100));
          grandTotal += (batch.qty * taxableRate);
        }
      }
    });
    return grandTotal;
  }

  /// 2. THE GREAT INVENTORY REBUILD (CN/DN Impact Integrated with Loose Stock & Opening Batch Guard)
  static void rebuildAllInventory({
    required List<Medicine> medicines,
    required Map<String, List<BatchInfo>> batchHistory,
    required List<Purchase> purchases,
    required List<Sale> sales,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
  }) {
    // STEP 0: Consolidate any legacy med.id / med.name keys into med.identityKey
    for (final med in medicines) {
      final String primaryKey = med.identityKey.trim();
      if (primaryKey.isEmpty) continue;
      final Set<String> altKeys = {
        if (med.id.trim().isNotEmpty && med.id.trim() != primaryKey) med.id.trim(),
        if (med.name.trim().isNotEmpty && med.name.trim() != primaryKey) med.name.trim(),
        if (med.name.trim().isNotEmpty && med.name.trim().toUpperCase() != primaryKey)
          med.name.trim().toUpperCase(),
      };
      for (final alt in altKeys) {
        if (batchHistory.containsKey(alt)) {
          final altList = batchHistory.remove(alt);
          if (altList != null && altList.isNotEmpty) {
            final primaryList = batchHistory.putIfAbsent(primaryKey, () => []);
            for (final ab in altList) {
              final cleanBNo = ab.batch.trim().toUpperCase();
              final idx = primaryList.indexWhere((pb) => pb.batch.trim().toUpperCase() == cleanBNo);
              if (idx == -1) {
                primaryList.add(ab);
              } else if (primaryList[idx].qty <= 0 && ab.qty > 0) {
                primaryList[idx] = ab;
              }
            }
          }
        }
      }
    }

    // Build set of batches that have active inward purchases in this Financial Year
    final Set<String> purchasedBatchKeys = {};
    for (final pur in purchases.where((p) => p.isDeleted != 1)) {
      for (final item in pur.items) {
        final String cleanBatch = item.batch.trim().toUpperCase();
        if (cleanBatch.isEmpty) continue;
        final Medicine? med = _findMedicine(medicines, item.medicineID, item.name);
        final String medKey = med != null ? med.identityKey : item.medicineID.trim();
        if (medKey.isNotEmpty) {
          purchasedBatchKeys.add("${medKey}_$cleanBatch");
        }
      }
    }

    // STEP A: RESET - Base Stock (Opening + Adjustments) par reset karein
    // 🛡️ OPENING STOCK HEAL: Agar kisi batch me qty > 0 hai par openingQty == 0 hai aur is saal
    // uska koi purchase bill nahi hai (jaise manual/carried-forward batch), to openingQty = qty preserve karein!
    batchHistory.forEach((key, list) {
      for (var b in list) {
        final String cleanBatch = b.batch.trim().toUpperCase();
        if (b.qty > 0 &&
            b.openingQty == 0.0 &&
            b.adjustmentQty == 0.0 &&
            !purchasedBatchKeys.contains("${key}_$cleanBatch")) {
          b.openingQty = b.qty;
        }
        b.qty = b.openingQty + b.adjustmentQty;
      }
    });

    // STEP B: PROCESS PURCHASES (Stock IN +)
    for (var pur in purchases.where((p) => p.isDeleted != 1)) {
      for (var item in pur.items) {
        _updateStock(
          batchHistory,
          medicines,
          item.medicineID,
          item.name,
          item.batch,
          (item.qty + item.freeQty),
          true,
          item,
        );
      }
    }

    // STEP C: PROCESS SALES (Stock OUT -)
    for (var sale in sales.where((s) => s.isDeleted != 1 && (s.status.isEmpty || s.status == "Active"))) {
      for (var item in sale.items) {
        _updateStock(
          batchHistory,
          medicines,
          item.medicineID,
          item.name,
          item.batch,
          (item.qty + item.freeQty),
          false,
          item,
        );
      }
    }

    // STEP D: SALE RETURNS / CREDIT NOTES (Stock IN + ONLY IF SELLABLE)
    for (var ret in saleReturns.where((r) => r.isDeleted != 1 && (r.status.isEmpty || r.status == "Active"))) {
      for (var item in ret.items) {
        if (item.isBreakage == false) {
          _updateStock(
            batchHistory,
            medicines,
            item.medicineID,
            item.name,
            item.batch,
            (item.qty + item.freeQty),
            true,
            item,
          );
        }
      }
    }

    // STEP E: PURCHASE RETURNS / DEBIT NOTES (Stock OUT -)
    for (var ret in purchaseReturns.where((r) => r.isDeleted != 1 && (r.status.isEmpty || r.status == "Active"))) {
      for (var item in ret.items) {
        _updateStock(
          batchHistory,
          medicines,
          item.medicineID,
          item.name,
          item.batch,
          (item.qty + item.freeQty),
          false,
          item,
        );
      }
    }

    // --- 🛡️ STEP F: FINAL SYNC WITH LOOSE STOCK GUARD ---
    for (var med in medicines) {
      if (batchHistory.containsKey(med.identityKey) && batchHistory[med.identityKey]!.isNotEmpty) {
        double total = 0;
        for (var b in batchHistory[med.identityKey]!) {
          total += b.qty;
        }
        med.stock = total;
      }
    }
  }

  static Medicine? _findMedicine(List<Medicine> medicines, String medId, String medName) {
    final String cleanId = medId.trim();
    final String cleanName = medName.trim().toUpperCase();
    for (final m in medicines) {
      if (cleanId.isNotEmpty && (m.id.trim() == cleanId || m.identityKey.trim() == cleanId)) {
        return m;
      }
    }
    if (cleanName.isNotEmpty) {
      for (final m in medicines) {
        if (m.name.trim().toUpperCase() == cleanName) {
          return m;
        }
      }
    }
    return null;
  }

  static void _updateStock(
    Map<String, List<BatchInfo>> batchHistory,
    List<Medicine> medicines,
    String medId,
    String medName,
    String batchNo,
    double qty,
    bool isAdd,
    dynamic item,
  ) {
    try {
      final String cleanBatchNo = batchNo.trim();
      if (cleanBatchNo.isEmpty) return;

      final Medicine? med = _findMedicine(medicines, medId, medName);
      if (med == null) return;

      final String key = med.identityKey;
      if (!batchHistory.containsKey(key)) batchHistory[key] = [];
      var batches = batchHistory[key]!;
      int idx = batches.indexWhere(
        (b) => b.batch.trim().toUpperCase() == cleanBatchNo.toUpperCase(),
      );

      if (idx != -1) {
        batches[idx].qty += isAdd ? qty : -qty;
      } else if (isAdd) {
        final bool isPurItem = item is PurchaseItem;
        final double mrp = (item.mrp as num?)?.toDouble() ?? med.mrp;
        final double purRate = isPurItem
            ? item.purchaseRate
            : ((item.rate as num?)?.toDouble() ?? med.purRate);
        final double rateA = isPurItem && item.rateA > 0
            ? item.rateA
            : (med.rateA > 0 ? med.rateA : mrp);
        final double rateB = isPurItem && item.rateB > 0
            ? item.rateB
            : (med.rateB > 0 ? med.rateB : rateA * 0.95);
        final double rateC = isPurItem && item.rateC > 0
            ? item.rateC
            : (med.rateC > 0 ? med.rateC : rateA * 0.92);

        batches.add(
          BatchInfo(
            batch: cleanBatchNo,
            exp: (item.exp ?? "").toString(),
            packing: (item.packing ?? med.packing).toString(),
            mrp: mrp,
            rate: purRate,
            purRate: purRate,
            rateA: rateA,
            rateB: rateB,
            rateC: rateC,
            rateCFormula: isPurItem ? item.rateCFormula : 0.0,
            appliedRateType: isPurItem ? item.appliedRateType : "A",
            qty: qty,
            isShell: false,
          ),
        );
      }
    } catch (e) {}
  }
}
