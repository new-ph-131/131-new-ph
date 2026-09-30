// FILE: lib/batch_sync_engine.dart (UPGRADED TWO-WAY SYNC ENGINE)

import 'models.dart';
import 'pharoah_manager.dart';
import 'expiry_master.dart';

class BatchSyncEngine {
  
  /// ===========================================================================
  /// 1. BATCH REGISTRATION & TWO-WAY SYNC (CASE SENSITIVE SAFE)
  /// Isse Sale/Purchase/Import/CN/DN ke waqt batch memory aur disk par likha jata hai.
  /// ===========================================================================
  static void registerBatchActivity({
    required PharoahManager ph,
    required String productKey, 
    required String batchNo,    
    required String exp,
    required String packing,
    required double mrp,
    required double rate, // Purchase rate reference
    double rateA = 0.0,
    double rateB = 0.0,
    double rateC = 0.0,
    double rateCFormula = 0.0,
    String appliedRateType = "A",
    double qtyChange = 0.0,
    String status = "Active",
  }) {
    if (ph.activeCompany == null) return;

    if (!ph.batchHistory.containsKey(productKey)) {
      ph.batchHistory[productKey] = [];
    }

    List<BatchInfo> history = ph.batchHistory[productKey]!;
    
    // CASE SENSITIVE MATCHING (DL-101 != dl-101)
    int existingIdx = history.indexWhere(
      (b) => b.batch.trim() == batchNo.trim()
    );

    // Fallbacks to handle legacy files smoothly
    double finalRateA = rateA == 0.0 ? mrp : rateA;
    double finalRateB = rateB == 0.0 ? (rateA == 0.0 ? mrp * 0.95 : rateA * 0.95) : rateB;
    double finalRateC = rateC == 0.0 ? (rateA == 0.0 ? mrp * 0.92 : rateA * 0.92) : rateC;

    if (existingIdx != -1) {
      // 🔄 SCENARIO C: UPDATE METADATA (Usi batch me edit)
      history[existingIdx].exp = exp;
      history[existingIdx].mrp = mrp;
      history[existingIdx].rate = rate; // purchase rate
      history[existingIdx].packing = packing;
      
      // Syncing new Marg-style pricing fields
      history[existingIdx].purRate = rate;
      history[existingIdx].rateA = finalRateA;
      history[existingIdx].rateB = finalRateB;
      history[existingIdx].rateC = finalRateC;
      history[existingIdx].rateCFormula = rateCFormula;
      history[existingIdx].appliedRateType = appliedRateType;
      history[existingIdx].status = status;
      if (qtyChange != 0.0) {
        history[existingIdx].qty += qtyChange;
      }
    } else {
      // 🆕 SCENARIO B: CREATE NEW BATCH (Manual Entry or Inward)
      history.add(BatchInfo(
        batch: batchNo.trim(), 
        exp: exp,
        packing: packing,
        mrp: mrp,
        rate: rate,
        qty: qtyChange, 
        openingQty: qtyChange,
        isShell: false,
        purRate: rate,
        rateA: finalRateA,
        rateB: finalRateB,
        rateC: finalRateC,
        rateCFormula: rateCFormula,
        appliedRateType: appliedRateType,
        status: status,
      ));
    }

    // Disk par direct atomic save
    ph.save();
  }

  /// ===========================================================================
  /// 2. BATCH SUGGESTIONS (FOR SEARCH & SELECTION)
  /// ===========================================================================
  static List<BatchInfo> getFilteredBatches({
    required PharoahManager ph,
    required String productKey,
    bool hideExpired = false, 
  }) {
    if (ph.activeCompany == null) return [];
    if (!ph.batchHistory.containsKey(productKey)) return [];

    List<BatchInfo> allBatches = ph.batchHistory[productKey]!;
    
    if (hideExpired) {
      // Sales / Billing screen par expired batches ko block karne ke liye
      DateTime systemToday = DateTime.now();
      return allBatches.where((b) {
        try {
          final parts = b.exp.split('/');
          int m = int.parse(parts[0]);
          int y = 2000 + int.parse(parts[1]);
          DateTime lastDay = DateTime(y, m + 1, 0);
          return !lastDay.isBefore(systemToday); // Keep non-expired
        } catch (_) {
          return true; // Keep if parsing fails (fallback safety)
        }
      }).toList();
    }

    return allBatches;
  }
}
