// FILE: lib/web_live_sync/sub_views/web_returns/debit_note/mechanism/debit_note_mechanism.dart
// ignore_for_file: prefer_const_constructors, unnecessary_const

import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';

class DebitNoteMechanism {
  /// 1. सप्लायर का पिछला खरीद इतिहास (Magic Purchase History Engine)
  static List<Map<String, dynamic>> fetchSupplierPurchaseHistory({
    required PharoahWebManager webPh,
    required String supplierId,
    required String supplierName,
    required String medicineId,
    required String medicineName,
  }) {
    List<Map<String, dynamic>> history = [];

    for (var purchase in webPh.purchases) {
      bool matchesSupplier = (supplierId.isNotEmpty && purchase.partyId == supplierId) ||
          purchase.distributorName.trim().toUpperCase() == supplierName.trim().toUpperCase();
      if (!matchesSupplier) continue;

      for (var item in purchase.items) {
        bool matchesMed = (medicineId.isNotEmpty && item.medicineID == medicineId) ||
            item.name.trim().toUpperCase() == medicineName.trim().toUpperCase();

        if (matchesMed) {
          history.add({
            'billNo': purchase.billNo,
            'internalNo': purchase.internalNo,
            'date': purchase.date,
            'batch': item.batch,
            'exp': item.exp,
            'qty': item.qty,
            'free': item.freeQty,
            'purchaseRate': item.purchaseRate,
            'mrp': item.mrp,
            'gst': item.gstRate,
            'packing': item.packing,
            'appliedRateType': item.appliedRateType,
            'discountPer': item.discountPer,
          });
        }
      }
    }

    history.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    return history;
  }

  /// 2. आइटम टैक्स व टोटल गणना (Local CGST/SGST vs Interstate IGST)
  static Map<String, double> calculateItemTotals({
    required double qty,
    required double purchaseRate,
    required double discPer,
    required double discAmt,
    required double gstRate,
    required String shopState,
    required String supplierState,
  }) {
    double gross = qty * purchaseRate;
    double taxable = gross - discAmt;
    if (taxable < 0) taxable = 0.0;

    double tax = taxable * (gstRate / 100);
    bool isLocal = shopState.trim().toLowerCase() == supplierState.trim().toLowerCase();

    return {
      'gross': gross,
      'taxable': taxable,
      'cgst': isLocal ? tax / 2 : 0.0,
      'sgst': isLocal ? tax / 2 : 0.0,
      'igst': !isLocal ? tax : 0.0,
      'total': taxable + tax,
    };
  }

  /// 3. डेबिट नोट सेव, 2-वे बैच स्टॉक रिवर्सल, लेजर एडजस्टमेंट और क्लाउड सिंक
  static Future<bool> commitDebitNote({
    required PharoahWebManager webPh,
    required String noteId,
    required String noteNo,
    required Party supplier,
    required DateTime date,
    required List<PurchaseItem> items,
    required double totalAmount,
    required double extraDiscount,
    required double roundOff,
    required String returnType,
    String? existingId,
  }) async {
    // अगर एडिट मोड है तो पुराना डेबिट नोट हटाएं
    if (existingId != null) {
      webPh.deletePurchaseReturn(existingId);
    }

    final newReturn = PurchaseReturn(
      id: noteId,
      billNo: noteNo,
      distributorName: supplier.name,
      date: date,
      items: List.from(items),
      totalAmount: totalAmount,
      extraDiscount: extraDiscount,
      roundOff: roundOff,
      returnType: returnType,
      status: "Active",
    );

    webPh.purchaseReturns.add(newReturn);

    // 2-Way Batch Inventory Activity (Stock OUT -)
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        final med = webPh.medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey;
      } catch (_) {}

      // अगर आइटम Sellable है, तो स्टॉक घटेगा -(qty + freeQty)
      // अगर Breakage/Expiry है, तो बेचने लायक स्टॉक में 0 परिवर्तन होगा
      double qtyChange = item.isBreakage ? 0.0 : -(item.qty + item.freeQty);

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
        qtyChange: qtyChange,
      );
    }

    // सप्लायर के बकाए (Payable) में से डेबिट नोट घटाएं
    supplier.opBal -= totalAmount;
    webPh.updateParty(supplier);

    webPh.rebuildInventory();
    return await webPh.pushUpdatedDataToCloud();
  }
}
