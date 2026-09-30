// FILE: lib/pdf/pdf_router_service.dart (FINAL STABLE VERSION)

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; 
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw; 
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart'; 

import '../models.dart';
import '../pharoah_manager.dart';
import '../gateway/company_registry_model.dart';
import '../logic/email_service.dart';

// --- PDF Generators ---
import 'sale_invoice_pdf.dart';
import 'architect_sale_pdf.dart';
import 'purchase_pdf.dart';
import 'sale_challan_pdf.dart';
import 'purchase_challan_pdf.dart';
import 'credit_note_pdf.dart'; 
import 'debit_note_pdf.dart';
import 'voucher_pdf.dart'; 
import 'statements/party_ledger_pdf.dart';
import 'statements/company_stock_pdf.dart';
import 'statements/party_stock_pdf.dart';
import 'universal_thermal_engine.dart'; 
import 'sale_report_pdf.dart';
import 'purchase_report_pdf.dart';
import '../gst_report_service.dart';

class PdfRouterService {
  
  // ===========================================================================
  // 1. HELPER: PARTY FINDER
  // ===========================================================================
  static Party _getLatestParty(PharoahManager ph, String partyId, String partyName, {String gst = "", String state = "Rajasthan"}) {
    try {
      return ph.parties.firstWhere((p) => p.id == partyId || p.name == partyName);
    } catch (e) {
      try {
        return ph.parties.firstWhere((p) => p.name.toUpperCase() == partyName.toUpperCase());
      } catch (e) {
        return Party(id: 'temp', name: partyName, gst: gst, state: state);
      }
    }
  }

  // ===========================================================================
  // 2. PUBLIC PRINT METHODS (FIXED: Added Back)
  // ===========================================================================
  
  static Future<void> printVoucher({required Voucher voucher, required Party party, required PharoahManager ph}) async {
    if (ph.activeCompany == null) return;
    if (ph.config.printFormat == "Thermal") {
      await UniversalThermalEngine.generate(doc: voucher, party: party, ph: ph, type: "VOUCHER");
    } else {
      await VoucherPdf.generate(voucher, party, ph.activeCompany!, ph);
    }
  }

  static Future<void> printSale({required Sale sale, required Party party, required PharoahManager ph}) async {
    final latestParty = _getLatestParty(ph, sale.partyId, sale.partyName, gst: sale.partyGstin, state: sale.partyState);
    if (ph.config.printFormat == "Thermal") {
      await UniversalThermalEngine.generate(doc: sale, party: latestParty, ph: ph, type: "SALE");
    } else {
      if (ph.config.isArchitectMode) {
        await ArchitectSalePdf.generate(sale, latestParty, ph.activeCompany!, ph.config);
      } else {
        await SaleInvoicePdf.generate(sale, latestParty, ph.activeCompany!);
      }
    }
  }

  static Future<void> printPurchase({required Purchase purchase, required Party supplier, required PharoahManager ph}) async {
    if (ph.config.printFormat == "Thermal") {
      await UniversalThermalEngine.generate(doc: purchase, party: supplier, ph: ph, type: "PURCHASE");
    } else {
      await PurchasePdf.generate(purchase, supplier, ph.activeCompany!);
    }
  }

  static Future<void> printChallan({required dynamic challan, required Party party, required PharoahManager ph, required bool isSaleChallan}) async {
    if (ph.config.printFormat == "Thermal") {
      await UniversalThermalEngine.generate(doc: challan, party: party, ph: ph, type: "CHALLAN");
    } else {
      if (isSaleChallan) await SaleChallanPdf.generate(challan, party, ph.activeCompany!);
      else await PurchaseChallanPdf.generate(challan, party, ph.activeCompany!);
    }
  }

  static Future<void> printCreditNote({required SaleReturn returnObj, required Party party, required PharoahManager ph}) async {
    if (ph.config.printFormat == "Thermal") await UniversalThermalEngine.generate(doc: returnObj, party: party, ph: ph, type: "RETURN");
    else await CreditNotePdf.generate(returnObj, party, ph.activeCompany!, ph.config);
  }

  static Future<void> printDebitNote({required PurchaseReturn returnObj, required Party supplier, required PharoahManager ph}) async {
    if (ph.config.printFormat == "Thermal") await UniversalThermalEngine.generate(doc: returnObj, party: supplier, ph: ph, type: "RETURN");
    else await DebitNotePdf.generate(returnObj, supplier, ph.activeCompany!, ph.config);
  }

 // FILE: lib/pdf/pdf_router_service.dart

  // ===========================================================================
  // 📧 MASTER EMAIL DISPATCHER (FINAL UPDATED LOGIC)
  // ===========================================================================
  static Future<void> emailDocument({
    required BuildContext context,
    required dynamic doc, 
    required Party party,
    required PharoahManager ph,
    required String type, 
    bool isAuditAction = false, // NAYA PARAMETER
  }) async {
    final config = ph.config;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Preparing professional PDF for mail..."),
      duration: Duration(seconds: 2),
    ));

    if (!config.isMailActive) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mail service is OFF in Settings."), backgroundColor: Colors.orange));
      return;
    }

    // --- 🎯 THE NEW SMART TARGET LOGIC ---
    String targetMail = "";
    String targetName = "";
    
    // Agar CA Mode ON hai, toh sab kuch CA ko jayega
    if (config.isAuditMode) {
      targetMail = config.caMailID;
      targetName = config.caName.isNotEmpty ? config.caName : "Auditor";
    } 
    // Agar CA Mode OFF hai, toh party ko jayega
    else {
      targetMail = party.email;
      targetName = party.name;
    }
    
    targetMail = targetMail.trim();

    // Quick Add Mail if Missing
    if (targetMail.isEmpty || !targetMail.contains('@')) {
      String? newMail = await _showQuickEmailDialog(context, targetName);
      if (newMail == null || newMail.isEmpty) return;
      
      // Update Master records
      if (config.isAuditMode) {
        ph.config.caMailID = newMail;
        ph.updateAppConfig(ph.config);
      } else if (party.id != 'internal') {
        int idx = ph.parties.indexWhere((p) => p.id == party.id);
        if (idx != -1) { ph.parties[idx].email = newMail; await ph.save(); }
      }
      targetMail = newMail;
    }

    Uint8List pdfBytes;
    String docNo = "";
    String dateRange = "";

    try {
      if (type == "SALE") {
        if (doc is Sale) {
          docNo = doc.billNo;
          if (config.isArchitectMode) pdfBytes = await ArchitectSalePdf.generateBytes(doc, party, ph.activeCompany!, config);
          else pdfBytes = await SaleInvoicePdf.generateBytes(doc, party, ph.activeCompany!);
        } else {
          docNo = (doc as Purchase).billNo;
          pdfBytes = await PurchasePdf.generateBytes(doc, party, ph.activeCompany!);
        }
      } 
      else if (type == "CHALLAN") {
        if (doc is SaleChallan) {
          docNo = doc.billNo;
          pdfBytes = await SaleChallanPdf.generateBytes(doc, party, ph.activeCompany!);
        } else {
          docNo = (doc as PurchaseChallan).billNo;
          pdfBytes = await PurchaseChallanPdf.generateBytes(doc, party, ph.activeCompany!);
        }
      }
      else if (type == "RETURN" || type == "CN" || type == "DN") {
        if (doc is SaleReturn) {
          docNo = doc.billNo;
          pdfBytes = await CreditNotePdf.generateBytes(doc, party, ph.activeCompany!, config);
        } else {
          docNo = (doc as PurchaseReturn).billNo;
          pdfBytes = await DebitNotePdf.generateBytes(doc, party, ph.activeCompany!, config);
        }
      }
    else if (type == "LEDGER") {
        docNo = "GST_Report";
        
        // --- 🛡️ ISOLATED GST MAIL FIX ---
        if (party.name.contains("GSTR-1") && doc is List<Sale>) {
          pdfBytes = await GstReportService.generateGstr1Bytes(doc, ph.activeCompany!);
        } 
        else if (party.name.contains("GSTR-3B") && doc is List<Sale>) {
          pdfBytes = await GstReportService.generateGstr3bBytes(doc, ph.purchases, ph.activeCompany!);
        } 
        else if (party.name.contains("CA Summary")) {
          if (doc is List<Sale>) {
            pdfBytes = await SaleReportPdf.generateBytes(doc, ph.activeCompany!);
          } else {
            pdfBytes = await PurchaseReportPdf.generateBytes((doc as List).cast<Purchase>(), ph.activeCompany!);
          }
        } 
        else {
          // Normal Ledger: Sirf tabhi chalega jab data List of Sale NA HO
          pdfBytes = await PartyLedgerPdf.generateBytes(
            shop: ph.activeCompany!, 
            party: party, 
            data: (doc as List).cast<Map<String, dynamic>>(), 
            from: DateTime.now(), 
            to: DateTime.now()
          );
        }
      }
      else if (type == "STOCK") {
        docNo = "StockReport";
        if (doc.containsKey('basis')) {
          pdfBytes = await CompanyStockPdf.generateBytes(shop: ph.activeCompany!, groupedData: doc['grouped'], from: doc['from'], to: doc['to'], valuationBasis: doc['basis'], ph: ph);
        } else {
          pdfBytes = await PartyStockPdf.generateBytes(shop: ph.activeCompany!, groupedData: doc['grouped'], from: doc['from'], to: doc['to'], mode: doc['mode']);
        }
      } 
      else if (type == "VOUCHER") {
        docNo = (doc as Voucher).voucherNo;
        pdfBytes = await VoucherPdf.generateBytes(doc, party, ph.activeCompany!, ph);
      }
      else { return; }

      final template = PharoahEmailService.getTemplate(type: type, shopName: ph.activeCompany!.name, docNo: docNo, dateRange: dateRange);
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sending to $targetMail..."), backgroundColor: Colors.indigo));

      bool success = await PharoahEmailService.sendEmailWithPdf(
        config: config,
        shopName: ph.activeCompany!.name,
        recipientEmail: targetMail,
        subject: template['subject']!,
        body: template['body']!,
        pdfBytes: pdfBytes,
        fileName: "${type}_$docNo",
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Mail Sent Successfully!"), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Failed to send mail. Check SMTP Credentials."), backgroundColor: Colors.red));
      }
    } catch (e) {
      debugPrint("Router Mail Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("System Error: $e"), backgroundColor: Colors.red));
    }
  }

  // ===========================================================================
  // 📦 4. BATCH DISPATCHERS (STITCHER & AUDIT)
  // ===========================================================================
  
  // For Stitcher Wizard
  static Future<String> createBulkZip({required List<Map<String, dynamic>> selectedDrafts, required PharoahManager ph, required Function(double progress, String filename) onProgress}) async {
    final archive = Archive();
    for (int i = 0; i < selectedDrafts.length; i++) {
      var draft = selectedDrafts[i];
      dynamic billObj = draft['saleObj']; 
      Uint8List pdfBytes;
      if (billObj is Sale) {
        final p = _getLatestParty(ph, billObj.partyId, billObj.partyName);
        onProgress((i + 1) / selectedDrafts.length, p.name);
        pdfBytes = ph.config.isArchitectMode ? await ArchitectSalePdf.generateBytes(billObj, p, ph.activeCompany!, ph.config) : await SaleInvoicePdf.generateBytes(billObj, p, ph.activeCompany!);
      } else {
        final p = _getLatestParty(ph, (billObj as Purchase).partyId, billObj.distributorName);
        onProgress((i + 1) / selectedDrafts.length, p.name);
        pdfBytes = await PurchasePdf.generateBytes(billObj, p, ph.activeCompany!);
      }
      archive.addFile(ArchiveFile("${billObj.billNo}.pdf", pdfBytes.length, pdfBytes));
    }
    final zipData = ZipEncoder().encode(archive);
    final tempDir = await getTemporaryDirectory();
    final zipPath = '${tempDir.path}/Export_${DateFormat('HHmm').format(DateTime.now())}.zip';
    await File(zipPath).writeAsBytes(zipData!);
    return zipPath;
  }

  // For CA Audit Mode
// For CA Audit Mode
  static Future<void> sendBatchToCa({required List<dynamic> documents, required PharoahManager ph, required String type}) async {
    // UPDATED: caMailID
    if (!ph.config.isAuditMode || ph.config.caMailID.isEmpty) return; 
    try {
      final archive = Archive();
      for (var doc in documents) {
        Uint8List pdfBytes;
        if (type == "SALE" && doc is Sale) {
          final p = _getLatestParty(ph, doc.partyId, doc.partyName);
          pdfBytes = ph.config.isArchitectMode ? await ArchitectSalePdf.generateBytes(doc, p, ph.activeCompany!, ph.config) : await SaleInvoicePdf.generateBytes(doc, p, ph.activeCompany!);
        } else if (type == "PURCHASE" && doc is Purchase) {
          final p = _getLatestParty(ph, doc.partyId, doc.distributorName);
          pdfBytes = await PurchasePdf.generateBytes(doc, p, ph.activeCompany!);
        } else { continue; }
        archive.addFile(ArchiveFile("${doc.billNo}.pdf", pdfBytes.length, pdfBytes));
      }
      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) return;
      
      // UPDATED: caMailID
      await PharoahEmailService.sendEmailWithPdf(
        config: ph.config, shopName: ph.activeCompany!.name, recipientEmail: ph.config.caMailID,
        subject: "AUDIT BUNDLE: ${documents.length} $type Bills",
        body: "Attached is the zipped bundle for audit.",
        pdfBytes: Uint8List.fromList(zipData),
        fileName: "Audit_${type}_${DateFormat('ddMM').format(DateTime.now())}.zip",
      );
    } catch (e) { debugPrint("Batch Error: $e"); }
  }
  static Future<String?> _showQuickEmailDialog(BuildContext context, String partyName) async {
    final emailC = TextEditingController();
    return showDialog<String>(
      context: context, barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Email Required"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [Text("Target: $partyName. Enter Email:"), const SizedBox(height: 15), TextField(controller: emailC, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: "Email ID", border: OutlineInputBorder()))]),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")), ElevatedButton(onPressed: () => Navigator.pop(c, emailC.text.trim()), child: const Text("PROCEED"))],
      ),
    );
  }
}
