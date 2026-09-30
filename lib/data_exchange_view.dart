// FILE: lib/data_exchange_view.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'pharoah_manager.dart';
import 'csv_engine.dart';
import 'import_review_screen.dart';
import 'export_selector_view.dart';
import 'pharoah_ai_vision.dart';

class DataExchangeView extends StatefulWidget {
  const DataExchangeView({super.key});
  @override State<DataExchangeView> createState() => _DataExchangeViewState();
}

class _DataExchangeViewState extends State<DataExchangeView> {
  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F9),
      appBar: AppBar(
        title: const Text("PHAROAH DATA HUB", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAiSection(),
            const SizedBox(height: 30),
            const Text("SELECT BUSINESS RELATIONSHIP", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5)),
            const SizedBox(height: 15),

            // --- PATH 1: COMPANY TO COMPANY ---
            _buildRelationCard(
              title: "STORE TO STORE (C2C)",
              subtitle: "Full data sync between your own branches. Includes Purchase Rates.",
              icon: Icons.sync_alt_rounded,
              color: Colors.blue.shade800,
              onTap: () => _showExchangeMenu(context, ph, "C2C"),
            ),

            const SizedBox(height: 20),

            // --- PATH 2: COMPANY TO VENDOR ---
            _buildRelationCard(
              title: "VENDOR TO SUPPLY (C2V)",
              subtitle: "Trade with external parties. Hides your Purchase Rates for privacy.",
              icon: Icons.business_center_rounded,
              color: Colors.teal.shade700,
              onTap: () => _showExchangeMenu(context, ph, "C2V"),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // UI COMPONENTS
  // ===========================================================================

  Widget _buildAiSection() => InkWell(
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const PharoahAiVision())),
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6A1B9A), Color(0xFF4527A0)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(children: [
        Icon(Icons.auto_awesome, color: Colors.white, size: 30),
        SizedBox(width: 15),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("PHAROAH AI VISION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          Text("Scan physical bills into digital entries", style: TextStyle(color: Colors.white70, fontSize: 11)),
        ])),
        Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 14),
      ]),
    ),
  );

  Widget _buildRelationCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.2), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 28)),
          const SizedBox(width: 18),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey, height: 1.3)),
          ])),
        ]),
      ),
    );
  }

  // ===========================================================================
  // LOGIC: DYNAMIC MENU (C2C vs C2V)
  // ===========================================================================

  void _showExchangeMenu(BuildContext context, PharoahManager ph, String mode) {
    bool isC2V = mode == "C2V";
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isC2V ? "EXTERNAL TRADE (C2V)" : "INTERNAL SYNC (C2C)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isC2V ? Colors.teal : Colors.blue)),
            const Divider(height: 30),
            
            // IMPORT OPTIONS
            _menuTile(Icons.file_download_rounded, "Import Sale as Purchase", "Converts vendor bill to stock inward", Colors.green, 
                () { Navigator.pop(c); _pickFile(ph, "PURCHASE", mode); }),
            
            _menuTile(Icons.cloud_download_outlined, "Import Sale as Sale", "Mirror sale records between stores", Colors.blue, 
                () { Navigator.pop(c); _pickFile(ph, "SALE", mode); }),

            const Divider(),

            // EXPORT OPTIONS
            _menuTile(Icons.file_upload_rounded, "Export My Sales", isC2V ? "Hides your Purchase Rates" : "Includes Purchase Rates", Colors.orange, 
                () { Navigator.pop(c); Navigator.push(context, MaterialPageRoute(builder: (c) => ExportSelectorView(exportType: "SALE", maskPurchaseRate: isC2V))); }),

            _menuTile(Icons.inventory_2_outlined, "Export My Purchases", "Backup or Share Inward records", Colors.brown, 
                () { Navigator.pop(c); Navigator.push(context, MaterialPageRoute(builder: (c) => const ExportSelectorView(exportType: "PURCHASE"))); }),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData i, String t, String s, Color c, VoidCallback onTap) => ListTile(
    leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: c.withOpacity(0.1), shape: BoxShape.circle), child: Icon(i, color: c, size: 20)),
    title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
    subtitle: Text(s, style: const TextStyle(fontSize: 10)),
    onTap: onTap,
    trailing: const Icon(Icons.chevron_right, size: 16),
  );

  // FILE: lib/data_exchange_view.dart (Partially provided, focus on _pickFile)

  void _pickFile(PharoahManager ph, String importType, String exchangeMode) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      String content = await file.readAsString();
      List<List<dynamic>> rows = CsvEngine.parseCsv(content);
      
      if (mounted) {
        if (rows.length <= 1) { 
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Selected file is empty!"))); 
          return; 
        }
        // FIXED: Passing all required named parameters
        Navigator.push(context, MaterialPageRoute(
          builder: (c) => ImportReviewScreen(
            csvData: rows, 
            importType: importType,
            exchangeMode: exchangeMode, // C2C or C2V
          )
        ));
      }
    }
  }}
