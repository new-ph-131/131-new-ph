// FILE: lib/pdf/purchase_report_pdf.dart (UPDATED FOR EMAIL BYTES)

import 'dart:typed_data'; // NAYA: Bytes के लिए
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../gateway/company_registry_model.dart';

class PurchaseReportPdf {
  
  // 1. ORIGINAL GENERATE (For Printing)
  static Future<void> generate(List<Purchase> purchases, DateTime fDate, DateTime tDate, Party? selectedDist, CompanyProfile shop) async {
    final bytes = await generateBytes(purchases, shop, from: fDate, to: tDate);
    await Printing.layoutPdf(onLayout: (format) async => bytes, name: 'Purchase_Register_${shop.name}', format: PdfPageFormat.a4.landscape);
  }

  // ===========================================================================
  // 📧 2. NAYA: GENERATE BYTES (For Email Dispatch)
  // ===========================================================================
  static Future<Uint8List> generateBytes(List<Purchase> purchases, CompanyProfile shop, {DateTime? from, DateTime? to}) async {
    final pdf = pw.Document();
    String shopName = shop.name.toUpperCase();

    // Summary Totals
    double totalTaxable = 0; double totalGst = 0; double netTotal = 0;
    int billCount = purchases.length;

    for (var p in purchases) {
      double pTaxable = p.items.fold(0.0, (sum, it) => sum + (it.purchaseRate * it.qty));
      totalTaxable += pTaxable;
      totalGst += (p.totalAmount - pTaxable);
      netTotal += p.totalAmount;
    }

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      header: (context) => pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(shopName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
            pw.Text("PURCHASE REGISTER (SUMMARY REPORT)", style: const pw.TextStyle(fontSize: 12)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            if (from != null && to != null)
              pw.Text("Period: ${DateFormat('dd/MM/yy').format(from)} to ${DateFormat('dd/MM/yy').format(to)}"),
            pw.Text("Total Entries: $billCount"),
          ]),
        ]),
        pw.Divider(thickness: 1, color: PdfColors.orange900),
        pw.SizedBox(height: 10),
      ]),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.orange900),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headers: ['DATE', 'BILL NO', 'INTERNAL ID', 'SUPPLIER NAME', 'MODE', 'TAXABLE', 'GST (ITC)', 'TOTAL'],
          data: purchases.map((p) {
            double taxable = p.items.fold(0.0, (sum, it) => sum + (it.purchaseRate * it.qty));
            return [
              DateFormat('dd/MM/yy').format(p.date), 
              p.billNo, 
              p.internalNo, 
              p.distributorName, 
              p.paymentMode,
              taxable.toStringAsFixed(2), 
              (p.totalAmount - taxable).toStringAsFixed(2), 
              p.totalAmount.toStringAsFixed(2)
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
           _sumBox("TOTAL BILLS", billCount.toDouble(), isInt: true),
           _sumBox("TAXABLE AMT", totalTaxable),
           _sumBox("INPUT GST (ITC)", totalGst),
           _sumBox("NET PURCHASE", netTotal, isBold: true)
        ]),
      ],
    ));

    return pdf.save(); // Bytes रिटर्न करेगा
  }

  static pw.Widget _sumBox(String label, double val, {bool isBold = false, bool isInt = false}) {
    return pw.Column(children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
      pw.Text(isInt ? val.toInt().toString() : "Rs. ${val.toStringAsFixed(2)}", 
        style: pw.TextStyle(fontSize: 12, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, 
        color: isBold ? PdfColors.orange900 : PdfColors.black)),
    ]);
  }
}
