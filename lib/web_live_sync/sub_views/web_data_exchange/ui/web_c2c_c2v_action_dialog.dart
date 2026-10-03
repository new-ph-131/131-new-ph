// FILE: lib/web_live_sync/sub_views/web_data_exchange/ui/web_c2c_c2v_action_dialog.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../engine/web_csv_engine.dart';

class WebC2cC2vActionDialog extends StatelessWidget {
  final String mode; // "C2C" or "C2V"
  final Function(List<List<dynamic>> rows, String importType, String exchangeMode) onImportCsvReady;
  final Function(String exportType, bool maskPurchaseRate) onOpenExportSelector;

  const WebC2cC2vActionDialog({
    super.key,
    required this.mode,
    required this.onImportCsvReady,
    required this.onOpenExportSelector,
  });

  void _pickAndParseCsv(BuildContext context, String importType) async {
    Navigator.pop(context);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception("Selected CSV file is empty.");
      }

      String content = utf8.decode(bytes);
      List<List<dynamic>> rows = WebCsvEngine.parseCsvString(content);

      if (rows.length <= 1) {
        throw Exception("CSV file has no data rows.");
      }

      onImportCsvReady(rows, importType, mode);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("CSV Import Error: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isC2v = mode == "C2V";
    Color themeColor = isC2v ? const Color(0xFF0D9488) : const Color(0xFF2563EB);

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: themeColor.withAlpha(120), width: 1.5),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: themeColor.withAlpha(35), shape: BoxShape.circle),
            child: Icon(isC2v ? Icons.business_center_rounded : Icons.sync_alt_rounded, color: themeColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isC2v ? "EXTERNAL TRADE (C2V)" : "STORE TO STORE SYNC (C2C)",
                  style: TextStyle(color: themeColor, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
                Text(
                  isC2v ? "Purchase rates masked for vendor privacy" : "Full sync between your own stores/branches",
                  style: const TextStyle(color: Colors.white54, fontSize: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "IMPORT OPTIONS (INWARD DATA)",
              style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            _menuOption(
              icon: Icons.file_download_rounded,
              title: "Import Sale as Purchase (Stock Inward)",
              subtitle: "Converts sender sales invoice into inward purchase with batches",
              color: Colors.greenAccent,
              onTap: () => _pickAndParseCsv(context, "PURCHASE"),
            ),
            const SizedBox(height: 8),
            _menuOption(
              icon: Icons.cloud_download_outlined,
              title: "Import Sale as Sale (Mirror Outward)",
              subtitle: "Mirror sales records across retail branches",
              color: const Color(0xFF38BDF8),
              onTap: () => _pickAndParseCsv(context, "SALE"),
            ),
            const Divider(color: Colors.white10, height: 24),
            const Text(
              "EXPORT OPTIONS (39-COL CSV)",
              style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            _menuOption(
              icon: Icons.file_upload_rounded,
              title: "Export My Sales",
              subtitle: isC2v ? "Purchase rate masked to 0.0" : "Includes full purchase & sale rate",
              color: Colors.orangeAccent,
              onTap: () {
                Navigator.pop(context);
                onOpenExportSelector("SALE", isC2v);
              },
            ),
            const SizedBox(height: 8),
            _menuOption(
              icon: Icons.inventory_2_outlined,
              title: "Export My Purchases",
              subtitle: "Backup or share inward stock records",
              color: const Color(0xFFFBBF24),
              onTap: () {
                Navigator.pop(context);
                onOpenExportSelector("PURCHASE", false);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }

  Widget _menuOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 12),
          ],
        ),
      ),
    );
  }
}
