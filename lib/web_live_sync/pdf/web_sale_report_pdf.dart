// FILE: lib/web_live_sync/pdf/web_sale_report_pdf.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../web_models.dart';

class WebSaleReportPdf {
  static Future<Uint8List> generateBytes({
    required List<Sale> sales,
    required CompanyProfile shop,
    required DateTime from,
    required DateTime to,
  }) async {
    final pdf = pw.Document();
    String shopName = shop.name.toUpperCase();

    double totalTaxable = 0;
    double totalGst = 0;
    double netTotal = 0;
    double cashTotal = 0;
    double creditTotal = 0;

    for (var s in sales) {
      double sTax = s.items.fold(0.0, (sum, it) => sum + (it.cgst + it.sgst + it.igst));
      totalTaxable += (s.totalAmount - sTax);
      totalGst += sTax;
      netTotal += s.totalAmount;
      if (s.paymentMode.toUpperCase() == 'CASH') {
        cashTotal += s.totalAmount;
      } else {
        creditTotal += s.totalAmount;
      }
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
                    pw.Text(shopName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text("SALES REGISTER (SUMMARY REPORT)", style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Period: ${DateFormat('dd/MM/yyyy').format(from)} to ${DateFormat('dd/MM/yyyy').format(to)}", style: const pw.TextStyle(fontSize: 9.5)),
                    pw.Text("Total Bills: ${sales.length}", style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 1, color: PdfColors.blue900),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellStyle: const pw.TextStyle(fontSize: 8),
            columnWidths: const {
              0: pw.FixedColumnWidth(60),
              1: pw.FixedColumnWidth(75),
              2: pw.FlexColumnWidth(3),
              3: pw.FixedColumnWidth(100),
              4: pw.FixedColumnWidth(55),
              5: pw.FixedColumnWidth(75),
              6: pw.FixedColumnWidth(75),
              7: pw.FixedColumnWidth(85),
            },
            headers: ['DATE', 'BILL NO', 'PARTY NAME', 'GSTIN', 'MODE', 'TAXABLE', 'GST', 'TOTAL'],
            data: sales.map((s) {
              double tax = s.items.fold(0.0, (sum, it) => sum + (it.cgst + it.sgst + it.igst));
              return [
                DateFormat('dd/MM/yy').format(s.date),
                s.billNo,
                s.partyName,
                s.partyGstin.isNotEmpty ? s.partyGstin : 'N/A',
                s.paymentMode,
                (s.totalAmount - tax).toStringAsFixed(2),
                tax.toStringAsFixed(2),
                s.totalAmount.toStringAsFixed(2),
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _sumBox("CASH SALE", cashTotal),
              _sumBox("CREDIT SALE", creditTotal),
              _sumBox("TAXABLE AMT", totalTaxable),
              _sumBox("OUTPUT GST", totalGst),
              _sumBox("NET TOTAL", netTotal, isBold: true),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _sumBox(String label, double val, {bool isBold = false}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Text(
          "Rs. ${val.toStringAsFixed(2)}",
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: isBold ? PdfColors.blue900 : PdfColors.black,
          ),
        ),
      ],
    );
  }

  static Future<void> printReport({
    required List<Sale> sales,
    required CompanyProfile shop,
    required DateTime from,
    required DateTime to,
  }) async {
    final bytes = await generateBytes(sales: sales, shop: shop, from: from, to: to);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: "Sale_Register_${DateFormat('ddMMyy').format(DateTime.now())}",
      format: PdfPageFormat.a4.landscape,
    );
  }

  static Future<void> downloadReport({
    required List<Sale> sales,
    required CompanyProfile shop,
    required DateTime from,
    required DateTime to,
  }) async {
    final bytes = await generateBytes(sales: sales, shop: shop, from: from, to: to);
    await Printing.sharePdf(
      bytes: bytes,
      filename: "Sale_Register_${DateFormat('ddMMyy').format(DateTime.now())}.pdf",
    );
  }
}
