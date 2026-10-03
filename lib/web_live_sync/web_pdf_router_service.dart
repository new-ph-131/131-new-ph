// FILE: lib/web_live_sync/web_pdf_router_service.dart
// ignore_for_file: prefer_const_constructors, unnecessary_const, prefer_interpolation_to_compose_strings

import "dart:typed_data";
import "package:pdf/pdf.dart";
import "package:pdf/widgets.dart" as pw;
import "package:printing/printing.dart";
import "package:intl/intl.dart";
import "web_models.dart";
import "pharoah_web_manager.dart";
import "pdf/web_voucher_pdf.dart";
import "package:pharoah_erp/pdf/pdf_master_service.dart";
import "pdf/web_sale_report_pdf.dart";
import "pdf/web_purchase_report_pdf.dart";
import "pdf/web_party_ledger_pdf.dart";

class WebPdfRouterService {
    
  // ===========================================================================
  // 1. SALE INVOICE PDF
  // ===========================================================================
  static Future<Uint8List> generateSaleBytes({
    required Sale sale,
    required Party party,
    required CompanyProfile shop,
    required AppConfig config,
  }) async {
    final pdf = pw.Document();
    const double masterWidth = 800; 
    const double pageHeightLimit = 530; 
    const int itemsPerPage = 16;
    
    int totalPages = (sale.items.length / itemsPerPage).ceil(); 
    if (totalPages == 0) totalPages = 1;
    bool isLocal = shop.state.trim().toLowerCase() == sale.partyState.trim().toLowerCase();

    for (int pageNum = 0; pageNum < totalPages; pageNum++) {
      int start = pageNum * itemsPerPage;
      int end = (start + itemsPerPage < sale.items.length) ? start + itemsPerPage : sale.items.length;
      List<BillItem> pageItems = sale.items.sublist(start, end);
      bool isLastPage = (pageNum == totalPages - 1);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          build: (context) => pw.Column(
            children: [
              pw.Container(
                width: masterWidth,
                height: pageHeightLimit,
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.Column(
                  children: [
                    pw.Row(
                      children: [
                        _hBox(
                          280, true,
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                              pw.Text(shop.address, style: pw.TextStyle(fontSize: 7), maxLines: 2),
                              pw.Text("GSTIN: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                              pw.Text("Mob: ${shop.phone}${shop.email.isNotEmpty ? ' | Email: ${shop.email.toLowerCase()}' : ''}", style: pw.TextStyle(fontSize: 7)),
                            ],
                          ),
                        ),
                        _hBox(
                          175, true,
                          pw.Column(
                            children: [
                              pw.Text("TAX INVOICE", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                              pw.Text(sale.paymentMode.toUpperCase(), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                              pw.Divider(thickness: 0.5),
                              pw.Text("No: ${sale.billNo}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                              pw.Text(DateFormat("dd/MM/yyyy").format(sale.date), style: pw.TextStyle(fontSize: 8)),
                            ],
                          ),
                        ),
                        _hBox(
                          345, false,
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text("CONSIGNEE:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                              pw.Text(sale.partyName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                              pw.Text("${sale.partyAddress.isNotEmpty ? sale.partyAddress : party.address}, ${sale.partyCity.isNotEmpty ? sale.partyCity : party.city}", style: pw.TextStyle(fontSize: 7.5), maxLines: 2),
                              pw.Text("GST: ${sale.partyGstin} | DL: ${sale.partyDl.isNotEmpty ? sale.partyDl : party.dl}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                              pw.Text("Mob: ${sale.partyPhone.isNotEmpty ? sale.partyPhone : party.phone}", style: pw.TextStyle(fontSize: 7)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      color: PdfColors.grey200,
                      child: pw.Row(
                        children: [
                          _tCol("S.N", 25), _tCol("Qty+Free", 60), _tCol("Pack", 40),
                          _tCol("Product Description", 220, isLeft: true),
                          _tCol("Batch", 70), _tCol("Exp", 45), _tCol("HSN", 45),
                          _tCol("MRP", 55), _tCol("Rate", 55),
                          if (isLocal) ...[_tCol("CGST", 40), _tCol("SGST", 40)] else _tCol("IGST", 80),
                          _tCol("Net Amt", 100, isLast: true),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        children: pageItems.asMap().entries.map((entry) {
                          int idx = entry.key;
                          var i = entry.value;
                          String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
                          String qtyDisplay = "${fmt(i.qty)} + ${fmt(i.freeQty)}";

                          return pw.Container(
                            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
                            child: pw.Row(
                              children: [
                                _cell("${start + idx + 1}", 25), _cell(qtyDisplay, 60), _cell(i.packing, 40),
                                pw.Container(
                                  width: 220, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft,
                                  child: pw.Text(i.name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                                ),
                                _cell(i.batch, 70), _cell(i.exp, 45), _cell(i.hsn, 45),
                                _cell(i.mrp.toStringAsFixed(2), 55), _cell(i.rate.toStringAsFixed(2), 55),
                                if (isLocal) ...[_cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40), _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40)] else _cell("${i.gstRate.toStringAsFixed(1)}%", 80),
                                _cell(i.total.toStringAsFixed(2), 100),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    if (isLastPage) _buildSaleFooter(shop.name, sale, isLocal)
                    else pw.Container(
                      height: 25, alignment: pw.Alignment.centerRight, padding: const pw.EdgeInsets.only(right: 20),
                      child: pw.Text("Continued on next page...", style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 8)),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text(
                  "This is a system-generated document. | Powered by Pharoah ERP",
                  style: pw.TextStyle(fontSize: 5, color: PdfColors.grey600),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return pdf.save();
  }

  static Future<void> printSaleInvoice({required Sale sale, required Party party, required CompanyProfile shop, required AppConfig config}) async {
    final bytes = await generateSaleBytes(sale: sale, party: party, shop: shop, config: config);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: "Invoice_${sale.billNo}", format: PdfPageFormat.a4.landscape);
  }

  static Future<void> downloadSalePdf({required Sale sale, required Party party, required CompanyProfile shop, required AppConfig config}) async {
    final bytes = await generateSaleBytes(sale: sale, party: party, shop: shop, config: config);
    await Printing.sharePdf(bytes: bytes, filename: "Invoice_${sale.billNo}.pdf");
  }

  // ===========================================================================
  // 2. SALE CHALLAN (OUTWARD DELIVERY NOTE)
  // ===========================================================================
  static Future<Uint8List> generateSaleChallanBytes({
    required SaleChallan challan,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final pdf = pw.Document();
    const double masterWidth = 800;
    const double pageHeightLimit = 530;
    const int itemsPerPage = 15;

    int totalPages = (challan.items.length / itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    for (int pageNum = 0; pageNum < totalPages; pageNum++) {
      int start = pageNum * itemsPerPage;
      int end = (start + itemsPerPage < challan.items.length) ? start + itemsPerPage : challan.items.length;
      List<BillItem> pageItems = challan.items.sublist(start, end);
      bool isLastPage = (pageNum == totalPages - 1);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          build: (context) => pw.Column(
            children: [
              pw.Container(
                width: masterWidth,
                height: pageHeightLimit,
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.Column(
                  children: [
                    pw.Row(
                      children: [
                        _hBox(
                          280, true,
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                              pw.Text(shop.address, style: pw.TextStyle(fontSize: 7), maxLines: 2),
                              pw.Text("GST: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                              pw.Text("Mob: ${shop.phone}${shop.email.isNotEmpty ? ' | Email: ${shop.email.toLowerCase()}' : ''}", style: pw.TextStyle(fontSize: 7)),
                            ],
                          ),
                        ),
                        _hBox(
                          175, true,
                          pw.Column(
                            children: [
                              pw.Text("DELIVERY CHALLAN", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                              pw.Divider(thickness: 0.5),
                              pw.Text(challan.billNo, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                              pw.Text(DateFormat("dd/MM/yyyy").format(challan.date), style: pw.TextStyle(fontSize: 8)),
                            ],
                          ),
                        ),
                        _hBox(
                          345, false,
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text("CONSIGNEE DETAILS:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                              pw.Text(party.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                              pw.Text("${party.address.isNotEmpty ? party.address : challan.partyState}, ${party.city}", style: pw.TextStyle(fontSize: 7.5), maxLines: 2),
                              pw.Text("GSTIN: ${party.gst.isNotEmpty ? party.gst : challan.partyGstin} | DL: ${party.dl}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                              if (party.phone.isNotEmpty || party.email.isNotEmpty)
                                pw.Text("Mob: ${party.phone}${party.email.isNotEmpty ? ' | Email: ${party.email.toLowerCase()}' : ''}", style: pw.TextStyle(fontSize: 7)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      color: PdfColors.grey200,
                      child: pw.Row(
                        children: [
                          _tCol("S.N", 25), _tCol("Qty+Free", 55), _tCol("Pack", 45),
                          _tCol("Product Description", 210, isLeft: true),
                          _tCol("Batch", 75), _tCol("Exp", 45), _tCol("HSN", 50),
                          _tCol("MRP", 55), _tCol("Rate", 55), _tCol("GST%", 40),
                          _tCol("Net Total", 145, isLast: true),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        children: pageItems.asMap().entries.map((entry) {
                          int idx = entry.key;
                          var i = entry.value;
                          String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
                          String qtyDisp = "${fmt(i.qty)} + ${fmt(i.freeQty)}";

                          return pw.Container(
                            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
                            child: pw.Row(
                              children: [
                                _cell("${start + idx + 1}", 25), _cell(qtyDisp, 55), _cell(i.packing, 45),
                                pw.Container(
                                  width: 210, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft,
                                  child: pw.Text(i.name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                                ),
                                _cell(i.batch, 75), _cell(i.exp, 45), _cell(i.hsn, 50),
                                _cell(i.mrp.toStringAsFixed(2), 55), _cell(i.rate.toStringAsFixed(2), 55),
                                _cell("${i.gstRate.toInt()}%", 40),
                                _cell(i.total.toStringAsFixed(2), 145),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    if (isLastPage) _buildChallanFooter(shop.name, challan)
                    else pw.Container(
                      height: 25, alignment: pw.Alignment.centerRight, padding: const pw.EdgeInsets.only(right: 20),
                      child: pw.Text("Continued on next page...", style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return pdf.save();
  }

  static pw.Widget _buildChallanFooter(String shopName, SaleChallan challan) {
    String sealCode = challan.sigHistory.isNotEmpty ? challan.sigHistory.last.verificationCode : "N/A";
    String remarks = challan.remarks.trim().isNotEmpty ? challan.remarks.trim() : "Verified.";

    return pw.Container(
      height: 100,
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
      child: pw.Row(
        children: [
          pw.Container(
            width: 480, padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 35),
                pw.Text("RECEIVER SIGNATURE & STAMP", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                pw.Spacer(),
                pw.Text(
                  "SECURE NOTICE: Locked with code $sealCode.",
                  style: pw.TextStyle(fontSize: 6, color: PdfColors.grey700, fontStyle: pw.FontStyle.italic),
                ),
              ],
            ),
          ),
          pw.Container(
            width: 320, padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("GRAND TOTAL VALUE", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Rs. ${challan.totalAmount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text("REMARKS: $remarks", style: pw.TextStyle(fontSize: 7)),
                ),
                pw.Spacer(),
                pw.Text("For $shopName", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 25),
                pw.Text("AUTHORISED SIGNATORY", style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> printSaleChallan({
    required SaleChallan challan,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final bytes = await generateSaleChallanBytes(challan: challan, party: party, shop: shop);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: "Challan_${challan.billNo}", format: PdfPageFormat.a4.landscape);
  }

  static Future<void> downloadSaleChallanPdf({
    required SaleChallan challan,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final bytes = await generateSaleChallanBytes(challan: challan, party: party, shop: shop);
    await Printing.sharePdf(bytes: bytes, filename: "Challan_${challan.billNo}.pdf");
  }

  // ===========================================================================
  // 3. PURCHASE CHALLAN (INWARD DELIVERY NOTE)
  // ===========================================================================
  static Future<Uint8List> generatePurchaseChallanBytes({
    required PurchaseChallan challan,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final pdf = pw.Document();
    const double masterWidth = 800;
    const double pageHeightLimit = 530;
    const int itemsPerPage = 15;

    int totalPages = (challan.items.length / itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    for (int pageNum = 0; pageNum < totalPages; pageNum++) {
      int start = pageNum * itemsPerPage;
      int end = (start + itemsPerPage < challan.items.length) ? start + itemsPerPage : challan.items.length;
      List<PurchaseItem> pageItems = challan.items.sublist(start, end);
      bool isLastPage = (pageNum == totalPages - 1);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          build: (context) => pw.Column(
            children: [
              pw.Container(
                width: masterWidth,
                height: pageHeightLimit,
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.Column(
                  children: [
                    pw.Row(
                      children: [
                        _hBox(
                          280, true,
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                              pw.Text(shop.address, style: pw.TextStyle(fontSize: 7), maxLines: 2),
                              pw.Text("GST: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                              pw.Text("Mob: ${shop.phone}${shop.email.isNotEmpty ? ' | Email: ${shop.email.toLowerCase()}' : ''}", style: pw.TextStyle(fontSize: 7)),
                            ],
                          ),
                        ),
                        _hBox(
                          175, true,
                          pw.Column(
                            children: [
                              pw.Text("INWARD CHALLAN", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900)),
                              pw.Divider(thickness: 0.5),
                              pw.Text("ID: ${challan.internalNo}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                              pw.Text("Ref: ${challan.billNo}", style: const pw.TextStyle(fontSize: 8)),
                              pw.Text(DateFormat("dd/MM/yyyy").format(challan.date), style: const pw.TextStyle(fontSize: 8)),
                            ],
                          ),
                        ),
                        _hBox(
                          345, false,
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text("SUPPLIER DETAILS:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                              pw.Text(party.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                              pw.Text("${party.address}, ${party.city}", style: const pw.TextStyle(fontSize: 7.5), maxLines: 2),
                              pw.Text("GSTIN: ${party.gst} | DL: ${party.dl}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                              if (party.phone.isNotEmpty || party.email.isNotEmpty)
                                pw.Text("Mob: ${party.phone}${party.email.isNotEmpty ? ' | Email: ${party.email.toLowerCase()}' : ''}", style: const pw.TextStyle(fontSize: 7)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      color: PdfColors.grey200,
                      child: pw.Row(
                        children: [
                          _tCol("S.N", 25), _tCol("Qty+Free", 55), _tCol("Pack", 45),
                          _tCol("Product Description", 210, isLeft: true),
                          _tCol("Batch", 75), _tCol("Exp", 45), _tCol("HSN", 50),
                          _tCol("MRP", 55), _tCol("Pur.Rate", 55), _tCol("GST%", 40),
                          _tCol("Net Total", 145, isLast: true),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        children: pageItems.asMap().entries.map((entry) {
                          int idx = entry.key;
                          var i = entry.value;
                          String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
                          String qtyDisp = "${fmt(i.qty)} + ${fmt(i.freeQty)}";

                          return pw.Container(
                            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
                            child: pw.Row(
                              children: [
                                _cell("${start + idx + 1}", 25), _cell(qtyDisp, 55), _cell(i.packing, 45),
                                pw.Container(
                                  width: 210, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft,
                                  child: pw.Text(i.name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                                ),
                                _cell(i.batch, 75), _cell(i.exp, 45), _cell(i.hsn, 50),
                                _cell(i.mrp.toStringAsFixed(2), 55), _cell(i.purchaseRate.toStringAsFixed(2), 55),
                                _cell("${i.gstRate.toInt()}%", 40),
                                _cell(i.total.toStringAsFixed(2), 145),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    if (isLastPage) _buildPurchaseChallanFooter(shop.name, challan)
                    else pw.Container(
                      height: 25, alignment: pw.Alignment.centerRight, padding: const pw.EdgeInsets.only(right: 20),
                      child: pw.Text("Continued on next page...", style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return pdf.save();
  }

  static pw.Widget _buildPurchaseChallanFooter(String shopName, PurchaseChallan challan) {
    String remarks = challan.remarks.trim().isNotEmpty ? challan.remarks.trim() : "Stock inward verified.";

    return pw.Container(
      height: 100,
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
      child: pw.Row(
        children: [
          pw.Container(
            width: 480, padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("STOCK INWARD CONFIRMATION", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text("Note: Material verified and stored in inventory.", style: pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
                pw.Spacer(),
                pw.Text("REMARKS: $remarks", style: pw.TextStyle(fontSize: 7)),
              ],
            ),
          ),
          pw.Container(
            width: 320, padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("TOTAL INWARD VALUE", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Rs. ${challan.totalAmount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900)),
                  ],
                ),
                pw.Spacer(),
                pw.Text("For $shopName", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 25),
                pw.Text("STORE MANAGER / RECEIVER", style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> printPurchaseChallan({
    required PurchaseChallan challan,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final bytes = await generatePurchaseChallanBytes(challan: challan, party: party, shop: shop);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: "Inward_${challan.internalNo}", format: PdfPageFormat.a4.landscape);
  }

  static Future<void> downloadPurchaseChallanPdf({
    required PurchaseChallan challan,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final bytes = await generatePurchaseChallanBytes(challan: challan, party: party, shop: shop);
    await Printing.sharePdf(bytes: bytes, filename: "Inward_${challan.internalNo}.pdf");
  }

  // ===========================================================================
  // 4. CREDIT NOTE PDF (SALE RETURN) - PERFECT MULTI-PAGE RENDER
  // ===========================================================================
  static Future<Uint8List> generateCreditNoteBytes({
    required SaleReturn returnObj,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final pdf = pw.Document();
    const double masterWidth = 800;
    const double pageHeightLimit = 530; 
    const int itemsPerPage = 14; 

    String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
    bool isLocal = shop.state.trim().toLowerCase() == party.state.trim().toLowerCase();

    final sellable = returnObj.items.where((i) => i.isBreakage == false).toList();
    final breakage = returnObj.items.where((i) => i.isBreakage == true).toList();

    List<dynamic> combinedList = [];
    if (sellable.isNotEmpty) {
      combinedList.add(">> SALES RETURN (SELLABLE STOCK)");
      combinedList.addAll(sellable);
    }
    if (breakage.isNotEmpty) {
      combinedList.add(">> BREAKAGE & EXPIRY (NON-SELLABLE)");
      combinedList.addAll(breakage);
    }

    int totalPages = (combinedList.length / itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    for (int pageNum = 0; pageNum < totalPages; pageNum++) {
      int start = pageNum * itemsPerPage;
      int end = (start + itemsPerPage < combinedList.length) ? start + itemsPerPage : combinedList.length;
      List<dynamic> pageContent = combinedList.sublist(start, end);
      bool isLastPage = (pageNum == totalPages - 1);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          build: (context) => pw.Column(
            children: [
              pw.Container(
                width: masterWidth,
                height: pageHeightLimit,
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.Column(
                  children: [
                    // Header Box
                    pw.Row(
                      children: [
                        _hBox(
                          280, true,
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                              pw.Text(shop.address, style: pw.TextStyle(fontSize: 7), maxLines: 2),
                              pw.Text("GSTIN: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                              pw.Text("Mob: ${shop.phone}${shop.email.isNotEmpty ? ' | Email: ${shop.email.toLowerCase()}' : ''}", style: pw.TextStyle(fontSize: 7)),
                            ],
                          ),
                        ),
                        _hBox(
                          175, true,
                          pw.Column(
                            children: [
                              pw.Text("CREDIT NOTE", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                              pw.Divider(thickness: 0.5),
                              pw.Text("CN: ${returnObj.billNo}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                              pw.Text(DateFormat("dd/MM/yyyy").format(returnObj.date), style: pw.TextStyle(fontSize: 8)),
                            ],
                          ),
                        ),
                        _hBox(
                          345, false,
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text("CONSIGNEE:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                              pw.Text(party.name.toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                              pw.Text("${party.address.isNotEmpty ? party.address : ''}${party.city.isNotEmpty ? ', ${party.city}' : ''}", style: pw.TextStyle(fontSize: 7.5), maxLines: 2),
                              pw.Text("GST: ${party.gst.isNotEmpty ? party.gst : 'N/A'}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Table Header
                    pw.Container(
                      color: PdfColors.grey200,
                      child: pw.Row(
                        children: [
                          _tCol("S.N", 25), _tCol("Qty+Free", 50), _tCol("Pack", 40),
                          _tCol("Description", 210, isLeft: true),
                          _tCol("Batch", 70), _tCol("Exp", 45), _tCol("HSN", 45),
                          _tCol("MRP", 55), _tCol("Rate", 55),
                          if (isLocal) ...[_tCol("CGST", 40), _tCol("SGST", 40)] else _tCol("IGST", 80),
                          _tCol("Total", 125, isLast: true),
                        ],
                      ),
                    ),

                    // Items Rows
                    pw.Expanded(
                      child: pw.Column(
                        children: pageContent.map((entry) {
                          if (entry is String) {
                            return pw.Container(
                              width: masterWidth,
                              height: 18,
                              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                              alignment: pw.Alignment.centerLeft,
                              child: pw.Text(entry, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                            );
                          }
                          BillItem i = entry as BillItem;
                          String qtyDisp = "${fmt(i.qty)}+${fmt(i.freeQty)}";

                          return pw.Container(
                            height: 18,
                            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
                            child: pw.Row(
                              children: [
                                _cell("${returnObj.items.indexOf(i) + 1}", 25),
                                _cell(qtyDisp, 50),
                                _cell(i.packing, 40),
                                pw.Container(
                                  width: 210, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft,
                                  child: pw.Text(i.name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), maxLines: 1),
                                ),
                                _cell(i.batch, 70), _cell(i.exp, 45), _cell(i.hsn, 45),
                                _cell(i.mrp.toStringAsFixed(2), 55),
                                _cell(i.rate.toStringAsFixed(2), 55),
                                if (isLocal) ...[
                                  _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40),
                                  _cell("${(i.gstRate / 2).toStringAsFixed(1)}%", 40),
                                ] else ...[
                                  _cell("${i.gstRate.toStringAsFixed(1)}%", 80),
                                ],
                                _cell(i.total.toStringAsFixed(2), 125),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Page Footer Dock
                    if (isLastPage) _buildCreditNoteFooter(shop.name, returnObj, isLocal)
                    else pw.Container(
                      height: 20, alignment: pw.Alignment.centerRight, padding: const pw.EdgeInsets.only(right: 20),
                      child: pw.Text("Continued on next page...", style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 8)),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Powered by Pharoah ERP", style: pw.TextStyle(fontSize: 5, color: PdfColors.grey600)),
                  pw.Text("Page ${pageNum + 1} of $totalPages", style: pw.TextStyle(fontSize: 5, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return pdf.save();
  }

  static pw.Widget _buildCreditNoteFooter(String shopName, SaleReturn returnObj, bool isLocal) {
    double taxable = returnObj.items.fold(0.0, (sum, i) => sum + (i.qty * i.rate));
    double totalTax = returnObj.totalAmount - taxable;

    return pw.Container(
      height: 100,
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
      child: pw.Row(
        children: [
          pw.Container(
            width: 320, padding: const pw.EdgeInsets.all(5),
            decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Amount: RUPEES ${PdfMasterService.numberToWords(returnObj.totalAmount.round())} ONLY", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                pw.Spacer(),
                pw.Text("Verified return account settlement.", style: pw.TextStyle(fontSize: 7)),
              ],
            ),
          ),
          pw.Container(
            width: 250, padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Column(
              children: [
                _fRow("TAXABLE VAL", taxable),
                if (returnObj.extraDiscount > 0) _fRow("EXTRA DISCOUNT (-)", returnObj.extraDiscount),
                if (returnObj.roundOff != 0) _fRow("ROUND OFF", returnObj.roundOff),
                if (isLocal) ...[
                  _fRow("CGST TOTAL", totalTax / 2),
                  _fRow("SGST TOTAL", totalTax / 2),
                ] else ...[
                  _fRow("IGST TOTAL", totalTax),
                ],
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("NET CREDIT", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Rs. ${returnObj.totalAmount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          pw.Container(
            width: 230, padding: const pw.EdgeInsets.all(6),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Align(
                  alignment: pw.Alignment.topRight,
                  child: pw.Text("For $shopName", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Align(
                  alignment: pw.Alignment.bottomRight,
                  child: pw.Text("Authorised Signatory", style: pw.TextStyle(fontSize: 7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> printCreditNote({
    required SaleReturn returnObj,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final bytes = await generateCreditNoteBytes(returnObj: returnObj, party: party, shop: shop);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: "CreditNote_${returnObj.billNo}", format: PdfPageFormat.a4.landscape);
  }

  static Future<void> downloadCreditNotePdf({
    required SaleReturn returnObj,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final bytes = await generateCreditNoteBytes(returnObj: returnObj, party: party, shop: shop);
    await Printing.sharePdf(bytes: bytes, filename: "CreditNote_${returnObj.billNo}.pdf");
  }

  // ===========================================================================
  // 5. DEBIT NOTE PDF (PURCHASE RETURN) - EXACT 1:1 APP MATCH (3-BOX FOOTER)
  // ===========================================================================
  static Future<Uint8List> generateDebitNoteBytes({
    required PurchaseReturn returnObj,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final pdf = pw.Document();
    const double masterWidth = 800;
    const double pageHeightLimit = 530;
    const int itemsPerPage = 16;

    String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
    bool isLocal = shop.state.trim().toLowerCase() == party.state.trim().toLowerCase();

    final sellable = returnObj.items.where((i) => i.isBreakage == false).toList();
    final breakage = returnObj.items.where((i) => i.isBreakage == true).toList();

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

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          build: (context) => pw.Column(
            children: [
              pw.Container(
                width: masterWidth,
                height: pageHeightLimit,
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.Column(
                  children: [
                    // Header (Height: 95pt)
                    pw.Row(
                      children: [
                        _hBox(
                          280, true,
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                              pw.Text(shop.address, style: pw.TextStyle(fontSize: 7), maxLines: 2),
                              pw.Text("GSTIN: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                              pw.Text("Mob: ${shop.phone}${shop.email.isNotEmpty ? ' | Email: ${shop.email.toLowerCase()}' : ''}", style: pw.TextStyle(fontSize: 7)),
                            ],
                          ),
                        ),
                        _hBox(
                          175, true,
                          pw.Column(
                            children: [
                              pw.Text("DEBIT NOTE", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.brown900)),
                              pw.Divider(thickness: 0.5),
                              pw.Text("No: ${returnObj.billNo}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                              pw.Text(DateFormat("dd/MM/yyyy").format(returnObj.date), style: pw.TextStyle(fontSize: 8)),
                            ],
                          ),
                        ),
                        _hBox(
                          345, false,
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text("SEND TO SUPPLIER:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                              pw.Text(party.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                              pw.Text("${party.address}, ${party.city}", style: pw.TextStyle(fontSize: 7.5), maxLines: 2),
                              pw.Text("GST: ${party.gst} | DL: ${party.dl}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Table Header: 12 Columns matching App layout
                    pw.Container(
                      color: PdfColors.grey200,
                      child: pw.Row(
                        children: [
                          _tCol("S.N", 25), _tCol("Qty+Free", 60), _tCol("Pack", 40),
                          _tCol("Product Name", 220, isLeft: true),
                          _tCol("Batch", 75), _tCol("Exp", 45), _tCol("HSN", 45),
                          _tCol("MRP", 55), _tCol("Rate", 55),
                          if (isLocal) ...[_tCol("CGST", 40), _tCol("SGST", 40)] else _tCol("IGST", 80),
                          _tCol("Total", 100, isLast: true),
                        ],
                      ),
                    ),

                    // Items List
                    pw.Expanded(
                      child: pw.Column(
                        children: pageItems.map((entry) {
                          if (entry is String) {
                            return pw.Container(
                              width: masterWidth,
                              height: 18,
                              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                              alignment: pw.Alignment.centerLeft,
                              child: pw.Text(entry, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.brown900)),
                            );
                          }
                          PurchaseItem i = entry as PurchaseItem;
                          int sNo = returnObj.items.indexOf(i) + 1;
                          double taxableRow = i.purchaseRate * i.qty;
                          double taxAmt = i.total - taxableRow;

                          return pw.Container(
                            height: 18,
                            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
                            child: pw.Row(
                              children: [
                                _cell("$sNo", 25),
                                _cell("${fmt(i.qty)} + ${fmt(i.freeQty)}", 60),
                                _cell(i.packing, 40),
                                pw.Container(
                                  width: 220, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft,
                                  child: pw.Text(i.name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), maxLines: 1),
                                ),
                                _cell(i.batch, 75), _cell(i.exp, 45), _cell(i.hsn, 45),
                                _cell(i.mrp.toStringAsFixed(2), 55),
                                _cell(i.purchaseRate.toStringAsFixed(2), 55),
                                if (isLocal) ...[
                                  _cell((taxAmt / 2).toStringAsFixed(1), 40),
                                  _cell((taxAmt / 2).toStringAsFixed(1), 40),
                                ] else ...[
                                  _cell(taxAmt.toStringAsFixed(1), 80),
                                ],
                                _cell(i.total.toStringAsFixed(2), 100),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Footer with 3 Boxes (Total in the center)
                    if (isLastPage) _buildFixedSyncFooter(shop.name, returnObj, isLocal)
                    else pw.Container(
                      height: 25, alignment: pw.Alignment.centerRight, padding: const pw.EdgeInsets.only(right: 20),
                      child: pw.Text("Continued on next page...", style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 8)),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Powered by Pharoah ERP", style: pw.TextStyle(fontSize: 5, color: PdfColors.grey600)),
                  pw.Text("Page ${pageNum + 1} of $totalPages", style: pw.TextStyle(fontSize: 5, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return pdf.save();
  }

  // Exact 3-Box Footer matching App Layout
  static pw.Widget _buildFixedSyncFooter(String shopName, PurchaseReturn returnObj, bool isLocal) {
    double taxable = returnObj.items.fold(0.0, (sum, i) => sum + (i.purchaseRate * i.qty));
    double tax = returnObj.totalAmount - taxable;

    return pw.Container(
      height: 100,
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
      child: pw.Row(
        children: [
          // Box 1: Left (330pt)
          pw.Container(
            width: 330, padding: const pw.EdgeInsets.all(5),
            decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Amt Words: RUPEES ${PdfMasterService.numberToWords(returnObj.totalAmount.round())} ONLY", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                pw.Spacer(),
                pw.Text("Note: Outward Debit Settlement with Distributor.", style: pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
              ],
            ),
          ),
          // Box 2: Center (250pt) -> Total in the middle
          pw.Container(
            width: 250, padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Column(
              children: [
                _fRow("PUR. TAXABLE", taxable),
                if (returnObj.extraDiscount > 0) _fRow("EXTRA DISCOUNT (-)", returnObj.extraDiscount),
                if (returnObj.roundOff != 0) _fRow("ROUND OFF", returnObj.roundOff),
                if (isLocal) ...[
                  _fRow("CGST REVERSE", tax / 2),
                  _fRow("SGST REVERSE", tax / 2),
                ] else ...[
                  _fRow("IGST REVERSE", tax),
                ],
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("NET DEBIT", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Rs. ${returnObj.totalAmount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: PdfColors.brown900)),
                  ],
                ),
              ],
            ),
          ),
          // Box 3: Right (220pt) -> For Shop & Authorised Signatory
          pw.Container(
            width: 220, padding: const pw.EdgeInsets.all(6),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Align(
                  alignment: pw.Alignment.topRight,
                  child: pw.Text("For $shopName", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Align(
                  alignment: pw.Alignment.bottomRight,
                  child: pw.Text("AUTHORISED SIGNATORY", style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> printDebitNote({
    required PurchaseReturn returnObj,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final bytes = await generateDebitNoteBytes(returnObj: returnObj, party: party, shop: shop);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: "DebitNote_${returnObj.billNo}", format: PdfPageFormat.a4.landscape);
  }

  static Future<void> downloadDebitNotePdf({
    required PurchaseReturn returnObj,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final bytes = await generateDebitNoteBytes(returnObj: returnObj, party: party, shop: shop);
    await Printing.sharePdf(bytes: bytes, filename: "DebitNote_${returnObj.billNo}.pdf");
  }

  // --- STUBS & UTILITIES ---
  static Future<Uint8List> generateSaleReportBytes({required List<Sale> sales, required CompanyProfile shop, required DateTime from, required DateTime to}) async {
    return await WebSaleReportPdf.generateBytes(sales: sales, shop: shop, from: from, to: to);
  }
  static Future<void> printSaleReport({required List<Sale> sales, required CompanyProfile shop, required DateTime from, required DateTime to}) async {
    await WebSaleReportPdf.printReport(sales: sales, shop: shop, from: from, to: to);
  }
  static Future<void> downloadSaleReport({required List<Sale> sales, required CompanyProfile shop, required DateTime from, required DateTime to}) async {
    await WebSaleReportPdf.downloadReport(sales: sales, shop: shop, from: from, to: to);
  }
  static Future<Uint8List> generatePurchaseBytes({required Purchase purchase, required Party party, required CompanyProfile shop}) async => pw.Document().save();
  static Future<void> printPurchaseInvoice({required Purchase purchase, required Party party, required CompanyProfile shop}) async {}
  static Future<Uint8List> generatePurchaseReportBytes({required List<Purchase> purchases, required CompanyProfile shop, required DateTime from, required DateTime to}) async {
    return await WebPurchaseReportPdf.generateBytes(purchases: purchases, shop: shop, from: from, to: to);
  }
  static Future<void> printPurchaseReport({required List<Purchase> purchases, required CompanyProfile shop, required DateTime from, required DateTime to}) async {
    await WebPurchaseReportPdf.printReport(purchases: purchases, shop: shop, from: from, to: to);
  }
  static Future<void> downloadPurchaseReport({required List<Purchase> purchases, required CompanyProfile shop, required DateTime from, required DateTime to}) async {
    await WebPurchaseReportPdf.downloadReport(purchases: purchases, shop: shop, from: from, to: to);
  }
  static Future<void> printChallanReport({required List<dynamic> challans, required CompanyProfile shop, required DateTime from, required DateTime to, required bool isSaleChallan}) async {}
  static Future<void> downloadBulkZip({required List<dynamic> documents, required CompanyProfile shop, required AppConfig config, required Function(double, String) onProgress}) async {}


  static Future<void> printPartyLedger({
    required CompanyProfile shop,
    required Party party,
    required List<Map<String, dynamic>> data,
    required DateTime from,
    required DateTime to,
  }) async {
    await WebPartyLedgerPdf.printStatement(shop: shop, party: party, data: data, from: from, to: to);
  }

  static Future<void> downloadPartyLedger({
    required CompanyProfile shop,
    required Party party,
    required List<Map<String, dynamic>> data,
    required DateTime from,
    required DateTime to,
  }) async {
    await WebPartyLedgerPdf.downloadStatement(shop: shop, party: party, data: data, from: from, to: to);
  }


  static Future<void> printVoucher({
    required Voucher voucher,
    required Party party,
    required CompanyProfile shop,
    required PharoahWebManager webPh,
  }) async {
    final bytes = await WebVoucherPdf.generateBytes(voucher, party, shop, webPh);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: "Voucher_${voucher.voucherNo}",
      format: const PdfPageFormat(105 * PdfPageFormat.mm, 148 * PdfPageFormat.mm, marginAll: 5 * PdfPageFormat.mm),
    );
  }

  static pw.Widget _hBox(double w, bool b, pw.Widget child) => pw.Container(width: w, height: 95, padding: const pw.EdgeInsets.all(5), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: b ? 0.5 : 0), bottom: const pw.BorderSide(width: 0.5))), child: child);
  static pw.Widget _tCol(String t, double w, {bool isLast = false, bool isLeft = false}) => pw.Container(width: w, height: 18, alignment: isLeft ? pw.Alignment.centerLeft : pw.Alignment.center, padding: const pw.EdgeInsets.only(left: 5), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: isLast ? 0 : 0.5), bottom: const pw.BorderSide(width: 0.5))), child: pw.Text(t, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)));
  static pw.Widget _cell(String t, double w) => pw.Container(width: w, height: 18, alignment: pw.Alignment.center, decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.2, color: PdfColors.grey))), child: pw.Text(t, style: pw.TextStyle(fontSize: 7.5)));

  static pw.Widget _buildSaleFooter(String shopName, Sale sale, bool isLocal) {
    double taxableTotal = sale.items.fold(0.0, (sum, i) => sum + (i.qty * i.rate));
    double totalTax = sale.items.fold(0.0, (sum, i) => sum + (i.cgst + i.sgst + i.igst));

    return pw.Container(
      height: 100, decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
      child: pw.Row(
        children: [
          pw.Container(
            width: 330, padding: const pw.EdgeInsets.all(5), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Amount in Words:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                pw.Text("RUPEES ${PdfMasterService.numberToWords(sale.totalAmount.round())} ONLY", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                pw.Spacer(),
                pw.Text("Terms: Goods once sold will not be taken back.", style: pw.TextStyle(fontSize: 6)),
              ],
            ),
          ),
          pw.Container(
            width: 250, padding: const pw.EdgeInsets.all(4), decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Column(
              children: [
                _fRow("TAXABLE TOTAL", taxableTotal),
                if (isLocal) ...[_fRow("CGST TOTAL", totalTax / 2), _fRow("SGST TOTAL", totalTax / 2)] else _fRow("IGST TOTAL", totalTax),
                if (sale.extraDiscount > 0) _fRow("EXTRA DISCOUNT (-)", sale.extraDiscount),
                _fRow("ROUND OFF", sale.roundOff),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("GRAND TOTAL", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Rs. ${sale.totalAmount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          pw.Container(
            width: 220, padding: const pw.EdgeInsets.all(5),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("For $shopName", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 25),
                pw.Text("AUTHORISED SIGNATORY", style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _fRow(String l, double v) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(l, style: pw.TextStyle(fontSize: 7.5)),
          pw.Text(v.toStringAsFixed(2), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
        ],
      );
}
