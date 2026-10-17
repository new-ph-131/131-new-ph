// FILE: lib/web_live_sync/sub_views/web_returns/credit_note/mechanism/credit_note_mechanism.dart

import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';

class CreditNoteMechanism {
  /// 1. ग्राहक का पिछला बिक्री इतिहास (Magic History Engine)
  static List<Map<String, dynamic>> fetchCustomerSaleHistory({
    required PharoahWebManager webPh,
    required String partyId,
    required String partyName,
    required String medicineId,
    required String medicineName,
  }) {
    List<Map<String, dynamic>> history = [];

    for (var sale in webPh.sales) {
      if (sale.status != "Active") continue;

      bool matchesParty = (partyId.isNotEmpty && sale.partyId == partyId) ||
          sale.partyName.trim().toUpperCase() == partyName.trim().toUpperCase();
      if (!matchesParty) continue;

      for (var item in sale.items) {
        bool matchesMed = (medicineId.isNotEmpty && item.medicineID == medicineId) ||
            item.name.trim().toUpperCase() == medicineName.trim().toUpperCase();

        if (matchesMed) {
          history.add({
            'billNo': sale.billNo,
            'date': sale.date,
            'batch': item.batch,
            'exp': item.exp,
            'qty': item.qty,
            'free': item.freeQty,
            'rate': item.rate,
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
    required double rate,
    required double discPer,
    required double discAmt,
    required double gstRate,
    required String shopState,
    required String partyState,
  }) {
    double gross = qty * rate;
    double taxable = gross - discAmt;
    if (taxable < 0) taxable = 0.0;

    double tax = taxable * (gstRate / 100);
    bool isLocal = shopState.trim().toLowerCase() == partyState.trim().toLowerCase();

    return {
      'gross': gross,
      'taxable': taxable,
      'cgst': isLocal ? tax / 2 : 0.0,
      'sgst': isLocal ? tax / 2 : 0.0,
      'igst': !isLocal ? tax : 0.0,
      'total': taxable + tax,
    };
  }

  /// 3. क्रेडिट नोट सेव, 2-वे बैच सिंक, इन्वेंट्री रीबिल्ड और क्लाउड पुश
  static Future<bool> commitCreditNote({
    required PharoahWebManager webPh,
    required String noteId,
    required String noteNo,
    required Party customer,
    required DateTime date,
    required List<BillItem> items,
    required double totalAmount,
    required double extraDiscount,
    required double roundOff,
    required String returnType,
    String? existingId,
  }) async {
    webPh.addSaleReturnAndSync(newReturn);

    // ग्राहक के लेजर बैलेंस में क्रेडिट घटाएं (कस्टमर का बकाया कम होगा)
    customer.opBal -= totalAmount;
    webPh.updateParty(customer);

    return await webPh.pushUpdatedDataToCloud();
  }
}
