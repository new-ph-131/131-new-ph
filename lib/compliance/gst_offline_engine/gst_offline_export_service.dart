// FILE: lib/compliance/gst_offline_engine/gst_offline_export_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';

import '../../models.dart';
import '../../gateway/company_registry_model.dart';
import 'gst_offline_models.dart';
import 'gst_offline_json_builder.dart';
import 'gst_offline_csv_builder.dart';
import 'gst_preflight_validator.dart';

/// Unified GST Offline Export & Audit Orchestrator
/// Works across Web, Android, and Desktop platforms.
class GstOfflineExportService {
  /// Exports Official GSTR-1 JSON for direct portal upload
  static Future<bool> exportGstr1Json({
    required BuildContext context,
    required List<Sale> sales,
    required List<SaleReturn> returns,
    required List<Party> parties,
    required CompanyProfile shop,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      final payload = GstOfflineJsonBuilder.buildGstr1Payload(
        sales: sales,
        returns: returns,
        parties: parties,
        shop: shop,
        fromDate: fromDate,
        toDate: toDate,
      );

      final jsonStr = payload.toFormattedJson();
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      final cleanGstin = shop.gstin.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      final fileName = "GSTR1_${cleanGstin.isNotEmpty ? cleanGstin : 'PORTAL'}_${payload.fp}";

      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        ext: "json",
        mimeType: MimeType.other,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F766E),
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "✅ Official GSTR-1 JSON ($fileName.json) ready for GST Portal upload!",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text("❌ Failed to generate GST JSON: $e"),
          ),
        );
      }
      return false;
    }
  }

  /// Exports official Government V2.2 CSVs (B2B, B2CS, HSN, DOCS)
  static Future<void> exportCsvSection({
    required BuildContext context,
    required String section, // "B2B", "B2CS", "HSN", "DOCS"
    required List<Sale> sales,
    required List<Party> parties,
    required CompanyProfile shop,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      String csvContent = "";
      String sectionName = "";

      switch (section.toUpperCase()) {
        case "B2B":
          csvContent = GstOfflineCsvBuilder.buildB2bCsv(
            sales: sales,
            parties: parties,
            shop: shop,
            fromDate: fromDate,
            toDate: toDate,
          );
          sectionName = "b2b_sez_de";
          break;
        case "B2CS":
          csvContent = GstOfflineCsvBuilder.buildB2csCsv(
            sales: sales,
            shop: shop,
            fromDate: fromDate,
            toDate: toDate,
          );
          sectionName = "b2cs";
          break;
        case "HSN":
          csvContent = GstOfflineCsvBuilder.buildHsnCsv(
            sales: sales,
            shop: shop,
            fromDate: fromDate,
            toDate: toDate,
          );
          sectionName = "hsn";
          break;
        case "DOCS":
          csvContent = GstOfflineCsvBuilder.buildDocsCsv(
            sales: sales,
            fromDate: fromDate,
            toDate: toDate,
          );
          sectionName = "docs";
          break;
        default:
          return;
      }

      final bytes = Uint8List.fromList(utf8.encode(csvContent));
      final fp = DateFormat('MMyyyy').format(fromDate);
      final fileName = "GSTR1_${sectionName}_$fp";

      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        ext: "csv",
        mimeType: MimeType.csv,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.teal.shade800,
            content: Text("✅ Exported $fileName.csv (GST Offline Tool format)"),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text("❌ Error exporting CSV: $e"),
          ),
        );
      }
    }
  }

  /// Opens full pre-upload audit modal dialog
  static void showAuditModal({
    required BuildContext context,
    required List<Sale> sales,
    required List<SaleReturn> returns,
    required List<Party> parties,
    required CompanyProfile shop,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final report = GstPreflightValidator.audit(
      sales: sales,
      shop: shop,
      fromDate: fromDate,
      toDate: toDate,
    );

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.white12),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: report.isReadyForUpload
                    ? Colors.green.withAlpha(40)
                    : Colors.amber.withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: Icon(
                report.isReadyForUpload
                    ? Icons.verified_rounded
                    : Icons.warning_amber_rounded,
                color: report.isReadyForUpload ? Colors.greenAccent : Colors.amberAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "GSTN Pre-Upload Audit",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    report.isReadyForUpload
                        ? "0 Critical Errors • Ready for GST Portal"
                        : "${report.errorCount} Errors, ${report.warningCount} Warnings",
                    style: TextStyle(
                      color: report.isReadyForUpload ? Colors.greenAccent : Colors.amberAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                // Stats Grid
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _statItem("Total Bills", "${report.totalBills}"),
                          _statItem("B2B (Tax)", "${report.b2bBills}"),
                          _statItem("B2C (Retail)", "${report.b2cBills}"),
                          _statItem("Cancelled", "${report.cancelledBills}"),
                        ],
                      ),
                      const Divider(color: Colors.white10, height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _statItem("Taxable ₹", "₹${report.totalTaxable.toStringAsFixed(2)}"),
                          _statItem("CGST+SGST", "₹${(report.totalCgst + report.totalSgst).toStringAsFixed(2)}"),
                          _statItem("IGST ₹", "₹${report.totalIgst.toStringAsFixed(2)}"),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "AUDIT LOGS & WARNINGS",
                  style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                if (report.issues.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.greenAccent.withAlpha(50)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "All party GSTINs, HSN codes, and invoice dates strictly comply with CBIC schema.",
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    children: report.issues.map((issue) {
                      final isErr = issue.severity == GstIssueSeverity.error;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isErr ? Colors.red.withAlpha(25) : Colors.amber.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isErr ? Colors.redAccent.withAlpha(50) : Colors.amberAccent.withAlpha(40)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              isErr ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                              color: isErr ? Colors.redAccent : Colors.amberAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    issue.title + (issue.billNo != null ? " (Bill: ${issue.billNo})" : ""),
                                    style: TextStyle(
                                      color: isErr ? Colors.redAccent : Colors.amberAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    issue.message,
                                    style: const TextStyle(color: Colors.white70, fontSize: 10.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CLOSE", style: TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(c);
              exportGstr1Json(
                context: context,
                sales: sales,
                returns: returns,
                parties: parties,
                shop: shop,
                fromDate: fromDate,
                toDate: toDate,
              );
            },
            icon: const Icon(Icons.file_download_rounded, size: 16),
            label: const Text("DOWNLOAD GOVT JSON", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  static Widget _statItem(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5)),
    ],
  );
}
