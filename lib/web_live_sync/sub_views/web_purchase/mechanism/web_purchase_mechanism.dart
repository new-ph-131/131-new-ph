// FILE: lib/web_live_sync/sub_views/web_purchase/mechanism/web_purchase_mechanism.dart

import 'package:pharoah_erp/web_live_sync/web_models.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';

class WebPurchaseMechanism {
  static Future<bool> commitPurchase({
    required PharoahWebManager webPh,
    required String purchaseId,
    required String internalNo,
    required String billNo,
    required Party supplier,
    required DateTime billDate,
    required DateTime entryDate,
    required String paymentMode,
    required List<PurchaseItem> items,
    required double totalAmount,
    required double extraDiscount,
    required double roundOff,
    required List<String> linkedChallanIds,
    String? existingId,
  }) async {
    if (existingId != null) {
      webPh.purchases.removeWhere((p) => p.id == existingId);
    }

    final newPurchase = Purchase(
      id: purchaseId,
      internalNo: internalNo,
      billNo: billNo,
      partyId: supplier.id,
      distributorName: supplier.name,
      date: billDate,
      entryDate: entryDate,
      paymentMode: paymentMode,
      totalAmount: totalAmount,
      extraDiscount: extraDiscount,
      roundOff: roundOff,
      gstStatus: "Pending",
      items: List.from(items),
      linkedChallanIds: linkedChallanIds,
      sourceTag: "WEB-PORTAL",
    );

    webPh.purchases.add(newPurchase);

    // 2-Way Batch Inventory Activity + Medicine Master L.P.R. Update
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        int mIdx = webPh.medicines.indexWhere(
          (m) => m.id == item.medicineID || m.name.trim().toUpperCase() == item.name.trim().toUpperCase()
        );
        if (mIdx != -1) {
          final med = webPh.medicines[mIdx];
          resolvedKey = med.identityKey;
          med.purRate = item.purchaseRate;
          if (item.mrp > 0) med.mrp = item.mrp;
          if (item.rateA > 0) med.rateA = item.rateA;
          if (item.rateB > 0) med.rateB = item.rateB;
          if (item.rateC > 0) med.rateC = item.rateC;
          webPh.updateMedicine(med);
        }
      } catch (_) {}

      webPh.registerBatchActivity(
        productKey: resolvedKey,
        batchNo: item.batch,
        exp: item.exp,
        packing: item.packing,
        mrp: item.mrp,
        rate: item.purchaseRate,
        rateA: item.rateA,
        rateB: item.rateB,
        rateC: item.rateC,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
        qtyChange: item.qty + item.freeQty,
      );
    }

    // Revert any linked challans to Billed
    if (linkedChallanIds.isNotEmpty) {
      for (var id in linkedChallanIds) {
        int idx = webPh.purchaseChallans.indexWhere((c) => c.id == id);
        if (idx != -1) webPh.purchaseChallans[idx].status = "Billed";
      }
    }

    // Update supplier payable
    supplier.opBal += totalAmount;
    webPh.updateParty(supplier);

    webPh.rebuildInventory();
    return await webPh.pushUpdatedDataToCloud();
  }
}
