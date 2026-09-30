import 'package:csv/csv.dart';
import '../models/medilente_bill_model.dart';

class MedilenteCsvGenerator {
  /// Generates dedicated standalone CSV for Medilente invoice
  static String generateCsvString(MedilenteBill bill) {
    List<List<dynamic>> rows = [];

    // Header Row
    rows.add([
      "INVOICE_NO", "INVOICE_DATE", "SUPPLIER_NAME", "SUPPLIER_GSTIN", "SUPPLIER_PHONE", "SUPPLIER_STATE",
      "BUYER_NAME", "BUYER_GSTIN",
      "SR_NO", "HSN", "PRODUCT_NAME", "PACKING", "BATCH", "EXPIRY", "MFG",
      "QTY", "FREE_QTY", "PURCHASE_RATE", "MRP", "OLD_MRP", "IGST_PERCENT", "IGST_VALUE", "ITEM_AMOUNT",
      "TAXABLE_TOTAL", "TOTAL_IGST", "ROUND_OFF", "GRAND_TOTAL"
    ]);

    for (var it in bill.items) {
      rows.add([
        bill.invoiceNo, bill.invoiceDate, bill.supplierName, bill.supplierGstin, bill.supplierPhone, "HARYANA",
        bill.buyerName, bill.buyerGstin,
        it.srNo, it.hsn, it.productName, it.pack, it.batch, it.exp, it.mfg,
        it.qty, it.freeQty, it.rate, it.netMrp, it.oldMrp, it.igstRate, it.igstValue, it.amount,
        bill.taxableTotal, bill.igstTotal, bill.roundOff, bill.grandTotal
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }
}
