// FILE: lib/pdf/architect_sale_pdf.dart (FULLY RESOLVED PRODUCTION CODE - WITH BANK DETAILS ON PRINT)

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

class ArchitectSalePdf {
  // ===========================================================================
  // 🖨️ 1. DIRECT PRINT METHOD
  // ===========================================================================
  static Future<void> generate(Sale sale, Party party, CompanyProfile shop, AppConfig config) async {
    try {
      final bytes = await generateBytes(sale, party, shop, config);
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: 'Architect_Bill_${sale.billNo}',
        format: PdfPageFormat.a4.landscape,
      );
    } catch (e) {
      print("Print Error: $e");
    }
  }

  // ===========================================================================
  // 📧 2. GENERATE BYTES METHOD
  // ===========================================================================
  static Future<Uint8List> generateBytes(Sale sale, Party party, CompanyProfile shop, AppConfig config) async {
    final pdf = pw.Document();
    
    // --- SAFE IMAGE LOADING ENGINE ---
    pw.MemoryImage? logoImage;
    pw.MemoryImage? qrImage;

    try {
      if (config.showLogo && config.logoPath != null) {
        final file = File(config.logoPath!);
        if (await file.exists()) {
          logoImage = pw.MemoryImage(await file.readAsBytes());
        }
      }
      if (config.showQrCode && config.qrCodePath != null) {
        final file = File(config.qrCodePath!);
        if (await file.exists()) {
          qrImage = pw.MemoryImage(await file.readAsBytes());
        }
      }
    } catch (imgError) {
      print("Safe Image Engine: Logo/QR not found, skipping images. $imgError");
    }

    const double masterWidth = 800; 
    const int itemsPerPage = 18; 
    int totalPages = (sale.items.length / itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;
    bool isLocal = shop.state.trim().toLowerCase() == sale.partyState.trim().toLowerCase();

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
              // --- HEADER ---
              pw.Row(children: [
                _hBox(280, true, pw.Row(children: [
                  if (logoImage != null)
                    pw.Container(width: 40, height: 40, margin: const pw.EdgeInsets.only(right: 5), child: pw.Image(logoImage)),
                  pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text(shop.address, style: const pw.TextStyle(fontSize: 7), maxLines: 2),
                    pw.Text("GSTIN: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Mob: ${shop.phone}", style: const pw.TextStyle(fontSize: 6.5)),
                  ])),
                ])),
                _hBox(175, true, pw.Column(children: [
                  pw.Text("TAX INVOICE", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Divider(thickness: 0.5),
                  pw.Text(sale.billNo, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(DateFormat('dd/MM/yyyy').format(sale.date), style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(sale.paymentMode.toUpperCase(), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                ])),
                _hBox(345, false, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text("CONSIGNEE DETAILS:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                  pw.Text(party.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text("${party.address}, ${party.city}", style: const pw.TextStyle(fontSize: 7.5), maxLines: 2),
                  pw.Text("GSTIN: ${party.gst} | DL: ${party.dl}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ])),
              ]),

         // --- TABLE HEADER ---
pw.Container(
  color: PdfColors.grey200, 
  decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
  child: pw.Row(children: [
    _tCol("S.N", 25), _tCol("Qty+Free", 50), _tCol("Pack", 40), 
    _tCol("Product Description", 210, isLeft: true), 
    _tCol("Batch", 70), _tCol("Exp", 45), _tCol("HSN", 45),
    _tCol("MRP", 55), _tCol("Rate", 55), 
    if (isLocal) ...[
      _tCol("CGST", 40),
      _tCol("SGST", 40),
    ] else ...[
      _tCol("IGST", 80),
    ],
    _tCol("Net Total", 125, isLast: true), 
  ]),
),

              // --- ITEM ROWS ---
              pw.Expanded(child: pw.Column(children: pageItems.asMap().entries.map((entry) {
                int idx = entry.key; var i = entry.value;
                bool isShaded = config.useZebraShading && (idx % 2 != 0);
                String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
               return pw.Container(
  color: isShaded ? PdfColors.grey50 : PdfColors.white,
  decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
  child: pw.Row(children: [
    _cell("${start + idx + 1}", 25), _cell("${fmt(i.qty)}+${fmt(i.freeQty)}", 50), _cell(i.packing, 40),
    pw.Container(width: 210, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft, child: pw.Text(i.name, style: const pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
    _cell(i.batch, 70), _cell(i.exp, 45), _cell(i.hsn, 45),
    _cell(i.mrp.toStringAsFixed(2), 55), _cell(i.rate.toStringAsFixed(2), 55),
    if (isLocal) ...[
      _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40),
      _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40),
    ] else ...[
      _cell("${i.gstRate.toStringAsFixed(1)}%", 80),
    ],
    _cell(i.total.toStringAsFixed(2), 125),
  ]),
);
              }).toList())),

              if (isLastPage) _buildArchitectFooter(shop.name, sale, config, shop, isLocal, qrImage)
              else pw.Container(height: 30, alignment: pw.Alignment.centerRight, padding: const pw.EdgeInsets.only(right: 20), child: pw.Text("Next Page...", style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 8))),
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

  // --- HELPERS ---
  static pw.Widget _hBox(double w, bool b, pw.Widget child) => pw.Container(width: w, height: 105, padding: const pw.EdgeInsets.all(5), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: b ? 0.5 : 0), bottom: const pw.BorderSide(width: 0.5))), child: child);
  static pw.Widget _tCol(String t, double w, {bool isLast = false, bool isLeft = false}) => pw.Container(width: w, height: 20, alignment: isLeft ? pw.Alignment.centerLeft : pw.Alignment.center, padding: pw.EdgeInsets.only(left: 5), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: isLast ? 0 : 0.5), bottom: const pw.BorderSide(width: 0.5))), child: pw.Text(t, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)));
  static pw.Widget _cell(String t, double w) => pw.Container(width: w, height: 18, alignment: pw.Alignment.center, decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.2, color: PdfColors.grey))), child: pw.Text(t, style: const pw.TextStyle(fontSize: 7.5)));

  static pw.Widget _buildArchitectFooter(String shopName, Sale sale, AppConfig config, CompanyProfile shop, bool isLocal, pw.MemoryImage? qrImage) {
    double taxableTotal = sale.items.fold(0.0, (sum, i) => sum + (i.qty * i.rate));
    double totalTax = sale.items.fold(0.0, (sum, i) => sum + (i.cgst + i.sgst + i.igst));

    return pw.Container(height: 115, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))), child: pw.Row(children: [
      // Left Footer Box (QR Code and Bank Details side-by-side)
      pw.Container(width: 320, padding: const pw.EdgeInsets.all(5), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text("Amt In Words: RUPEES ${PdfMasterService.numberToWords(sale.totalAmount.round())} ONLY", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
        pw.Spacer(),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (qrImage != null) pw.Container(width: 45, height: 45, margin: const pw.EdgeInsets.only(right: 10), child: pw.Image(qrImage)),
            if (config.bankAccNumber.isNotEmpty)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text("BENEFICIARY: ${config.bankAccName.toUpperCase()}", style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text("BANK: ${config.bankNameBranch.toUpperCase()}", style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text("A/C NO: ${config.bankAccNumber}", style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text("IFSC: ${config.bankIfsc.toUpperCase()}", style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
                ]
              )
          ]
        ),
      ])),
      pw.Container(width: 250, padding: const pw.EdgeInsets.all(5), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))), child: pw.Column(children: [
        _fRow("TAXABLE TOTAL", taxableTotal),
        if (isLocal) ...[ _fRow("CGST TOTAL", totalTax / 2), _fRow("SGST TOTAL", totalTax / 2), ] else _fRow("IGST TOTAL", totalTax),
        if (sale.extraDiscount > 0) _fRow("EXTRA DISCOUNT (-)", sale.extraDiscount),
        _fRow("ROUND OFF", sale.roundOff),
        pw.Divider(thickness: 0.5),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text("NET PAYABLE", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text("Rs. ${sale.totalAmount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ]),
      ])),
      pw.Container(width: 230, padding: const pw.EdgeInsets.all(5), child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text("For $shopName", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 30),
        pw.Text("AUTHORISED SIGNATORY", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
      ])),
    ]));
  }
  static pw.Widget _fRow(String l, double v) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(l, style: const pw.TextStyle(fontSize: 7.5)), pw.Text(v.toStringAsFixed(2), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))]);
}
