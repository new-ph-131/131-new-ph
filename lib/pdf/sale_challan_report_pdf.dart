// FILE: lib/pdf/sale_challan_report_pdf.dart

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../gateway/company_registry_model.dart';

class SaleChallanReportPdf {
  static Future<void> generate(List<SaleChallan> list, DateTime fDate, DateTime tDate, CompanyProfile shop) async {
    final pdf = pw.Document();
    String shopName = shop.name.toUpperCase();
    double grandTotal = list.fold(0, (sum, item) => sum + item.totalAmount);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      header: (context) => pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(shopName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text("SALE CHALLAN REGISTER REPORT", style: const pw.TextStyle(fontSize: 12)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text("Period: ${DateFormat('dd/MM/yy').format(fDate)} to ${DateFormat('dd/MM/yy').format(tDate)}"),
            pw.Text("Total Records: ${list.length}"),
          ]),
        ]),
        pw.Divider(thickness: 1),
        pw.SizedBox(height: 10),
      ]),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headers: ['DATE', 'CHALLAN NO', 'PARTY NAME', 'GSTIN', 'AMOUNT'],
          data: list.map((ch) => [
            DateFormat('dd/MM/yy').format(ch.date),
            ch.billNo,
            ch.partyName,
            ch.partyGstin,
            ch.totalAmount.toStringAsFixed(2),
          ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
            child: pw.Row(children: [
              pw.Text("GRAND TOTAL: ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text("Rs. ${grandTotal.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
            ]),
          )
        ]),
      ],
    ));

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Challan_Report_${DateFormat('ddMMyy').format(DateTime.now())}');
  }
}
