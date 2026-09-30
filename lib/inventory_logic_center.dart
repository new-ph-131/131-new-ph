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
        parentMed = medicines.firstWhere((m) => m.identityKey == medKey);
      } catch (e) { parentMed = null; }

      double gstRate = parentMed?.gst ?? 12.0;
      for (var batch in batches) {
        if (batch.qty > 0) {
          double taxableRate = batch.rate / (1 + (gstRate / 100));
          grandTotal += (batch.qty * taxableRate);
        }
      }
    });
    return grandTotal;
  }

  /// 2. THE GREAT INVENTORY REBUILD (CN/DN Impact Integrated with Loose Stock Guard)
  static void rebuildAllInventory({
    required List<Medicine> medicines,
    required Map<String, List<BatchInfo>> batchHistory,
    required List<Purchase> purchases,
    required List<Sale> sales,
    required List<SaleReturn> saleReturns,      
    required List<PurchaseReturn> purchaseReturns 
  }) {
    // STEP A: RESET - Base Stock (Opening + Adjustments) par reset karein
    batchHistory.forEach((key, list) {
      for (var b in list) { b.qty = b.openingQty + b.adjustmentQty; }
    });

    // STEP B: PROCESS PURCHASES (Stock IN +)
    for (var pur in purchases) {
      for (var item in pur.items) {
        _updateStock(batchHistory, medicines, item.medicineID, item.name, item.batch, (item.qty + item.freeQty), true, item);
      }
    }

    // STEP C: PROCESS SALES (Stock OUT -)
    for (var sale in sales.where((s) => s.status == "Active")) {
      for (var item in sale.items) {
        _updateStock(batchHistory, medicines, item.medicineID, item.name, item.batch, (item.qty + item.freeQty), false, item);
      }
    }

    // STEP D: SALE RETURNS / CREDIT NOTES (Stock IN + ONLY IF SELLABLE)
    for (var ret in saleReturns.where((r) => r.status == "Active")) {
      for (var item in ret.items) {
        if (item.isBreakage == false) {
          _updateStock(batchHistory, medicines, item.medicineID, item.name, item.batch, (item.qty + item.freeQty), true, item);
        }
      }
    }

    // STEP E: PURCHASE RETURNS / DEBIT NOTES (Stock OUT -)
    for (var ret in purchaseReturns.where((r) => r.status == "Active")) {
      for (var item in ret.items) {
        _updateStock(batchHistory, medicines, item.medicineID, item.name, item.batch, (item.qty + item.freeQty), false, item);
      }
    }

    // --- 🛡️ STEP F: FINAL SYNC WITH LOOSE STOCK GUARD (RESOLVED) ---
    // Agar kisi medicine ke batches bats.json mein nahi hain (Loose Stock),
    // toh uske stock ko zero (0) karne ke bajaye hum uska existing stock safe rakhenge.
    for (var med in medicines) {
      if (batchHistory.containsKey(med.identityKey) && batchHistory[med.identityKey]!.isNotEmpty) {
        double total = 0;
        for (var b in batchHistory[med.identityKey]!) { 
          total += b.qty; 
        }
        med.stock = total; // Overwrite only if active batches exist
      }
      // If no batches exist, we PRESERVE the existing med.stock (Loose Stock Saved!)
    }
  } // <--- REBUILDALLINVENTORY FUNCTION KA CLOSING BRACE (FIXED!)

  // Private Helper function for batch quantity adjustment
  static void _updateStock(Map<String, List<BatchInfo>> batchHistory, List<Medicine> medicines, String medId, String medName, String batchNo, double qty, bool isAdd, dynamic item) {
    try {
      Medicine med = medicines.firstWhere((m) => m.id == medId || m.name == medName);
      String key = med.identityKey;
      if (!batchHistory.containsKey(key)) batchHistory[key] = [];
      var batches = batchHistory[key]!;
      int idx = batches.indexWhere((b) => b.batch == batchNo);
      
      if (idx != -1) {
        batches[idx].qty += isAdd ? qty : -qty;
      } else if (isAdd) {
        // Agar batch history mein nahi hai toh naya shell batch banao (sirf Stock-IN ke liye)
        batches.add(BatchInfo(
          batch: batchNo, exp: item.exp, packing: item.packing, 
          mrp: item.mrp, rate: (item is PurchaseItem) ? item.purchaseRate : item.rate, 
          qty: qty, isShell: false
        ));
      }
    } catch (e) {}
  }
} // <--- CLASS INVENTORYLOGICCENTER KA CLOSING BRACE
