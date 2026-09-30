// FILE: lib/pdf/credit_note_pdf.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../gateway/company_registry_model.dart';
import '../logic/app_settings_model.dart';
import 'pdf_master_service.dart';

class CreditNotePdf {
  // 1. PRINT / PREVIEW
  static Future<void> generate(SaleReturn ret, Party party, CompanyProfile shop, AppConfig config) async {
    final bytes = await generateBytes(ret, party, shop, config);
    await Printing.layoutPdf(onLayout: (format) async => bytes, name: 'CreditNote_${ret.billNo}', format: PdfPageFormat.a4.landscape);
  }

  // 2. GENERATE BYTES FOR EMAIL / DISPATCH (Fixed Future type & FontWeights)
  static Future<Uint8List> generateBytes(SaleReturn ret, Party party, CompanyProfile shop, AppConfig config) async {
    final pdf = pw.Document();
    const double masterWidth = 800; 
    const int itemsPerPage = 20;
    String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
    bool isLocal = shop.state.trim().toLowerCase() == party.state.trim().toLowerCase();

    final sellable = ret.items.where((i) => i.isBreakage == false).toList();
    final breakage = ret.items.where((i) => i.isBreakage == true).toList();

    List<dynamic> combinedList = [];
    if (sellable.isNotEmpty) { combinedList.add(">> SALES RETURN (SELLABLE STOCK)"); combinedList.addAll(sellable); }
    if (breakage.isNotEmpty) { combinedList.add(">> BREAKAGE & EXPIRY (NON-SELLABLE)"); combinedList.addAll(breakage); }

    int totalPages = (combinedList.length / itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    for (int pageNum = 0; pageNum < totalPages; pageNum++) {
      int start = pageNum * itemsPerPage;
      int end = (start + itemsPerPage < combinedList.length) ? start + itemsPerPage : combinedList.length;
      List<dynamic> pageContent = combinedList.sublist(start, end);
      bool isLastPage = (pageNum == totalPages - 1);

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15), // 🆕 Strictly locked to 15 vertical margin
        build: (pw.Context context) => pw.Column(children: [
          pw.Container(
            width: masterWidth,
            height: 550, // 🆕 Height strictly locked to 550 points (pageHeightLimit)
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
            child: pw.Column(children: [
              // --- BOX HEADER (800pt FIXED) ---
              pw.Row(children: [
                _hBox(280, true, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text(shop.address, style: const pw.TextStyle(fontSize: 7), maxLines: 2),
                  pw.Text("GSTIN: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                ])),
                _hBox(175, true, pw.Column(children: [
                  pw.Text("CREDIT NOTE", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                  pw.Divider(thickness: 0.5),
                  pw.Text("CN: ${ret.billNo}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(DateFormat('dd/MM/yyyy').format(ret.date), style: const pw.TextStyle(fontSize: 8)),
                ])),
                _hBox(345, false, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text("CONSIGNEE:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                  pw.Text(party.name.toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text("GST: ${party.gst}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ])),
              ]),

              // --- TABLE HEADER ---
              pw.Container(color: PdfColors.grey200, child: pw.Row(children: [
                _tCol("S.N", 25), _tCol("Qty+Free", 50), _tCol("Pack", 40), _tCol("Description", 210, isLeft: true), 
                _tCol("Batch", 70), _tCol("Exp", 45), _tCol("HSN", 45), _tCol("MRP", 55), _tCol("Rate", 55), 
                _tCol("CGST", 40), _tCol("SGST", 40), _tCol("Total", 125, isLast: true), 
              ])),

              // --- SMART CONTENT ---
              pw.Expanded(child: pw.Column(children: pageContent.map((entry) {
                if (entry is String) return pw.Container(width: masterWidth, padding: const pw.EdgeInsets.all(3), decoration: const pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border(bottom: pw.BorderSide(width: 0.5))), child: pw.Text(entry, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)));
                BillItem i = entry as BillItem;
                return pw.Container(decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))), child: pw.Row(children: [
                    _cell("${ret.items.indexOf(i) + 1}", 25), _cell("${fmt(i.qty)}+${fmt(i.freeQty)}", 50), _cell(i.packing, 40),
                    pw.Container(width: 210, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft, child: pw.Text(i.name, style: const pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                    _cell(i.batch, 70), _cell(i.exp, 45), _cell(i.hsn, 45), _cell(i.mrp.toStringAsFixed(2), 55), _cell(i.rate.toStringAsFixed(2), 55),
                    _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40), _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40),
                    _cell(i.total.toStringAsFixed(2), 125),
                ]));
              }).toList())),

              if (isLastPage) _buildFooter(shop.name, ret, isLocal)
            ]),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "This is a system-generated document. | Powered by Pharoah ERP [Download from Play Store] | Support: cloudcubeapps.ok@gmail.com",
              style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey600),
            ),
          ),
        ])
      ));
    }
    return pdf.save();
  }

  static pw.Widget _hBox(double w, bool b, pw.Widget child) => pw.Container(width: w, height: 105, padding: const pw.EdgeInsets.all(5), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: b ? 0.5 : 0), bottom: const pw.BorderSide(width: 0.5))), child: child);
  static pw.Widget _tCol(String t, double w, {bool isLast = false, bool isLeft = false}) => pw.Container(width: w, height: 20, alignment: isLeft ? pw.Alignment.centerLeft : pw.Alignment.center, padding: pw.EdgeInsets.only(left: 5), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: isLast ? 0 : 0.5), bottom: const pw.BorderSide(width: 0.5))), child: pw.Text(t, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)));
  static pw.Widget _cell(String t, double w) => pw.Container(width: w, height: 18, alignment: pw.Alignment.center, decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.2, color: PdfColors.grey))), child: pw.Text(t, style: const pw.TextStyle(fontSize: 7.5)));

  static pw.Widget _buildFooter(String n, SaleReturn ret, bool local) {
    double taxable = ret.items.fold(0.0, (s, i) => s + (i.qty * i.rate));
    double tax = ret.totalAmount - taxable;
    return pw.Container(height: 110, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))), child: pw.Row(children: [
      pw.Container(width: 320, padding: const pw.EdgeInsets.all(5), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text("Amount: RUPEES ${PdfMasterService.numberToWords(ret.totalAmount.round())} ONLY", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
        pw.Spacer(),
        pw.Text("Verified return account settlement.", style: const pw.TextStyle(fontSize: 7)),
      ])),
      pw.Container(width: 250, padding: const pw.EdgeInsets.all(5), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))), child: pw.Column(children: [
        _fRow("TAXABLE VAL", taxable),
        if (ret.extraDiscount > 0) _fRow("EXTRA DISCOUNT (-)", ret.extraDiscount),
        if (ret.roundOff != 0) _fRow("ROUND OFF", ret.roundOff),
        if (local) ...[_fRow("CGST TOTAL", tax / 2), _fRow("SGST TOTAL", tax / 2)] else _fRow("IGST TOTAL", tax),
        pw.Divider(thickness: 0.5),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text("NET CREDIT", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text("Rs. ${ret.totalAmount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ]),
      ])),
      pw.Container(width: 230, padding: const pw.EdgeInsets.all(8), child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text("For $n", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)), pw.Text("Authorised Signatory", style: const pw.TextStyle(fontSize: 7))])),
    ]));
  }
  static pw.Widget _fRow(String l, double v) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(l, style: const pw.TextStyle(fontSize: 7.5)), pw.Text(v.toStringAsFixed(2), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))]);
}
