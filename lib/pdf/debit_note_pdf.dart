// FILE: lib/pdf/debit_note_pdf.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../gateway/company_registry_model.dart';
import '../logic/app_settings_model.dart';
import 'pdf_master_service.dart';
import '../logic/app_billing_gst_engine.dart';
import '../logic/gst_compliance_helper.dart';

class DebitNotePdf {
  static Future<void> generate(PurchaseReturn ret, Party supplier, CompanyProfile shop, AppConfig config) async {
    final pdf = pw.Document();
    const double masterWidth = 800;
    const int itemsPerPage = 18;

    String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
    bool isLocal = GstComplianceHelper.isIntraStateReturn(
      shopGstin: shop.gstin,
      shopState: shop.state,
      partyGstin: supplier.gst.isNotEmpty ? supplier.gst : ret.partyGstin,
      partyState: supplier.state.isNotEmpty ? supplier.state : ret.partyState,
    );

    final originSummary = GstComplianceHelper.summarizeOriginInvoices(
      ret.items,
      fallbackBillNo: ret.origBillNo,
      fallbackDate: ret.origBillDate,
    );
    final bool showReverseLabel = GstComplianceHelper.isCommercialNoteAllowed(config);

    // Logic: Categorization 100% aligned with plan
    final sellable = ret.items.where((i) => i.isBreakage == false).toList();
    final breakage = ret.items.where((i) => i.isBreakage == true).toList();

    List<dynamic> layoutList = [];
    if (sellable.isNotEmpty) {
      layoutList.add(">> PURCHASE RETURN (STOCK OUT)");
      layoutList.addAll(sellable);
    }
    if (breakage.isNotEmpty) {
      layoutList.add(">> BREAKAGE/EXPIRY RETURN (NON-SELLABLE)");
      layoutList.addAll(breakage);
    }

    int totalPages = (layoutList.length / itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    for (int pageNum = 0; pageNum < totalPages; pageNum++) {
      int start = pageNum * itemsPerPage;
      int end = (start + itemsPerPage < layoutList.length) ? start + itemsPerPage : layoutList.length;
      List<dynamic> pageItems = layoutList.sublist(start, end);
      bool isLastPage = (pageNum == totalPages - 1);

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15), // 🆕 Strictly locked to 15 vertical margin
        build: (pw.Context context) => pw.Column(children: [
          pw.Container(
            width: masterWidth,
            height: 550, // 🆕 Height strictly locked to 550 points (pageHeightLimit)
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
            child: pw.Column(children: [
              // --- HEADER BOXES (Exact match to Architect Sale Bill) ---
              pw.Row(children: [
                _hBox(280, true, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text(shop.address, style: pw.TextStyle(fontSize: 7), maxLines: 2),
                  pw.Text("GSTIN: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Mob: ${shop.phone} | Email: ${shop.email.toLowerCase()}", style: pw.TextStyle(fontSize: 7)),
                ])),
                _hBox(175, true, pw.Column(children: [
                  pw.Text(ret.isCommercial ? "COMMERCIAL DEBIT NOTE" : "DEBIT NOTE", style: pw.TextStyle(fontSize: ret.isCommercial ? 9.5 : 11, fontWeight: pw.FontWeight.bold, color: ret.isCommercial ? PdfColors.orange900 : PdfColors.brown900)),
                  if (ret.isCommercial) pw.Text("(SEC 34 - WITHOUT GST)", style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                  pw.Divider(thickness: 0.5),
                  pw.Text("No: ${ret.billNo} | ${ret.paymentMode.isNotEmpty ? ret.paymentMode : 'CREDIT'}", style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text(DateFormat('dd/MM/yyyy').format(ret.date), style: pw.TextStyle(fontSize: 8)),
                  if (originSummary.headerBillNo.isNotEmpty)
                    pw.Text("Orig: ${originSummary.headerBillNo}${(originSummary.uniqueCount == 1 && originSummary.headerDate != null) ? ' (${DateFormat('dd/MM/yy').format(originSummary.headerDate!)})' : ''}", style: pw.TextStyle(fontSize: 6.5), maxLines: 1),
                ])),
                _hBox(345, false, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text("SEND TO SUPPLIER:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                  pw.Text(supplier.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text("${supplier.address}, ${supplier.city}", style: pw.TextStyle(fontSize: 7.5), maxLines: 2),
                  pw.Text("GST: ${supplier.gst} | DL: ${supplier.dl}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text("PAN: ${supplier.pan} | Mob: ${supplier.phone}", style: pw.TextStyle(fontSize: 7)),
                  if (supplier.email.isNotEmpty) pw.Text("Email: ${supplier.email.toLowerCase()}", style: pw.TextStyle(fontSize: 7)),
                ])),
              ]),

              // --- SYNCED TABLE GRID (15 COLUMNS - TOTAL 800PT WITH DISC% & TAXABLE) ---
              pw.Container(color: PdfColors.grey200, child: pw.Row(children: [
                _tCol("S.N", 22), _tCol("Qty+Free", 44), _tCol("Pack", 35),
                _tCol("Product Name", 132, isLeft: true),
                _tCol("Orig. Bill", 58),
                _tCol("Batch", 62), _tCol("Exp", 38), _tCol("HSN", 45),
                _tCol("MRP", 46), _tCol("Rate", 46),
                _tCol("Disc%", 34), _tCol("Taxable", 62),
                if (isLocal) ...[_tCol("CGST%", 40), _tCol("SGST%", 40)] else ...[_tCol("GST%", 35), _tCol("IGST", 45)],
                _tCol("Total", 96, isLast: true),
              ])),

              // --- SMART CONTENT ---
              pw.Expanded(child: pw.Column(children: pageItems.map((entry) {
                if (entry is String) {
                  return pw.Container(width: masterWidth, padding: const pw.EdgeInsets.all(3), decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                  child: pw.Text(entry, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.brown900)));
                }
                PurchaseItem i = entry as PurchaseItem;
                int sNo = ret.items.indexOf(i) + 1;
                bool isShaded = config.useZebraShading && (sNo % 2 != 0);

                double grossRow = i.purchaseRate * i.qty;
                double taxableRow = grossRow - i.discountRupees;
                if (taxableRow < 0) taxableRow = 0.0;
                double discPct = i.discountPer > 0
                    ? i.discountPer
                    : (grossRow > 0 && i.discountRupees > 0 ? (i.discountRupees / grossRow) * 100.0 : 0.0);
                String discLabel = discPct > 0.005
                    ? "${discPct % 1 == 0 ? discPct.toInt() : discPct.toStringAsFixed(1)}%"
                    : "-";
                double effGst = ret.isCommercial ? 0.0 : i.gstRate;
                double taxAmt = ret.isCommercial ? 0.0 : (i.total - taxableRow);
                if (taxAmt < 0) taxAmt = 0.0;
                double rowTotal = ret.isCommercial ? taxableRow : i.total;

                return pw.Container(
                  decoration: pw.BoxDecoration(color: isShaded ? PdfColors.grey50 : PdfColors.white, border: pw.Border(bottom: pw.BorderSide(width: 0.1))),
                  child: pw.Row(children: [
                    _cell("$sNo", 22),
                    _cell("${fmt(i.qty)}+${fmt(i.freeQty)}", 44),
                    _cell(i.packing, 35),
                    pw.Container(width: 132, padding: const pw.EdgeInsets.only(left: 6), alignment: pw.Alignment.centerLeft, child: pw.Text(i.name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), maxLines: 1)),
                    _origCell(i.origBillNo, i.origBillDate, 58),
                    _cell(i.batch, 62), _cell(i.exp, 38), _cell(i.hsn, 45),
                    _cell(i.mrp.toStringAsFixed(2), 46),
                    _cell(i.purchaseRate.toStringAsFixed(2), 46),
                    _cell(discLabel, 34),
                    _cell(taxableRow.toStringAsFixed(2), 62),
                    if (isLocal) ...[
                      _cell("${(effGst / 2).toStringAsFixed(1)}%", 40),
                      _cell("${(effGst / 2).toStringAsFixed(1)}%", 40),
                    ] else ...[
                      _cell("${effGst.toStringAsFixed(1)}%", 35),
                      _cell(taxAmt.toStringAsFixed(1), 45),
                    ],
                    _cell(rowTotal.toStringAsFixed(2), 96),
                  ]),
                );
              }).toList())),

              if (isLastPage) _buildFixedSyncFooter(shop.name, ret, isLocal, showReverseLabel, config.signLabel)
            ]),
          ),
          pw.SizedBox(height: 4), // Professional margins spacer
          pw.Center(
            child: pw.Text(
              "This is a system-generated document. | Powered by Pharoah ERP [Download from Play Store] | Support: cloudcubeapps.ok@gmail.com",
              style: pw.TextStyle(fontSize: 5, color: PdfColors.grey600),
            ),
          ),
        ])
      ));
    }
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), format: PdfPageFormat.a4.landscape);
  }
  // 📧 NAYA: EMAIL KE LIYE BYTES GENERATE KARNA
  static Future<Uint8List> generateBytes(PurchaseReturn ret, Party supplier, CompanyProfile shop, AppConfig config) async {
    final pdf = pw.Document();
    const double masterWidth = 800;
    const int itemsPerPage = 18;
    String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
    bool isLocal = GstComplianceHelper.isIntraStateReturn(
      shopGstin: shop.gstin,
      shopState: shop.state,
      partyGstin: supplier.gst.isNotEmpty ? supplier.gst : ret.partyGstin,
      partyState: supplier.state.isNotEmpty ? supplier.state : ret.partyState,
    );

    final originSummary = GstComplianceHelper.summarizeOriginInvoices(
      ret.items,
      fallbackBillNo: ret.origBillNo,
      fallbackDate: ret.origBillDate,
    );
    final bool showReverseLabel = GstComplianceHelper.isCommercialNoteAllowed(config);

    final sellable = ret.items.where((i) => i.isBreakage == false).toList();
    final breakage = ret.items.where((i) => i.isBreakage == true).toList();

    List<dynamic> layoutList = [];
    if (sellable.isNotEmpty) { layoutList.add(">> PURCHASE RETURN (STOCK OUT)"); layoutList.addAll(sellable); }
    if (breakage.isNotEmpty) { layoutList.add(">> BREAKAGE/EXPIRY RETURN (NON-SELLABLE)"); layoutList.addAll(breakage); }

    int totalPages = (layoutList.length / itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    for (int pageNum = 0; pageNum < totalPages; pageNum++) {
      int start = pageNum * itemsPerPage;
      int end = (start + itemsPerPage < layoutList.length) ? start + itemsPerPage : layoutList.length;
      List<dynamic> pageItems = layoutList.sublist(start, end);
      bool isLastPage = (pageNum == totalPages - 1);

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(15),
        build: (pw.Context context) => pw.Container(
          width: masterWidth,
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
          child: pw.Column(children: [
            pw.Row(children: [
              _hBox(280, true, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                pw.Text(shop.address, style: pw.TextStyle(fontSize: 7), maxLines: 2),
                pw.Text("GSTIN: ${shop.gstin}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
              ])),
              _hBox(175, true, pw.Column(children: [
                pw.Text(ret.isCommercial ? "COMMERCIAL DEBIT NOTE" : "DEBIT NOTE", style: pw.TextStyle(fontSize: ret.isCommercial ? 9.5 : 11, fontWeight: pw.FontWeight.bold, color: ret.isCommercial ? PdfColors.orange900 : PdfColors.brown900)),
                if (ret.isCommercial) pw.Text("(SEC 34 - WITHOUT GST)", style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                pw.Divider(thickness: 0.5),
                pw.Text("No: ${ret.billNo} | ${ret.paymentMode.isNotEmpty ? ret.paymentMode : 'CREDIT'}", style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                pw.Text(DateFormat('dd/MM/yyyy').format(ret.date), style: pw.TextStyle(fontSize: 8)),
                if (originSummary.headerBillNo.isNotEmpty)
                  pw.Text("Orig: ${originSummary.headerBillNo}${(originSummary.uniqueCount == 1 && originSummary.headerDate != null) ? ' (${DateFormat('dd/MM/yy').format(originSummary.headerDate!)})' : ''}", style: pw.TextStyle(fontSize: 6.5), maxLines: 1),
              ])),
              _hBox(345, false, pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text("SEND TO SUPPLIER:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                pw.Text(supplier.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                pw.Text("GST: ${supplier.gst}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ])),
            ]),
            pw.Container(color: PdfColors.grey200, child: pw.Row(children: [
              _tCol("S.N", 22), _tCol("Qty+Free", 44), _tCol("Pack", 35), _tCol("Product Name", 132, isLeft: true), _tCol("Orig. Bill", 58),
              _tCol("Batch", 62), _tCol("Exp", 38), _tCol("HSN", 45), _tCol("MRP", 46), _tCol("Rate", 46),
              _tCol("Disc%", 34), _tCol("Taxable", 62),
              if (isLocal) ...[_tCol("CGST%", 40), _tCol("SGST%", 40)] else ...[_tCol("GST%", 35), _tCol("IGST", 45)],
              _tCol("Total", 96, isLast: true),
            ])),
            pw.Expanded(child: pw.Column(children: pageItems.map((entry) {
              if (entry is String) return pw.Container(width: masterWidth, padding: const pw.EdgeInsets.all(3), decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border(bottom: pw.BorderSide(width: 0.5))), child: pw.Text(entry, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)));
              PurchaseItem i = entry as PurchaseItem;
              double grossRow = i.purchaseRate * i.qty;
              double taxableRow = grossRow - i.discountRupees;
              if (taxableRow < 0) taxableRow = 0.0;
              double discPct = i.discountPer > 0
                  ? i.discountPer
                  : (grossRow > 0 && i.discountRupees > 0 ? (i.discountRupees / grossRow) * 100.0 : 0.0);
              String discLabel = discPct > 0.005
                  ? "${discPct % 1 == 0 ? discPct.toInt() : discPct.toStringAsFixed(1)}%"
                  : "-";
              double effGst = ret.isCommercial ? 0.0 : i.gstRate;
              double taxAmt = ret.isCommercial ? 0.0 : (i.total - taxableRow);
              if (taxAmt < 0) taxAmt = 0.0;
              double rowTotal = ret.isCommercial ? taxableRow : i.total;
              return pw.Container(decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1))), child: pw.Row(children: [
                  _cell("${ret.items.indexOf(i) + 1}", 22), _cell("${fmt(i.qty)}+${fmt(i.freeQty)}", 44), _cell(i.packing, 35),
                  pw.Container(width: 132, padding: const pw.EdgeInsets.only(left: 6), alignment: pw.Alignment.centerLeft, child: pw.Text(i.name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), maxLines: 1)),
                  _origCell(i.origBillNo, i.origBillDate, 58),
                  _cell(i.batch, 62), _cell(i.exp, 38), _cell(i.hsn, 45), _cell(i.mrp.toStringAsFixed(2), 46), _cell(i.purchaseRate.toStringAsFixed(2), 46),
                  _cell(discLabel, 34), _cell(taxableRow.toStringAsFixed(2), 62),
                  if (isLocal) ...[
                    _cell("${(effGst / 2).toStringAsFixed(1)}%", 40),
                    _cell("${(effGst / 2).toStringAsFixed(1)}%", 40),
                  ] else ...[
                    _cell("${effGst.toStringAsFixed(1)}%", 35),
                    _cell(taxAmt.toStringAsFixed(1), 45),
                  ],
                  _cell(rowTotal.toStringAsFixed(2), 96),
              ]));
            }).toList())),
            if (isLastPage) _buildFixedSyncFooter(shop.name, ret, isLocal, showReverseLabel, config.signLabel)
          ])),
      ));
    }
    return pdf.save();
  }

  static pw.Widget _hBox(double w, bool b, pw.Widget child) => pw.Container(width: w, height: 105, padding: const pw.EdgeInsets.all(5), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: b ? 0.5 : 0), bottom: const pw.BorderSide(width: 0.5))), child: child);
  static pw.Widget _tCol(String t, double w, {bool isLast = false, bool isLeft = false}) => pw.Container(width: w, height: 20, alignment: isLeft ? pw.Alignment.centerLeft : pw.Alignment.center, padding: pw.EdgeInsets.only(left: 5), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: isLast ? 0 : 0.5), bottom: const pw.BorderSide(width: 0.5))), child: pw.Text(t, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)));
  static pw.Widget _cell(String t, double w) => pw.Container(width: w, height: 18, alignment: pw.Alignment.center, decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.2, color: PdfColors.grey))), child: pw.Text(t, style: pw.TextStyle(fontSize: 7.5)));
  static pw.Widget _origCell(String billNo, DateTime? date, double w) {
    final clean = billNo.trim();
    return pw.Container(
      width: w,
      height: 18,
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2),
      decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.2, color: PdfColors.grey))),
      child: clean.isEmpty
          ? pw.SizedBox()
          : pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(clean, style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold), maxLines: 1),
                if (date != null)
                  pw.Text(DateFormat('dd/MM/yy').format(date), style: pw.TextStyle(fontSize: 5, color: PdfColors.grey700), maxLines: 1),
              ],
            ),
    );
  }

  static pw.Widget _buildFixedSyncFooter(String n, PurchaseReturn ret, bool local, bool showReverseLabel, String signLabel) {
    final originSummary = GstComplianceHelper.summarizeOriginInvoices(
      ret.items,
      fallbackBillNo: ret.origBillNo,
      fallbackDate: ret.origBillDate,
    );
    final summary = AppBillingGstEngine.calculateForPurchase(
      items: ret.items,
      extraDiscount: ret.extraDiscount,
      isLocal: local,
      isCommercial: ret.isCommercial,
    );
    final String sigText = signLabel.trim().isNotEmpty ? signLabel.trim().toUpperCase() : "AUTHORISED SIGNATORY";
    return pw.Container(height: 110, decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))), child: pw.Row(children: [
      pw.Container(width: 330, padding: const pw.EdgeInsets.all(5), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text("Amt Words: RUPEES ${PdfMasterService.numberToWords(summary.finalGrandTotal.round())} ONLY", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
        if (ret.reason.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text("Reason: ${ret.reason}", style: const pw.TextStyle(fontSize: 7))),
        if (originSummary.footerRefText.isNotEmpty) pw.Text("Ref Bill: ${originSummary.footerRefText}", style: pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700), maxLines: 2),
        pw.Spacer(),
        pw.Text(
          ret.isCommercial
              ? "Commercial Debit Note (Without GST / Sec 34(2) CGST Act)."
              : (!showReverseLabel
                  ? "Note: Outward Debit Settlement with Distributor (Section 34 CGST Compliant) | Reverse Charge: No"
                  : "Note: Outward Debit Settlement with Distributor (Section 34 CGST Compliant)."),
          style: pw.TextStyle(fontSize: 6, color: ret.isCommercial ? PdfColors.orange900 : PdfColors.black),
        ),
      ])),
      pw.Container(width: 250, padding: const pw.EdgeInsets.all(4), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))), child: pw.Column(children: [
        _fRow("GROSS TAXABLE", summary.grossTaxable),
        if (summary.extraDiscount > 0) _fRow("EXTRA DISCOUNT (-)", summary.extraDiscount),
        if (summary.extraDiscount > 0) _fRow("NET TAXABLE", summary.netTaxable),
        if (local) ...[
          if (summary.totalCGST > 0) _fRow(showReverseLabel ? "CGST REVERSE" : "CGST TOTAL", summary.totalCGST),
          if (summary.totalSGST > 0) _fRow(showReverseLabel ? "SGST REVERSE" : "SGST TOTAL", summary.totalSGST),
        ] else ...[
          if (summary.totalIGST > 0) _fRow(showReverseLabel ? "IGST REVERSE" : "IGST TOTAL", summary.totalIGST),
        ],
        if (summary.roundOff != 0) _fRow("ROUND OFF", summary.roundOff),
        pw.Divider(thickness: 0.5),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text("NET DEBIT", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text("Rs. ${summary.finalGrandTotal.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.brown900)),
        ]),
      ])),
      pw.Container(width: 220, padding: const pw.EdgeInsets.all(5), child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text("For $n", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 30),
        pw.Text(sigText, style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      ])),
    ]));
  }
    static pw.Widget _fRow(String l, double v) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(l, style: pw.TextStyle(fontSize: 7.5)), pw.Text(v.toStringAsFixed(2), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))]);
}
