// FILE: lib/web_live_sync/pdf/web_voucher_pdf.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../web_models.dart';
import '../pharoah_web_manager.dart';
import 'package:pharoah_erp/pdf/pdf_master_service.dart';

class WebVoucherPdf {
  static const PdfPageFormat a6Portrait = PdfPageFormat(
    105 * PdfPageFormat.mm, 
    148 * PdfPageFormat.mm, 
    marginAll: 5 * PdfPageFormat.mm,
  );

  static Future<Uint8List> generateBytes(Voucher v, Party party, CompanyProfile shop, PharoahWebManager ph) async {
    final pdf = pw.Document();
    bool isReceipt = v.type == "Receipt";

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
          pw.Column(children: [
            pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text(shop.address.toUpperCase(), style: const pw.TextStyle(fontSize: 5.5), textAlign: pw.TextAlign.center, maxLines: 2),
            pw.Text("GSTIN: ${shop.gstin} | Mob: ${shop.phone}", style: const pw.TextStyle(fontSize: 5.5)),
            pw.SizedBox(height: 4),
            pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
              child: pw.Column(children: [
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(2),
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                  child: pw.Center(child: pw.Text("${v.type.toUpperCase()} VOUCHER", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text("Voucher No: ${v.voucherNo}", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Date: ${DateFormat('dd-MM-yyyy').format(v.date)}", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                  ]),
                ),
                if (v.paymentMode == "Bank" && v.chequeNo.isNotEmpty)
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.3, style: pw.BorderStyle.dashed))),
                    child: pw.Text("CHQ NO: ${v.chequeNo}  |  DATED: ${v.chequeDate != null ? DateFormat('dd-MM-yyyy').format(v.chequeDate!) : 'N/A'}", 
                      style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
                  ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5), bottom: pw.BorderSide(width: 0.5))),
                  child: pw.Row(children: [
                    pw.Expanded(flex: 5, child: pw.Text("Particulars", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(flex: 2, child: pw.Text("Debit", textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(flex: 2, child: pw.Text("Credit", textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                  ]),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(5), 
                  child: pw.Column(children: [
                    pw.Row(children: [
                      pw.Expanded(flex: 5, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text(isReceipt ? v.depositedIn.toUpperCase() : party.name.toUpperCase(), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                        if (!isReceipt) pw.Text("GST: ${party.gst} | ${party.city}", style: const pw.TextStyle(fontSize: 5)),
                      ])),
                      pw.Expanded(flex: 2, child: pw.Text(v.amount.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7.5))),
                      pw.Expanded(flex: 2, child: pw.Text("", textAlign: pw.TextAlign.right)),
                    ]),
                    pw.SizedBox(height: 4),
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
                if (adjList.isNotEmpty)
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(3),
                    decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.3, style: pw.BorderStyle.dashed))),
                    child: pw.Text("ADJ AGAINST: ${adjList.join(', ')}", style: const pw.TextStyle(fontSize: 5.5), maxLines: 2),
                  ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
                  child: pw.Row(children: [
                    pw.Expanded(flex: 5, child: pw.Text("TOTAL", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(flex: 2, child: pw.Text(v.amount.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(flex: 2, child: pw.Text(v.amount.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                  ]),
                ),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(4),
                  decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text("Rupees ${PdfMasterService.numberToWords(v.amount.round())} Only", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                    if (v.narration.isNotEmpty)
                      pw.Text("Remarks: ${v.narration}", style: pw.TextStyle(fontSize: 5.5, fontStyle: pw.FontStyle.italic)),
                  ]),
                ),
              ]),
            ),
            pw.Spacer(),
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
            pw.Text("System Generated Document via Pharoah ERP Web", style: const pw.TextStyle(fontSize: 4, color: PdfColors.grey500)),
          ]),
        ]);
      },
    ));
    return pdf.save();
  }
}
