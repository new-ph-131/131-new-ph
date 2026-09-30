// FILE: lib/csv_engine.dart
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'gateway/company_registry_model.dart';

class CsvEngine {
// 38 Columns Header (Total 39 items, Index 0 to 38)
          // --- UNIVERSAL 39-COLUMN HEADER (Index 0 to 38) ---
          static List<String> get _universalHeader => [
            "DATE", "BILL_NO", // 0, 1
            "PARTY_NAME", "PARTY_GST", "PARTY_DL", "PARTY_PAN", "PARTY_MOBILE", "PARTY_EMAIL", "PARTY_ADDRESS", "PARTY_CITY", "PARTY_STATE", // 2-10
            "SENDER_NAME", "SENDER_GST", "SENDER_DL", "SENDER_PAN", "SENDER_MOBILE", "SENDER_EMAIL", "SENDER_ADDRESS", // 11-17
            "ITEM_NAME", "ITEM_PACKING", "ITEM_HSN", "ITEM_MFG", "ITEM_SALT", "ITEM_FORM", "IS_NARCOTIC", "IS_H1", // 18-25
            "ITEM_BATCH", "ITEM_EXP", "QTY", "FREE", "MRP", "PUR_RATE", "SALE_RATE", "GST_PER", // 26-33
            "ITEM_TOTAL", "ITEM_DISCOUNT_PER", "ITEM_DISCOUNT_AMT", "BILL_EXTRA_DISCOUNT", "BILL_ROUNDOFF" // 34, 35, 36, 37, 38
          ];

  static String convertSalesToCsv({
    required List<Sale> sales, required CompanyProfile shop, required List<Medicine> allMeds,
    required List<Company> allComps, required List<Salt> allSalts, required List<Party> allParties,
    bool maskPurchaseRate = false, 
  }) {
    List<List<dynamic>> rows = [_universalHeader];
    for (var s in sales) {
      Party masterParty = allParties.firstWhere((p) => p.name == s.partyName, orElse: () => Party(id: '', name: s.partyName));
      String finalMobile = s.partyPhone.isNotEmpty ? s.partyPhone : (masterParty.phone.isNotEmpty ? masterParty.phone : "N/A");

      for (var i in s.items) {
        Medicine med = allMeds.firstWhere((m) => m.id == i.medicineID, orElse: () => Medicine(id: '', name: i.name, packing: i.packing));
        String mfg = allComps.firstWhere((c) => c.id == med.companyId, orElse: () => Company(id: '', name: 'N/A')).name;
        String salt = allSalts.firstWhere((sl) => sl.id == med.saltId, orElse: () => Salt(id: '', name: 'N/A')).name;

        // NEW: Calculate Item-wise Discount Percentage
        double discPer = 0.0;
        if (i.qty > 0 && i.rate > 0) {
          discPer = (i.discountRupees / (i.rate * i.qty)) * 100;
        }

        rows.add([
                  DateFormat('dd/MM/yyyy').format(s.date), s.billNo, // 0, 1
                  s.partyName, s.partyGstin, s.partyDl, s.partyPan, finalMobile, s.partyEmail, s.partyAddress, s.partyCity, s.partyState, // 2-10
                  shop.name, shop.gstin, shop.dlNo, "N/A", shop.phone, shop.email, shop.address, // 11-17
                  i.name, i.packing, i.hsn, mfg, salt, med.drugForm, med.isNarcotic ? "YES" : "NO", med.isScheduleH1 ? "YES" : "NO", // 18-25
                  i.batch, i.exp, i.qty, i.freeQty, i.mrp, maskPurchaseRate ? 0.0 : med.purRate, i.rate, i.gstRate, // 26-33
                  i.total, discPer, i.discountRupees, s.extraDiscount, s.roundOff // 34, 35, 36, 37, 38
                ]);
      }
    }
    return const ListToCsvConverter().convert(rows);
  }

  static String convertPurchasesToCsv({
    required List<Purchase> purchases, required CompanyProfile shop, required List<Medicine> allMeds,
    required List<Company> allComps, required List<Salt> allSalts, required List<Party> allParties,
  }) {
    List<List<dynamic>> rows = [_universalHeader];
    for (var p in purchases) {
      Party masterParty = allParties.firstWhere((pt) => pt.id == p.partyId || pt.name == p.distributorName, orElse: () => Party(id: '', name: p.distributorName));
      for (var i in p.items) {
        Medicine med = allMeds.firstWhere((m) => m.id == i.medicineID, orElse: () => Medicine(id: '', name: i.name, packing: i.packing));
        String mfg = allComps.firstWhere((c) => c.id == med.companyId, orElse: () => Company(id: '', name: 'N/A')).name;
        String salt = allSalts.firstWhere((sl) => sl.id == med.saltId, orElse: () => Salt(id: '', name: 'N/A')).name;
        rows.add([
                  DateFormat('dd/MM/yyyy').format(p.date), p.billNo, // 0, 1
                  p.distributorName, masterParty.gst, masterParty.dl, masterParty.pan, masterParty.phone, masterParty.email, masterParty.address, masterParty.city, masterParty.state, // 2-10
                  shop.name, shop.gstin, shop.dlNo, "N/A", shop.phone, shop.email, shop.address, // 11-17
                  i.name, i.packing, i.hsn, mfg, salt, med.drugForm, med.isNarcotic ? "YES" : "NO", med.isScheduleH1 ? "YES" : "NO", // 18-25
                  i.batch, i.exp, i.qty, i.freeQty, i.mrp, i.purchaseRate, i.rateA, i.gstRate, // 26-33
                  i.total, i.discountPer, i.discountRupees, p.extraDiscount, p.roundOff // 34, 35, 36, 37, 38 (🆕 Real purchase properties mapped)
                ]);
      }
    }
    return const ListToCsvConverter().convert(rows);
  }

  static List<List<dynamic>> parseCsv(String content) => const CsvToListConverter(shouldParseNumbers: true, allowInvalid: true).convert(content);
}
