// FILE: lib/web_live_sync/sub_views/web_settings/web_branding_settings_view.dart
// Revision: #PH-REV-792 (ENTERPRISE-WEB-SETTINGS-HUB-AND-D1-CONFIG-SYNC)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import '../../pharoah_web_manager.dart';
import 'web_settings_sync_coordinator.dart';

class WebBrandingSettingsView extends StatefulWidget {
  final VoidCallback onBack;
  const WebBrandingSettingsView({super.key, required this.onBack});

  @override
  State<WebBrandingSettingsView> createState() => _WebBrandingSettingsViewState();
}

class _WebBrandingSettingsViewState extends State<WebBrandingSettingsView> {
  late bool showLogo;
  String? logoPath;
  late String printFormat;
  late bool showTerms;
  late TextEditingController termsC;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    showLogo = webPh.appConfig.showLogo;
    logoPath = webPh.appConfig.logoPath;
    printFormat = webPh.appConfig.printFormat;
    showTerms = webPh.appConfig.showTerms;
    termsC = TextEditingController(text: webPh.appConfig.termsAndConditions);
  }

  @override
  void dispose() {
    termsC.dispose();
    super.dispose();
  }

  Future<void> _pickLogo(PharoahWebManager webPh) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'png', 'jpeg', 'webp'],
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final base64String = "data:image/png;base64,${base64Encode(bytes)}";
        setState(() {
          logoPath = base64String;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Logo loaded! Click Save to apply."), backgroundColor: Colors.teal),
          );
        }
      }
    } catch (e) {
      debugPrint("Logo pick error: $e");
    }
  }

  Future<void> _save(PharoahWebManager webPh) async {
    setState(() => isSaving = true);
    final cfg = webPh.appConfig;
    cfg.showLogo = showLogo;
    cfg.logoPath = logoPath;
    cfg.printFormat = printFormat;
    cfg.showTerms = showTerms;
    cfg.termsAndConditions = termsC.text.trim();

    bool synced = await WebSettingsSyncCoordinator.saveAndBroadcastConfig(
      webPh: webPh,
      updatedConfig: cfg,
    );
    setState(() => isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(synced
              ? "✅ Branding Settings Synced to Cloud & App!"
              : "⚠️ Saved locally, cloud sync retrying in background."),
          backgroundColor: synced ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: ListView(
        children: [
          // Header
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("SETTINGS HUB", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.palette_rounded, color: Colors.purpleAccent, size: 24),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "BRANDING & DOCUMENT STYLE",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  Text(
                    "Shop Logo, Print Layout (A4/Thermal) and Statutory Rules",
                    style: TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 30),

          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 680),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.purple.withOpacity(0.3), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo Switch
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: showLogo ? Colors.purple.withOpacity(0.12) : Colors.black26,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: showLogo ? Colors.purpleAccent : Colors.white10),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("SHOW SHOP LOGO ON INVOICE & PDF", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: const Text("Toggles the business branding logo block on invoices", style: TextStyle(color: Colors.white54, fontSize: 10)),
                      value: showLogo,
                      activeColor: Colors.purpleAccent,
                      onChanged: (val) => setState(() => showLogo = val),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Upload Logo Button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.purpleAccent),
                        foregroundColor: Colors.purpleAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _pickLogo(webPh),
                      icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                      label: const Text("CHOOSE SHOP LOGO IMAGE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                  if (logoPath != null && logoPath!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.purple.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text("Logo configured & active", style: TextStyle(color: Colors.white70, fontSize: 11)),
                          ),
                          TextButton(
                            onPressed: () => setState(() => logoPath = null),
                            child: const Text("REMOVE", style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Divider(color: Colors.white10, height: 36),

                  // Printing Format Selector
                  const Text("DEFAULT PRINTING FORMAT", style: TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _formatCard("A4 Landscape", "A4", Icons.description_outlined),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _formatCard("80mm Thermal", "Thermal", Icons.receipt_long_rounded),
                      ),
                    ],
                  ),

                  const Divider(color: Colors.white10, height: 36),

                  // Statutory Terms Switch & Input
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: showTerms ? Colors.purple.withOpacity(0.12) : Colors.black26,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: showTerms ? Colors.purpleAccent : Colors.white10),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("ENABLE STATUTORY TERMS & CONDITIONS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: const Text("Print standard business policy & jurisdiction notice at footer", style: TextStyle(color: Colors.white54, fontSize: 10)),
                      value: showTerms,
                      activeColor: Colors.purpleAccent,
                      onChanged: (val) => setState(() => showTerms = val),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text("TERMS & CONDITIONS TEXT", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: TextField(
                      controller: termsC,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(border: InputBorder.none),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF9333EA),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: isSaving ? null : () => _save(webPh),
                      icon: isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        isSaving ? "SAVING BRANDING..." : "SAVE BRANDING SETTINGS",
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatCard(String label, String value, IconData icon) {
    bool isSel = printFormat == value;
    return InkWell(
      onTap: () => setState(() => printFormat = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSel ? Colors.purple.withOpacity(0.2) : Colors.black26,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSel ? Colors.purpleAccent : Colors.white12, width: isSel ? 1.5 : 1.0),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSel ? Colors.purpleAccent : Colors.white54, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSel ? Colors.white : Colors.white70,
                  fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            if (isSel) const Icon(Icons.check_circle_rounded, color: Colors.purpleAccent, size: 16),
          ],
        ),
      ),
    );
  }
}
