import 'dart:convert';
import '../models/medilente_bill_model.dart';

class MedilenteDirectParser {
  static MedilenteBill parseRawText(String rawText) {
    if (rawText.trim().isEmpty) {
      throw Exception("PDF text is completely empty.");
    }

    // 1. Pre-normalization of separators
    String normalized = rawText
        .replaceAllMapped(RegExp(r'(\d+)\s*[\*xX]\s*(\d+)'), (m) => '${m[1]}*${m[2]}')
        .replaceAllMapped(RegExp(r'(\d{1,2})\s*/\s*(\d{2,4})'), (m) => '${m[1]}/${m[2]}');

    final lines = const LineSplitter().convert(normalized);

    // 2. Invoice Number
    String invoiceNo = "";
    RegExp invRegex = RegExp(r'Invoice\s*No\.?\s*[:\-]?\s*([A-Za-z0-9]+)', caseSensitive: false);
    var invMatch = invRegex.firstMatch(normalized);
    if (invMatch != null) {
      invoiceNo = invMatch.group(1)?.trim().toUpperCase() ?? "";
    }
    if (invoiceNo.isEmpty) {
      RegExp altInv = RegExp(r'\b(A\d{5,8})\b');
      var m = altInv.firstMatch(normalized);
      if (m != null) invoiceNo = m.group(1)!.toUpperCase();
    }
    if (invoiceNo.isEmpty) {
      invoiceNo = "INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    }

    // 3. Invoice Date
    String invoiceDate = "";
    RegExp dateRegex = RegExp(r'Invoice\s*Date\s*[:\-]?\s*([0-9]{1,2}/[0-9]{1,2}/[0-9]{4})', caseSensitive: false);
    var dateMatch = dateRegex.firstMatch(normalized);
    if (dateMatch != null) {
      invoiceDate = dateMatch.group(1)?.trim() ?? "";
    }
    if (invoiceDate.isEmpty) {
      RegExp altDate = RegExp(r'\b(\d{2}/\d{2}/\d{4})\b');
      var m = altDate.firstMatch(normalized);
      if (m != null) invoiceDate = m.group(1)!;
    }
    if (invoiceDate.isEmpty) {
      final now = DateTime.now();
      invoiceDate = "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";
    }

    // 4. Strict GST Mapping (06 = Medilente Haryana, 08 = Lifecare Rajasthan)
    String supplierName = "MEDILENTE PHARMA PRIVATE LTD.";
    String supplierGstin = "06AAICM6627L1Z2";
    String supplierPan = "AAICM6627L";
    String supplierDl = "WLF20B2023HR000048,WLF21B2023HR000048";
    String supplierEmail = "medilentepharma@gmail.com";
    String supplierPhone = "9875949453";
    String supplierAddress = "BARWALA PANCHKULA, HARYANA";

    String buyerName = "LIFECARE PHARMACEUTICALS";
    String buyerGstin = "08FSBPM0623R1ZC";

    RegExp supGstRegex = RegExp(r'06[A-Z]{5}\d{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}');
    var sMatch = supGstRegex.firstMatch(normalized);
    if (sMatch != null) supplierGstin = sMatch.group(0)!;

    RegExp buyGstRegex = RegExp(r'08[A-Z]{5}\d{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}');
    var bMatch = buyGstRegex.firstMatch(normalized);
    if (bMatch != null) buyerGstin = bMatch.group(0)!;

    RegExp partyRegex = RegExp(r'Party\s*Name\s*[:\-]?\s*\n?([A-Za-z0-9\s\.\,\-]+)', caseSensitive: false);
    var pMatch = partyRegex.firstMatch(normalized);
    if (pMatch != null) {
      String cand = pMatch.group(1)?.trim() ?? "";
      if (cand.isNotEmpty && cand.length > 3) {
        buyerName = cand.split('\n').first.trim().toUpperCase();
      }
    }

    // 5. Totals Extraction
    double rawGrandTotal = 0.0;
    double rawTaxable = 0.0;
    double rawIgst = 0.0;
    double rawRoundOff = 0.0;

    RegExp grandTotalRegex = RegExp(r'Grand\s*Total\s*[:\-]?\s*([0-9,]+\.[0-9]{2})', caseSensitive: false);
    var gtMatch = grandTotalRegex.firstMatch(normalized);
    if (gtMatch != null) {
      rawGrandTotal = double.tryParse(gtMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
    }

    RegExp roundOffRegex = RegExp(r'Round\s*off\s*[:\-]?\s*([+\-]?[0-9,]+\.[0-9]{2})', caseSensitive: false);
    var roMatch = roundOffRegex.firstMatch(normalized);
    if (roMatch != null) {
      rawRoundOff = double.tryParse(roMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
    }

    // 6. Universal Pack Pattern: matches 10*10, 2*15, 5*1ML, 10*1*10, etc.
    RegExp universalPackRegex = RegExp(r'^\d+(?:[\*xX]\d+)+[A-Za-z]*$', caseSensitive: false);

    // 7. Multi-Line Item Extraction
    List<MedilenteItem> items = [];

    for (var line in lines) {
      String trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      String upper = trimmed.toUpperCase();
      if (upper.contains("GRAND TOTAL") || upper.contains("CLASS TOTAL") || upper.contains("TERMS & CONDITIONS") || upper.contains("TOTAL ITEMS")) {
        continue;
      }

      // --- CASE A: SERVICE / FREIGHT CHARGES LINE (Item 7) ---
      if (upper.contains("FREIGHT") || upper.contains("CHARGES")) {
        List<double> nums = RegExp(r'[0-9]+(?:\.[0-9]{2})')
            .allMatches(trimmed)
            .map((m) => double.tryParse(m.group(0)!) ?? 0.0)
            .toList();

        if (nums.isNotEmpty) {
          double rate = nums.length >= 2 ? nums[1] : nums[0];
          double amount = nums.last > 0 ? nums.last : rate;
          double igstPer = 18.0;
          for (var n in nums) {
            if (n == 18.0 || n == 12.0 || n == 5.0) igstPer = n;
          }
          double igstVal = amount * (igstPer / 100);

          items.add(MedilenteItem(
            srNo: items.length + 1,
            hsn: "9968",
            productName: "FREIGHT CHARGES (18% TAX)",
            pack: "1 PCS",
            qty: 1.0,
            freeQty: 0.0,
            batch: "FREIGHT",
            mfg: "SERVICES",
            exp: "12/99",
            netMrp: amount,
            oldMrp: 0.0,
            rate: rate,
            discountPer: 0.0,
            igstRate: igstPer,
            igstValue: igstVal,
            amount: amount,
            originalPack: "1 PCS",
            conversionFactor: 1,
          ));
          continue;
        }
      }

      // --- CASE B: MEDICINE PRODUCT LINE ---
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
        if (universalPackRegex.hasMatch(tokens[k])) {
          packIdx = k;
          break;
        }
      }
      if (packIdx == -1) continue;

      String pack = tokens[packIdx];

      // Tokens between pack and exp: [Qty] [Free] [Batch] [Mfg...]
      List<String> midTokens = List.from(tokens.sublist(packIdx + 1, expIdx));
      if (midTokens.isEmpty) continue;

      double qty = 1.0;
      double freeQty = 0.0;
      String batch = "AUTO";
      String mfg = "GEN";

      // 1st mid token is Qty if numeric
      if (midTokens.isNotEmpty && RegExp(r'^\d+(?:\.\d+)?$').hasMatch(midTokens.first.replaceAll(',', ''))) {
        qty = double.tryParse(midTokens.removeAt(0).replaceAll(',', '')) ?? 1.0;
      }

      // 2nd mid token is Free if '-' or numeric
      if (midTokens.isNotEmpty && (midTokens.first == '-' || RegExp(r'^\d+(?:\.\d+)?$').hasMatch(midTokens.first))) {
        freeQty = double.tryParse(midTokens.removeAt(0)) ?? 0.0;
      }

      // Remaining mid tokens are Batch & Mfg
      if (midTokens.length >= 2) {
        batch = midTokens.removeAt(0);
        mfg = midTokens.join(" "); // Joins e.g. "MMG H"
      } else if (midTokens.length == 1) {
        String merged = midTokens.first;
        // If merged like BSG250990ABIONE
        if (merged.length > 8 && RegExp(r'^[A-Z0-9]+[A-Z]{3,}$').hasMatch(merged)) {
          batch = merged.substring(0, merged.length - 5);
          mfg = merged.substring(merged.length - 5);
        } else {
          batch = merged;
          mfg = "GEN";
        }
      }

      // Tokens before pack: [S.N] [HSN] [Product Name...]
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
      if (productName.isEmpty) productName = "PRODUCT ITEM $srNo";

      // Numbers after Expiry:
      List<double> numbers = [];
      for (int k = expIdx + 1; k < tokens.length; k++) {
        double? val = double.tryParse(tokens[k].replaceAll(',', ''));
        if (val != null) numbers.add(val);
      }

      double netMrp = 0.0;
      double oldMrp = 0.0;
      double rate = 0.0;
      double disPer = 0.0;
      double igstRate = 12.0;
      double igstVal = 0.0;
      double amount = 0.0;

      if (numbers.length >= 7) {
        // [N.MRP, OLD_MRP, Rate, Dis, IGST, IGST_Val, Amount]
        netMrp = numbers[0];
        oldMrp = numbers[1];
        rate = numbers[2];
        disPer = numbers[3];
        igstRate = numbers[4];
        igstVal = numbers[5];
        amount = numbers[6];
      } else if (numbers.length == 6) {
        // [M.R.P, Rate, Dis, IGST, IGST_Val, Amount]
        netMrp = numbers[0];
        rate = numbers[1];
        disPer = numbers[2];
        igstRate = numbers[3];
        igstVal = numbers[4];
        amount = numbers[5];
      } else if (numbers.length >= 2) {
        netMrp = numbers[0];
        rate = numbers.length > 2 ? numbers[1] : (netMrp * 0.7);
        amount = numbers.last;
      }

      if (amount <= 0.0) amount = qty * rate;
      if (igstVal <= 0.0) igstVal = amount * (igstRate / 100);

      items.add(MedilenteItem(
        srNo: srNo,
        hsn: hsn,
        productName: productName,
        pack: pack,
        qty: qty,
        freeQty: freeQty,
        batch: batch,
        mfg: mfg,
        exp: exp,
        netMrp: netMrp,
        oldMrp: oldMrp,
        rate: rate,
        discountPer: disPer,
        igstRate: igstRate,
        igstValue: igstVal,
        amount: amount,
        originalPack: pack,
        conversionFactor: 1,
      ));
    }

    if (items.isEmpty) {
      throw Exception("Could not find table rows in PDF.");
    }

    double taxableTotal = items.fold(0.0, (sum, it) => sum + it.amount);
    double igstTotal = items.fold(0.0, (sum, it) => sum + it.igstValue);
    if (rawGrandTotal <= 0.0) {
      rawGrandTotal = taxableTotal + igstTotal + rawRoundOff;
    }

    return MedilenteBill(
      invoiceNo: invoiceNo,
      invoiceDate: invoiceDate,
      supplierName: supplierName,
      supplierGstin: supplierGstin,
      supplierPan: supplierPan,
      supplierDl: supplierDl,
      supplierEmail: supplierEmail,
      supplierPhone: supplierPhone,
      supplierAddress: supplierAddress,
      buyerName: buyerName,
      buyerGstin: buyerGstin,
      items: items,
      taxableTotal: rawTaxable > 0 ? rawTaxable : taxableTotal,
      igstTotal: rawIgst > 0 ? rawIgst : igstTotal,
      roundOff: rawRoundOff,
      grandTotal: rawGrandTotal,
    );
  }
}
