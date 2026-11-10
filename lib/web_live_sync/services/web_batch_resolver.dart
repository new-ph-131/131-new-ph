// FILE: lib/web_live_sync/services/web_batch_resolver.dart
// Revision: #PH-REV-799 (ENTERPRISE-MULTI-KEY-BATCH-RESOLVER-AND-NON-EXPIRY-SUPPORT)

import '../../models.dart';

class WebBatchResolver {
  /// Resolves all batches for [med] across [batchHistory] even if batches were historically
  /// keyed under `med.identityKey`, `med.id`, `med.systemId`, or `med.name.trim().toUpperCase()`.
  /// Also consolidates them under `med.identityKey` in-place so future lookups are O(1).
  static List<BatchInfo> resolveBatchesForMedicine(
    Medicine med,
    Map<String, List<BatchInfo>> batchHistory,
  ) {
    final String primaryKey = med.identityKey.trim();
    final Set<String> candidateKeys = {
      if (primaryKey.isNotEmpty) primaryKey,
      if (med.id.trim().isNotEmpty) med.id.trim(),
      if (med.systemId.trim().isNotEmpty) med.systemId.trim(),
      if (med.name.trim().isNotEmpty) med.name.trim(),
      if (med.name.trim().isNotEmpty) med.name.trim().toUpperCase(),
    };

    final Map<String, BatchInfo> mergedByBatchNo = {};

    for (final key in candidateKeys) {
      final list = batchHistory[key];
      if (list == null || list.isEmpty) continue;
      for (final b in list) {
        final cleanBatchNo = b.batch.trim().toUpperCase();
        if (cleanBatchNo.isEmpty) continue;
        if (!mergedByBatchNo.containsKey(cleanBatchNo)) {
          mergedByBatchNo[cleanBatchNo] = b;
        } else {
          final existing = mergedByBatchNo[cleanBatchNo]!;
          if (b.version > existing.version ||
              (b.version == existing.version && b.updatedAt > existing.updatedAt) ||
              (existing.qty <= 0 && b.qty > 0)) {
            mergedByBatchNo[cleanBatchNo] = b;
          }
        }
      }
    }

    final List<BatchInfo> result = mergedByBatchNo.values.toList();

    // If medicine has positive stock (e.g. Opening / Loose Stock) but no batch record exists at all,
    // synthesize a default non-expiry OPENING batch so the user can always bill it in POS / Challan / Return!
    if (result.isEmpty && med.stock > 0) {
      final defaultBatch = BatchInfo(
        batch: "OPENING",
        exp: "N/A",
        packing: med.packing,
        mrp: med.mrp,
        rate: med.purRate > 0 ? med.purRate : med.rateA,
        purRate: med.purRate > 0 ? med.purRate : med.rateA,
        rateA: med.rateA > 0 ? med.rateA : med.mrp,
        rateB: med.rateB > 0 ? med.rateB : (med.rateA > 0 ? med.rateA * 0.95 : med.mrp * 0.95),
        rateC: med.rateC > 0 ? med.rateC : (med.rateA > 0 ? med.rateA * 0.92 : med.mrp * 0.92),
        qty: med.stock,
        openingQty: med.stock,
        isShell: false,
        status: "Active",
      );
      result.add(defaultBatch);
    }

    if (primaryKey.isNotEmpty && result.isNotEmpty) {
      batchHistory[primaryKey] = result;
    }

    return result;
  }

  /// Normalizes all keys in [batchHistory] to match `med.identityKey` for all known [medicines],
  /// and preserves `openingQty` when a batch has `qty > 0` and `openingQty == 0` with no inward purchases.
  static void normalizeAndHealBatchHistory({
    required List<Medicine> medicines,
    required Map<String, List<BatchInfo>> batchHistory,
    required List<Purchase> purchases,
  }) {
    // 1. Consolidate legacy med.id / med.name keys into med.identityKey
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

    // 2. Build set of (medIdentityKey, batchNo) that have active Purchases in this FY
    final Set<String> purchasedBatchKeys = {};
    for (final pur in purchases) {
      if (pur.isDeleted == 1) continue;
      for (final item in pur.items) {
        final cleanBatch = item.batch.trim().toUpperCase();
        if (cleanBatch.isEmpty) continue;
        String medKey = item.medicineID.trim();
        try {
          final m = medicines.firstWhere(
            (m) =>
                m.id == item.medicineID ||
                m.identityKey == item.medicineID ||
                m.name.trim().toUpperCase() == item.name.trim().toUpperCase(),
          );
          medKey = m.identityKey;
        } catch (_) {}
        purchasedBatchKeys.add("${medKey}_$cleanBatch");
      }
    }

    // 3. Heal batches that have qty > 0, openingQty == 0, adjustmentQty == 0, and NO purchase in this FY
    // (e.g. Opening Stock / Carried Forward / Manual Batches where only qty was stored)
    batchHistory.forEach((medKey, list) {
      for (final b in list) {
        final cleanBatch = b.batch.trim().toUpperCase();
        if (b.qty > 0 &&
            b.openingQty == 0.0 &&
            b.adjustmentQty == 0.0 &&
            !purchasedBatchKeys.contains("${medKey}_$cleanBatch")) {
          b.openingQty = b.qty;
        }
      }
    });
  }
}
