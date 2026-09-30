import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../models.dart';
import '../../gateway/company_registry_model.dart';

class ExpiryAuditPdf {
  static Future<void> generate({
    required CompanyProfile shop,
    required Company selectedCompany,
    required List<Map<String, dynamic>> auditData,
    required int horizon,
    required String viewMode,
  }) async {
    final pdf = pw.Document();

    // Summary calculation for footer
    double totalLossVal = auditData.fold(0, (sum, item) => sum + item['val']);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(30),
        header: (context) => _buildHeader(shop, selectedCompany.name, horizon),
        build: (context) {
          return [
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.red900),
              cellStyle: const pw.TextStyle(fontSize: 8),
              columnWidths: {
                0: const pw.FixedColumnWidth(30), // SN
                1: const pw.FlexColumnWidth(3),   // Product
                2: const pw.FixedColumnWidth(80), // Batch
                3: const pw.FixedColumnWidth(60), // Exp
                4: const pw.FixedColumnWidth(60), // Qty
                5: const pw.FixedColumnWidth(80), // Supplier (Conditional)
                6: const pw.FixedColumnWidth(70), // Value
              },
              headers: [
                'SN', 'PRODUCT NAME', 'BATCH', 'EXPIRY', 'QTY', 
                viewMode == "PARTY" ? 'LAST SUPPLIER' : 'STATUS', 
                'LOSS VAL'
              ],
              data: List.generate(auditData.length, (index) {
                final row = auditData[index];
                return [
                  "${index + 1}",
                  row['med'].name,
                  row['batch'].batch,
                  row['batch'].exp,
                  row['batch'].qty.toStringAsFixed(2),
                  viewMode == "PARTY" ? (row['supplier'] ?? "N/A") : row['status'],
                  "Rs. ${row['val'].toStringAsFixed(2)}",
                ];
              }),
            ),
            pw.SizedBox(height: 20),
            _buildSummaryFooter(totalLossVal, shop.name),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Expiry_Audit_${selectedCompany.name}');
  }

  static pw.Widget _buildHeader(CompanyProfile shop, String company, int horizon) {
    return pw.Column(children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
          pw.Text(shop.address, style: const pw.TextStyle(fontSize: 8)),
          pw.Text("GSTIN: ${shop.gstin}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text("COMPANY EXPIRY AUDIT", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text("Horizon: Next $horizon Months", style: const pw.TextStyle(fontSize: 9)),
          pw.Text("Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 9)),
        ]),
      ]),
      pw.SizedBox(height: 10),
      pw.Container(
        width: double.infinity, padding: const pw.EdgeInsets.all(5),
        color: PdfColors.red50,
        child: pw.Text("AUDIT TARGET: $company", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
      ),
      pw.SizedBox(height: 10),
    ]);
  }

  static pw.Widget _buildSummaryFooter(double total, String shopName) {
    return pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Container(width: 300, child: pw.Text("Note: This report lists items expiring within the selected timeline. Please process return claims with the respective suppliers using the 'Last Supplier' info.", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700))),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 1), color: PdfColors.grey100),
        child: pw.Column(children: [
          pw.Text("ESTIMATED TOTAL LOSS", style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.Text("Rs. ${total.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
          pw.SizedBox(height: 5),
          pw.Text("For $shopName", style: const pw.TextStyle(fontSize: 8)),
        ]),
      )
    ]);
  }
}
