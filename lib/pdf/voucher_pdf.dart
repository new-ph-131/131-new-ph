// FILE: lib/pdf/voucher_pdf.dart (FINAL COMPLETED & FIXED VERSION)

import 'dart:io';
import 'dart:typed_data'; // 🔥 FIXED: Added for Uint8List
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../pharoah_manager.dart';
import '../gateway/company_registry_model.dart';
import 'pdf_master_service.dart';

class VoucherPdf {
  // --- DIMENSION: A6 Portrait (105mm x 148mm) - Perfect 1/4 of A4 ---
  static const PdfPageFormat a6Portrait = PdfPageFormat(
    105 * PdfPageFormat.mm, 
    148 * PdfPageFormat.mm, 
    marginAll: 5 * PdfPageFormat.mm,
  );

  // ===========================================================================
  // 🖨️ 1. DIRECT PRINT METHOD
  // ===========================================================================
  static Future<void> generate(Voucher v, Party party, CompanyProfile shop, PharoahManager ph) async {
    try {
      final bytes = await generateBytes(v, party, shop, ph);
      await Printing.layoutPdf(
        onLayout: (format) async => bytes, 
        name: 'Voucher_${v.voucherNo}',
        format: a6Portrait,
      );
    } catch (e) {
      print("Voucher Print Error: $e");
    }
  }

  // ===========================================================================
  // 📧 2. GENERATE BYTES METHOD (For Email & Printing - Common Logic)
  // ===========================================================================
  static Future<Uint8List> generateBytes(Voucher v, Party party, CompanyProfile shop, PharoahManager ph) async {
    final pdf = pw.Document();
    bool isReceipt = v.type == "Receipt";

    // --- LOGIC: Bill Adjustment with Dates ---
    List<String> adjList = [];
    for (var bNo in v.linkedBillNumbers) {
      String dateStr = "";
      try {
        if (isReceipt) {
          final s = ph.sales.firstWhere((element) => element.billNo == bNo);
          dateStr = DateFormat('dd/MM').format(s.date);
        } else {
          final p = ph.purchases.firstWhere((element) => element.billNo == bNo);
          dateStr = DateFormat('dd/MM').format(p.date);
        }
        adjList.add("$bNo ($dateStr)");
      } catch (e) {
        adjList.add(bNo);
      }
    }

    pdf.addPage(pw.Page(
      pageFormat: a6Portrait,
      build: (pw.Context context) {
        return pw.Stack(children: [
          // 1. ADVANCED SHADOW WATERMARK (Centered for A6)
          pw.Center(
            child: pw.Opacity(
              opacity: 0.05,
              child: pw.Transform.rotate(
                angle: 0.5,
                child: pw.Text(shop.name.toUpperCase(), 
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ),
          ),

          // 2. MAIN LAYOUT CONTENT
          pw.Column(children: [
            // SHOP HEADER
            pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text(shop.address.toUpperCase(), 
              style: const pw.TextStyle(fontSize: 5.5), textAlign: pw.TextAlign.center, maxLines: 2),
            pw.Text("GSTIN: ${shop.gstin} | Mob: ${shop.phone}", style: const pw.TextStyle(fontSize: 5.5)),
            
            pw.SizedBox(height: 4),

            // MAIN VOUCHER BOX
            pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
              child: pw.Column(children: [
                // Type Header Bar
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(2),
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                  child: pw.Center(child: pw.Text("${v.type.toUpperCase()} VOUCHER", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                ),

                // Voucher No & Date Row
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text("Voucher No: ${v.voucherNo}", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Date: ${DateFormat('dd-MM-yyyy').format(v.date)}", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                  ]),
                ),

                // CHEQUE/BANK INFO (Only if applicable)
                if (v.paymentMode == "Bank" && v.chequeNo.isNotEmpty)
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.3, style: pw.BorderStyle.dashed))),
                    child: pw.Text("CHQ NO: ${v.chequeNo}  |  DATED: ${v.chequeDate != null ? DateFormat('dd-MM-yyyy').format(v.chequeDate!) : 'N/A'}", 
                      style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
                  ),

                // TABLE HEADER
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5), bottom: pw.BorderSide(width: 0.5))),
                  child: pw.Row(children: [
                    pw.Expanded(flex: 5, child: pw.Text("Particulars", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(flex: 2, child: pw.Text("Debit", textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(flex: 2, child: pw.Text("Credit", textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                  ]),
                ),

                // LEDGER TRANSACTIONS (High Density Area)
                pw.Container(
                  padding: const pw.EdgeInsets.all(5), // 🔥 FIXED: pw. prefix not needed here if using widgets.dart correctly, but kept simple
                  child: pw.Column(children: [
                    // ROW 1: Principal Ledger
                    pw.Row(children: [
                      pw.Expanded(flex: 5, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text(isReceipt ? v.depositedIn.toUpperCase() : party.name.toUpperCase(), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                        if (!isReceipt) pw.Text("GST: ${party.gst} | ${party.city}", style: const pw.TextStyle(fontSize: 5)),
                      ])),
                      pw.Expanded(flex: 2, child: pw.Text(v.amount.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7.5))),
                      pw.Expanded(flex: 2, child: pw.Text("", textAlign: pw.TextAlign.right)),
                    ]),
                    pw.SizedBox(height: 4),
                    // ROW 2: Counter Ledger
                    pw.Row(children: [
                      pw.Expanded(flex: 5, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text(isReceipt ? party.name.toUpperCase() : v.depositedIn.toUpperCase(), style: const pw.TextStyle(fontSize: 7.5)),
                        if (isReceipt) pw.Text("GST: ${party.gst} | ${party.city}", style: const pw.TextStyle(fontSize: 5)),
                      ])),
                      pw.Expanded(flex: 2, child: pw.Text("", textAlign: pw.TextAlign.right)),
                      pw.Expanded(flex: 2, child: pw.Text(v.amount.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7.5))),
                    ]),
                  ]),
                ),

                // BILL ADJUSTMENT STRIP
                if (adjList.isNotEmpty)
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(3),
                    decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.3, style: pw.BorderStyle.dashed))),
                    child: pw.Text("ADJ AGAINST: ${adjList.join(', ')}", 
                      style: const pw.TextStyle(fontSize: 5.5), maxLines: 2),
                  ),

                // TOTAL ROW
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
                  child: pw.Row(children: [
                    pw.Expanded(flex: 5, child: pw.Text("TOTAL", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(flex: 2, child: pw.Text(v.amount.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(flex: 2, child: pw.Text(v.amount.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                  ]),
                ),

                // WORDS & NARRATION
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(4),
                  decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text("Rupees ${PdfMasterService.numberToWords(v.amount.round())} Only", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                    if (v.narration.isNotEmpty)
                      pw.Text("Remarks: ${v.narration}", style: const pw.TextStyle(fontSize: 5.5, fontStyle: pw.FontStyle.italic)),
                  ]),
                ),
              ]),
            ),

            pw.Spacer(),

            // AUTHORISED SIGNATORY FOOTER
            pw.Container(
              width: double.infinity,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text("Authorised Signatory for", style: const pw.TextStyle(fontSize: 6)),
                pw.SizedBox(height: 1),
                pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 15),
                pw.Container(width: 70, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5)))),
              ]),
            ),
            pw.SizedBox(height: 2),
            pw.Text("System Generated Document via Pharoah ERP", 
              style: const pw.TextStyle(fontSize: 4, color: PdfColors.grey500)),
          ]),
        ]);
      },
    ));

    return pdf.save();
  }
}
