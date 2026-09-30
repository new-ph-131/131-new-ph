import 'dart:io';
import 'dart:typed_data'; // 🔥 ADDED
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../models.dart';
import '../../gateway/company_registry_model.dart';

class PartyStockPdf {
  static Future<void> generate({
    required CompanyProfile shop,
    required Map<String, List<Map<String, dynamic>>> groupedData,
    required DateTime from,
    required DateTime to,
    required String mode,
  }) async {
    final pdf = pw.Document();
    double grandQty = 0; double grandFree = 0; double grandAmt = 0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(30),
        header: (context) => _buildHeader(shop, from, to, mode),
        build: (context) {
          List<pw.Widget> content = [];
          for (var pName in groupedData.keys) {
            var items = groupedData[pName]!;
            double pQty = 0; double pFree = 0; double pAmt = 0;
            List<List<String>> tableRows = [];
            for (var it in items) {
              pQty += it['qty']; pFree += it['free']; pAmt += it['total'];
              tableRows.add([
                it['name'], it['type'], it['qty'].toStringAsFixed(2),
                it['free'].toStringAsFixed(2), it['rate'].toStringAsFixed(2),
                it['total'].toStringAsFixed(2),
              ]);
            }
            grandQty += pQty; grandFree += pFree; grandAmt += pAmt;
            content.add(pw.Container(
              width: double.infinity, padding: const pw.EdgeInsets.all(5),
              margin: const pw.EdgeInsets.only(top: 15),
              decoration: const pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border(left: pw.BorderSide(width: 3, color: PdfColors.teal800))),
              child: pw.Text("PARTY: $pName", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            ));
            content.add(pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.teal900),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headers: ['PRODUCT NAME', 'TYPE', 'QTY', 'FREE', 'RATE', 'AMOUNT'],
              data: tableRows,
            ));
            content.add(pw.Container(
              padding: const pw.EdgeInsets.all(5),
              decoration: const pw.BoxDecoration(color: PdfColors.grey50),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                pw.Text("SUB-TOTAL: ", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Text("Q: ${pQty.toStringAsFixed(2)} | Amt: ₹${pAmt.toStringAsFixed(2)}", 
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
              ]),
            ));
          }
          content.add(pw.SizedBox(height: 30));
          content.add(pw.Container(
            padding: const pw.EdgeInsets.all(15),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1), color: PdfColors.teal50),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text("GRAND TOTAL STATEMENT", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text("NET AMOUNT: Rs. ${grandAmt.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
            ]),
          ));
          return content;
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Party_Stock_Report');
  }

  static Future<Uint8List> generateBytes({
    required CompanyProfile shop,
    required Map<String, List<Map<String, dynamic>>> groupedData,
    required DateTime from,
    required DateTime to,
    required String mode,
  }) async {
    final pdf = pw.Document();
    double grandQty = 0; double grandFree = 0; double grandAmt = 0;
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(30),
        header: (context) => _buildHeader(shop, from, to, mode),
        build: (context) {
          List<pw.Widget> content = [];
          for (var pName in groupedData.keys) {
            var items = groupedData[pName]!;
            double pQty = 0; double pFree = 0; double pAmt = 0;
            List<List<String>> tableRows = [];
            for (var it in items) {
              pQty += it['qty']; pFree += it['free']; pAmt += it['total'];
              tableRows.add([it['name'], it['type'], it['qty'].toStringAsFixed(2), it['free'].toStringAsFixed(2), it['rate'].toStringAsFixed(2), it['total'].toStringAsFixed(2)]);
            }
            grandQty += pQty; grandFree += pFree; grandAmt += pAmt;
            content.add(pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(5), margin: const pw.EdgeInsets.only(top: 15), decoration: const pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border(left: pw.BorderSide(width: 3, color: PdfColors.teal800))), child: pw.Text("PARTY: $pName", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))));
            content.add(pw.TableHelper.fromTextArray(headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white), headerDecoration: const pw.BoxDecoration(color: PdfColors.teal900), cellStyle: const pw.TextStyle(fontSize: 8), headers: ['PRODUCT NAME', 'TYPE', 'QTY', 'FREE', 'RATE', 'AMOUNT'], data: tableRows));
            content.add(pw.Container(padding: const pw.EdgeInsets.all(5), decoration: const pw.BoxDecoration(color: PdfColors.grey50), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text("SUB-TOTAL: ", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)), pw.Text("Q: ${pQty.toStringAsFixed(2)} | Amt: ₹${pAmt.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900))])));
          }
          content.add(pw.SizedBox(height: 30));
          content.add(pw.Container(padding: const pw.EdgeInsets.all(15), decoration: pw.BoxDecoration(border: pw.Border.all(width: 1), color: PdfColors.teal50), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text("GRAND TOTAL STATEMENT", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)), pw.Text("NET AMOUNT: Rs. ${grandAmt.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900))])));
          return content;
        },
      ),
    );
    return pdf.save();
  }

  static pw.Widget _buildHeader(CompanyProfile shop, DateTime from, DateTime to, String mode) {
    return pw.Column(children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
          pw.Text(shop.address, style: const pw.TextStyle(fontSize: 8)),
          pw.Text("GSTIN: ${shop.gstin}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text("PARTY WISE ITEM MOVEMENT", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text("Period: ${DateFormat('dd/MM/yy').format(from)} to ${DateFormat('dd/MM/yy').format(to)}", style: const pw.TextStyle(fontSize: 9)),
          pw.Text("Mode: ${mode == 'SALE_ONLY' ? 'SALE RECORDS' : 'PURCHASE & SALE'}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey700)),
        ]),
      ]),
      pw.Divider(thickness: 1, color: PdfColors.teal800),
      pw.SizedBox(height: 10),
    ]);
  }
}
