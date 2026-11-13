// FILE: lib/inventory_intel/app_stock/app_stock_pdf_and_export.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'app_stock_analytics_engine.dart';

class AppStockPdfAndExport {
  static Future<Uint8List> generateStockValuationPdfBytes({
    required List<Medicine> medicines,
    required PharoahManager ph,
    required String selectedCompanyName,
    required String filterTag,
  }) async {
    final pdf = pw.Document();
    final comp = ph.activeCompany;
    final shopName = (comp?.name ?? 'PHAROAH ERP STORE').toUpperCase();
    final shopGst = (comp?.gstin.isNotEmpty == true ? comp!.gstin : 'UNREGISTERED').toUpperCase();
    final shopAddress = comp?.address ?? '';
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    double totalStockUnits = 0.0;
    double totalPurValuation = 0.0;
    double totalMrpValuation = 0.0;

    for (final m in medicines) {
      totalStockUnits += m.stock;
      totalPurValuation += AppStockAnalyticsEngine.computePurValuation(ph, m);
      totalMrpValuation += AppStockAnalyticsEngine.computeMrpValuation(ph, m);
    }

    final double marginPotential = totalMrpValuation > 0
        ? ((totalMrpValuation - totalPurValuation) / totalMrpValuation) * 100
        : 0.0;

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
                    pw.Text(
                      shopName,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#004D40'),
                      ),
                    ),
                    if (shopAddress.isNotEmpty)
                      pw.Text(shopAddress, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    pw.Text("GSTIN: $shopGst", style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      "INVENTORY VALUATION REPORT",
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#00695C'),
                      ),
                    ),
                    pw.Text("Date: $dateStr  •  FY: ${ph.currentFY}", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text("Filter: $filterTag  •  Company: $selectedCompanyName", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 1, color: PdfColor.fromHex('#004D40')),
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
              0: pw.FixedColumnWidth(25),
              1: pw.FixedColumnWidth(55),
              2: pw.FlexColumnWidth(3.2),
              3: pw.FixedColumnWidth(45),
              4: pw.FlexColumnWidth(2.0),
              5: pw.FixedColumnWidth(30),
              6: pw.FixedColumnWidth(45),
              7: pw.FixedColumnWidth(50),
              8: pw.FixedColumnWidth(50),
              9: pw.FixedColumnWidth(60),
              10: pw.FixedColumnWidth(60),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E0F2F1')),
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
                final int index = entry.key + 1;
                final m = entry.value;
                final String cName = AppStockAnalyticsEngine.resolveCompanyName(ph, m.companyId);
                final double purVal = AppStockAnalyticsEngine.computePurValuation(ph, m);
                final double mrpVal = AppStockAnalyticsEngine.computeMrpValuation(ph, m);

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
                    _pdfTd(formatQty(m.stock), isRight: true, isBold: true),
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
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#EDF5F3'),
              border: pw.Border.all(color: PdfColor.fromHex('#00695C')),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _pdfStat("TOTAL PRODUCTS", "${medicines.length} Items"),
                _pdfStat("TOTAL STOCK QUANTITY", "${formatQty(totalStockUnits)} Units"),
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

  static Future<Uint8List> generateItemMovementLedgerPdfBytes({
    required Medicine medicine,
    required String companyName,
    required List<Map<String, dynamic>> movements,
    required PharoahManager ph,
  }) async {
    final pdf = pw.Document();
    final shopName = (ph.activeCompany?.name ?? 'PHAROAH ERP STORE').toUpperCase();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
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
                    pw.Text(
                      shopName,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#004D40'),
                      ),
                    ),
                    pw.Text("PRODUCT 360 MOVEMENT PASSBOOK", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Text("Date: $dateStr", style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#E0F2F1'),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Item: ${medicine.name} (${medicine.packing})", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
                  pw.Text("Company: $companyName", style: const pw.TextStyle(fontSize: 8.5)),
                  pw.Text("Stock: ${formatQty(medicine.stock)} Qty", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
                  pw.Text("MRP: Rs. ${medicine.mrp.toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 8.5)),
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
              0: pw.FixedColumnWidth(52),
              1: pw.FlexColumnWidth(2.0),
              2: pw.FixedColumnWidth(62),
              3: pw.FlexColumnWidth(2.3),
              4: pw.FixedColumnWidth(50),
              5: pw.FixedColumnWidth(40),
              6: pw.FixedColumnWidth(40),
              7: pw.FixedColumnWidth(45),
              8: pw.FixedColumnWidth(50),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E0F2F1')),
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
                final int idx = entry.key;
                final double inQ = (t['inQty'] as double?) ?? 0.0;
                final double outQ = (t['outQty'] as double?) ?? 0.0;
                final double rate = (t['rate'] as double?) ?? 0.0;
                final double bal = (t['balance'] as double?) ?? 0.0;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: idx % 2 == 0 ? PdfColors.grey50 : PdfColors.white),
                  children: [
                    _pdfTd(DateFormat('dd/MM/yy').format(t['date'] as DateTime)),
                    _pdfTd(t['typeLabel'].toString(), isLeft: true),
                    _pdfTd(t['docNo'].toString(), isBold: true),
                    _pdfTd(t['party'].toString(), isLeft: true),
                    _pdfTd(t['batch'].toString()),
                    _pdfTd(inQ > 0 ? "+${formatQty(inQ)}" : "-", isRight: true),
                    _pdfTd(outQ > 0 ? "-${formatQty(outQ)}" : "-", isRight: true),
                    _pdfTd(rate.toStringAsFixed(2), isRight: true),
                    _pdfTd("${formatQty(bal)} Qty", isRight: true, isBold: true),
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

  static ({Uint8List bytes, String fileName}) buildCsvPayload({
    required List<Medicine> medicines,
    required PharoahManager ph,
    required String selectedCompanyName,
    required String activeFilter,
  }) {
    final List<List<dynamic>> rows = [];
    final shopName = (ph.activeCompany?.name ?? 'PHAROAH STORE').toUpperCase();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    rows.add(["STORE:", shopName, "", "EXPORT DATE:", dateStr]);
    rows.add(["FILTER:", activeFilter, "", "COMPANY:", selectedCompanyName]);
    rows.add([]);
    rows.add([
      "SR NO",
      "ITEM CODE",
      "PRODUCT NAME",
      "PACKING",
      "FORM",
      "COMPANY / MANUFACTURER",
      "RACK LOCATION",
      "GST %",
      "CURRENT STOCK",
      "PURCHASE RATE (RS)",
      "MRP (RS)",
      "PURCHASE VALUATION (RS)",
      "MRP VALUATION (RS)",
      "ACTIVE BATCH COUNT",
      "REORDER LEVEL",
      "STOCK STATUS"
    ]);

    int sr = 1;
    for (final m in medicines) {
      final cName = AppStockAnalyticsEngine.resolveCompanyName(ph, m.companyId);
      final batches = ph.getBatchesForMedicine(m);
      final activeBatches = batches.where((b) => b.qty > 0).length;
      final purVal = AppStockAnalyticsEngine.computePurValuation(ph, m);
      final mrpVal = AppStockAnalyticsEngine.computeMrpValuation(ph, m);

      String status = "IN STOCK";
      if (m.stock <= 0) {
        status = "OUT OF STOCK";
      } else if (m.reorderLevel > 0 && m.stock <= m.reorderLevel) {
        status = "LOW STOCK";
      }

      rows.add([
        sr++,
        m.systemId.isNotEmpty ? m.systemId : m.id,
        m.name.toUpperCase(),
        m.packing,
        m.drugForm,
        cName.toUpperCase(),
        m.rackNo.isNotEmpty ? m.rackNo : "-",
        "${m.gst.toInt()}%",
        formatQty(m.stock),
        m.purRate.toStringAsFixed(2),
        m.mrp.toStringAsFixed(2),
        purVal.toStringAsFixed(2),
        mrpVal.toStringAsFixed(2),
        activeBatches,
        formatQty(m.reorderLevel),
        status,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final fileDate = DateFormat('ddMMMyy_HHmm').format(DateTime.now());
    final safeComp = selectedCompanyName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return (bytes: bytes, fileName: "Stock_Analysis_${safeComp}_$fileDate");
  }

  static Future<void> saveStockCsv({
    required List<Medicine> medicines,
    required PharoahManager ph,
    required String selectedCompanyName,
    required String activeFilter,
  }) async {
    final payload = buildCsvPayload(
      medicines: medicines,
      ph: ph,
      selectedCompanyName: selectedCompanyName,
      activeFilter: activeFilter,
    );
    await FileSaver.instance.saveAs(
      name: payload.fileName,
      bytes: payload.bytes,
      ext: "csv",
      mimeType: MimeType.csv,
    );
  }

  static Future<void> shareStockCsv({
    required List<Medicine> medicines,
    required PharoahManager ph,
    required String selectedCompanyName,
    required String activeFilter,
  }) async {
    final payload = buildCsvPayload(
      medicines: medicines,
      ph: ph,
      selectedCompanyName: selectedCompanyName,
      activeFilter: activeFilter,
    );
    await Share.shareXFiles(
      [
        XFile.fromData(
          payload.bytes,
          mimeType: 'text/csv',
          name: '${payload.fileName}.csv',
        ),
      ],
      subject: 'Stock Valuation Report (${payload.fileName})',
    );
  }

  static pw.Widget _pdfTh(String text, {bool isLeft = false, bool isRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(
        text,
        textAlign: isLeft ? pw.TextAlign.left : (isRight ? pw.TextAlign.right : pw.TextAlign.center),
        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#004D40')),
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
        pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#004D40'))),
      ],
    );
  }
}
