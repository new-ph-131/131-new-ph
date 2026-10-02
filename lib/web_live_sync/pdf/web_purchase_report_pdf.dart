// FILE: lib/web_live_sync/pdf/web_purchase_report_pdf.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../web_models.dart';

class WebPurchaseReportPdf {
  static Future<Uint8List> generateBytes({
    required List<Purchase> purchases,
    required CompanyProfile shop,
    required DateTime from,
    required DateTime to,
  }) async {
    final pdf = pw.Document();
    String shopName = shop.name.toUpperCase();

    double totalTaxable = 0;
    double totalGst = 0;
    double netTotal = 0;

    for (var p in purchases) {
      double pTaxable = p.items.fold(0.0, (sum, it) => sum + (it.purchaseRate * it.qty - it.discountRupees));
      totalTaxable += pTaxable;
      totalGst += (p.totalAmount - pTaxable);
      netTotal += p.totalAmount;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(shopName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                    pw.Text("PURCHASE INWARD REGISTER (SUMMARY REPORT)", style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Period: ${DateFormat('dd/MM/yyyy').format(from)} to ${DateFormat('dd/MM/yyyy').format(to)}", style: const pw.TextStyle(fontSize: 9.5)),
                    pw.Text("Total Entries: ${purchases.length}", style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 1, color: PdfColors.orange900),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.orange900),
            cellStyle: const pw.TextStyle(fontSize: 8),
            columnWidths: const {
              0: pw.FixedColumnWidth(60),
              1: pw.FixedColumnWidth(75),
              2: pw.FixedColumnWidth(70),
              3: pw.FlexColumnWidth(3),
              4: pw.FixedColumnWidth(55),
              5: pw.FixedColumnWidth(75),
              6: pw.FixedColumnWidth(75),
              7: pw.FixedColumnWidth(85),
            },
            headers: ['DATE', 'BILL NO', 'INTERNAL ID', 'SUPPLIER NAME', 'MODE', 'TAXABLE', 'GST (ITC)', 'TOTAL'],
            data: purchases.map((p) {
              double taxable = p.items.fold(0.0, (sum, it) => sum + (it.purchaseRate * it.qty - it.discountRupees));
              return [
                DateFormat('dd/MM/yy').format(p.date),
                p.billNo,
                p.internalNo,
                p.distributorName,
                p.paymentMode,
                taxable.toStringAsFixed(2),
                (p.totalAmount - taxable).toStringAsFixed(2),
                p.totalAmount.toStringAsFixed(2),
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _sumBox("TOTAL ENTRIES", purchases.length.toDouble(), isInt: true),
              _sumBox("TAXABLE AMT", totalTaxable),
              _sumBox("INPUT GST (ITC)", totalGst),
              _sumBox("NET PURCHASE", netTotal, isBold: true),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _sumBox(String label, double val, {bool isBold = false, bool isInt = false}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Text(
          isInt ? val.toInt().toString() : "Rs. ${val.toStringAsFixed(2)}",
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: isBold ? PdfColors.orange900 : PdfColors.black,
          ),
        ),
      ],
    );
  }

  static Future<void> printReport({
    required List<Purchase> purchases,
    required CompanyProfile shop,
    required DateTime from,
    required DateTime to,
  }) async {
    final bytes = await generateBytes(purchases: purchases, shop: shop, from: from, to: to);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: "Purchase_Register_${DateFormat('ddMMyy').format(DateTime.now())}",
      format: PdfPageFormat.a4.landscape,
    );
  }

  static Future<void> downloadReport({
    required List<Purchase> purchases,
    required CompanyProfile shop,
    required DateTime from,
    required DateTime to,
  }) async {
    final bytes = await generateBytes(purchases: purchases, shop: shop, from: from, to: to);
    await Printing.sharePdf(
      bytes: bytes,
      filename: "Purchase_Register_${DateFormat('ddMMyy').format(DateTime.now())}.pdf",
    );
  }
}
