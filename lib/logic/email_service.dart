// FILE: lib/logic/email_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path_provider/path_provider.dart';
import 'app_settings_model.dart';

class PharoahEmailService {
  
  // ===========================================================================
  // 📬 MAIN DISPATCH LOGIC (Renamed variables to 'Mail' for conflict safety)
  // ===========================================================================
  static Future<bool> sendEmailWithPdf({
    required AppConfig config,
    required String shopName,
    required String recipientEmail,
    required String subject,
    required String body,
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    // UPDATED: config.isMailActive, config.smtpMailID, config.smtpMailPass
    if (!config.isMailActive || config.smtpMailID.isEmpty || config.smtpMailPass.isEmpty) {
      print("Mail service not configured in settings.");
      return false;
    }

    // A. Temporary File Preparation
    final tempDir = await getTemporaryDirectory();
    String finalFileName = fileName.toLowerCase().endsWith('.zip') 
        ? fileName 
        : '$fileName.pdf';
        
    final file = File('${tempDir.path}/$finalFileName');
    await file.writeAsBytes(pdfBytes);
    
    // B. SMTP Server Config (UPDATED: smtpMailID, smtpMailPass)
    final smtpServer = SmtpServer(
      config.smtpHost,
      port: config.smtpPort,
      username: config.smtpMailID,
      password: config.smtpMailPass,
    );

    // C. Mail Composition (UPDATED: config.smtpMailID)
    final message = Message()
      ..from = Address(config.smtpMailID, shopName)
      ..recipients.add(recipientEmail)
      ..subject = subject
      ..text = body
      ..attachments.add(FileAttachment(file));

    try {
      // D. Dispatch
      await send(message, smtpServer);
      print("Mail sent successfully to $recipientEmail");
      return true;
    } catch (e) {
      print("Mail Dispatch Error: $e");
      return false;
    }
  }

 // ===========================================================================
          // 📝 SMART MESSAGE TEMPLATES (REFINED PROFESSIONAL SIGNATURES)
          // ===========================================================================
          static Map<String, String> getTemplate({
            required String type, 
            required String shopName,
            String docNo = "",
            String dateRange = "",
          }) {
            String subject = "";
            String messageBody = "";

            // Centralized Support & Promo Signature Block
            const String footerSign = "\n\n---\nPowered by Pharoah ERP - Modern Business Billing App.\nDownload now for your business from Google Play Store.\nNeed help or facing download issues? Email us: cloudcubeapps.ok@gmail.com";

            switch (type.toUpperCase()) {
              case "SALE":
                subject = "Tax Invoice Attached: $docNo from $shopName";
                messageBody = "Dear Customer,\n\nPlease find attached your Tax Invoice $docNo for your recent transaction with us.\nWe highly appreciate your business!\n\nRegards,\n$shopName";
                break;
              case "CHALLAN":
                subject = "Delivery Challan Attached: $docNo from $shopName";
                messageBody = "Dear Customer,\n\nPlease find attached the Delivery Challan $docNo for the materials dispatched.\n\nRegards,\n$shopName";
                break;
              case "LEDGER":
                subject = "Ledger Statement: $shopName";
                messageBody = "Dear Customer,\n\nPlease find attached your detailed Ledger Statement of account${dateRange.isNotEmpty ? ' for the period ' + dateRange : ''}.\nKindly review the statement.\n\nRegards,\n$shopName";
                break;
              case "STOCK":
                subject = "Stock Analysis Report: $shopName";
                messageBody = "Dear Partner / Auditor,\n\nPlease find attached the detailed Stock Summary & Valuation report.\n\nRegards,\n$shopName";
                break;
              case "RETURN":
              case "CN":
              case "DN":
                subject = "Credit/Debit Note Attached: $docNo from $shopName";
                messageBody = "Dear Customer / Supplier,\n\nPlease find attached the verified Credit / Debit Note $docNo regarding the returned materials.\n\nRegards,\n$shopName";
                break;
              case "VOUCHER":
                subject = "Voucher Receipt Attached: $docNo from $shopName";
                messageBody = "Dear Customer,\n\nPlease find attached the payment confirmation Voucher Receipt $docNo for your records.\n\nRegards,\n$shopName";
                break;
              default:
                subject = "Document Attached from $shopName";
                messageBody = "Dear Customer,\n\nPlease find attached the document for your reference.\n\nRegards,\n$shopName";
            }

            return {
              "subject": subject, 
              "body": "$messageBody$footerSign"
            };
          }
}
