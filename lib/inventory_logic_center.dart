// FILE: lib/inventory_logic_center.dart
// Revision: #PH-REV-810 (FULL-FOUR-CONFIG-BATCH-EXPIRY-AND-NONBATCH-LOT-ENGINE)

import 'models.dart';
import 'expiry_master.dart';

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

  /// Normalizes an expiry string for lot identity comparisons.
  /// Empty or non-expiry sentinels ("N/A", "NONE", "00/00", etc.) normalize to "".
  static String normalizeExpKey(String exp) {
    return ExpiryMaster.isNonExpiryValue(exp) ? "" : exp.trim().toUpperCase();
  }

  /// Builds a canonical lot key that distinguishes:
  /// - Named batches by uppercase batch number.
  /// - Non-batch lots (empty batchNo) by (normalizedExp, mrp, purRate) so unrelated
  ///   non-batch lots with different expiry, MRP, or purchase rate never merge.
  static String makeLotKey(
    String batchNo, {
    String exp = '',
    double mrp = 0.0,
    double purRate = 0.0,
  }) {
    final String cleanBatch = batchNo.trim().toUpperCase();
    if (cleanBatch.isNotEmpty) return cleanBatch;
    final String normExp = normalizeExpKey(exp);
    return "__NOBATCH__|$normExp|${mrp.toStringAsFixed(2)}|${purRate.toStringAsFixed(2)}";
  }

  /// Builds a deterministic cloud/D1 sync key for a batch or non-batch stock lot.
  static String makeSyncKey(
    String medIdentityKey,
    String batchNo, {
    String exp = '',
    double mrp = 0.0,
    double purRate = 0.0,
  }) {
    final String cleanMed = medIdentityKey.trim().toUpperCase();
    final String cleanBatch = batchNo.trim().toUpperCase();
    if (cleanBatch.isNotEmpty) {
      return "BATCH_${cleanMed}_$cleanBatch";
    }
    return "BATCH_${cleanMed}_${makeLotKey('', exp: exp, mrp: mrp, purRate: purRate)}";
  }

  /// Finds the matching BatchInfo index in [list] for both batch-managed and non-batch stock.
  /// - When [batchNo] is non-empty, matches by case-insensitive batch number.
  /// - When [batchNo] is empty:
  ///   - If [exactEmptyBatchLot] is true (e.g. Purchase inward or lot registration with purchase rate),
  ///     requires matching (normalizedExp, mrp, purRate) so distinct non-batch lots stay separate.
  ///   - If [exactEmptyBatchLot] is false (e.g. Sale, Return, or lookup), matches by (normalizedExp, mrp)
  ///     with fallback to normalizedExp / mrp / positive stock.
  static int findMatchingBatchIndex(
    List<BatchInfo> list, {
    required String batchNo,
    String exp = '',
    double mrp = 0.0,
    double purRate = 0.0,
    bool preferPositiveStock = false,
    bool exactEmptyBatchLot = false,
  }) {
    final String cleanBatch = batchNo.trim().toUpperCase();
    if (cleanBatch.isNotEmpty) {
      return list.indexWhere((b) => b.batch.trim().toUpperCase() == cleanBatch);
    }

    final String normExp = normalizeExpKey(exp);

    // 1. Exact match on (batch == "", normExp, mrp, purRate) when purRate > 0
    if (purRate > 0) {
      for (int i = 0; i < list.length; i++) {
        final b = list[i];
        if (b.batch.trim().isNotEmpty) continue;
        final double bPur = b.purRate > 0 ? b.purRate : b.rate;
        if (normalizeExpKey(b.exp) == normExp &&
            (b.mrp - mrp).abs() < 0.01 &&
            (bPur - purRate).abs() < 0.01) {
          return i;
        }
      }
    }

    if (exactEmptyBatchLot) {
      if (purRate <= 0) {
        for (int i = 0; i < list.length; i++) {
          final b = list[i];
          if (b.batch.trim().isNotEmpty) continue;
          final double bPur = b.purRate > 0 ? b.purRate : b.rate;
          if (normalizeExpKey(b.exp) == normExp &&
              (b.mrp - mrp).abs() < 0.01 &&
              bPur <= 0.01) {
            return i;
          }
        }
      }
      // Hydrate an unused empty shell lot if present
      for (int i = 0; i < list.length; i++) {
        final b = list[i];
        if (b.batch.trim().isEmpty &&
            b.isShell &&
            b.openingQty == 0.0 &&
            b.adjustmentQty == 0.0 &&
            b.qty == 0.0) {
          return i;
        }
      }
      return -1;
    }

    int pickBest(List<int> candidates) {
      if (candidates.isEmpty) return -1;
      if (preferPositiveStock) {
        for (final idx in candidates) {
          if (list[idx].qty > 0) return idx;
        }
      }
      return candidates.first;
    }

    // 2. Match on (batch == "", normExp, mrp)
    final List<int> expMrpMatches = [];
    for (int i = 0; i < list.length; i++) {
      final b = list[i];
      if (b.batch.trim().isNotEmpty) continue;
      if (normalizeExpKey(b.exp) == normExp &&
          (mrp <= 0 || (b.mrp - mrp).abs() < 0.01)) {
        expMrpMatches.add(i);
      }
    }
    if (expMrpMatches.isNotEmpty) return pickBest(expMrpMatches);

    // 3. If mrp was not specified (<= 0), match on normExp alone
    if (mrp <= 0) {
      final List<int> expMatches = [];
      for (int i = 0; i < list.length; i++) {
        final b = list[i];
        if (b.batch.trim().isNotEmpty) continue;
        if (normalizeExpKey(b.exp) == normExp) {
          expMatches.add(i);
        }
      }
      if (expMatches.isNotEmpty) return pickBest(expMatches);
    }

    // 4. If expiry was omitted on outward/return, match empty-batch lot by MRP
    if (normExp.isEmpty && mrp > 0) {
      final List<int> mrpMatches = [];
      for (int i = 0; i < list.length; i++) {
        final b = list[i];
        if (b.batch.trim().isNotEmpty) continue;
        if ((b.mrp - mrp).abs() < 0.01) {
          mrpMatches.add(i);
        }
      }
      if (mrpMatches.isNotEmpty) return pickBest(mrpMatches);
    }

    // 5. If both batch and expiry/mrp are unspecified, match any empty-batch lot
    if (normExp.isEmpty && mrp <= 0) {
      final List<int> anyNoBatch = [];
      for (int i = 0; i < list.length; i++) {
        if (list[i].batch.trim().isEmpty) {
          anyNoBatch.add(i);
        }
      }
      if (anyNoBatch.isNotEmpty) return pickBest(anyNoBatch);
    }

    // 6. Legacy OPENING fallback for outward sales when no empty-batch lot exists
    if (preferPositiveStock && normExp.isEmpty) {
      for (int i = 0; i < list.length; i++) {
        final b = list[i];
        if (b.batch.trim().toUpperCase() == "OPENING" &&
            (mrp <= 0 || b.mrp <= 0 || (b.mrp - mrp).abs() < 0.01)) {
          return i;
        }
      }
    }

    return -1;
  }

  /// 1. NET TAXABLE INVENTORY VALUE (Strictly Pre-GST for Accounting)
  static double getInventoryValuation({
    required List<Medicine> medicines,
    required Map<String, List<BatchInfo>> batchHistory,
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

  /// 2. THE GREAT INVENTORY REBUILD (CN/DN Impact Integrated with Loose Stock & All 4 Batch/Expiry Configs)
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
              final double abPur = ab.purRate > 0 ? ab.purRate : ab.rate;
              final idx = findMatchingBatchIndex(
                primaryList,
                batchNo: ab.batch,
                exp: ab.exp,
                mrp: ab.mrp,
                purRate: abPur,
                exactEmptyBatchLot: true,
              );
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

    // Build set of lots that have active inward purchases in this Financial Year
    final Set<String> purchasedBatchKeys = {};
    for (final pur in purchases.where((p) => p.isDeleted != 1)) {
      for (final item in pur.items) {
        final String lotKey = makeLotKey(
          item.batch,
          exp: item.exp,
          mrp: item.mrp,
          purRate: item.purchaseRate,
        );
        final Medicine? med = _findMedicine(medicines, item.medicineID, item.name);
        final String medKey = med != null ? med.identityKey : item.medicineID.trim();
        if (medKey.isNotEmpty) {
          purchasedBatchKeys.add("${medKey}_$lotKey");
        }
      }
    }

    // STEP A: RESET - Base Stock (Opening + Adjustments) par reset karein
    // 🛡️ OPENING STOCK HEAL: Sirf pre-openingQty legacy JSON records ke liye heal karein;
    // normal/deleted purchase batches par kabhi phantom openingQty generate na ho!
    batchHistory.forEach((key, list) {
      for (var b in list) {
        final double bPur = b.purRate > 0 ? b.purRate : b.rate;
        final String lotKey = makeLotKey(
          b.batch,
          exp: b.exp,
          mrp: b.mrp,
          purRate: bPur,
        );
        if (b.legacyOpeningHealPending &&
            b.qty > 0 &&
            b.openingQty == 0.0 &&
            b.adjustmentQty == 0.0 &&
            !purchasedBatchKeys.contains("${key}_$lotKey")) {
          b.openingQty = b.qty;
        }
        b.legacyOpeningHealPending = false;
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
      if (batchHistory.containsKey(med.identityKey)) {
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
      final Medicine? med = _findMedicine(medicines, medId, medName);
      if (med == null) return;
      final String key = med.identityKey;
      if (!batchHistory.containsKey(key)) batchHistory[key] = [];

      final List<BatchInfo> batches = batchHistory[key]!;
      final bool isPurItem = item is PurchaseItem;
      final String itemExp = (item.exp ?? "").toString().trim();
      final double mrp = (item.mrp as num?)?.toDouble() ?? med.mrp;
      final double lookupPurRate = isPurItem ? item.purchaseRate : 0.0;

      final int idx = findMatchingBatchIndex(
        batches,
        batchNo: cleanBatchNo,
        exp: itemExp,
        mrp: mrp,
        purRate: lookupPurRate,
        preferPositiveStock: !isAdd,
        exactEmptyBatchLot: isAdd && isPurItem,
      );

      if (idx != -1) {
        final target = batches[idx];
        target.qty += isAdd ? qty : -qty;
        target.isShell = false;
        if (isAdd && isPurItem) {
          if (itemExp.isNotEmpty) target.exp = itemExp;
          if (mrp > 0) target.mrp = mrp;
          if (item.purchaseRate > 0) {
            target.rate = item.purchaseRate;
            target.purRate = item.purchaseRate;
          }
          if (item.rateA > 0) target.rateA = item.rateA;
          if (item.rateB > 0) target.rateB = item.rateB;
          if (item.rateC > 0) target.rateC = item.rateC;
          if (item.rateCFormula > 0) target.rateCFormula = item.rateCFormula;
        }
      } else if (isAdd) {
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
            exp: itemExp,
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
