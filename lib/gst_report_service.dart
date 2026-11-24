// FILE: lib/gst_report_service.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'gateway/company_registry_model.dart';
import 'logic/gst_compliance_helper.dart';

class GstReportService {
  
  // ===========================================================================
  // 1. GSTR-1 (SALES)
  // ===========================================================================
  static Future<void> generateGstr1Pdf(List<Sale> sales, String period, CompanyProfile shop) async {
    final bytes = await generateGstr1Bytes(sales, shop);
    await Printing.layoutPdf(onLayout: (format) async => bytes, name: "GSTR1_${shop.name}");
  }

  static Future<Uint8List> generateGstr1Bytes(List<Sale> sales, CompanyProfile shop) async {
    final pdf = pw.Document();
    List<Sale> b2b = sales.where((s) => s.invoiceType == "B2B" && s.status == "Active").toList();
    List<Sale> b2c = sales.where((s) => s.invoiceType == "B2C" && s.status == "Active").toList();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      header: (context) => _header(shop.name, "GSTR-1 (Sales Register)", "Audit Summary"),
      build: (context) => [
        _title("B2B SALES SUMMARY"), 
        _tableB2B(b2b),
        pw.SizedBox(height: 25),
        _title("B2C SALES SUMMARY"), 
        _tableB2C(b2c),
      ],
    ));
    return pdf.save();
  }

  // ===========================================================================
  // 2. GSTR-2 (PURCHASES & ITC) - RE-ADDED & FIXED
  // ===========================================================================
  static Future<void> generateGstr2Pdf(List<Purchase> purchases, List<Voucher> vouchers, List<Party> parties, String period, CompanyProfile shop) async {
    final bytes = await generateGstr2Bytes(purchases, shop);
    await Printing.layoutPdf(onLayout: (format) async => bytes, name: "GSTR2_${shop.name}");
  }

  static Future<Uint8List> generateGstr2Bytes(List<Purchase> purchases, CompanyProfile shop) async {
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      header: (context) => _header(shop.name, "GSTR-2 (Inward & ITC)", "Audit Report"),
      build: (context) => [
        _title("PURCHASE INWARD REGISTER"), 
        _tablePur(purchases)
      ],
    ));
    return pdf.save();
  }

  // ===========================================================================
  // 3. GSTR-3B (MONTHLY SUMMARY)
  // ===========================================================================
  static Future<void> generateGstr3bPdf(
    List<Sale> sales,
    List<Purchase> purchases,
    String period,
    CompanyProfile shop, {
    List<SaleReturn> saleReturns = const [],
    List<PurchaseReturn> purchaseReturns = const [],
    List<Party> parties = const [],
  }) async {
    final bytes = await generateGstr3bBytes(
      sales,
      purchases,
      shop,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
      parties: parties,
    );
    await Printing.layoutPdf(onLayout: (format) async => bytes, name: "GSTR3B_${shop.name}");
  }

  static Future<Uint8List> generateGstr3bBytes(
    List<Sale> sales,
    List<Purchase> purchases,
    CompanyProfile shop, {
    List<SaleReturn> saleReturns = const [],
    List<PurchaseReturn> purchaseReturns = const [],
    List<Party> parties = const [],
  }) async {
    final pdf = pw.Document();
    double sTaxVal = 0, sCgst = 0, sSgst = 0, sIgst = 0;
    double pTaxVal = 0, pCgst = 0, pSgst = 0, pIgst = 0;
    double dnTaxVal = 0, dnCgst = 0, dnSgst = 0, dnIgst = 0;

    for (var s in sales.where((s) => s.status == "Active" && s.isDeleted != 1)) {
      double t = s.items.fold(0.0, (sum, it) => sum + (it.cgst + it.sgst + it.igst));
      sTaxVal += (s.totalAmount - s.roundOff - t);
      for (var it in s.items) {
        sCgst += it.cgst;
        sSgst += it.sgst;
        sIgst += it.igst;
      }
    }
    for (var sr in saleReturns.where((r) => r.status == "Active" && r.isDeleted != 1 && !r.isCommercial)) {
      final match = parties.firstWhere(
        (pt) => (sr.partyId.isNotEmpty && pt.id == sr.partyId) || pt.name.trim().toLowerCase() == sr.partyName.trim().toLowerCase(),
        orElse: () => Party(id: '', name: sr.partyName, gst: sr.partyGstin, state: sr.partyState),
      );
      final isIntra = GstComplianceHelper.isIntraStateReturn(
        shopGstin: shop.gstin,
        shopState: shop.state,
        partyGstin: match.gst.isNotEmpty ? match.gst : sr.partyGstin,
        partyState: match.state.isNotEmpty ? match.state : sr.partyState,
      );
      double gross = 0.0;
      for (var it in sr.items) gross += ((it.qty * it.rate) - it.discountRupees);
      final discRatio = (sr.extraDiscount > 0 && gross > 0) ? (sr.extraDiscount / gross) : 0.0;
      for (var it in sr.items) {
        final tx = ((it.qty * it.rate) - it.discountRupees) * (1.0 - discRatio);
        final tax = tx * (it.gstRate / 100.0);
        sTaxVal -= tx;
        if (isIntra) {
          sCgst -= (tax / 2.0);
          sSgst -= (tax / 2.0);
        } else {
          sIgst -= tax;
        }
      }
    }

    for (var p in purchases.where((p) => p.isDeleted != 1 && p.gstStatus != "Cancelled" && p.gstStatus != "Deleted")) {
      final match = parties.firstWhere(
        (pt) => (p.partyId.isNotEmpty && pt.id == p.partyId) || pt.name.trim().toLowerCase() == p.distributorName.trim().toLowerCase(),
        orElse: () => Party(id: '', name: p.distributorName),
      );
      final isIntra = GstComplianceHelper.isIntraStateReturn(
        shopGstin: shop.gstin,
        shopState: shop.state,
        partyGstin: match.gst,
        partyState: match.state,
      );
      double gross = 0.0;
      for (var it in p.items) gross += ((it.qty * it.purchaseRate) - it.discountRupees);
      final discRatio = (p.extraDiscount > 0 && gross > 0) ? (p.extraDiscount / gross) : 0.0;
      for (var it in p.items) {
        final tx = ((it.qty * it.purchaseRate) - it.discountRupees) * (1.0 - discRatio);
        final tax = tx * (it.gstRate / 100.0);
        pTaxVal += tx;
        if (isIntra) {
          pCgst += (tax / 2.0);
          pSgst += (tax / 2.0);
        } else {
          pIgst += tax;
        }
      }
    }

    for (var pr in purchaseReturns.where((r) => r.status == "Active" && r.isDeleted != 1 && !r.isCommercial)) {
      final match = parties.firstWhere(
        (pt) => (pr.partyId.isNotEmpty && pt.id == pr.partyId) || pt.name.trim().toLowerCase() == pr.distributorName.trim().toLowerCase(),
        orElse: () => Party(id: '', name: pr.distributorName, gst: pr.partyGstin, state: pr.partyState),
      );
      final isIntra = GstComplianceHelper.isIntraStateReturn(
        shopGstin: shop.gstin,
        shopState: shop.state,
        partyGstin: match.gst.isNotEmpty ? match.gst : pr.partyGstin,
        partyState: match.state.isNotEmpty ? match.state : pr.partyState,
      );
      double gross = 0.0;
      for (var it in pr.items) gross += ((it.qty * it.purchaseRate) - it.discountRupees);
      final discRatio = (pr.extraDiscount > 0 && gross > 0) ? (pr.extraDiscount / gross) : 0.0;
      for (var it in pr.items) {
        final tx = ((it.qty * it.purchaseRate) - it.discountRupees) * (1.0 - discRatio);
        final tax = tx * (it.gstRate / 100.0);
        dnTaxVal += tx;
        if (isIntra) {
          dnCgst += (tax / 2.0);
          dnSgst += (tax / 2.0);
        } else {
          dnIgst += tax;
        }
      }
    }

    final netPurTaxVal = pTaxVal - dnTaxVal;
    final netPurCgst = pCgst - dnCgst;
    final netPurSgst = pSgst - dnSgst;
    final netPurIgst = pIgst - dnIgst;
    final sTaxTotal = sCgst + sSgst + sIgst;
    final pTaxTotal = pCgst + pSgst + pIgst;
    final dnTaxTotal = dnCgst + dnSgst + dnIgst;
    final netItcTotal = pTaxTotal - dnTaxTotal;

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (context) => pw.Column(children: [
        _header(shop.name, "GSTR-3B MONTHLY RETURN", "Net of Credit/Debit Notes"),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
          headers: ['DESCRIPTION', 'TAXABLE VALUE', 'IGST', 'CENTRAL TAX', 'STATE TAX', 'TOTAL TAX'],
          data: [
            ['3.1(a) Net Outward Supplies (Sales - CN)', sTaxVal.toStringAsFixed(2), sIgst.toStringAsFixed(2), sCgst.toStringAsFixed(2), sSgst.toStringAsFixed(2), sTaxTotal.toStringAsFixed(2)],
            ['4(A) Gross Eligible ITC (Purchases)', pTaxVal.toStringAsFixed(2), pIgst.toStringAsFixed(2), pCgst.toStringAsFixed(2), pSgst.toStringAsFixed(2), pTaxTotal.toStringAsFixed(2)],
            ['4(B)(2) ITC Reversal (Debit Notes)', dnTaxVal.toStringAsFixed(2), dnIgst.toStringAsFixed(2), dnCgst.toStringAsFixed(2), dnSgst.toStringAsFixed(2), dnTaxTotal.toStringAsFixed(2)],
            ['NET GST PAYABLE / REFUND', (sTaxVal - netPurTaxVal).toStringAsFixed(2), (sIgst - netPurIgst).toStringAsFixed(2), (sCgst - netPurCgst).toStringAsFixed(2), (sSgst - netPurSgst).toStringAsFixed(2), (sTaxTotal - netItcTotal).toStringAsFixed(2)],
          ]),
      ])
    ));
    return pdf.save();
  }

  // ===========================================================================
  // INTERNAL HELPERS
  // ===========================================================================
  static pw.Widget _header(String n, String t, String p) => pw.Column(children: [
    pw.Text(n.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
    pw.Text(t, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
    pw.Text(p, style: const pw.TextStyle(fontSize: 9)),
    pw.Divider(thickness: 1, color: PdfColors.indigo900)
  ]);

  static pw.Widget _title(String t) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5), 
    child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.blueGrey900))
  );

  static pw.Widget _tableB2B(List<Sale> l) => pw.TableHelper.fromTextArray(
    headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.black),
    headers: ['Date', 'Inv No', 'Party Name', 'GSTIN', 'Total Amt'], 
    data: l.map((s) => [DateFormat('dd/MM/yy').format(s.date), s.billNo, s.partyName, s.partyGstin, s.totalAmount.toStringAsFixed(2)]).toList()
  );

  static pw.Widget _tableB2C(List<Sale> l) => pw.TableHelper.fromTextArray(
    headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.black),
    headers: ['State', 'Taxable Val', 'GST Amt', 'Total Amt'], 
    data: l.map((s) => [s.partyState, (s.totalAmount * 0.88).toStringAsFixed(2), (s.totalAmount * 0.12).toStringAsFixed(2), s.totalAmount.toStringAsFixed(2)]).toList()
  );

  static pw.Widget _tablePur(List<Purchase> l) => pw.TableHelper.fromTextArray(
    headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.orange900),
    headers: ['Date', 'Bill No', 'Supplier Name', 'Amount'], 
    data: l.map((p) => [DateFormat('dd/MM/yy').format(p.date), p.billNo, p.distributorName, p.totalAmount.toStringAsFixed(2)]).toList()
  );
}
