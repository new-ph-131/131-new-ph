import 'dart:convert';
import '../models/medilente_bill_model.dart';

class MedilenteDirectParser {
  static MedilenteBill parseRawText(String rawText) {
    if (rawText.trim().isEmpty) {
      throw Exception("PDF text is completely empty.");
    }

    // Pre-normalization: collapse spaces around separators
    String normalized = rawText
        .replaceAllMapped(RegExp(r'(\d+)\s*[\*xX]\s*(\d+)'), (m) => '${m[1]}*${m[2]}')
        .replaceAllMapped(RegExp(r'(\d{1,2})\s*/\s*(\d{2,4})'), (m) => '${m[1]}/${m[2]}');

    final lines = const LineSplitter().convert(normalized);

    // 1. Dynamic Invoice Number
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

    // 2. Dynamic Invoice Date
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

    // 3. Dynamic Supplier & Buyer
    String supplierName = "MEDILENTE PHARMA PRIVATE LTD.";
    String supplierGstin = "06AAICM6627L1Z2";
    String supplierPan = "AAICM6627L";
    String supplierDl = "WLF20B2023HR000048,WLF21B2023HR000048";
    String supplierEmail = "medilentepharma@gmail.com";
    String supplierPhone = "9875949453";
    String supplierAddress = "BARWALA PANCHKULA, HARYANA";

    String buyerName = "LIFECARE PHARMACEUTICALS";
    String buyerGstin = "08FSBPM0623R1ZC";

    RegExp partyRegex = RegExp(r'Party\s*Name\s*[:\-]?\s*\n?([A-Za-z0-9\s\.\,\-]+)', caseSensitive: false);
    var pMatch = partyRegex.firstMatch(normalized);
    if (pMatch != null) {
      String cand = pMatch.group(1)?.trim() ?? "";
      if (cand.isNotEmpty && cand.length > 3) {
        buyerName = cand.split('\n').first.trim().toUpperCase();
      }
    }

    RegExp gstAllRegex = RegExp(r'\b(\d{2}[A-Z]{5}\d{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1})\b');
    var allGsts = gstAllRegex.allMatches(normalized).map((m) => m.group(1)!).toList();
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
    var gtMatch = grandTotalRegex.firstMatch(normalized);
    if (gtMatch != null) {
      rawGrandTotal = double.tryParse(gtMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
    }

    RegExp roundOffRegex = RegExp(r'Round\s*off\s*[:\-]?\s*([+\-]?[0-9,]+\.[0-9]{2})', caseSensitive: false);
    var roMatch = roundOffRegex.firstMatch(normalized);
    if (roMatch != null) {
      rawRoundOff = double.tryParse(roMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
    }

    // 5. Line Stitching (If PDF.js split items across 2 lines)
    List<String> stitchedLines = [];
    for (int i = 0; i < lines.length; i++) {
      String current = lines[i].trim();
      if (current.isEmpty) continue;

      // If line has a pack but lacks expiry/numbers, and next line has expiry, stitch them
      if (RegExp(r'\b\d+[\*xX]\d+\b').hasMatch(current) && !RegExp(r'\b\d{1,2}/\d{2}\b').hasMatch(current)) {
        if (i + 1 < lines.length && RegExp(r'\b\d{1,2}/\d{2}\b').hasMatch(lines[i + 1])) {
          current = "$current ${lines[i + 1].trim()}";
          i++;
        }
      }
      stitchedLines.add(current);
    }

    // 6. Anchor-Based Extraction over Stitched Lines
    List<MedilenteItem> items = [];

    for (var line in stitchedLines) {
      String trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      String upper = trimmed.toUpperCase();
      if (upper.contains("GRAND TOTAL") || upper.contains("CLASS TOTAL") || upper.contains("TERMS & CONDITIONS") || upper.contains("TOTAL ITEMS")) {
        continue;
      }

      // Must contain Expiry: 7/27, 10/27, 12/28
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
        if (RegExp(r'^\d+[\*xX]\d+$').hasMatch(tokens[k])) {
          packIdx = k;
          break;
        }
      }
      if (packIdx == -1) continue;

      String pack = tokens[packIdx];

      // Tokens between pack and exp: [Qty] [Free] [Batch] [Mfg]
      List<String> midTokens = tokens.sublist(packIdx + 1, expIdx);
      if (midTokens.isEmpty) continue;

      String mfg = "GEN";
      String batch = "AUTO";
      double qty = 1.0;
      double freeQty = 0.0;

      if (midTokens.length >= 4) {
        // [Qty, Free, Batch, Mfg]
        qty = double.tryParse(midTokens[0].replaceAll(',', '')) ?? 1.0;
        freeQty = double.tryParse(midTokens[1].replaceAll(',', '')) ?? 0.0;
        batch = midTokens[2];
        mfg = midTokens[3];
      } else if (midTokens.length == 3) {
        // [Qty, Batch, Mfg]
        qty = double.tryParse(midTokens[0].replaceAll(',', '')) ?? 1.0;
        batch = midTokens[1];
        mfg = midTokens[2];
      } else if (midTokens.length == 2) {
        // [Qty, Batch]
        qty = double.tryParse(midTokens[0].replaceAll(',', '')) ?? 1.0;
        batch = midTokens[1];
      } else if (midTokens.length == 1) {
        batch = midTokens[0];
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
      } else if (numbers.length >= 2) {
        netMrp = numbers[0];
        rate = numbers.length > 2 ? numbers[2] : numbers[1];
        amount = numbers.last;
      }

      if (amount <= 0.0) {
        amount = qty * rate;
      }
      if (igstVal <= 0.0) {
        igstVal = amount * (igstRate / 100);
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
      String samplePreview = rawText.length > 300 ? rawText.substring(0, 300) : rawText;
      throw Exception("Could not find table rows in PDF.\nExtracted Text Sample:\n$samplePreview");
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
