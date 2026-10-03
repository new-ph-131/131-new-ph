// FILE: lib/web_live_sync/pdf/web_party_ledger_pdf.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../web_models.dart';

class WebPartyLedgerPdf {
  static Future<Uint8List> generateBytes({
    required CompanyProfile shop,
    required Party party,
    required List<Map<String, dynamic>> data,
    required DateTime from,
    required DateTime to,
  }) async {
    final pdf = pw.Document();

    double totalDr = data.where((e) => e['type'] != 'OPENING').fold(0.0, (s, e) => s + ((e['dr'] as num?)?.toDouble() ?? 0.0));
    double totalCr = data.where((e) => e['type'] != 'OPENING').fold(0.0, (s, e) => s + ((e['cr'] as num?)?.toDouble() ?? 0.0));
    double closingBal = (data.isNotEmpty ? (data.last['bal'] as num?)?.toDouble() : 0.0) ?? 0.0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(25),
        header: (context) => _buildHeader(shop, party, from, to),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}  •  Powered by Pharoah ERP', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
            cellStyle: const pw.TextStyle(fontSize: 8),
            columnWidths: const {
              0: pw.FixedColumnWidth(50),
              1: pw.FlexColumnWidth(3),
              2: pw.FixedColumnWidth(55),
              3: pw.FixedColumnWidth(65),
              4: pw.FixedColumnWidth(65),
              5: pw.FixedColumnWidth(75),
            },
            headers: ['DATE', 'PARTICULARS / REF NO', 'TYPE', 'DEBIT (Dr)', 'CREDIT (Cr)', 'BALANCE'],
            data: data.map((row) {
              bool isOp = row['type'] == 'OPENING';
              DateTime dt = row['date'] as DateTime;
              double dr = (row['dr'] as num?)?.toDouble() ?? 0.0;
              double cr = (row['cr'] as num?)?.toDouble() ?? 0.0;
              double bal = (row['bal'] as num?)?.toDouble() ?? 0.0;

              return [
                DateFormat('dd/MM/yy').format(dt),
                isOp ? row['particulars'] : "${row['particulars'] ?? ''} (${row['ref'] ?? ''})",
                row['type'],
                dr > 0 ? dr.toStringAsFixed(2) : "",
                cr > 0 ? cr.toStringAsFixed(2) : "",
                "${bal.abs().toStringAsFixed(2)} ${bal >= 0 ? 'Dr' : 'Cr'}",
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 18),
          _buildSummaryBox(totalDr, totalCr, closingBal, shop.name),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(CompanyProfile shop, Party party, DateTime from, DateTime to) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                pw.Text(shop.address, style: const pw.TextStyle(fontSize: 7.5)),
                pw.Text("GSTIN: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                pw.Text("Mob: ${shop.phone}${shop.email.isNotEmpty ? ' | Email: ${shop.email.toLowerCase()}' : ''}", style: const pw.TextStyle(fontSize: 7)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text("STATEMENT OF ACCOUNT", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                pw.Text("Period: ${DateFormat('dd/MM/yyyy').format(from)} to ${DateFormat('dd/MM/yyyy').format(to)}", style: const pw.TextStyle(fontSize: 8.5)),
              ],
            ),
          ],
        ),
        pw.Divider(thickness: 1, color: PdfColors.indigo900),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(width: 0.5, color: PdfColors.grey400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("PARTY / CUSTOMER:", style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
                  pw.Text(party.name.toUpperCase(), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                  pw.Text("${party.address.isNotEmpty ? party.address : ''}${party.city.isNotEmpty ? ', ${party.city}' : ''}", style: const pw.TextStyle(fontSize: 7.5)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("GSTIN: ${party.gst.isNotEmpty ? party.gst : 'N/A'}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text("DL No: ${party.dl.isNotEmpty ? party.dl : 'N/A'}", style: const pw.TextStyle(fontSize: 7.5)),
                  if (party.phone.isNotEmpty) pw.Text("Mob: ${party.phone}", style: const pw.TextStyle(fontSize: 7.5)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
      ],
    );
  }

  static pw.Widget _buildSummaryBox(double dr, double cr, double bal, String shopName) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 250,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Terms & Instructions:", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text("1. Please check the ledger statement and report any discrepancy within 7 days.", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey800)),
              pw.Text("2. Payment can be made via UPI / Bank Transfer / Cheque.", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey800)),
            ],
          ),
        ),
        pw.Container(
          width: 230,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(width: 0.8, color: PdfColors.indigo900),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            children: [
              _sumRow("Total Debits (+):", dr),
              _sumRow("Total Credits (-):", cr),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("CLOSING BALANCE:", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    "Rs. ${bal.abs().toStringAsFixed(2)} ${bal >= 0 ? 'Dr' : 'Cr'}",
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: bal >= 0 ? PdfColors.green900 : PdfColors.red900),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text("For $shopName", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 18),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text("Authorised Signatory", style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _sumRow(String l, double v) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(l, style: const pw.TextStyle(fontSize: 7.5)),
        pw.Text("Rs. ${v.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );

  static Future<void> printStatement({
    required CompanyProfile shop,
    required Party party,
    required List<Map<String, dynamic>> data,
    required DateTime from,
    required DateTime to,
  }) async {
    final bytes = await generateBytes(shop: shop, party: party, data: data, from: from, to: to);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: "Ledger_${party.name.replaceAll(' ', '_')}_${DateFormat('ddMMMyy').format(from)}",
      format: PdfPageFormat.a4,
    );
  }

  static Future<void> downloadStatement({
    required CompanyProfile shop,
    required Party party,
    required List<Map<String, dynamic>> data,
    required DateTime from,
    required DateTime to,
  }) async {
    final bytes = await generateBytes(shop: shop, party: party, data: data, from: from, to: to);
    await Printing.sharePdf(
      bytes: bytes,
      filename: "Ledger_${party.name.replaceAll(' ', '_')}_${DateFormat('ddMMMyy').format(from)}.pdf",
    );
  }
}
