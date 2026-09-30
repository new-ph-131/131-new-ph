import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../models.dart';
import '../../gateway/company_registry_model.dart';

class ItemLedgerPdf {
  static Future<void> generate({
    required CompanyProfile shop,
    required Medicine med,
    required List<Map<String, dynamic>> movementData,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        header: (context) => _buildHeader(shop, med),
        build: (context) => [
          _buildMovementTable(movementData),
          pw.SizedBox(height: 20),
          _buildFinalSummary(med, shop.name),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Item_Ledger_${med.name}');
  }

  static pw.Widget _buildHeader(CompanyProfile shop, Medicine med) {
    return pw.Column(children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          pw.Text("ITEM MOVEMENT AUDIT (LIFECYCLE)", style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text("Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 9)),
        ]),
      ]),
      pw.Divider(thickness: 1),
      pw.SizedBox(height: 10),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), color: PdfColors.grey50),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text("PRODUCT NAME:", style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
            pw.Text(med.name, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Text("Packing: ${med.packing} | HSN: ${med.hsnCode}", style: const pw.TextStyle(fontSize: 9)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text("MRP: ₹${med.mrp}", style: const pw.TextStyle(fontSize: 9)),
            pw.Text("PUR RATE: ₹${med.purRate}", style: const pw.TextStyle(fontSize: 9)),
          ]),
        ]),
      ),
      pw.SizedBox(height: 15),
    ]);
  }

  static pw.Widget _buildMovementTable(List<Map<String, dynamic>> data) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
      cellStyle: const pw.TextStyle(fontSize: 8),
      columnWidths: {
        0: const pw.FixedColumnWidth(50), // Date
        1: const pw.FlexColumnWidth(3),   // Party
        2: const pw.FixedColumnWidth(60), // Type
        3: const pw.FixedColumnWidth(50), // In
        4: const pw.FixedColumnWidth(50), // Out
        5: const pw.FixedColumnWidth(60), // Balance
      },
      headers: ['DATE', 'PARTY / SOURCE DETAILS', 'TYPE', 'IN (+)', 'OUT (-)', 'STOCK BAL'],
      data: data.map((row) {
        return [
          DateFormat('dd/MM/yy').format(row['date']),
          row['party'],
          row['type'],
          row['in'] > 0 ? row['in'].toInt().toString() : "",
          row['out'] > 0 ? row['out'].toInt().toString() : "",
          pw.Text(row['bal'].toInt().toString(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ];
      }).toList(),
    );
  }

  static pw.Widget _buildFinalSummary(Medicine med, String shopName) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text("CLOSING STOCK ON HAND: ${med.stock.toInt()} UNITS", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
        pw.SizedBox(height: 20),
        pw.Text("Verified by $shopName", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ]),
    );
  }
}
