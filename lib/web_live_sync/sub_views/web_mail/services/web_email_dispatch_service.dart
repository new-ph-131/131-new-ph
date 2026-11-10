// FILE: lib/web_live_sync/sub_views/web_mail/services/web_email_dispatch_service.dart
// Revision: #PH-REV-798 (ENTERPRISE-WEB-EMAIL-DISPATCH-SERVICE)
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../../logic/app_settings_model.dart';
import '../../../web_cloud_config.dart';

/// 📬 WebEmailDispatchService
/// Web twin of PharoahEmailService (`lib/logic/email_service.dart`).
/// Strict File Separation Rule: Handles message templates & Cloudflare Edge SMTP dispatch.
class WebEmailDispatchService {
  static String get mailRelayEndpoint => "${WebCloudConfig.webPortalUrl}/api/send_mail";

  /// Dispatches PDF or ZIP attachment over Cloudflare Edge SMTP Relay
  static Future<bool> sendEmailWithPdf({
    required AppConfig config,
    required String shopName,
    required String recipientEmail,
    required String subject,
    required String body,
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    if (!config.isMailActive || config.smtpMailID.trim().isEmpty || config.smtpMailPass.trim().isEmpty) {
      debugPrint("WebEmailDispatchService: Mail service not configured in settings.");
      return false;
    }

    final String finalFileName = (fileName.toLowerCase().endsWith('.zip') || fileName.toLowerCase().endsWith('.pdf'))
        ? fileName
        : '$fileName.pdf';

    final payload = {
      "smtpHost": config.smtpHost.trim().isNotEmpty ? config.smtpHost.trim() : "smtp.gmail.com",
      "smtpPort": config.smtpPort > 0 ? config.smtpPort : 587,
      "smtpMailID": config.smtpMailID.replaceAll(RegExp(r'\s+'), '').trim(),
      "smtpMailPass": config.smtpMailPass.replaceAll(RegExp(r'\s+'), '').trim(),
      "shopName": shopName.trim().isNotEmpty ? shopName.trim() : "Pharoah ERP",
      "recipientEmail": recipientEmail.replaceAll(RegExp(r'\s+'), '').trim(),
      "subject": subject,
      "body": body,
      "fileName": finalFileName,
      "attachmentBase64": base64Encode(pdfBytes),
    };

    try {
      final response = await http
          .post(
            Uri.parse(mailRelayEndpoint),
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded["status"] == "SUCCESS") {
          debugPrint("✅ [WebEmailDispatchService] Mail sent to $recipientEmail");
          return true;
        }
      }
      debugPrint("❌ [WebEmailDispatchService] Server returned ${response.statusCode}: ${response.body}");
      return false;
    } catch (e) {
      debugPrint("⚠️ [WebEmailDispatchService] Dispatch Error: $e");
      return false;
    }
  }

  /// Exact same professional email templates & signatures as Mobile App (`PharoahEmailService.getTemplate`)
  static Map<String, String> getTemplate({
    required String type,
    required String shopName,
    String docNo = "",
    String dateRange = "",
  }) {
    String subject = "";
    String messageBody = "";

    const String footerSign =
        "\n\n---\nPowered by Pharoah ERP - Modern Business Billing App.\nDownload now for your business from Google Play Store.\nNeed help or facing download issues? Email us: cloudcubeapps.ok@gmail.com";

    switch (type.toUpperCase()) {
      case "SALE":
        subject = "Tax Invoice Attached: $docNo from $shopName";
        messageBody =
            "Dear Customer,\n\nPlease find attached your Tax Invoice $docNo for your recent transaction with us.\nWe highly appreciate your business!\n\nRegards,\n$shopName";
        break;
      case "PURCHASE":
        subject = "Purchase Inward Invoice Attached: $docNo from $shopName";
        messageBody =
            "Dear Supplier / Partner,\n\nPlease find attached the Purchase Inward Invoice $docNo recorded in our books.\n\nRegards,\n$shopName";
        break;
      case "CHALLAN":
        subject = "Delivery Challan Attached: $docNo from $shopName";
        messageBody =
            "Dear Customer,\n\nPlease find attached the Delivery Challan $docNo for the materials dispatched.\n\nRegards,\n$shopName";
        break;
      case "LEDGER":
        subject = "Ledger Statement: $shopName";
        messageBody =
            "Dear Customer,\n\nPlease find attached your detailed Ledger Statement of account${dateRange.isNotEmpty ? ' for the period ' + dateRange : ''}.\nKindly review the statement.\n\nRegards,\n$shopName";
        break;
      case "STOCK":
        subject = "Stock Analysis Report: $shopName";
        messageBody =
            "Dear Partner / Auditor,\n\nPlease find attached the detailed Stock Summary & Valuation report.\n\nRegards,\n$shopName";
        break;
      case "RETURN":
      case "CN":
      case "DN":
        subject = "Credit/Debit Note Attached: $docNo from $shopName";
        messageBody =
            "Dear Customer / Supplier,\n\nPlease find attached the verified Credit / Debit Note $docNo regarding the returned materials.\n\nRegards,\n$shopName";
        break;
      case "VOUCHER":
        subject = "Voucher Receipt Attached: $docNo from $shopName";
        messageBody =
            "Dear Customer,\n\nPlease find attached the payment confirmation Voucher Receipt $docNo for your records.\n\nRegards,\n$shopName";
        break;
      default:
        subject = "Document Attached from $shopName";
        messageBody =
            "Dear Customer,\n\nPlease find attached the document for your reference.\n\nRegards,\n$shopName";
    }

    return {
      "subject": subject,
      "body": "$messageBody$footerSign",
    };
  }
}
