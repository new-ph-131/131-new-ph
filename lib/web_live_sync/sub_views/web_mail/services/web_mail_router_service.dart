// FILE: lib/web_live_sync/sub_views/web_mail/services/web_mail_router_service.dart
// Revision: #PH-REV-798 (ENTERPRISE-WEB-MAIL-ROUTER-AND-AUDIT-ENGINE)
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../pharoah_web_manager.dart';
import '../../../web_models.dart';
import '../../../web_pdf_router_service.dart';
import '../../../pdf/web_party_ledger_pdf.dart';
import '../../../pdf/web_voucher_pdf.dart';
import '../../web_settings/web_settings_sync_coordinator.dart';
import 'web_email_dispatch_service.dart';

/// 📧 WebMailRouterService
/// Exact Web twin of App's `PdfRouterService.emailDocument` and `PdfRouterService.sendBatchToCa`.
/// Handles Party vs CA (Auditor) redirection, Quick Email Popup when missing,
/// PDF byte generation, 3-step toast messages, and Bulk ZIP CA dispatch.
class WebMailRouterService {
  /// Master Email Dispatcher for Single Documents & Summary Reports
  static Future<void> emailDocument({
    required BuildContext context,
    required dynamic doc,
    required Party party,
    required PharoahWebManager webPh,
    required String type,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final config = webPh.appConfig;
    final shop = CompanyProfile.fromMap(webPh.companyProfile);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Preparing professional PDF for mail..."),
          duration: Duration(seconds: 2),
        ),
      );
    }

    if (!config.isMailActive) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Mail service is OFF in Settings."),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // --- 🎯 THE SMART TARGET LOGIC (Same as App) ---
    String targetMail = "";
    String targetName = "";

    if (config.isAuditMode) {
      targetMail = config.caMailID;
      targetName = config.caName.trim().isNotEmpty ? config.caName.trim() : "Auditor (CA)";
    } else {
      targetMail = party.email;
      targetName = party.name.trim().isNotEmpty ? party.name.trim() : "Customer / Party";
    }

    targetMail = targetMail.replaceAll(RegExp(r'\s+'), '').trim();

    // Quick Add Mail if Missing (Exact App Behavior)
    if (targetMail.isEmpty || !targetMail.contains('@')) {
      if (!context.mounted) return;
      String? newMail = await _showQuickEmailDialog(context, targetName, isCaMode: config.isAuditMode);
      if (newMail == null || newMail.trim().isEmpty || !newMail.contains('@')) return;

      newMail = newMail.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();

      // Update Master records & sync to D1/Cloud
      if (config.isAuditMode) {
        webPh.appConfig.caMailID = newMail;
        await WebSettingsSyncCoordinator.saveAndBroadcastConfig(
          webPh: webPh,
          updatedConfig: webPh.appConfig,
        );
      } else if (party.id != 'internal' && party.id != 'temp') {
        party.email = newMail;
        webPh.updateParty(party);
      } else if (party.name.trim().isNotEmpty && party.id != 'internal') {
        try {
          final existingParty = webPh.parties.firstWhere(
            (p) => p.name.trim().toLowerCase() == party.name.trim().toLowerCase(),
          );
          existingParty.email = newMail;
          webPh.updateParty(existingParty);
        } catch (_) {}
      }
      targetMail = newMail;
    }

    Uint8List pdfBytes;
    String docNo = "";
    String dateRange = "";
    if (fromDate != null && toDate != null) {
      dateRange = "${DateFormat('dd/MM/yyyy').format(fromDate)} to ${DateFormat('dd/MM/yyyy').format(toDate)}";
    }

    try {
      final upperType = type.toUpperCase();
      if (upperType == "SALE") {
        if (doc is Sale) {
          docNo = doc.billNo;
          pdfBytes = await WebPdfRouterService.generateSaleBytes(
            sale: doc,
            party: party,
            shop: shop,
            config: config,
          );
        } else if (doc is Purchase) {
          docNo = doc.billNo.isNotEmpty ? doc.billNo : doc.internalNo;
          pdfBytes = await WebPdfRouterService.generatePurchaseBytes(
            purchase: doc,
            party: party,
            shop: shop,
          );
        } else {
          return;
        }
      } else if (upperType == "PURCHASE") {
        final p = doc as Purchase;
        docNo = p.billNo.isNotEmpty ? p.billNo : p.internalNo;
        pdfBytes = await WebPdfRouterService.generatePurchaseBytes(
          purchase: p,
          party: party,
          shop: shop,
        );
      } else if (upperType == "CHALLAN") {
        if (doc is SaleChallan) {
          docNo = doc.billNo;
          pdfBytes = await WebPdfRouterService.generateSaleChallanBytes(
            challan: doc,
            party: party,
            shop: shop,
          );
        } else if (doc is PurchaseChallan) {
          docNo = doc.billNo.isNotEmpty ? doc.billNo : doc.internalNo;
          pdfBytes = await WebPdfRouterService.generatePurchaseChallanBytes(
            challan: doc,
            party: party,
            shop: shop,
          );
        } else {
          return;
        }
      } else if (upperType == "RETURN" || upperType == "CN" || upperType == "DN") {
        if (doc is SaleReturn) {
          docNo = doc.billNo;
          pdfBytes = await WebPdfRouterService.generateCreditNoteBytes(
            returnObj: doc,
            party: party,
            shop: shop,
          );
        } else if (doc is PurchaseReturn) {
          docNo = doc.billNo;
          pdfBytes = await WebPdfRouterService.generateDebitNoteBytes(
            returnObj: doc,
            party: party,
            shop: shop,
          );
        } else {
          return;
        }
      } else if (upperType == "LEDGER") {
        if (doc is List<Sale>) {
          docNo = "Sales_Summary_Report";
          pdfBytes = await WebPdfRouterService.generateSaleReportBytes(
            sales: doc,
            shop: shop,
            from: fromDate ?? DateTime.now(),
            to: toDate ?? DateTime.now(),
          );
        } else if (doc is List<Purchase>) {
          docNo = "Purchase_Summary_Report";
          pdfBytes = await WebPdfRouterService.generatePurchaseReportBytes(
            purchases: doc,
            shop: shop,
            from: fromDate ?? DateTime.now(),
            to: toDate ?? DateTime.now(),
          );
        } else {
          docNo = "Ledger_${party.name.replaceAll(' ', '_')}";
          pdfBytes = await WebPartyLedgerPdf.generateBytes(
            shop: shop,
            party: party,
            data: (doc as List).cast<Map<String, dynamic>>(),
            from: fromDate ?? DateTime.now(),
            to: toDate ?? DateTime.now(),
          );
        }
      } else if (upperType == "VOUCHER") {
        final v = doc as Voucher;
        docNo = v.voucherNo;
        pdfBytes = await WebVoucherPdf.generateBytes(v, party, shop, webPh);
      } else {
        return;
      }

      final template = WebEmailDispatchService.getTemplate(
        type: upperType,
        shopName: shop.name.isNotEmpty ? shop.name : "Pharoah ERP",
        docNo: docNo,
        dateRange: dateRange,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sending to $targetMail..."),
            backgroundColor: Colors.indigo,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      final bool success = await WebEmailDispatchService.sendEmailWithPdf(
        config: config,
        shopName: shop.name.isNotEmpty ? shop.name : "Pharoah ERP",
        recipientEmail: targetMail,
        subject: template['subject']!,
        body: template['body']!,
        pdfBytes: pdfBytes,
        fileName: "${upperType}_$docNo",
      );

      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("✅ Mail Sent Successfully to $targetMail!"),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Failed to send mail. Check SMTP Credentials in Settings."),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("WebMailRouterService Error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("System Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 📦 Batch ZIP Dispatcher for CA Audit Mode (Exact Web twin of `PdfRouterService.sendBatchToCa`)
  static Future<bool> sendBatchToCa({
    required BuildContext context,
    required List<dynamic> documents,
    required PharoahWebManager webPh,
    required String type,
    Function(double progress, String label)? onProgress,
  }) async {
    final config = webPh.appConfig;
    final shop = CompanyProfile.fromMap(webPh.companyProfile);

    if (!config.isMailActive) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Mail service is OFF in Settings."),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return false;
    }

    String targetMail = config.caMailID.replaceAll(RegExp(r'\s+'), '').trim();
    final String targetName = config.caName.trim().isNotEmpty ? config.caName.trim() : "Auditor (CA)";

    if (targetMail.isEmpty || !targetMail.contains('@')) {
      if (!context.mounted) return false;
      String? newMail = await _showQuickEmailDialog(context, targetName, isCaMode: true);
      if (newMail == null || newMail.trim().isEmpty || !newMail.contains('@')) return false;
      targetMail = newMail.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();
      webPh.appConfig.caMailID = targetMail;
      await WebSettingsSyncCoordinator.saveAndBroadcastConfig(
        webPh: webPh,
        updatedConfig: webPh.appConfig,
      );
    }

    try {
      final archive = Archive();
      for (int i = 0; i < documents.length; i++) {
        final doc = documents[i];
        Uint8List pdfBytes;
        String fileNo = "";

        if (doc is Sale) {
          fileNo = doc.billNo;
          final p = webPh.parties.firstWhere(
            (x) => (doc.partyId.isNotEmpty && x.id == doc.partyId) || x.name.trim().toLowerCase() == doc.partyName.trim().toLowerCase(),
            orElse: () => Party(id: doc.partyId, name: doc.partyName, gst: doc.partyGstin, state: doc.partyState),
          );
          if (onProgress != null) onProgress((i + 1) / documents.length, p.name);
          pdfBytes = await WebPdfRouterService.generateSaleBytes(sale: doc, party: p, shop: shop, config: config);
        } else if (doc is Purchase) {
          fileNo = doc.billNo.isNotEmpty ? doc.billNo : doc.internalNo;
          final p = webPh.parties.firstWhere(
            (x) => (doc.partyId.isNotEmpty && x.id == doc.partyId) || x.name.trim().toLowerCase() == doc.distributorName.trim().toLowerCase(),
            orElse: () => Party(id: doc.partyId, name: doc.distributorName),
          );
          if (onProgress != null) onProgress((i + 1) / documents.length, p.name);
          pdfBytes = await WebPdfRouterService.generatePurchaseBytes(purchase: doc, party: p, shop: shop);
        } else if (doc is SaleReturn) {
          fileNo = doc.billNo;
          final p = webPh.parties.firstWhere(
            (x) => x.name.trim().toLowerCase() == doc.partyName.trim().toLowerCase(),
            orElse: () => Party(id: 'temp', name: doc.partyName),
          );
          if (onProgress != null) onProgress((i + 1) / documents.length, p.name);
          pdfBytes = await WebPdfRouterService.generateCreditNoteBytes(returnObj: doc, party: p, shop: shop);
        } else if (doc is PurchaseReturn) {
          fileNo = doc.billNo;
          final p = webPh.parties.firstWhere(
            (x) => x.name.trim().toLowerCase() == doc.distributorName.trim().toLowerCase(),
            orElse: () => Party(id: 'temp', name: doc.distributorName),
          );
          if (onProgress != null) onProgress((i + 1) / documents.length, p.name);
          pdfBytes = await WebPdfRouterService.generateDebitNoteBytes(returnObj: doc, party: p, shop: shop);
        } else {
          continue;
        }

        final safeFileNo = fileNo.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
        archive.addFile(ArchiveFile("$safeFileNo.pdf", pdfBytes.length, pdfBytes));
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) return false;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sending Audit ZIP (${documents.length} bills) to CA ($targetMail)..."),
            backgroundColor: Colors.indigo,
          ),
        );
      }

      final bool ok = await WebEmailDispatchService.sendEmailWithPdf(
        config: config,
        shopName: shop.name.isNotEmpty ? shop.name : "Pharoah ERP",
        recipientEmail: targetMail,
        subject: "AUDIT BUNDLE: ${documents.length} $type Bills from ${shop.name}",
        body: "Dear $targetName,\n\nAttached is the zipped bundle of ${documents.length} $type bills for audit verification.\n\nRegards,\n${shop.name}",
        pdfBytes: Uint8List.fromList(zipData),
        fileName: "Audit_${type}_${DateFormat('ddMM').format(DateTime.now())}.zip",
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? "✅ ${documents.length} $type Bills Zipped & Mailed to CA ($targetMail)!"
                : "❌ Failed to mail ZIP bundle to CA. Check SMTP settings."),
            backgroundColor: ok ? Colors.green : Colors.redAccent,
          ),
        );
      }
      return ok;
    } catch (e) {
      debugPrint("WebMailRouterService Batch Error: $e");
      return false;
    }
  }

  /// Dark-theme Web Quick Email Dialog (Matches App's `_showQuickEmailDialog`)
  static Future<String?> _showQuickEmailDialog(
    BuildContext context,
    String targetName, {
    bool isCaMode = false,
  }) async {
    final emailC = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isCaMode ? const Color(0xFFEA580C) : Colors.blueAccent),
        ),
        title: Row(
          children: [
            Icon(
              isCaMode ? Icons.forward_to_inbox_rounded : Icons.alternate_email_rounded,
              color: isCaMode ? const Color(0xFFFB923C) : const Color(0xFF38BDF8),
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              isCaMode ? "Auditor (CA) Email Required" : "Email Required",
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Target: $targetName\nEnter email address to dispatch PDF and save to master:",
              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: emailC,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: "Email ID (e.g. name@gmail.com)",
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF38BDF8), size: 18),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onSubmitted: (val) => Navigator.pop(c, val.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isCaMode ? const Color(0xFFEA580C) : const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(c, emailC.text.trim()),
            icon: const Icon(Icons.send_rounded, size: 14),
            label: const Text("SAVE & PROCEED", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
