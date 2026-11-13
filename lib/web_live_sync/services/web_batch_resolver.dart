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
}
