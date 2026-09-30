// FILE: lib/pdf/history_report_pdf.dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../gateway/company_registry_model.dart';
import 'pdf_master_service.dart';

class HistoryReportPdf {
  static Future<void> generate({
    required List<Voucher> list, 
    required DateTime fDate, 
    required DateTime tDate, 
    required CompanyProfile shop,
    required double openingFlow,
  }) async {
    final pdf = pw.Document();

    // Sum of filtered list
    double totalRec = list.where((v) => v.type == "Receipt" && v.status == "Active").fold(0.0, (s, e) => s + e.amount);
    double totalPaid = list.where((v) => v.type == "Payment" && v.status == "Active").fold(0.0, (s, e) => s + e.amount);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(25),
      header: (pw.Context context) => pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
            pw.Text(shop.address, style: const pw.TextStyle(fontSize: 8)),
            pw.Text("GSTIN: ${shop.gstin} | Mob: ${shop.phone}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text("ACCOUNT STATEMENT", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
            pw.Text("Period: ${DateFormat('dd/MM/yy').format(fDate)} to ${DateFormat('dd/MM/yy').format(tDate)}", style: const pw.TextStyle(fontSize: 9)),
          ]),
        ]),
        pw.SizedBox(height: 5),
        pw.Divider(thickness: 1, color: PdfColors.indigo900),
        
        // OPENING FLOW DISPLAY
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text("OPENING BALANCE (Vouchers before ${DateFormat('dd/MM/yy').format(fDate)})", 
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.Text("Rs. ${openingFlow.toStringAsFixed(2)}", 
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: openingFlow >= 0 ? PdfColors.green900 : PdfColors.red900)),
          ]),
        ),
      ]),
      build: (pw.Context context) => [
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
          cellStyle: const pw.TextStyle(fontSize: 8),
          columnWidths: {
            0: const pw.FixedColumnWidth(50), // Date
            1: const pw.FixedColumnWidth(60), // ID
            2: const pw.FlexColumnWidth(3),   // Account Name
            3: const pw.FixedColumnWidth(60), // Mode
            4: const pw.FixedColumnWidth(70), // Debit
            5: const pw.FixedColumnWidth(70), // Credit
          },
          headers: ['DATE', 'TXN ID', 'PARTICULARS / ACCOUNT NAME', 'MODE', 'PAID (Dr)', 'REC (Cr)'],
          data: list.map((v) {
            bool isCan = v.status == "Cancelled";
            bool isReceipt = v.type == "Receipt";
            return [
              DateFormat('dd/MM/yy').format(v.date),
              v.voucherNo,
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(v.partyName.toUpperCase(), style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, 
                  decoration: isCan ? pw.TextDecoration.lineThrough : null, 
                  color: isCan ? PdfColors.red900 : PdfColors.black
                )),
                pw.Text("${isReceipt ? 'INTO' : 'FROM'}: ${v.depositedIn.toUpperCase()}", style: const pw.TextStyle(fontSize: 6, color: PdfColors.blueGrey800)),
                if(v.narration.isNotEmpty) pw.Text(v.narration, style: const pw.TextStyle(fontSize: 6, fontStyle: pw.FontStyle.italic)),
              ]),
              v.paymentMode,
              isReceipt ? "" : (isCan ? "(Cancelled)" : v.amount.toStringAsFixed(2)),
              isReceipt ? (isCan ? "(Cancelled)" : v.amount.toStringAsFixed(2)) : "",
            ];
          }).toList(),
        ),
      ],
      footer: (pw.Context context) => pw.Column(children: [
        pw.Divider(thickness: 0.5),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text("Pharoah ERP Audit History", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          pw.Row(children: [
            _statTile("PERIOD REC: ", totalRec, PdfColors.green900),
            pw.SizedBox(width: 25),
            _statTile("PERIOD PAID: ", totalPaid, PdfColors.red900),
          ]),
        ]),
      ]),
    ));

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Statement_${shop.name}');
  }

  static pw.Widget _statTile(String label, double val, PdfColor color) => pw.RichText(text: pw.TextSpan(children: [
    pw.TextSpan(text: label, style: const pw.TextStyle(fontSize: 8)),
    pw.TextSpan(text: "Rs. ${val.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color)),
  ]));
}
