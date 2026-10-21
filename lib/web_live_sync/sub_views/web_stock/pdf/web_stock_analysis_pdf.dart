// FILE: lib/web_live_sync/sub_views/web_stock/pdf/web_stock_analysis_pdf.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:pharoah_erp/web_live_sync/web_models.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';

class WebStockAnalysisPdf {
  // ===========================================================================
  // 1. A4 LANDSCAPE FULL STOCK VALUATION REPORT
  // ===========================================================================
  static Future<Uint8List> generateStockValuationReportBytes({
    required List<Medicine> medicines,
    required PharoahWebManager webPh,
    required String selectedCompanyName,
    required String filterTag,
  }) async {
    final pdf = pw.Document();

    final shopName = (webPh.companyProfile['name'] ?? webPh.companyName ?? 'PHAROAH ERP STORE').toString().toUpperCase();
    final shopGst = (webPh.companyProfile['gst'] ?? 'UNREGISTERED').toString().toUpperCase();
    final shopAddress = (webPh.companyProfile['address'] ?? '').toString();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    double totalStockUnits = 0.0;
    double totalPurValuation = 0.0;
    double totalMrpValuation = 0.0;

    for (var m in medicines) {
      totalStockUnits += m.stock;
      totalPurValuation += (m.stock * m.purRate);
      totalMrpValuation += (m.stock * m.mrp);
    }

    double marginPotential = totalMrpValuation > 0 ? ((totalMrpValuation - totalPurValuation) / totalMrpValuation) * 100 : 0.0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(shopName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    if (shopAddress.isNotEmpty)
                      pw.Text(shopAddress, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    pw.Text("GSTIN: $shopGst", style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("INVENTORY VALUATION REPORT", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                    pw.Text("Date: $dateStr", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text("Filter: $filterTag  •  Company: $selectedCompanyName", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 1, color: PdfColors.blueGrey800),
            pw.SizedBox(height: 4),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text("Pharoah ERP Stock Audit System", style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
            pw.Text("Page ${context.pageNumber} of ${context.pagesCount}", style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
          ],
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(25),  // Sr
              1: pw.FixedColumnWidth(55),  // Code
              2: pw.FlexColumnWidth(3.2),  // Name
              3: pw.FixedColumnWidth(45),  // Pack
              4: pw.FlexColumnWidth(2.0),  // Company
              5: pw.FixedColumnWidth(30),  // GST
              6: pw.FixedColumnWidth(45),  // Stock
              7: pw.FixedColumnWidth(50),  // Pur.Rate
              8: pw.FixedColumnWidth(50),  // MRP
              9: pw.FixedColumnWidth(60),  // Pur.Val
              10: pw.FixedColumnWidth(60), // MRP.Val
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
                children: [
                  _pdfTh("SR"),
                  _pdfTh("CODE"),
                  _pdfTh("PRODUCT NAME", isLeft: true),
                  _pdfTh("PACK"),
                  _pdfTh("COMPANY", isLeft: true),
                  _pdfTh("GST", isRight: true),
                  _pdfTh("STOCK", isRight: true),
                  _pdfTh("PUR.RATE", isRight: true),
                  _pdfTh("MRP", isRight: true),
                  _pdfTh("PUR.VAL", isRight: true),
                  _pdfTh("MRP.VAL", isRight: true),
                ],
              ),
              ...medicines.asMap().entries.map((entry) {
                int index = entry.key + 1;
                final m = entry.value;

                String cName = selectedCompanyName;
                if (selectedCompanyName == "All Companies") {
                  if (m.companyId.isNotEmpty) {
                    try {
                      cName = webPh.companies.firstWhere((c) => c.id == m.companyId || c.name.toUpperCase() == m.companyId.toUpperCase()).name;
                    } catch (_) {
                      cName = m.companyId;
                    }
                  } else {
                    cName = "Unassigned";
                  }
                }

                double purVal = m.stock * m.purRate;
                double mrpVal = m.stock * m.mrp;

                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: index % 2 == 0 ? PdfColors.grey100 : PdfColors.white,
                  ),
                  children: [
                    _pdfTd("$index"),
                    _pdfTd(m.systemId.isNotEmpty ? m.systemId : m.id),
                    _pdfTd(m.name, isLeft: true, isBold: true),
                    _pdfTd(m.packing),
                    _pdfTd(cName, isLeft: true),
                    _pdfTd("${m.gst.toInt()}%", isRight: true),
                    _pdfTd("${m.stock.toInt()}", isRight: true, isBold: true),
                    _pdfTd(m.purRate.toStringAsFixed(2), isRight: true),
                    _pdfTd(m.mrp.toStringAsFixed(2), isRight: true),
                    _pdfTd(purVal.toStringAsFixed(2), isRight: true),
                    _pdfTd(mrpVal.toStringAsFixed(2), isRight: true),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 12),
          // SUMMARY BOX
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              border: pw.Border.all(color: PdfColors.blueGrey),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _pdfStat("TOTAL PRODUCTS", "${medicines.length} Items"),
                _pdfStat("TOTAL STOCK QUANTITY", "${totalStockUnits.toInt()} Units"),
                _pdfStat("TOTAL PURCHASE VALUATION", "Rs. ${totalPurValuation.toStringAsFixed(2)}"),
                _pdfStat("TOTAL MRP VALUATION", "Rs. ${totalMrpValuation.toStringAsFixed(2)}"),
                _pdfStat("POTENTIAL GROSS MARGIN", "${marginPotential.toStringAsFixed(1)}%"),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ===========================================================================
  // 2. PRODUCT 360° MOVEMENT LEDGER (A4 PORTRAIT)
  // ===========================================================================
  static Future<Uint8List> generateItemMovementLedgerPdf({
    required Medicine medicine,
    required String companyName,
    required List<Map<String, dynamic>> movements,
    required PharoahWebManager webPh,
  }) async {
    final pdf = pw.Document();

    final shopName = (webPh.companyProfile['name'] ?? webPh.companyName ?? 'PHAROAH STORE').toString().toUpperCase();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(shopName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text("PRODUCT MOVEMENT PASSBOOK", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Text("Date: $dateStr", style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
              ],
            ),
            pw.SizedBox(height: 8),
            // Product info banner
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Item: ${medicine.name} (${medicine.packing})", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.Text("Company: $companyName", style: const pw.TextStyle(fontSize: 9)),
                  pw.Text("Current Stock: ${medicine.stock.toInt()} Qty", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
                  pw.Text("MRP: Rs. ${medicine.mrp.toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
          ],
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(55),  // Date
              1: pw.FlexColumnWidth(2.0),  // Type
              2: pw.FixedColumnWidth(65),  // Doc
              3: pw.FlexColumnWidth(2.5),  // Party
              4: pw.FixedColumnWidth(50),  // Batch
              5: pw.FixedColumnWidth(40),  // In
              6: pw.FixedColumnWidth(40),  // Out
              7: pw.FixedColumnWidth(45),  // Rate
              8: pw.FixedColumnWidth(50),  // Balance
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
                children: [
                  _pdfTh("DATE"),
                  _pdfTh("TYPE", isLeft: true),
                  _pdfTh("DOC #"),
                  _pdfTh("PARTY", isLeft: true),
                  _pdfTh("BATCH"),
                  _pdfTh("IN (+)", isRight: true),
                  _pdfTh("OUT (-)", isRight: true),
                  _pdfTh("RATE", isRight: true),
                  _pdfTh("BALANCE", isRight: true),
                ],
              ),
              ...movements.asMap().entries.map((entry) {
                final t = entry.value;
                int idx = entry.key;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: idx % 2 == 0 ? PdfColors.grey50 : PdfColors.white),
                  children: [
                    _pdfTd(DateFormat('dd/MM/yy').format(t['date'] as DateTime)),
                    _pdfTd(t['typeLabel'].toString(), isLeft: true),
                    _pdfTd(t['docNo'].toString(), isBold: true),
                    _pdfTd(t['party'].toString(), isLeft: true),
                    _pdfTd(t['batch'].toString()),
                    _pdfTd((t['inQty'] as double) > 0 ? "+${(t['inQty'] as double).toInt()}" : "-", isRight: true),
                    _pdfTd((t['outQty'] as double) > 0 ? "-${(t['outQty'] as double).toInt()}" : "-", isRight: true),
                    _pdfTd((t['rate'] as double).toStringAsFixed(2), isRight: true),
                    _pdfTd("${(t['balance'] as double).toInt()} Qty", isRight: true, isBold: true),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _pdfTh(String text, {bool isLeft = false, bool isRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(
        text,
        textAlign: isLeft ? pw.TextAlign.left : (isRight ? pw.TextAlign.right : pw.TextAlign.center),
        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
      ),
    );
  }

  static pw.Widget _pdfTd(String text, {bool isLeft = false, bool isRight = false, bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(
        text,
        textAlign: isLeft ? pw.TextAlign.left : (isRight ? pw.TextAlign.right : pw.TextAlign.center),
        style: pw.TextStyle(fontSize: 8, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }

  static pw.Widget _pdfStat(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
      ],
    );
  }
}
