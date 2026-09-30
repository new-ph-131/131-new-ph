import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../models.dart';
import '../../gateway/company_registry_model.dart';
import '../pdf_master_service.dart';

class PartyLedgerPdf {
  static Future<void> generate({
    required CompanyProfile shop,
    required Party party,
    required List<Map<String, dynamic>> data,
    required DateTime from,
    required DateTime to,
  }) async {
    final pdf = pw.Document();

    // Summary Calculations for Footer
    double totalDr = data.where((e) => e['type'] != 'OPENING').fold(0, (s, e) => s + (e['dr'] ?? 0));
    double totalCr = data.where((e) => e['type'] != 'OPENING').fold(0, (s, e) => s + (e['cr'] ?? 0));
    double closingBal = data.last['bal'];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        header: (context) => _buildHeader(shop, party, from, to),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildStatementTable(data),
          pw.SizedBox(height: 20),
          _buildSummaryBox(totalDr, totalCr, closingBal, shop.name),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Ledger_${party.name}_${DateFormat('ddMMMyy').format(from)}',
    );
  }
  // 📧 NAYA: EMAIL KE LIYE BYTES GENERATE KARNA
  static Future<Uint8List> generateBytes({
    required CompanyProfile shop,
    required Party party,
    required List<Map<String, dynamic>> data,
    required DateTime from,
    required DateTime to,
  }) async {
    final pdf = pw.Document();
    
    // Summary Calculations
    double totalDr = data.where((e) => e['type'] != 'OPENING').fold(0, (s, e) => s + (e['dr'] ?? 0));
    double totalCr = data.where((e) => e['type'] != 'OPENING').fold(0, (s, e) => s + (e['cr'] ?? 0));
    double closingBal = data.last['bal'];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        header: (context) => _buildHeader(shop, party, from, to),
        build: (context) => [
          _buildStatementTable(data),
          pw.SizedBox(height: 20),
          _buildSummaryBox(totalDr, totalCr, closingBal, shop.name),
        ],
      ),
    );

    return pdf.save(); // Direct bytes return karega
  }

  // --- 1. PROFESSIONAL HEADER (Shop + Party Details) ---
  static pw.Widget _buildHeader(CompanyProfile shop, Party party, DateTime from, DateTime to) {
    return pw.Column(children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          pw.Text(shop.address, style: const pw.TextStyle(fontSize: 8)),
          pw.Text("GSTIN: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.Text("Phone: ${shop.phone}", style: const pw.TextStyle(fontSize: 8)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text("ACCOUNT STATEMENT", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
          pw.Text("Period: ${DateFormat('dd/MM/yy').format(from)} to ${DateFormat('dd/MM/yy').format(to)}", style: const pw.TextStyle(fontSize: 9)),
        ]),
      ]),
      pw.Divider(thickness: 1, color: PdfColors.grey400),
      pw.SizedBox(height: 10),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5, color: PdfColors.grey400), color: PdfColors.grey50),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text("STATEMENT FOR:", style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
            pw.Text(party.name, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text("${party.address}, ${party.city}", style: const pw.TextStyle(fontSize: 8)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text("GSTIN: ${party.gst}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.Text("DL No: ${party.dl}", style: const pw.TextStyle(fontSize: 8)),
          ]),
        ]),
      ),
      pw.SizedBox(height: 15),
    ]);
  }

  // --- 2. STATEMENT TABLE (Debit/Credit/Balance) ---
  static pw.Widget _buildStatementTable(List<Map<String, dynamic>> data) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.black),
      cellStyle: const pw.TextStyle(fontSize: 8),
      columnWidths: {
        0: const pw.FixedColumnWidth(45), // Date
        1: const pw.FlexColumnWidth(3),   // Particulars
        2: const pw.FixedColumnWidth(50), // Type
        3: const pw.FixedColumnWidth(60), // Debit
        4: const pw.FixedColumnWidth(60), // Credit
        5: const pw.FixedColumnWidth(70), // Balance
      },
      headers: ['DATE', 'PARTICULARS / REF NO', 'TYPE', 'DEBIT(Dr)', 'CREDIT(Cr)', 'OUTSTANDING'],
      data: data.map((row) {
        bool isOp = row['type'] == 'OPENING';
        return [
          DateFormat('dd/MM/yy').format(row['date']),
          isOp ? row['particulars'] : row['ref'],
          row['type'],
          row['dr'] > 0 ? row['dr'].toStringAsFixed(2) : "",
          row['cr'] > 0 ? row['cr'].toStringAsFixed(2) : "",
          pw.Text(row['bal'].toStringAsFixed(2), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ];
      }).toList(),
    );
  }

  // --- 3. SUMMARY & CLOSING BOX ---
  static pw.Widget _buildSummaryBox(double dr, double cr, double bal, String shopName) {
    return pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Container(width: 250, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text("Notes:", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.Text("1. Please check the statement and report any discrepancy within 7 days.", style: const pw.TextStyle(fontSize: 7)),
        pw.Text("2. This is a system-generated document and does not require a physical signature.", style: const pw.TextStyle(fontSize: 7)),
      ])),
      pw.Container(
        width: 220,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 1), color: PdfColors.grey100),
        child: pw.Column(children: [
          _sumRow("Total Debits (+):", dr),
          _sumRow("Total Credits (-):", cr),
          pw.Divider(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text("CLOSING BALANCE:", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text("Rs. ${bal.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          ]),
          pw.SizedBox(height: 10),
          pw.Text("For $shopName", style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 20),
          pw.Text("Authorised Signatory", style: const pw.TextStyle(fontSize: 7)),
        ]),
      )
    ]);
  }

  static pw.Widget _sumRow(String l, double v) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
    pw.Text(l, style: const pw.TextStyle(fontSize: 8)),
    pw.Text(v.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8)),
  ]);

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(alignment: pw.Alignment.centerRight, margin: const pw.EdgeInsets.only(top: 10), child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)));
  }
}
