// FILE: lib/web_live_sync/services/web_batch_resolver.dart
// Revision: #PH-REV-810 (SUPPORT-NONBATCH-AND-OPTIONAL-EXPIRY-WITHOUT-DUPLICATE-OPENING)

import '../../models.dart';
import '../../expiry_master.dart';
import '../../inventory_logic_center.dart';

class WebBatchResolver {
  /// Resolves all distinct stock options (named batches AND non-batch lots) for a given Medicine
  /// without discarding empty-batch lots or generating duplicate synthetic OPENING records.
  static List<BatchInfo> resolveBatchesForMedicine(
    Medicine med,
    Map<String, List<BatchInfo>> batchHistory,
  ) {
    final Set<String> candidateKeys = {
      if (med.identityKey.trim().isNotEmpty) med.identityKey.trim(),
      if (med.systemId.trim().isNotEmpty) med.systemId.trim(),
      if (med.id.trim().isNotEmpty) med.id.trim(),
      if (med.name.trim().isNotEmpty) med.name.trim(),
      if (med.name.trim().isNotEmpty) med.name.trim().toUpperCase(),
    };

    final Map<String, BatchInfo> deduplicatedBatches = {};
    bool hasExplicitEntryInHistory = false;

    for (final key in candidateKeys) {
      if (batchHistory.containsKey(key)) {
        hasExplicitEntryInHistory = true;
        final list = batchHistory[key]!;
        for (final b in list) {
          final double bPur = b.purRate > 0 ? b.purRate : b.rate;
          final String lotKey = InventoryLogicCenter.makeLotKey(
            b.batch,
            exp: b.exp,
            mrp: b.mrp,
            purRate: bPur,
          );
          if (!deduplicatedBatches.containsKey(lotKey)) {
            deduplicatedBatches[lotKey] = b;
          } else {
            final existing = deduplicatedBatches[lotKey]!;
            if (existing.qty <= 0 && b.qty > 0) {
              deduplicatedBatches[lotKey] = b;
            }
          }
        }
      }
    }

    final List<BatchInfo> result = deduplicatedBatches.values.toList();

    // Only synthesize a fallback OPENING batch if the product has NO batchHistory entry at all
    // and carries positive loose stock on the Medicine master. Never create duplicate OPENING lots!
    if (result.isEmpty && !hasExplicitEntryInHistory && med.stock > 0) {
      result.add(
        BatchInfo(
          batch: "OPENING",
          exp: "N/A",
          packing: med.packing,
          mrp: med.mrp,
          rate: med.purRate,
          purRate: med.purRate,
          rateA: med.rateA > 0 ? med.rateA : med.mrp,
          rateB: med.rateB > 0 ? med.rateB : (med.rateA > 0 ? med.rateA * 0.95 : med.mrp * 0.95),
          rateC: med.rateC > 0 ? med.rateC : (med.rateA > 0 ? med.rateA * 0.92 : med.mrp * 0.92),
          openingQty: med.stock,
          qty: med.stock,
          isShell: false,
          status: "Active",
        ),
      );
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
              final idx = InventoryLogicCenter.findMatchingBatchIndex(
                primaryList,
                batchNo: ab.batch,
                exp: ab.exp,
                mrp: ab.mrp,
                purRate: ab.purRate > 0 ? ab.purRate : ab.rate,
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

    final Set<String> purchasedBatchKeys = {};
    for (final pur in purchases) {
      if (pur.isDeleted == 1) continue;
      for (final item in pur.items) {
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
        final lotKey = InventoryLogicCenter.makeLotKey(
          item.batch,
          exp: item.exp,
          mrp: item.mrp,
          purRate: item.purchaseRate,
        );
        purchasedBatchKeys.add("${medKey}_$lotKey");
      }
    }

    batchHistory.forEach((medKey, list) {
      for (final b in list) {
        final lotKey = InventoryLogicCenter.makeLotKey(
          b.batch,
          exp: b.exp,
          mrp: b.mrp,
          purRate: b.purRate > 0 ? b.purRate : b.rate,
        );
        if (b.legacyOpeningHealPending &&
            b.qty > 0 &&
            b.openingQty == 0.0 &&
            b.adjustmentQty == 0.0 &&
            !purchasedBatchKeys.contains("${medKey}_$lotKey")) {
          b.openingQty = b.qty;
        }
        b.legacyOpeningHealPending = false;
      }
    });
  }
}
