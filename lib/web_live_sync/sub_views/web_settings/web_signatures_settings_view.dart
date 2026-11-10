// FILE: lib/web_live_sync/sub_views/web_settings/web_signatures_settings_view.dart
// Revision: #PH-REV-792 (ENTERPRISE-WEB-SETTINGS-HUB-AND-D1-CONFIG-SYNC)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../pharoah_web_manager.dart';
import 'web_settings_sync_coordinator.dart';

class WebSignaturesSettingsView extends StatefulWidget {
  final VoidCallback onBack;
  const WebSignaturesSettingsView({super.key, required this.onBack});

  @override
  State<WebSignaturesSettingsView> createState() => _WebSignaturesSettingsViewState();
}

class _WebSignaturesSettingsViewState extends State<WebSignaturesSettingsView> {
  late bool showCustomerSignChallan;
  late bool showStaffSign;
  late TextEditingController labelC;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    showCustomerSignChallan = webPh.appConfig.showCustomerSignChallan;
    showStaffSign = webPh.appConfig.showStaffSign;
    labelC = TextEditingController(text: webPh.appConfig.signLabel);
  }

  @override
  void dispose() {
    labelC.dispose();
    super.dispose();
  }

  Future<void> _save(PharoahWebManager webPh) async {
    setState(() => isSaving = true);
    final cfg = webPh.appConfig;
    cfg.showCustomerSignChallan = showCustomerSignChallan;
    cfg.showStaffSign = showStaffSign;
    cfg.signLabel = labelC.text.trim();

    bool synced = await WebSettingsSyncCoordinator.saveAndBroadcastConfig(
      webPh: webPh,
      updatedConfig: cfg,
    );
    setState(() => isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(synced
              ? "✅ Signature Settings Synced to Cloud & App!"
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
              const Icon(Icons.security, color: Colors.blueAccent, size: 24),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "SIGNATURE & SERIES AUDIT",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  Text(
                    "Authorised Signatures, Receiver Verification and Invoice Schemes",
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
                border: Border.all(color: Colors.blueAccent.withOpacity(0.3), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Switch 1: showCustomerSignChallan
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: showCustomerSignChallan ? Colors.blue.withOpacity(0.12) : Colors.black26,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: showCustomerSignChallan ? Colors.blueAccent : Colors.white10),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("ENABLE STAFF SIGNATURE CAPTURE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: const Text("Prompts for digital receiver/staff signature verification in challans", style: TextStyle(color: Colors.white54, fontSize: 10)),
                      value: showCustomerSignChallan,
                      activeColor: Colors.blueAccent,
                      onChanged: (val) => setState(() => showCustomerSignChallan = val),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Switch 2: showStaffSign
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: showStaffSign ? Colors.blue.withOpacity(0.12) : Colors.black26,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: showStaffSign ? Colors.blueAccent : Colors.white10),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("SHOW AUTHORISED SIGNATORY BLOCK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: const Text("Prints company stamp & signature placeholder on bills", style: TextStyle(color: Colors.white54, fontSize: 10)),
                      value: showStaffSign,
                      activeColor: Colors.blueAccent,
                      onChanged: (val) => setState(() => showStaffSign = val),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text("AUTHORISED SIGNATORY DESIGNATION", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: TextField(
                      controller: labelC,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "e.g., Authorised Signatory / Store Manager",
                        hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                      ),
                    ),
                  ),

                  const Divider(color: Colors.white10, height: 36),

                  // Series information card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.format_list_numbered_rounded, color: Colors.blueAccent, size: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("INVOICE NUMBERING SERIES", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.8)),
                              const SizedBox(height: 4),
                              Text(
                                "Default Sale Prefix: ${webPh.appConfig.salePrefix} | Pur Prefix: ${webPh.appConfig.purPrefix}",
                                style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: isSaving ? null : () => _save(webPh),
                      icon: isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        isSaving ? "SAVING SIGNATURES..." : "SAVE SIGNATURE SETTINGS",
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
}
