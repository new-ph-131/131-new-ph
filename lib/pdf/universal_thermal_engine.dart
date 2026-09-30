// FILE: lib/pdf/universal_thermal_engine.dart (FINAL COMPREHENSIVE VERSION)

import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../pharoah_manager.dart';
import '../gateway/company_registry_model.dart';
import '../logic/app_settings_model.dart';
import 'pdf_master_service.dart';

class UniversalThermalEngine {
  
  // ===========================================================================
  // 📠 1. MAIN GENERATOR
  // ===========================================================================
  static Future<void> generate({
    required dynamic doc, 
    required Party party, 
    required PharoahManager ph, 
    required String type, 
  }) async {
    final pdf = pw.Document();
    final shop = ph.activeCompany!;
    final config = ph.config;

    // Load Logo
    pw.MemoryImage? logoImg;
    if (config.showLogo && config.logoPath != null && File(config.logoPath!).existsSync()) {
      logoImg = pw.MemoryImage(File(config.logoPath!).readAsBytesSync());
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80, // 80mm
        margin: const pw.EdgeInsets.all(5),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildShopHeader(shop, logoImg),
              PdfMasterService.thermalDivider(),
              _buildPartyHeader(party, type),
              PdfMasterService.thermalDivider(),
              _buildDocMetadata(doc, type),
              PdfMasterService.thermalDivider(),
              
              // --- DYNAMIC CONTENT ---
              _buildMainContent(doc, type, config),
              
              PdfMasterService.thermalDivider(),
              
              // --- TAX & TOTALS ---
              _buildAdvancedFooter(doc, shop, config, type),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (f) async => pdf.save(), name: 'ERP_Print_${type}');
  }

  // ===========================================================================
  // 🏗️ 2. COMPACT HEADERS
  // ===========================================================================

  static pw.Widget _buildShopHeader(CompanyProfile shop, pw.MemoryImage? logo) {
    return pw.Center(child: pw.Column(children: [
      if (logo != null) pw.Container(width: 40, height: 40, margin: const pw.EdgeInsets.only(bottom: 3), child: pw.Image(logo)),
      pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.Text(shop.address.toUpperCase(), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 6.5)),
      pw.Text("GST: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
      pw.Text("Ph: ${shop.phone}", style: const pw.TextStyle(fontSize: 7)),
    ]));
  }

  static pw.Widget _buildPartyHeader(Party p, String type) {
    String label = "CONSIGNEE:";
    if (type == "PURCHASE") label = "SUPPLIER:";
    if (type == "LEDGER") label = "LEDGER OF:";

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
      pw.Text(p.name.toUpperCase(), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      pw.Text("${p.city} | GST: ${p.gst}", style: const pw.TextStyle(fontSize: 7.5)),
      if (p.dl.isNotEmpty && p.dl != "N/A") pw.Text("DL No: ${p.dl}", style: const pw.TextStyle(fontSize: 7)),
    ]);
  }

  static pw.Widget _buildDocMetadata(dynamic doc, String type) {
    String docNo = "";
    String date = DateFormat('dd/MM/yy').format(DateTime.now());
    String mode = "N/A";

    if (doc is Sale) { docNo = doc.billNo; date = DateFormat('dd/MM/yy').format(doc.date); mode = doc.paymentMode; }
    else if (doc is Purchase) { docNo = doc.billNo; date = DateFormat('dd/MM/yy').format(doc.date); mode = doc.paymentMode; }
    else if (doc is SaleChallan) { docNo = doc.billNo; date = DateFormat('dd/MM/yy').format(doc.date); }
    else if (doc is Voucher) { docNo = doc.voucherNo; date = DateFormat('dd/MM/yy').format(doc.date); mode = doc.paymentMode; }

    return pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text("${type.toUpperCase()}: $docNo", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.Text("MODE: $mode", style: const pw.TextStyle(fontSize: 7)),
      ]),
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text("DATE: $date", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.Text("TIME: ${DateFormat('hh:mm a').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 7)),
      ]),
    ]);
  }

  // ===========================================================================
  // 📦 3. MAIN CONTENT (STAKED ROW ENGINE)
  // ===========================================================================

  static pw.Widget _buildMainContent(dynamic doc, String type, AppConfig config) {
    if (type == "LEDGER") return _buildLedgerContent(doc as List<Map<String, dynamic>>);
    if (type == "VOUCHER") return _buildVoucherContent(doc as Voucher);
    
    // Default: Items List for Sale/Purchase/Challan/Return
    List<dynamic> items = [];
    try { items = doc.items; } catch(e) { return pw.Text("No Items Data"); }

    return pw.Column(children: List.generate(items.length, (index) {
      final i = items[index];
      bool isShaded = config.useZebraShading && (index % 2 != 0);
      String qtyStr = "${i.qty.toInt()}${i.freeQty > 0 ? ' + ${i.freeQty.toInt()}' : ''}";

      return pw.Container(
        padding: const pw.EdgeInsets.all(3),
        decoration: pw.BoxDecoration(color: isShaded ? PdfColors.grey100 : null, border: const pw.Border(bottom: pw.BorderSide(width: 0.1))),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          // Row 1: Name
          pw.Row(children: [
            pw.Text("${index + 1}. ", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
            pw.Expanded(child: pw.Text("${i.name} (${i.packing})", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
          ]),
          // Row 2: Specs
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text("B: ${i.batch} | E: ${i.exp}", style: const pw.TextStyle(fontSize: 7)),
            pw.Text("Qty: $qtyStr", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
          ]),
          // Row 3: Price
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text("MRP: ${i.mrp}", style: const pw.TextStyle(fontSize: 7)),
            pw.Text("Rate: ${(i is PurchaseItem ? i.purchaseRate : i.rate).toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 7)),
            pw.Text("Amt: ₹${i.total.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
          ]),
        ]),
      );
    }));
  }

  // ===========================================================================
  // 📒 4. STATEMENTS & VOUCHERS SPECIAL LOGIC
  // ===========================================================================

  static pw.Widget _buildLedgerContent(List<Map<String, dynamic>> data) {
    return pw.Column(children: data.map((row) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(DateFormat('dd/MM').format(row['date']), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
            pw.Text(row['ref'], style: const pw.TextStyle(fontSize: 7)),
          ]),
          pw.Text(row['dr'] > 0 ? "Dr: ${row['dr']}" : "Cr: ${row['cr']}", style: const pw.TextStyle(fontSize: 7.5)),
          pw.Text("₹${row['bal'].toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ]),
      );
    }).toList());
  }

  static pw.Widget _buildVoucherContent(Voucher v) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Center(child: pw.Text("AMOUNT RECEIVED: ₹${v.amount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 5),
      pw.Text("Narration: ${v.narration}", style: const pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
      if (v.linkedBillNumbers.isNotEmpty) ...[
        pw.SizedBox(height: 5),
        pw.Text("ADJUSTED AGAINST BILLS:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
        pw.Text(v.linkedBillNumbers.join(", "), style: const pw.TextStyle(fontSize: 7)),
      ]
    ]);
  }

  // ===========================================================================
  // 💰 5. FOOTER & COMPLIANCE
  // ===========================================================================

  static pw.Widget _buildAdvancedFooter(dynamic doc, CompanyProfile shop, AppConfig config, String type) {
    double totalAmt = 0;
    if (doc is Sale || doc is Purchase || doc is SaleChallan || doc is PurchaseChallan || doc is SaleReturn || doc is PurchaseReturn) {
      totalAmt = doc.totalAmount;
    } else if (doc is Voucher) {
      totalAmt = doc.amount;
    }

    return pw.Column(children: [
      // Total Box
      pw.Container(
        padding: const pw.EdgeInsets.all(5), color: PdfColors.grey200,
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text("NET PAYABLE", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text("₹${totalAmt.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
      pw.SizedBox(height: 3),
      pw.Text("RUPEES ${PdfMasterService.numberToWords(totalAmt.round())} ONLY", textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic)),
      
      PdfMasterService.thermalDivider(),

      // UPI QR
      if (config.showQrCode && config.qrCodePath != null && File(config.qrCodePath!).existsSync())
        pw.Center(child: pw.Container(width: 70, height: 70, child: pw.Image(pw.MemoryImage(File(config.qrCodePath!).readAsBytesSync())))),

      pw.SizedBox(height: 5),

      // Shop Name & Sign
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(height: 15),
          pw.Text("Receiver's Sign", style: const pw.TextStyle(fontSize: 7)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text("For ${shop.name}", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 15),
          pw.Text("Authorised Signatory", style: const pw.TextStyle(fontSize: 7)),
        ]),
      ]),
      pw.SizedBox(height: 5),
      pw.Center(child: pw.Text("System Generated via Pharoah ERP", style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600))),
    ]);
  }
}
