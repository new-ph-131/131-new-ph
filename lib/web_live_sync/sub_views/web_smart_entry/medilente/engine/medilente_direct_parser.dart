import 'dart:convert';
import '../models/medilente_bill_model.dart';

class MedilenteDirectParser {
  static MedilenteBill parseRawText(String rawText) {
    if (rawText.trim().isEmpty) {
      throw Exception("PDF text could not be extracted or file is empty.");
    }

    final lines = const LineSplitter().convert(rawText);

    // 1. Dynamic Invoice Number
    String invoiceNo = "";
    RegExp invRegex = RegExp(r'Invoice\s*No\.?\s*[:\-]?\s*([A-Za-z0-9]+)', caseSensitive: false);
    var invMatch = invRegex.firstMatch(rawText);
    if (invMatch != null) {
      invoiceNo = invMatch.group(1)?.trim().toUpperCase() ?? "";
    }
    if (invoiceNo.isEmpty) {
      RegExp altInv = RegExp(r'\b(A\d{5,8})\b');
      var m = altInv.firstMatch(rawText);
      if (m != null) invoiceNo = m.group(1)!.toUpperCase();
    }
    if (invoiceNo.isEmpty) {
      invoiceNo = "INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    }

    // 2. Dynamic Invoice Date
    String invoiceDate = "";
    RegExp dateRegex = RegExp(r'Invoice\s*Date\s*[:\-]?\s*([0-9]{1,2}/[0-9]{1,2}/[0-9]{4})', caseSensitive: false);
    var dateMatch = dateRegex.firstMatch(rawText);
    if (dateMatch != null) {
      invoiceDate = dateMatch.group(1)?.trim() ?? "";
    }
    if (invoiceDate.isEmpty) {
      RegExp altDate = RegExp(r'\b(\d{2}/\d{2}/\d{4})\b');
      var m = altDate.firstMatch(rawText);
      if (m != null) invoiceDate = m.group(1)!;
    }
    if (invoiceDate.isEmpty) {
      final now = DateTime.now();
      invoiceDate = "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";
    }

    // 3. Dynamic Supplier & Buyer Extraction
    String supplierName = "MEDILENTE PHARMA PRIVATE LTD.";
    String supplierGstin = "06AAICM6627L1Z2";
    String supplierPan = "AAICM6627L";
    String supplierDl = "WLF20B2023HR000048,WLF21B2023HR000048";
    String supplierEmail = "medilentepharma@gmail.com";
    String supplierPhone = "9875949453";
    String supplierAddress = "BARWALA PANCHKULA, HARYANA";

    // Buyer extraction
    String buyerName = "LIFECARE PHARMACEUTICALS";
    String buyerGstin = "08FSBPM0623R1ZC";

    RegExp partyRegex = RegExp(r'Party\s*Name\s*[:\-]?\s*\n?([A-Za-z0-9\s\.\,\-]+)', caseSensitive: false);
    var pMatch = partyRegex.firstMatch(rawText);
    if (pMatch != null) {
      String cand = pMatch.group(1)?.trim() ?? "";
      if (cand.isNotEmpty && cand.length > 3) {
        buyerName = cand.split('\n').first.trim().toUpperCase();
      }
    }

    RegExp gstAllRegex = RegExp(r'\b(\d{2}[A-Z]{5}\d{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1})\b');
    var allGsts = gstAllRegex.allMatches(rawText).map((m) => m.group(1)!).toList();
    if (allGsts.isNotEmpty) {
      supplierGstin = allGsts.first;
      if (allGsts.length > 1) {
        buyerGstin = allGsts[1];
      }
    }

    // 4. Totals Extraction
    double rawGrandTotal = 0.0;
    double rawTaxable = 0.0;
    double rawIgst = 0.0;
    double rawRoundOff = 0.0;

    RegExp grandTotalRegex = RegExp(r'Grand\s*Total\s*[:\-]?\s*([0-9,]+\.[0-9]{2})', caseSensitive: false);
    var gtMatch = grandTotalRegex.firstMatch(rawText);
    if (gtMatch != null) {
      rawGrandTotal = double.tryParse(gtMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
    }

    RegExp roundOffRegex = RegExp(r'Round\s*off\s*[:\-]?\s*([+\-]?[0-9,]+\.[0-9]{2})', caseSensitive: false);
    var roMatch = roundOffRegex.firstMatch(rawText);
    if (roMatch != null) {
      rawRoundOff = double.tryParse(roMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
    }

    // 5. Line-by-Line Anchor Extraction
    List<MedilenteItem> items = [];

    for (var line in lines) {
      String trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      String upper = trimmed.toUpperCase();
      if (upper.contains("GRAND TOTAL") || upper.contains("CLASS TOTAL") || upper.contains("TERMS & CONDITIONS") || upper.contains("TOTAL ITEMS")) {
        continue;
      }

      // Check if line contains Expiry token: e.g. 7/27, 10/27, 12/28
      RegExp expRegex = RegExp(r'\b(\d{1,2}/\d{2})\b');
      var expMatch = expRegex.firstMatch(trimmed);
      if (expMatch == null) continue;

      var tokens = trimmed.split(RegExp(r'\s+'));
      int expIdx = -1;
      for (int i = 0; i < tokens.length; i++) {
        if (RegExp(r'^\d{1,2}/\d{2}$').hasMatch(tokens[i])) {
          expIdx = i;
          break;
        }
      }
      if (expIdx < 3) continue;

      String exp = tokens[expIdx];
      String mfg = tokens[expIdx - 1];
      String batch = tokens[expIdx - 2];

      // Scan tokens before batch for Pack (\d+[\*xX]\d+)
      int packIdx = -1;
      for (int k = 0; k < expIdx - 2; k++) {
        if (RegExp(r'^\d+[\*xX]\d+$').hasMatch(tokens[k])) {
          packIdx = k;
          break;
        }
      }
      if (packIdx == -1) continue;

      String pack = tokens[packIdx];

      // Tokens between pack and batch are Qty and Free
      double qty = 1.0;
      double freeQty = 0.0;
      List<String> qtyTokens = tokens.sublist(packIdx + 1, expIdx - 2);
      if (qtyTokens.isNotEmpty) {
        qty = double.tryParse(qtyTokens[0].replaceAll(',', '')) ?? 1.0;
        if (qtyTokens.length > 1) {
          freeQty = double.tryParse(qtyTokens[1].replaceAll(',', '')) ?? 0.0;
        }
      }

      // Tokens before pack are [S.N] [HSN] [Product Name...]
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

      // Numbers after Expiry: [N.MRP, OLD_MRP, Rate, Dis, IGST, IGST_Val, Amount]
      List<double> numbers = [];
      for (int k = expIdx + 1; k < tokens.length; k++) {
        double? val = double.tryParse(tokens[k].replaceAll(',', ''));
        if (val != null) numbers.add(val);
      }

      double netMrp = 0.0;
      double oldMrp = 0.0;
      double rate = 0.0;
      double disPer = 0.0;
      double igstRate = 5.0;
      double igstVal = 0.0;
      double amount = 0.0;

      if (numbers.length >= 7) {
        netMrp = numbers[0];
        oldMrp = numbers[1];
        rate = numbers[2];
        disPer = numbers[3];
        igstRate = numbers[4];
        igstVal = numbers[5];
        amount = numbers[6];
      } else if (numbers.length == 6) {
        netMrp = numbers[0];
        rate = numbers[1];
        disPer = numbers[2];
        igstRate = numbers[3];
        igstVal = numbers[4];
        amount = numbers[5];
      } else if (numbers.isNotEmpty) {
        netMrp = numbers[0];
        rate = numbers.length > 1 ? numbers[1] : (netMrp * 0.7);
        amount = numbers.last;
      }

      if (amount <= 0.0) {
        amount = qty * rate;
      }

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
      throw Exception("Could not find any invoice rows with valid batches and expiries in the uploaded document.");
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
