import 'dart:convert';
import '../models/amazon_bill_model.dart';

class AmazonDirectParser {
  static AmazonBill parseRawText(String rawText) {
    if (rawText.trim().isEmpty) {
      throw Exception("PDF text is completely empty.");
    }

    String normalized = rawText
        .replaceAllMapped(RegExp(r'(\d+)\s*[\*xX]\s*(\d+)'), (m) => '${m[1]}*${m[2]}')
        .replaceAllMapped(RegExp(r'(\d{1,2})\s*[\/\-]\s*(\d{2,4})'), (m) => '${m[1]}/${m[2]}');

    final lines = const LineSplitter().convert(normalized);

    // 1. Invoice No
    String invoiceNo = "";
    RegExp invRegex = RegExp(r'Invoice\s*No\.?\s*[:\-]?\s*([A-Za-z0-9]+)', caseSensitive: false);
    var invMatch = invRegex.firstMatch(normalized);
    if (invMatch != null) invoiceNo = invMatch.group(1)?.trim().toUpperCase() ?? "";
    if (invoiceNo.isEmpty) {
      RegExp altInv = RegExp(r'\b(A\d{5,8})\b');
      var m = altInv.firstMatch(normalized);
      if (m != null) invoiceNo = m.group(1)!.toUpperCase();
    }
    if (invoiceNo.isEmpty) invoiceNo = "INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";

    // 2. Invoice Date (Handles DD-MM-YYYY and DD/MM/YYYY)
    String invoiceDate = "";
    RegExp dateRegex = RegExp(r'Invoice\s*Date\s*[:\-]?\s*([0-9]{1,2}[\/\-][0-9]{1,2}[\/\-][0-9]{4})', caseSensitive: false);
    var dateMatch = dateRegex.firstMatch(normalized);
    if (dateMatch != null) invoiceDate = dateMatch.group(1)?.replaceAll('-', '/') ?? "";
    if (invoiceDate.isEmpty) {
      RegExp altDate = RegExp(r'\b(\d{2}[\/\-]\d{2}[\/\-]\d{4})\b');
      var m = altDate.firstMatch(normalized);
      if (m != null) invoiceDate = m.group(1)!.replaceAll('-', '/');
    }
    if (invoiceDate.isEmpty) {
      final now = DateTime.now();
      invoiceDate = "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";
    }

    // 3. Supplier Details
    String supplierName = "AMAGEN PHARMA PRIVATE LIMITED";
    String supplierGstin = "08AAZCA9942R1Z9";
    String supplierPan = "AAZCA9942R";
    String supplierDl = "DRUG/24-25/20B-21B/120460-61";
    String supplierPhone = "9828052544";
    String supplierAddress = "DEVI NAGAR, JAIPUR-302019, RAJASTHAN";

    String buyerName = "LIFECARE PHARMACEUTICALS";
    String buyerGstin = "08FSBPM0623R1ZC";

    // Dynamic Party / Supplier Detection
    RegExp allGsts = RegExp(r'\b(\d{2}[A-Z]{5}\d{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1})\b');
    var gsts = allGsts.allMatches(normalized).map((m) => m.group(1)!).toList();
    if (gsts.isNotEmpty) {
      for (var g in gsts) {
        if (g == "08FSBPM0623R1ZC") {
          buyerGstin = g;
        } else {
          supplierGstin = g;
          supplierPan = g.substring(2, 12);
        }
      }
    }

    if (normalized.toUpperCase().contains("AMAGEN PHARMA")) {
      supplierName = "AMAGEN PHARMA PRIVATE LIMITED";
    }

    // 4. Totals
    double rawGrandTotal = 0.0;
    double rawTaxable = 0.0;
    double rawRoundOff = 0.0;

    RegExp grandTotalRegex = RegExp(r'Grand\s*Total\s*[:\-]?\s*([0-9,]+\.[0-9]{2})', caseSensitive: false);
    var gtMatch = grandTotalRegex.firstMatch(normalized);
    if (gtMatch != null) rawGrandTotal = double.tryParse(gtMatch.group(1)!.replaceAll(',', '')) ?? 0.0;

    RegExp roundOffRegex = RegExp(r'Round\s*off\s*[:\-]?\s*([+\-]?[0-9,]+\.[0-9]{2})', caseSensitive: false);
    var roMatch = roundOffRegex.firstMatch(normalized);
    if (roMatch != null) rawRoundOff = double.tryParse(roMatch.group(1)!.replaceAll(',', '')) ?? 0.0;

    // 5. Line Item Parser
    List<AmazonItem> items = [];
    RegExp packPattern = RegExp(r'^\d+[\*xX]\d+[A-Za-z]*$', caseSensitive: false);

    for (var line in lines) {
      String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      String upper = trimmed.toUpperCase();
      if (upper.contains("GRAND TOTAL") || upper.contains("CLASS TOTAL") || upper.contains("TERMS & CONDITIONS") || upper.contains("TOTAL ITEMS")) {
        continue;
      }

      // Check Expiry: 9/27, 5/27, 10/26
      RegExp expRegex = RegExp(r'\b(\d{1,2}/\d{2})\b');
      var expMatch = expRegex.firstMatch(trimmed);
      if (expMatch == null) continue;

      var tokens = trimmed.split(RegExp(r'\s+'));
      int expIdx = -1;
      for (int t = 0; t < tokens.length; t++) {
        if (RegExp(r'^\d{1,2}/\d{2}$').hasMatch(tokens[t])) {
          expIdx = t;
          break;
        }
      }
      if (expIdx < 2) continue;

      String exp = tokens[expIdx];

      // Find Pack before expIdx
      int packIdx = -1;
      for (int k = 0; k < expIdx; k++) {
        if (packPattern.hasMatch(tokens[k])) {
          packIdx = k;
          break;
        }
      }
      if (packIdx == -1) continue;

      String pack = tokens[packIdx];

      // Mid Tokens: Qty, Free, Batch, Mfg
      List<String> mid = List.from(tokens.sublist(packIdx + 1, expIdx));
      if (mid.isEmpty) continue;

      double qty = 1.0;
      double freeQty = 0.0;
      String batch = "AUTO";
      String mfg = "AMAGEN";

      if (mid.isNotEmpty && RegExp(r'^\d+(?:\.\d+)?$').hasMatch(mid.first.replaceAll(',', ''))) {
        qty = double.tryParse(mid.removeAt(0).replaceAll(',', '')) ?? 1.0;
      }
      if (mid.isNotEmpty && (mid.first == '-' || RegExp(r'^\d+(?:\.\d+)?$').hasMatch(mid.first))) {
        String fStr = mid.removeAt(0);
        freeQty = fStr == '-' ? 0.0 : (double.tryParse(fStr) ?? 0.0);
      }
      if (mid.isNotEmpty) {
        batch = mid.removeAt(0);
        if (mid.isNotEmpty) mfg = mid.join(" ");
      }

      // Tokens before pack: S.N, HSN, Product Name
      List<String> nameTokens = tokens.sublist(0, packIdx);
      int srNo = items.length + 1;
      String hsn = "300490";

      if (nameTokens.isNotEmpty && RegExp(r'^\d+$').hasMatch(nameTokens.first)) {
        srNo = int.tryParse(nameTokens.removeAt(0)) ?? (items.length + 1);
      }
      if (nameTokens.isNotEmpty && RegExp(r'^\d{4,8}$').hasMatch(nameTokens.first)) {
        hsn = nameTokens.removeAt(0);
      }
      String productName = nameTokens.join(" ").trim().toUpperCase();

      // Numbers after exp: [MRP, Rate, Dis, SGST, CGST, Amount]
      List<double> numbers = [];
      for (int k = expIdx + 1; k < tokens.length; k++) {
        double? val = double.tryParse(tokens[k].replaceAll(',', ''));
        if (val != null) numbers.add(val);
      }

      double mrp = 0.0;
      double rate = 0.0;
      double dis = 0.0;
      double sgstRate = 2.50;
      double cgstRate = 2.50;
      double amount = 0.0;

      if (numbers.length >= 6) {
        mrp = numbers[0];
        rate = numbers[1];
        dis = numbers[2];
        sgstRate = numbers[3];
        cgstRate = numbers[4];
        amount = numbers[5];
      } else if (numbers.length >= 2) {
        mrp = numbers[0];
        rate = numbers[1];
        amount = numbers.last;
      }

      if (amount <= 0.0) amount = qty * rate;
      double totalTaxRate = sgstRate + cgstRate;
      double taxAmt = amount * (totalTaxRate / 100);

      items.add(AmazonItem(
        srNo: srNo,
        hsn: hsn,
        productName: productName,
        pack: pack,
        qty: qty,
        freeQty: freeQty,
        batch: batch,
        mfg: mfg,
        exp: exp,
        mrp: mrp,
        rate: rate,
        discountPer: dis,
        sgstRate: sgstRate,
        cgstRate: cgstRate,
        igstRate: 0.0,
        totalTaxRate: totalTaxRate,
        taxAmount: taxAmt,
        amount: amount,
        originalPack: pack,
        conversionFactor: 1,
      ));
    }

    if (items.isEmpty) {
      throw Exception("Could not find table rows in PDF.");
    }

    double taxableTotal = items.fold(0.0, (s, i) => s + i.amount);
    double sgstTotal = items.fold(0.0, (s, i) => s + (i.amount * (i.sgstRate / 100)));
    double cgstTotal = items.fold(0.0, (s, i) => s + (i.amount * (i.cgstRate / 100)));
    double totalTax = sgstTotal + cgstTotal;
    if (rawGrandTotal <= 0.0) rawGrandTotal = taxableTotal + totalTax + rawRoundOff;

    return AmazonBill(
      invoiceNo: invoiceNo,
      invoiceDate: invoiceDate,
      supplierName: supplierName,
      supplierGstin: supplierGstin,
      supplierPan: supplierPan,
      supplierDl: supplierDl,
      supplierPhone: supplierPhone,
      supplierAddress: supplierAddress,
      buyerName: buyerName,
      buyerGstin: buyerGstin,
      items: items,
      taxableTotal: taxableTotal,
      sgstTotal: sgstTotal,
      cgstTotal: cgstTotal,
      totalTax: totalTax,
      roundOff: rawRoundOff,
      grandTotal: rawGrandTotal,
    );
  }
}
