// FILE: lib/pdf/bulk_pdf_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models.dart';
import '../gateway/company_registry_model.dart';
import 'pdf_master_service.dart';

class BulkPdfService {
  
  // ===========================================================================
  // 1. MAIN ZIP GENERATOR
  // ===========================================================================
  static Future<String> createBillsZip({
    required List<Map<String, dynamic>> selectedDrafts,
    required CompanyProfile shop,
    required Function(double progress, String filename) onProgress,
  }) async {
    final archive = Archive();

    for (int i = 0; i < selectedDrafts.length; i++) {
      var draft = selectedDrafts[i];
      dynamic billObj = draft['saleObj']; 
      Party party = draft['party'];

      onProgress((i + 1) / selectedDrafts.length, party.name);

      Uint8List pdfBytes;
      String billNo;

      if (billObj is Sale) {
        pdfBytes = await _generateSaleCloneBytes(billObj, party, shop);
        billNo = billObj.billNo;
      } else {
        pdfBytes = await _generatePurchaseCloneBytes(billObj, party, shop);
        billNo = (billObj as Purchase).billNo;
      }

      String cleanName = party.name.replaceAll(RegExp(r'[^A-Z0-9]'), '');
      String p5 = cleanName.padRight(5, 'X').substring(0, 5);
      String fileName = "${p5}_$billNo.pdf";

      archive.addFile(ArchiveFile(fileName, pdfBytes.length, pdfBytes));
    }

    final zipData = ZipEncoder().encode(archive);
    final tempDir = await getTemporaryDirectory();
    final zipPath = '${tempDir.path}/Batch_Bills_${DateFormat('ddMM_HHmm').format(DateTime.now())}.zip';
    await File(zipPath).writeAsBytes(zipData!);
    
    return zipPath;
  }

  // ===========================================================================
  // 2. PROFESSIONAL SALE CLONE (800pt FIXED)
  // ===========================================================================
  static Future<Uint8List> _generateSaleCloneBytes(Sale sale, Party party, CompanyProfile shop) async {
    final pdf = pw.Document();
    const double masterWidth = 800;
    const int itemsPerPage = 22; 
    int totalPages = (sale.items.length / itemsPerPage).ceil();

    double totalGross = sale.items.fold(0, (sum, i) => sum + (i.qty * i.rate));
    double totalSGST = sale.items.fold(0, (sum, i) => sum + i.sgst);
    double totalCGST = sale.items.fold(0, (sum, i) => sum + i.cgst);
    int roundedTotal = sale.totalAmount.round();

    String formatQty(double val) => val == val.toInt() ? val.toInt().toString() : val.toStringAsFixed(1);

    for (int pageNum = 0; pageNum < totalPages; pageNum++) {
      int start = pageNum * itemsPerPage;
      int end = (start + itemsPerPage < sale.items.length) ? start + itemsPerPage : sale.items.length;
      List<BillItem> pageItems = sale.items.sublist(start, end);
      bool isLastPage = (pageNum == totalPages - 1);

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 21, vertical: 15),
        build: (context) => pw.Container(
          width: masterWidth,
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
          child: pw.Column(children: [
            // Header (Total: 800)
            // --- REVISED HEADER BLOCK ---
            pw.Row(children: [
              // Box 1: Shop (285)
              _hBox(285, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                pw.Text(shop.address, style: const pw.TextStyle(fontSize: 7), maxLines: 2),
                pw.Text("GSTIN: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                pw.Text("Mob: ${shop.phone} | Email: ${shop.email.toLowerCase()}", style: const pw.TextStyle(fontSize: 7)),
              ])),
              // Box 2: Invoice Info (170)
              _hBox(170, pw.Column(children: [
                pw.Text("GST RECORD", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Divider(thickness: 0.5),
                pw.Text(billNo, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.Text(DateFormat('dd/MM/yyyy').format(DateTime.now()), style: const pw.TextStyle(fontSize: 8)),
              ])),
              // Box 3: Party Details (335)
              _hBox(335, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text("DETAILS:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                pw.Text(party.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                pw.Text("GSTIN: ${party.gst} | DL: ${party.dl}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Text("Mob: ${party.phone} | Email: ${party.email.toLowerCase()}", style: const pw.TextStyle(fontSize: 7)),
              ])),
            ]),

            // Table Header (800)
            pw.Container(color: PdfColors.grey100, child: pw.Row(children: [
              _tCol("S.N", 25), _tCol("Qty+Free", 55), _tCol("Pack", 45), _tCol("Product Name", 210, align: pw.Alignment.centerLeft),
              _tCol("Batch", 75), _tCol("Exp", 45), _tCol("HSN", 50), _tCol("MRP", 55), _tCol("Rate", 55), 
              _tCol("DIS%", 30), _tCol("SGST%", 50), _tCol("CGST%", 50), _tCol("Net Amt", 55),
            ])),

            // Rows
            pw.Expanded(child: pw.Column(children: pageItems.map((i) {
              String displayQty = i.freeQty > 0 ? "${formatQty(i.qty)} + ${formatQty(i.freeQty)}" : formatQty(i.qty);
              return pw.Container(
                decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
                child: pw.Row(children: [
                  _cell("${start + pageItems.indexOf(i) + 1}", 25), _cell(displayQty, 55), _cell(i.packing, 45), 
                  pw.Container(width: 210, padding: const pw.EdgeInsets.only(left: 5), alignment: pw.Alignment.centerLeft, child: pw.Text(i.name, style: const pw.TextStyle(fontSize: 7.5))),
                  _cell(i.batch, 75), _cell(i.exp, 45), _cell(i.hsn, 50), _cell(i.mrp.toStringAsFixed(2), 55), _cell(i.rate.toStringAsFixed(2), 55), 
                  _cell(i.discountRupees.toStringAsFixed(1), 30), _cell("${(i.gstRate/2).toStringAsFixed(1)}%", 50),
                  _cell("${(i.gstRate/2).toStringAsFixed(1)}%", 50), _cell(i.total.toStringAsFixed(2), 55),
                ]),
              );
            }).toList())),

            if (isLastPage) _buildProfessionalFooter(shop.name, totalGross, totalSGST, totalCGST, roundedTotal)
          ]),
        )
      ));
    }
    return pdf.save();
  }

  // ===========================================================================
  // 3. PROFESSIONAL PURCHASE CLONE (800pt FIXED)
  // ===========================================================================
  static Future<Uint8List> _generatePurchaseCloneBytes(Purchase pur, Party supplier, CompanyProfile shop) async {
    final pdf = pw.Document();
    const double masterWidth = 800;
    const int itemsPerPage = 12;
    int totalPages = (pur.items.length / itemsPerPage).ceil();

    double totalTaxable = pur.items.fold(0, (sum, i) => sum + (i.purchaseRate * i.qty));
    double totalGst = pur.totalAmount - totalTaxable;
    int roundedTotal = pur.totalAmount.round();

    for (int pageNum = 0; pageNum < totalPages; pageNum++) {
      int start = pageNum * itemsPerPage;
      int end = (start + itemsPerPage < pur.items.length) ? start + itemsPerPage : pur.items.length;
      List<PurchaseItem> pageItems = pur.items.sublist(start, end);
      bool isLastPage = (pageNum == totalPages - 1);

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 21, vertical: 15),
        build: (context) => pw.Container(
          width: masterWidth,
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
          child: pw.Column(children: [
            pw.Row(children: [
              _hBox(290, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                pw.Text(shop.address, style: const pw.TextStyle(fontSize: 8)),
                pw.Text("Phone: ${shop.phone} | GSTIN: ${shop.gstin}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ])),
              _hBox(175, pw.Column(children: [
                pw.Text("PURCHASE BILL", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                pw.Text(pur.paymentMode.toUpperCase(), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Divider(thickness: 0.5),
                pw.Text("Bill No: ${pur.billNo}", style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                pw.Text("Date: ${DateFormat('dd/MM/yyyy').format(pur.date)}", style: const pw.TextStyle(fontSize: 8.5)),
              ])),
              _hBox(335, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text("SUPPLIER DETAILS:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey)),
                pw.Text(supplier.name, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                pw.Text(supplier.address, style: const pw.TextStyle(fontSize: 8)),
                pw.Text("GSTIN: ${supplier.gst} | DL: ${supplier.dl}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ])),
            ]),

            pw.Container(color: PdfColors.grey200, child: pw.Row(children: [
              _tCol("S.N", 25), _tCol("Qty", 45), _tCol("Free", 35), _tCol("Pack", 45),
              _tCol("Product Name", 215, align: pw.Alignment.centerLeft),
              _tCol("Batch", 80), _tCol("Exp", 45), _tCol("HSN", 50),
              _tCol("MRP", 60), _tCol("Pur.Rate", 60), _tCol("GST%", 50), _tCol("Net Amt", 90),
            ])),

            pw.Expanded(child: pw.Column(children: pageItems.map((i) {
              return pw.Container(
                decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1))),
                child: pw.Row(children: [
                  _cell("${start + pageItems.indexOf(i) + 1}", 25), _cell(i.qty.toStringAsFixed(0), 45),
                  _cell(i.freeQty.toStringAsFixed(0), 35), _cell(i.packing, 45),
                  pw.Container(width: 215, padding: const pw.EdgeInsets.only(left: 5), alignment: pw.Alignment.centerLeft, child: pw.Text(i.name, style: const pw.TextStyle(fontSize: 7.5))),
                  _cell(i.batch, 80), _cell(i.exp, 45), _cell(i.hsn, 50),
                  _cell(i.mrp.toStringAsFixed(2), 60), _cell(i.purchaseRate.toStringAsFixed(2), 60), _cell("${i.gstRate}%", 50), _cell(i.total.toStringAsFixed(2), 90),
                ]),
              );
            }).toList())),

            if (isLastPage) _buildProfessionalFooter(shop.name, totalTaxable, totalGst/2, totalGst/2, roundedTotal, isPurchase: true)
          ]),
        )
      ));
    }
    return pdf.save();
  }

  // ===========================================================================
  // 4. SHARED PROFESSIONAL FOOTER (800pt FIXED)
  // ===========================================================================
  static pw.Widget _buildProfessionalFooter(String shopName, double gross, double sgst, double cgst, int total, {bool isPurchase = false}) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(width: 340, padding: const pw.EdgeInsets.all(5), decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5), right: pw.BorderSide(width: 0.5))), child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text("Amount in Words:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
            pw.Text("RUPEES ${PdfMasterService.numberToWords(total)} ONLY", style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
            pw.SizedBox(height: 5),
            pw.Text(isPurchase ? "Note: System generated purchase record." : "Terms: 1. Goods sold will not be taken back. 2. Disputes subject to local jurisdiction.", style: const pw.TextStyle(fontSize: 6)),
          ],
        )),
        pw.Container(width: 260, padding: const pw.EdgeInsets.all(5), decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5), right: pw.BorderSide(width: 0.5))), child: pw.Column(
          children: [
            _fRow(isPurchase ? "TAXABLE AMOUNT" : "GROSS TOTAL", gross), _fRow("TOTAL SGST", sgst), _fRow("TOTAL CGST", cgst),
            pw.Divider(thickness: 0.5),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text("NET AMOUNT", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text("Rs. $total.00", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ]),
          ],
        )),
        pw.Container(width: 200, height: 62, padding: const pw.EdgeInsets.all(5), decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))), child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text("For $shopName", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.Text("Authorised Signatory", style: const pw.TextStyle(fontSize: 7)),
          ],
        )),
      ],
    );
  }

  static pw.Widget _fRow(String l, double v) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(l, style: const pw.TextStyle(fontSize: 7)), pw.Text(v.toStringAsFixed(2), style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))]);
  static pw.Widget _hBox(double w, pw.Widget child) => pw.Container(width: w, height: 85, padding: const pw.EdgeInsets.all(5), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))), child: child);
  static pw.Widget _tCol(String text, double width, {pw.Alignment align = pw.Alignment.center}) => pw.Container(width: width, height: 20, alignment: align, decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5), bottom: pw.BorderSide(width: 0.5))), child: pw.Text(text, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)));
  static pw.Widget _cell(String t, double w, {pw.Alignment align = pw.Alignment.center}) => pw.Container(width: w, padding: const pw.EdgeInsets.symmetric(vertical: 2), alignment: align, child: pw.Text(t, style: const pw.TextStyle(fontSize: 7.5)));
}
