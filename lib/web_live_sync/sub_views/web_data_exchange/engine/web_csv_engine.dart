// FILE: lib/web_live_sync/sub_views/web_data_exchange/engine/web_csv_engine.dart
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import '../../../web_models.dart';

class WebCsvEngine {
  /// UNIVERSAL 39-COLUMN HEADER (Index 0 to 38)
  static List<String> get universal39Header => [
    "DATE", "BILL_NO",
    "PARTY_NAME", "PARTY_GST", "PARTY_DL", "PARTY_PAN", "PARTY_MOBILE", "PARTY_EMAIL", "PARTY_ADDRESS", "PARTY_CITY", "PARTY_STATE",
    "SENDER_NAME", "SENDER_GST", "SENDER_DL", "SENDER_PAN", "SENDER_MOBILE", "SENDER_EMAIL", "SENDER_ADDRESS",
    "ITEM_NAME", "ITEM_PACKING", "ITEM_HSN", "ITEM_MFG", "ITEM_SALT", "ITEM_FORM", "IS_NARCOTIC", "IS_H1",
    "ITEM_BATCH", "ITEM_EXP", "QTY", "FREE", "MRP", "PUR_RATE", "SALE_RATE", "GST_PER",
    "ITEM_TOTAL", "ITEM_DISCOUNT_PER", "ITEM_DISCOUNT_AMT", "BILL_EXTRA_DISCOUNT", "BILL_ROUNDOFF"
  ];

  static String convertSalesTo39Csv({
    required List<Sale> sales,
    required CompanyProfile shop,
    required List<Medicine> allMeds,
    required List<Company> allComps,
    required List<Salt> allSalts,
    required List<Party> allParties,
    bool maskPurchaseRate = false,
  }) {
    List<List<dynamic>> rows = [universal39Header];
    for (var s in sales) {
      Party masterParty = allParties.firstWhere(
        (p) => p.name == s.partyName || (s.partyGstin.isNotEmpty && p.gst == s.partyGstin),
        orElse: () => Party(id: '', name: s.partyName),
      );

      String finalMobile = s.partyPhone.isNotEmpty 
          ? s.partyPhone 
          : (masterParty.phone.isNotEmpty ? masterParty.phone : "N/A");
      String finalGst = s.partyGstin.isNotEmpty ? s.partyGstin : (masterParty.gst.isNotEmpty ? masterParty.gst : "");
      String finalDl = s.partyDl.isNotEmpty ? s.partyDl : (masterParty.dl.isNotEmpty ? masterParty.dl : "");
      String finalPan = s.partyPan.isNotEmpty ? s.partyPan : (masterParty.pan.isNotEmpty ? masterParty.pan : "");
      String finalEmail = s.partyEmail.isNotEmpty ? s.partyEmail : (masterParty.email.isNotEmpty ? masterParty.email : "");
      String finalAddress = s.partyAddress.isNotEmpty ? s.partyAddress : (masterParty.address.isNotEmpty ? masterParty.address : "");
      String finalCity = s.partyCity.isNotEmpty ? s.partyCity : (masterParty.city.isNotEmpty ? masterParty.city : "");
      String finalState = s.partyState.isNotEmpty ? s.partyState : (masterParty.state.isNotEmpty ? masterParty.state : (shop.state.isNotEmpty ? shop.state : "Rajasthan"));

      for (var i in s.items) {
        Medicine med = allMeds.firstWhere(
          (m) => m.id == i.medicineID || m.name == i.name,
          orElse: () => Medicine(id: '', name: i.name, packing: i.packing),
        );

        String mfg = allComps.firstWhere(
          (c) => c.id == med.companyId,
          orElse: () => Company(id: '', name: 'N/A'),
        ).name;

        String salt = allSalts.firstWhere(
          (sl) => sl.id == med.saltId,
          orElse: () => Salt(id: '', name: 'N/A'),
        ).name;

        double discAmt = i.discountRupees;
        double grossAmt = i.qty * i.rate;
        double discPer = i.discountPer > 0 
            ? i.discountPer 
            : (grossAmt > 0 ? double.parse(((discAmt / grossAmt) * 100).toStringAsFixed(2)) : 0.0);

        double taxable = grossAmt - discAmt;
        if (taxable < 0) taxable = 0.0;
        double taxAmt = taxable * (i.gstRate / 100.0);
        double lineTotal = double.parse((taxable + taxAmt).toStringAsFixed(2));

        rows.add([
          DateFormat('dd/MM/yyyy').format(s.date), s.billNo,
          s.partyName, finalGst, finalDl, finalPan, finalMobile, finalEmail, finalAddress, finalCity, finalState,
          shop.name, shop.gstin, shop.dlNo, "N/A", shop.phone, shop.email, shop.address,
          i.name, i.packing, i.hsn, mfg, salt, med.drugForm, med.isNarcotic ? "YES" : "NO", med.isScheduleH1 ? "YES" : "NO",
          i.batch, i.exp, i.qty, i.freeQty, i.mrp, maskPurchaseRate ? 0.0 : med.purRate, i.rate, i.gstRate,
          lineTotal, discPer, discAmt, s.extraDiscount, s.roundOff
        ]);
      }
    }
    return const ListToCsvConverter().convert(rows);
  }

  static String convertPurchasesTo39Csv({
    required List<Purchase> purchases,
    required CompanyProfile shop,
    required List<Medicine> allMeds,
    required List<Company> allComps,
    required List<Salt> allSalts,
    required List<Party> allParties,
  }) {
    List<List<dynamic>> rows = [universal39Header];
    for (var p in purchases) {
      Party masterParty = allParties.firstWhere(
        (pt) => pt.id == p.partyId || pt.name == p.distributorName,
        orElse: () => Party(id: '', name: p.distributorName),
      );

      for (var i in p.items) {
        Medicine med = allMeds.firstWhere(
          (m) => m.id == i.medicineID || m.name == i.name,
          orElse: () => Medicine(id: '', name: i.name, packing: i.packing),
        );

        String mfg = allComps.firstWhere(
          (c) => c.id == med.companyId,
          orElse: () => Company(id: '', name: 'N/A'),
        ).name;

        String salt = allSalts.firstWhere(
          (sl) => sl.id == med.saltId,
          orElse: () => Salt(id: '', name: 'N/A'),
        ).name;

        double discAmt = i.discountRupees;
        double grossAmt = i.qty * i.purchaseRate;
        double discPer = i.discountPer > 0
            ? i.discountPer
            : (grossAmt > 0 ? double.parse(((discAmt / grossAmt) * 100).toStringAsFixed(2)) : 0.0);

        double taxable = grossAmt - discAmt;
        if (taxable < 0) taxable = 0.0;
        double taxAmt = taxable * (i.gstRate / 100.0);
        double lineTotal = double.parse((taxable + taxAmt).toStringAsFixed(2));

        rows.add([
          DateFormat('dd/MM/yyyy').format(p.date), p.billNo,
          p.distributorName, masterParty.gst, masterParty.dl, masterParty.pan, masterParty.phone, masterParty.email, masterParty.address, masterParty.city, masterParty.state,
          shop.name, shop.gstin, shop.dlNo, "N/A", shop.phone, shop.email, shop.address,
          i.name, i.packing, i.hsn, mfg, salt, med.drugForm, med.isNarcotic ? "YES" : "NO", med.isScheduleH1 ? "YES" : "NO",
          i.batch, i.exp, i.qty, i.freeQty, i.mrp, i.purchaseRate, i.rateA, i.gstRate,
          lineTotal, discPer, discAmt, p.extraDiscount, p.roundOff
        ]);
      }
    }
    return const ListToCsvConverter().convert(rows);
  }

  static List<List<dynamic>> parseCsvString(String content) =>
      const CsvToListConverter(shouldParseNumbers: true, allowInvalid: true).convert(content);
}
