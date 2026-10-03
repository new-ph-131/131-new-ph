// FILE: lib/web_live_sync/sub_views/web_data_exchange/ui/web_data_exchange_hub.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../web_smart_entry/ui/web_smart_entry_hub.dart';
import '../engine/web_csv_engine.dart';
import 'web_export_selector_view.dart';
import 'web_c2c_c2v_action_dialog.dart';
import 'web_import_review_screen.dart';

class WebDataExchangeHub extends StatefulWidget {
  final VoidCallback onBack;
  final String? initialAction;

  const WebDataExchangeHub({super.key, required this.onBack, this.initialAction});

  @override
  State<WebDataExchangeHub> createState() => _WebDataExchangeHubState();
}

class _WebDataExchangeHubState extends State<WebDataExchangeHub> {
  String activeSubView = "HUB"; // "HUB", "SMART_ENTRY", "EXPORT_SELECTOR", "IMPORT_REVIEW"

  // Sub-view params
  String currentExportType = "SALE";
  bool currentMaskRate = false;

  List<List<dynamic>> currentCsvRows = [];
  String currentImportType = "PURCHASE";
  String currentExchangeMode = "C2C";

  @override
  void initState() {
    super.initState();
    if (widget.initialAction == "GO_SMART_ENTRY") {
      activeSubView = "SMART_ENTRY";
    } else if (widget.initialAction == "GO_C2C") {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openC2cDialog(context));
    } else if (widget.initialAction == "GO_C2V") {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openC2vDialog(context));
    } else if (widget.initialAction == "GO_CSV") {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showDirectCsvOptions(context));
    }
  }

  void _openC2cDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => WebC2cC2vActionDialog(
        mode: "C2C",
        onImportCsvReady: (rows, importType, mode) {
          setState(() {
            currentCsvRows = rows;
            currentImportType = importType;
            currentExchangeMode = mode;
            activeSubView = "IMPORT_REVIEW";
          });
        },
        onOpenExportSelector: (exportType, maskRate) {
          setState(() {
            currentExportType = exportType;
            currentMaskRate = maskRate;
            activeSubView = "EXPORT_SELECTOR";
          });
        },
      ),
    );
  }

  void _openC2vDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => WebC2cC2vActionDialog(
        mode: "C2V",
        onImportCsvReady: (rows, importType, mode) {
          setState(() {
            currentCsvRows = rows;
            currentImportType = importType;
            currentExchangeMode = mode;
            activeSubView = "IMPORT_REVIEW";
          });
        },
        onOpenExportSelector: (exportType, maskRate) {
          setState(() {
            currentExportType = exportType;
            currentMaskRate = maskRate;
            activeSubView = "EXPORT_SELECTOR";
          });
        },
      ),
    );
  }

  void _showDirectCsvOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.table_chart_rounded, color: Color(0xFFD97706), size: 20),
            SizedBox(width: 8),
            Text("39-COL UNIVERSAL CSV", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.file_download_rounded, color: Colors.greenAccent),
              title: const Text("Import 39-Col CSV File", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              subtitle: const Text("Upload and audit 39-column CSV into system", style: TextStyle(color: Colors.white38, fontSize: 10)),
              onTap: () {
                Navigator.pop(c);
                _pickDirectCsv(context, "PURCHASE");
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              dense: true,
              leading: const Icon(Icons.file_upload_rounded, color: Color(0xFF38BDF8)),
              title: const Text("Export Sales to 39-Col CSV", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              subtitle: const Text("Select sales invoices to download 39-column CSV", style: TextStyle(color: Colors.white38, fontSize: 10)),
              onTap: () {
                Navigator.pop(c);
                setState(() {
                  currentExportType = "SALE";
                  currentMaskRate = false;
                  activeSubView = "EXPORT_SELECTOR";
                });
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.inventory_2_outlined, color: Color(0xFFFBBF24)),
              title: const Text("Export Purchases to 39-Col CSV", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              subtitle: const Text("Select purchase inwards to download 39-column CSV", style: TextStyle(color: Colors.white38, fontSize: 10)),
              onTap: () {
                Navigator.pop(c);
                setState(() {
                  currentExportType = "PURCHASE";
                  currentMaskRate = false;
                  activeSubView = "EXPORT_SELECTOR";
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _pickDirectCsv(BuildContext context, String importType) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      Uint8List? bytes = result.files.first.bytes;
      if (bytes == null || bytes.isEmpty) return;

      String content = utf8.decode(bytes);
      List<List<dynamic>> rows = WebCsvEngine.parseCsvString(content);
      if (rows.length <= 1) {
        throw Exception("CSV file has no data rows.");
      }

      setState(() {
        currentCsvRows = rows;
        currentImportType = importType;
        currentExchangeMode = "UNIVERSAL_CSV";
        activeSubView = "IMPORT_REVIEW";
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (activeSubView == "SMART_ENTRY") {
      return WebSmartEntryHub(onBack: () => setState(() => activeSubView = "HUB"));
    }
    if (activeSubView == "EXPORT_SELECTOR") {
      return WebExportSelectorView(
        exportType: currentExportType,
        maskPurchaseRate: currentMaskRate,
        onBack: () => setState(() => activeSubView = "HUB"),
      );
    }
    if (activeSubView == "IMPORT_REVIEW") {
      return WebImportReviewScreen(
        csvData: currentCsvRows,
        importType: currentImportType,
        exchangeMode: currentExchangeMode,
        onBack: () => setState(() => activeSubView = "HUB"),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK TO DASHBOARD", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.cloud_sync_rounded, color: Color(0xFF38BDF8), size: 24),
              const SizedBox(width: 10),
              const Text(
                "DATA EXCHANGE & UNIVERSAL PROTOCOL HUB",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 25),

          const Text(
            "PRIMARY EXCHANGE MODULES",
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
          const SizedBox(height: 14),

          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = constraints.maxWidth > 950 ? 4 : (constraints.maxWidth > 650 ? 2 : 1);

              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.3,
                children: [
                  _hubCard(
                    title: "Smart Entry",
                    subtitle: "Medilente & Amazon AI/PDF Inward Importers",
                    badgeText: "PDF / OCR",
                    icon: Icons.auto_fix_high_rounded,
                    color: const Color(0xFF38BDF8),
                    onTap: () => setState(() => activeSubView = "SMART_ENTRY"),
                  ),
                  _hubCard(
                    title: "Store to Store (C2C)",
                    subtitle: "Full branch sync with unmasked purchase rates",
                    badgeText: "C2C Full",
                    icon: Icons.sync_alt_rounded,
                    color: const Color(0xFF2563EB),
                    onTap: () => _openC2cDialog(context),
                  ),
                  _hubCard(
                    title: "Vendor Supply (C2V)",
                    subtitle: "External trade with purchase rates masked to 0.0",
                    badgeText: "C2V Masked",
                    icon: Icons.business_center_rounded,
                    color: const Color(0xFF0D9488),
                    onTap: () => _openC2vDialog(context),
                  ),
                  _hubCard(
                    title: "39-Col CSV",
                    subtitle: "Pharoah proprietary 39-column CSV import/export",
                    badgeText: "Universal",
                    icon: Icons.table_chart_rounded,
                    color: const Color(0xFFD97706),
                    onTap: () => _showDirectCsvOptions(context),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),

          // Protocol Specification Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xFF38BDF8), size: 18),
                    SizedBox(width: 8),
                    Text(
                      "PHAROAH 39-COLUMN UNIVERSAL INTER-STORE PROTOCOL",
                      style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  "• 100% Seamless Trade: Sales exported from Store A auto-import into Store B as verified Stock Inward.\n"
                  "• C2C Sync preserves full purchase cost, MRP, batch numbers, and expiries across your branches.\n"
                  "• C2V Sync masks Column 31 (PUR_RATE) to 0.0 to protect your confidential profit margins while trading externally.\n"
                  "• Smart Date Watchdog ensures old invoices are compliant with the active Financial Year.",
                  style: TextStyle(color: Colors.white60, fontSize: 10.5, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubCard({
    required String title,
    required String subtitle,
    required String badgeText,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(90), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(20),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withAlpha(35), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 22),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withAlpha(90), width: 0.5),
                  ),
                  child: Text(badgeText, style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 9.5), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
