// FILE: lib/pdf/sale_invoice_pdf.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../gateway/company_registry_model.dart';
import 'pdf_master_service.dart';

class SaleInvoicePdf {
  static Future<void> generate(Sale sale, Party party, CompanyProfile shop) async {
    final bytes = await generateBytes(sale, party, shop);
    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: 'Invoice_${sale.billNo}',
      format: PdfPageFormat.a4.landscape,
    );
  }

  static Future<Uint8List> generateBytes(Sale sale, Party party, CompanyProfile shop) async {
    final pdf = pw.Document();
    const double masterWidth = 800; // Perfect 800pt width
    const int itemsPerPage = 20; 
    int totalPages = (sale.items.length / itemsPerPage).ceil();
    bool isLocal = shop.state.trim().toLowerCase() == sale.partyState.trim().toLowerCase();

    String fmt(double val) => val == val.toInt() ? val.toInt().toString() : val.toStringAsFixed(2);

 for (int pageNum = 0; pageNum < totalPages; pageNum++) {
      int start = pageNum * itemsPerPage;
      int end = (start + itemsPerPage < sale.items.length) ? start + itemsPerPage : sale.items.length;
      List<BillItem> pageItems = sale.items.sublist(start, end);
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
              // --- HEADER (280+170+350 = 800) ---
              pw.Row(children: [
                // Box 1: Company Profile (Width: 280)
                _hBox(280, true, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text(shop.address, style: const pw.TextStyle(fontSize: 7), maxLines: 2),
                  pw.Text("GSTIN: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Mob: ${shop.phone} | Email: ${shop.email.toLowerCase()}", style: const pw.TextStyle(fontSize: 7)),
                ])),
                // Box 2: Invoice Info (Width: 175)
                _hBox(175, true, pw.Column(children: [
                  pw.Text("TAX INVOICE", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text(sale.paymentMode.toUpperCase(), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Divider(thickness: 0.5),
                  pw.Text("No: ${sale.billNo}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(DateFormat('dd/MM/yyyy').format(sale.date), style: const pw.TextStyle(fontSize: 8)),
                ])),
                // Box 3: Party Details (Width: 345)
                _hBox(345, false, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text("CONSIGNEE:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                  pw.Text(sale.partyName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text("${sale.partyAddress}, ${sale.partyCity}", style: const pw.TextStyle(fontSize: 7.5), maxLines: 2),
                  pw.Text("GST: ${sale.partyGstin} | DL: ${sale.partyDl}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Mob: ${sale.partyPhone} | Email: ${sale.partyEmail}", style: const pw.TextStyle(fontSize: 7)),
                ])),
              ]),

          // --- TABLE HEADER (800 POINTS ALIGNED) ---
pw.Container(color: PdfColors.grey200, child: pw.Row(children: [
  _tCol("S.N", 25), _tCol("Qty+Free", 60), _tCol("Pack", 40), 
  _tCol("Product Description", 220, isLeft: true), 
  _tCol("Batch", 70), _tCol("Exp", 45), _tCol("HSN", 45),
  _tCol("MRP", 55), _tCol("Rate", 55), 
  if (isLocal) ...[
    _tCol("CGST", 40),
    _tCol("SGST", 40),
  ] else ...[
    _tCol("IGST", 80),
  ],
  _tCol("Net Amt", 100, isLast: true), 
])),

              // --- ITEM ROWS ---
              pw.Expanded(child: pw.Column(children: pageItems.asMap().entries.map((entry) {
                int idx = entry.key; var i = entry.value;
                
                // NAYA: Decimal formatting logic
                String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
                String qtyDisplay = "${fmt(i.qty)} + ${fmt(i.freeQty)}";

              return pw.Container(
  decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
  child: pw.Row(children: [
    _cell("${start + idx + 1}", 25), 
    _cell(qtyDisplay, 60), 
    _cell(i.packing, 40), 
    pw.Container(width: 220, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft, child: pw.Text(i.name, style: const pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
    _cell(i.batch, 70), _cell(i.exp, 45), _cell(i.hsn, 45),
    _cell(i.mrp.toStringAsFixed(2), 55), _cell(i.rate.toStringAsFixed(2), 55),
    if (isLocal) ...[
      _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40),
      _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40),
    ] else ...[
      _cell("${i.gstRate.toStringAsFixed(1)}%", 80),
    ],
    _cell(i.total.toStringAsFixed(2), 100),
  ]),
);
              }).toList())),

              if (isLastPage) _buildFooter(shop.name, sale, shop, isLocal)
              else pw.Container(height: 30, alignment: pw.Alignment.centerRight, padding: const pw.EdgeInsets.only(right: 20), child: pw.Text("Continued...", style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 8))),
            ]),
          ),
          pw.SizedBox(height: 4), // Professional margins spacer
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
  static pw.Widget _tCol(String t, double w, {bool isLast = false, bool isLeft = false}) => pw.Container(width: w, height: 20, alignment: isLeft ? pw.Alignment.centerLeft : pw.Alignment.center, padding: pw.EdgeInsets.only(left: isLeft ? 5 : 0), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: isLast ? 0 : 0.5), bottom: const pw.BorderSide(width: 0.5))), child: pw.Text(t, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)));
  static pw.Widget _cell(String t, double w) => pw.Container(width: w, height: 18, alignment: pw.Alignment.center, decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.2, color: PdfColors.grey))), child: pw.Text(t, style: const pw.TextStyle(fontSize: 7.5)));

  static pw.Widget _buildFooter(String shopName, Sale sale, CompanyProfile shop, bool isLocal) {
    double taxableTotal = sale.items.fold(0.0, (sum, i) => sum + (i.qty * i.rate));
    double totalTax = sale.items.fold(0.0, (sum, i) => sum + (i.cgst + i.sgst + i.igst));

    return pw.Container(height: 110, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))), child: pw.Row(children: [
      pw.Container(width: 330, padding: const pw.EdgeInsets.all(5), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text("Amount in Words:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
        pw.Text("RUPEES ${PdfMasterService.numberToWords(sale.totalAmount.round())} ONLY", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
        pw.Spacer(),
        pw.Text("Terms: Goods once sold will not be taken back. Disputes subject to local jurisdiction.", style: const pw.TextStyle(fontSize: 6), maxLines: 2),
      ])),
      pw.Container(width: 250, padding: const pw.EdgeInsets.all(5), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))), child: pw.Column(children: [
        _fRow("TAXABLE TOTAL", taxableTotal),
        if (isLocal) ...[
          _fRow("CGST TOTAL", totalTax / 2),
          _fRow("SGST TOTAL", totalTax / 2),
        ] else _fRow("IGST TOTAL", totalTax),
        // NAYA: DISCOUNT LOGIC ADDED HERE
        if (sale.extraDiscount > 0) _fRow("EXTRA DISCOUNT (-)", sale.extraDiscount),
        _fRow("ROUND OFF", sale.roundOff),
        pw.Divider(thickness: 0.5),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text("GRAND TOTAL", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text("Rs. ${sale.totalAmount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ]),
      ])),
      pw.Container(width: 220, padding: const pw.EdgeInsets.all(5), child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text("For $shopName", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 30),
        pw.Text("AUTHORISED SIGNATORY", style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      ])),
    ]));
  }
  static pw.Widget _fRow(String l, double v) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(l, style: const pw.TextStyle(fontSize: 7.5)), pw.Text(v.toStringAsFixed(2), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))]);
}
