// FILE: lib/pdf/purchase_challan_pdf.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../gateway/company_registry_model.dart';
import 'pdf_master_service.dart';

class PurchaseChallanPdf {
  static const int itemsPerPage = 15;

  static Future<void> generate(PurchaseChallan challan, Party supplier, CompanyProfile shop) async {
    final bytes = await generateBytes(challan, supplier, shop);
    await Printing.layoutPdf(onLayout: (format) async => bytes, name: 'Inward_${challan.internalNo}', format: PdfPageFormat.a4.landscape);
  }

  // 📧 NAYA: EMAIL DISPATCH LOGIC (With Dynamic Height-Lock and standard margins)
  static Future<Uint8List> generateBytes(PurchaseChallan challan, Party supplier, CompanyProfile shop) async {
    final pdf = pw.Document();
    
    // 🆕 STRICT ALIGNED PARAMETERS
    const int itemsPerPage = 15; 
    const double pageHeightLimit = 550;
    const double masterWidth = 800;

    int totalPages = (challan.items.length / itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    for (int pageNum = 0; pageNum < totalPages; pageNum++) {
      int start = pageNum * itemsPerPage;
      int end = (start + itemsPerPage < challan.items.length) ? start + itemsPerPage : challan.items.length;
      List<PurchaseItem> pageItems = challan.items.sublist(start, end);
      bool isLastPage = (pageNum == totalPages - 1);

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape, 
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15), // Symmetric margins locked
        build: (context) => pw.Column(
          children: [
            pw.Container(
              width: masterWidth, 
              height: pageHeightLimit, // Bounded height set to 550 (pageHeightLimit)
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
              child: pw.Column(
                children: [
                  pw.Row(children: [
                    _hBox(285, true, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      pw.Text(shop.address, style: const pw.TextStyle(fontSize: 7.5)),
                      pw.Text("GSTIN: ${shop.gstin}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ])),
                    _hBox(170, true, pw.Column(children: [
                      pw.Text("INWARD CHALLAN", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Divider(thickness: 0.5),
                      pw.Text("Ref: ${challan.billNo}", style: const pw.TextStyle(fontSize: 7.5)),
                      pw.Text(DateFormat('dd/MM/yyyy').format(challan.date), style: const pw.TextStyle(fontSize: 8)),
                    ])),
                    _hBox(335, false, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text("SUPPLIER:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                      pw.Text(supplier.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      pw.Text("GSTIN: ${supplier.gst}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ])),
                  ]),
                  pw.Container(color: PdfColors.grey200, child: pw.Row(children: [
                    _tCol("S.N", 30), _tCol("Product Description", 300, isLeft: true), _tCol("Packing", 60),
                    _tCol("Batch", 90), _tCol("Expiry", 60), _tCol("Qty", 60), _tCol("Rate", 100), _tCol("Total", 100, isLast: true),
                  ])),
                  pw.Expanded(child: pw.Column(children: pageItems.map((i) => pw.Container(
                    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1))),
                    child: pw.Row(children: [
                      _cell("${challan.items.indexOf(i) + 1}", 30), _cell(i.name, 300, isLeft: true), _cell(i.packing, 60),
                      _cell(i.batch, 90), _cell(i.exp, 60), _cell(i.qty.toInt().toString(), 60),
                      _cell(i.purchaseRate.toStringAsFixed(2), 100), _cell(i.total.toStringAsFixed(2), 100),
                    ]),
                  )).toList())),
                  if (isLastPage) _buildFooter(shop.name, challan.totalAmount, challan.remarks)
                ],
              ),
            ),
            pw.SizedBox(height: 4), // Professional margins spacer
            pw.Center(
              child: pw.Text(
                "This is a system-generated document. | Powered by Pharoah ERP [Download from Play Store] | Support: cloudcubeapps.ok@gmail.com",
                style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey600),
              ),
            ),
          ],
        ),
      ));
    }
    return pdf.save();
  }

  static pw.Widget _hBox(double w, bool b, pw.Widget child) => pw.Container(width: w, height: 80, padding: const pw.EdgeInsets.all(5), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: b ? 0.5 : 0), bottom: const pw.BorderSide(width: 0.5))), child: child);
  static pw.Widget _tCol(String t, double w, {bool isLast = false, bool isLeft = false}) => pw.Container(width: w, height: 20, alignment: isLeft ? pw.Alignment.centerLeft : pw.Alignment.center, padding: pw.EdgeInsets.only(left: isLeft ? 8 : 0), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: isLast ? 0 : 0.5), bottom: const pw.BorderSide(width: 0.5))), child: pw.Text(t, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)));
  static pw.Widget _cell(String t, double w, {bool isLeft = false}) => pw.Container(width: w, height: 18, padding: const pw.EdgeInsets.symmetric(horizontal: 5), alignment: isLeft ? pw.Alignment.centerLeft : pw.Alignment.center, decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.2, color: PdfColors.grey))), child: pw.Text(t, style: const pw.TextStyle(fontSize: 8)));
  static pw.Widget _buildFooter(String n, double t, String r) => pw.Container(height: 100, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))), child: pw.Row(children: [pw.Container(width: 480, padding: const pw.EdgeInsets.all(8), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text("REMARKS: $r", style: const pw.TextStyle(fontSize: 8)), pw.Spacer(), pw.Text("System generated record.", style: const pw.TextStyle(fontSize: 7))])), pw.Container(width: 320, padding: const pw.EdgeInsets.all(8), child: pw.Column(children: [pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text("TOTAL VALUE", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)), pw.Text("Rs. ${t.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))])]))]));
}
