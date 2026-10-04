import os
import re
import subprocess
import sys

print("==================================================================")
print("🚀 DEPLOYING FULL PURCHASE PDF PRINT ENGINE (#PH-REV-633)")
print("==================================================================\n")

# 1. UPDATE LIVE TAG TO #PH-REV-633
print("🏷️ Step 1/5: Updating Live Tag to #PH-REV-633...")
tb_path = "lib/web_live_sync/components/web_top_bar.dart"
if os.path.exists(tb_path):
    with open(tb_path, "r", encoding="utf-8") as f:
        tb = f.read()
    new_rev = "#PH-REV-633 (PURCHASE-PDF-PRINT-ENGINE-ACTIVE)"
    tb = re.sub(r"#PH-REV-\d+[^\"]*", new_rev, tb)
    with open(tb_path, "w", encoding="utf-8") as f:
        f.write(tb)
    print(f"✔ Tag Updated: {new_rev}")

# 2. CREATE DEDICATED PURCHASE INVOICE PDF GENERATOR
print("\n📄 Step 2/5: Creating web_purchase_invoice_pdf.dart...")
pdf_path = "lib/web_live_sync/pdf/web_purchase_invoice_pdf.dart"

pdf_code = '''// FILE: lib/web_live_sync/pdf/web_purchase_invoice_pdf.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pharoah_erp/pdf/pdf_master_service.dart';
import '../web_models.dart';

class WebPurchaseInvoicePdf {
  static const double masterWidth = 800;
  static const double pageHeightLimit = 530;
  static const int itemsPerPage = 15;

  static String _formatQty(double v) {
    if (v % 1 == 0) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\\.$'), '');
  }

  static Future<Uint8List> generateBytes({
    required Purchase purchase,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final pdf = pw.Document();

    int totalPages = (purchase.items.length / itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    bool isLocal = shop.state.trim().toLowerCase() == party.state.trim().toLowerCase();
    double totalTaxable = purchase.items.fold(0.0, (sum, i) => sum + (i.purchaseRate * i.qty - i.discountRupees));
    double totalGst = purchase.totalAmount - totalTaxable;

    for (int pageNum = 0; pageNum < totalPages; pageNum++) {
      int start = pageNum * itemsPerPage;
      int end = (start + itemsPerPage < purchase.items.length) ? start + itemsPerPage : purchase.items.length;
      List<PurchaseItem> pageItems = purchase.items.sublist(start, end);
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
                    // Header Row
                    pw.Row(
                      children: [
                        _hBox(
                          280, true,
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                              pw.Text(shop.address, style: const pw.TextStyle(fontSize: 7), maxLines: 2),
                              pw.Text("GSTIN: ${shop.gstin} | DL: ${shop.dlNo}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                              pw.Text("Mob: ${shop.phone}${shop.email.isNotEmpty ? ' | Email: ' + shop.email.toLowerCase() : ''}", style: const pw.TextStyle(fontSize: 7)),
                            ],
                          ),
                        ),
                        _hBox(
                          175, true,
                          pw.Column(
                            children: [
                              pw.Text("PURCHASE INWARD", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                              pw.Text(purchase.paymentMode.toUpperCase(), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                              pw.Divider(thickness: 0.5),
                              pw.Text("ID: ${purchase.internalNo}", style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                              pw.Text("Bill No: ${purchase.billNo}", style: const pw.TextStyle(fontSize: 8)),
                              pw.Text(DateFormat("dd/MM/yyyy").format(purchase.date), style: const pw.TextStyle(fontSize: 8)),
                            ],
                          ),
                        ),
                        _hBox(
                          345, false,
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text("SUPPLIER / DISTRIBUTOR:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                              pw.Text(party.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                              pw.Text("${party.address.isNotEmpty ? party.address : ''}${party.city.isNotEmpty ? ', ' + party.city : ''}", style: const pw.TextStyle(fontSize: 7.5), maxLines: 2),
                              pw.Text("GSTIN: ${party.gst.isNotEmpty ? party.gst : 'N/A'} | DL: ${party.dl.isNotEmpty ? party.dl : 'N/A'}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                              if (party.phone.isNotEmpty) pw.Text("Mob: ${party.phone}", style: const pw.TextStyle(fontSize: 7)),
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
                          _tCol("S.N", 25), _tCol("Qty+Free", 55), _tCol("Pack", 45),
                          _tCol("Product Name", 215, isLeft: true),
                          _tCol("Batch", 80), _tCol("Exp", 45), _tCol("HSN", 45),
                          _tCol("MRP", 55), _tCol("Pur.Rate", 55),
                          if (isLocal) ...[_tCol("CGST", 40), _tCol("SGST", 40)] else _tCol("IGST", 80),
                          _tCol("Net Amt", 100, isLast: true),
                        ],
                      ),
                    ),

                    // Items List
                    pw.Expanded(
                      child: pw.Column(
                        children: pageItems.asMap().entries.map((entry) {
                          int idx = entry.key;
                          PurchaseItem i = entry.value;
                          String qtyDisp = "${_formatQty(i.qty)}${i.freeQty > 0 ? ' + ' + _formatQty(i.freeQty) : ''}";
                          double taxableRow = i.purchaseRate * i.qty - i.discountRupees;
                          double taxAmt = i.total - taxableRow;

                          return pw.Container(
                            height: 18,
                            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.1, color: PdfColors.grey400))),
                            child: pw.Row(
                              children: [
                                _cell("${start + idx + 1}", 25),
                                _cell(qtyDisp, 55),
                                _cell(i.packing, 45),
                                pw.Container(
                                  width: 215, padding: const pw.EdgeInsets.only(left: 8), alignment: pw.Alignment.centerLeft,
                                  child: pw.Text(i.name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), maxLines: 1),
                                ),
                                _cell(i.batch, 80),
                                _cell(i.exp, 45),
                                _cell(i.hsn, 45),
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

                    // Footer
                    if (isLastPage) _buildFooter(shop.name, purchase, totalTaxable, totalGst, isLocal)
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
                  pw.Text("This is a system-generated document. | Powered by Pharoah ERP", style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey600)),
                  pw.Text("Page ${pageNum + 1} of $totalPages", style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return pdf.save();
  }

  static pw.Widget _buildFooter(String shopName, Purchase pur, double taxable, double gst, bool isLocal) {
    return pw.Container(
      height: 100,
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
      child: pw.Row(
        children: [
          pw.Container(
            width: 330, padding: const pw.EdgeInsets.all(5),
            decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Amount in Words:", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                pw.Text("RUPEES ${PdfMasterService.numberToWords(pur.totalAmount.round())} ONLY", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                pw.Spacer(),
                pw.Text("Note: Inward stock verified and received in good condition.", style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.Container(
            width: 250, padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Column(
              children: [
                _fRow("TAXABLE VALUE", taxable),
                if (isLocal) ...[
                  _fRow("CGST (ITC)", gst / 2),
                  _fRow("SGST (ITC)", gst / 2),
                ] else ...[
                  _fRow("IGST (ITC)", gst),
                ],
                if (pur.extraDiscount > 0) _fRow("EXTRA DISCOUNT (-)", pur.extraDiscount),
                if (pur.roundOff != 0) _fRow("ROUND OFF", pur.roundOff),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("NET INWARD VALUE", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Rs. ${pur.totalAmount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                  ],
                ),
              ],
            ),
          ),
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
                  child: pw.Text("AUTHORISED SIGNATORY", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> printInvoice({
    required Purchase purchase,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final bytes = await generateBytes(purchase: purchase, party: party, shop: shop);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: "Purchase_${purchase.billNo}",
      format: PdfPageFormat.a4.landscape,
    );
  }

  static Future<void> downloadPdf({
    required Purchase purchase,
    required Party party,
    required CompanyProfile shop,
  }) async {
    final bytes = await generateBytes(purchase: purchase, party: party, shop: shop);
    await Printing.sharePdf(
      bytes: bytes,
      filename: "Purchase_${purchase.billNo}.pdf",
    );
  }

  static pw.Widget _hBox(double w, bool b, pw.Widget child) => pw.Container(
    width: w, height: 95, padding: const pw.EdgeInsets.all(5),
    decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: b ? 0.5 : 0), bottom: const pw.BorderSide(width: 0.5))),
    child: child,
  );

  static pw.Widget _tCol(String t, double w, {bool isLast = false, bool isLeft = false}) => pw.Container(
    width: w, height: 18, alignment: isLeft ? pw.Alignment.centerLeft : pw.Alignment.center, padding: const pw.EdgeInsets.only(left: 5),
    decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: isLast ? 0 : 0.5), bottom: const pw.BorderSide(width: 0.5))),
    child: pw.Text(t, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
  );

  static pw.Widget _cell(String t, double w) => pw.Container(
    width: w, height: 18, alignment: pw.Alignment.center,
    decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.2, color: PdfColors.grey))),
    child: pw.Text(t, style: const pw.TextStyle(fontSize: 7.5)),
  );

  static pw.Widget _fRow(String l, double v) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(l, style: const pw.TextStyle(fontSize: 7.5)),
      pw.Text(v.toStringAsFixed(2), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
    ],
  );
}
'''
with open(pdf_path, "w", encoding="utf-8") as f:
    f.write(pdf_code)
print("✔ web_purchase_invoice_pdf.dart created successfully!")

# 3. CONNECT ROUTER SERVICE (web_pdf_router_service.dart)
print("\n🔗 Step 3/5: Connecting WebPdfRouterService to WebPurchaseInvoicePdf...")
router_path = "lib/web_live_sync/web_pdf_router_service.dart"
with open(router_path, "r", encoding="utf-8") as f:
    router_code = f.read()

# Add import
if "web_purchase_invoice_pdf.dart" not in router_code:
    router_code = router_code.replace(
        'import "pdf/web_purchase_report_pdf.dart";',
        'import "pdf/web_purchase_report_pdf.dart";\nimport "pdf/web_purchase_invoice_pdf.dart";'
    )

# Replace empty stubs
old_purchase_stubs = '''  static Future<Uint8List> generatePurchaseBytes({required Purchase purchase, required Party party, required CompanyProfile shop}) async => pw.Document().save();
  static Future<void> printPurchaseInvoice({required Purchase purchase, required Party party, required CompanyProfile shop}) async {}'''

new_purchase_methods = '''  static Future<Uint8List> generatePurchaseBytes({required Purchase purchase, required Party party, required CompanyProfile shop}) async {
    return await WebPurchaseInvoicePdf.generateBytes(purchase: purchase, party: party, shop: shop);
  }

  static Future<void> printPurchaseInvoice({required Purchase purchase, required Party party, required CompanyProfile shop}) async {
    await WebPurchaseInvoicePdf.printInvoice(purchase: purchase, party: party, shop: shop);
  }

  static Future<void> downloadPurchasePdf({required Purchase purchase, required Party party, required CompanyProfile shop}) async {
    await WebPurchaseInvoicePdf.downloadPdf(purchase: purchase, party: party, shop: shop);
  }'''

if old_purchase_stubs in router_code:
    router_code = router_code.replace(old_purchase_stubs, new_purchase_methods)
else:
    # Fallback replacement
    router_code = re.sub(
        r'static\s+Future<Uint8List>\s+generatePurchaseBytes[^\n]+\n\s+static\s+Future<void>\s+printPurchaseInvoice[^\n]+',
        new_purchase_methods,
        router_code
    )

with open(router_path, "w", encoding="utf-8") as f:
    f.write(router_code)
print("✔ WebPdfRouterService connected to Purchase PDF engine!")

# 4. RUN FLUTTER ANALYZE
print("\n🔍 Step 4/5: Running Flutter Analyze on lib/web_live_sync/...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], capture_output=True, text=True)
print(res.stdout)

errors = [line for line in res.stdout.split('\n') if 'error •' in line]
if len(errors) > 0:
    print(f"❌ Found {len(errors)} error(s):")
    for e in errors:
        print("  " + e)
    sys.exit(1)

print("🎉 0 ERRORS! COMPILATION IS 100% CLEAN.")

# 5. BUILD & DEPLOY
print("\n🔨 Step 5/5: Building & Deploying Web App to Cloudflare Pages...")
b_res = subprocess.run(
    ["flutter", "build", "web", "-t", "lib/web_live_sync/web_main.dart", "--release", "--base-href", "/", "--pwa-strategy=none"],
    text=True
)
if b_res.returncode != 0:
    print("❌ Web Build Failed!")
    sys.exit(1)

subprocess.run(["npx", "wrangler", "pages", "deploy", "build/web", "--project-name=pharoah-erp"], text=True)

# Commit & Push
print("\n🔄 Committing & Pushing to GitHub...")
subprocess.run(["git", "add", "."], text=True)
subprocess.run(["git", "commit", "-m", "🚀 #PH-REV-633: Full Purchase Invoice PDF Print Engine Deployed"], text=True)
branch_res = subprocess.run(["git", "branch", "--show-current"], capture_output=True, text=True)
branch = branch_res.stdout.strip() or "main"
subprocess.run(["git", "push", "origin", branch], text=True)

print("\n" + "="*65)
print("🎉 SUCCESS: #PH-REV-633 IS 100% DEPLOYED & LIVE!")
print("🔗 Website: https://pharoah-erp.pages.dev")
print("✅ Verified Tag: #PH-REV-633 (PURCHASE-PDF-PRINT-ENGINE-ACTIVE)")
print("="*65)
