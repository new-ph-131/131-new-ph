// FILE: lib/web_live_sync/sub_views/web_challans/sale_challan/mechanism/sale_challan_mechanism.dart

import 'package:pharoah_erp/models.dart';
import '../../../../pharoah_web_manager.dart';

class SaleChallanMechanism {
  /// नेट चालान टोटल की गणना
  static double calculateChallanTotal(List<BillItem> items) {
    return items.fold(0.0, (sum, it) => sum + it.total);
  }

  /// चालान सेव करना, बैच हिस्ट्री अपडेट करना और क्लाउड पर पुश करना
  static Future<bool> commitSaleChallan({
    required PharoahWebManager webPh,
    required String challanId,
    required String challanNo,
    required Party customer,
    required DateTime date,
    required List<BillItem> items,
    required double totalAmount,
    required String remarks,
    String? existingId,
  }) async {
    // अगर एडिट मोड है तो पुराना चालान हटाएं
    if (existingId != null) {
      webPh.deleteSaleChallan(existingId);
    }

    final newChallan = SaleChallan(
      id: challanId,
      billNo: challanNo,
      partyId: customer.id,
      partyName: customer.name,
      partyGstin: customer.gst,
      partyState: customer.state,
      date: date,
      items: List.from(items),
      totalAmount: totalAmount,
      status: "Pending",
      remarks: remarks,
    );

    webPh.saleChallans.add(newChallan);

    // 2-Way Batch Inventory Activity
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        final med = webPh.medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey;
      } catch (_) {}

      webPh.registerBatchActivity(
        productKey: resolvedKey,
        batchNo: item.batch,
        exp: item.exp,
        packing: item.packing,
        mrp: item.mrp,
        rate: item.rate,
        rateA: item.appliedRateType == "A" ? item.rate : 0.0,
        rateB: item.appliedRateType == "B" ? item.rate : 0.0,
        rateC: item.appliedRateType == "C" ? item.rate : 0.0,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
      );
    }

    webPh.rebuildInventory();
    return await webPh.pushUpdatedDataToCloud();
  }
}
