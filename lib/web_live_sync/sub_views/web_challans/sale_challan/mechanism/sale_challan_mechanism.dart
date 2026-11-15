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
    SaleChallan? existingCh;
    if (existingId != null && existingId.trim().isNotEmpty) {
      final idx = webPh.saleChallans.indexWhere((c) => c.id.trim() == existingId.trim());
      if (idx != -1) {
        existingCh = webPh.saleChallans[idx];
        if (existingCh.status == "Billed") {
          return false;
        }
      }
    }

    final String preservedOfy = (existingCh != null && existingCh.effectiveOriginalFy.isNotEmpty)
        ? existingCh.effectiveOriginalFy
        : normalizeFyString(webPh.financialYear);

    final newChallan = SaleChallan(
      id: existingCh?.id ?? challanId,
      billNo: challanNo,
      partyId: customer.id,
      partyName: customer.name,
      partyGstin: customer.gst,
      partyState: customer.state,
      date: date,
      items: List.from(items),
      totalAmount: totalAmount,
      status: existingCh?.status ?? "Pending",
      remarks: remarks,
      originalFy: preservedOfy,
      salesmanName: existingCh?.salesmanName ?? "WEB-PORTAL",
      sigHistory: existingCh != null ? List.from(existingCh.sigHistory) : [],
      isSigned: existingCh?.isSigned ?? false,
      version: existingCh != null ? existingCh.version + 1 : 1,
    );

    webPh.addSaleChallanAndSync(newChallan);
    return await webPh.pushUpdatedDataToCloud();
  }
}
