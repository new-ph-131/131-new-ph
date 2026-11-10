// FILE: lib/web_live_sync/sub_views/web_settings/web_finance_settings_view.dart
// Revision: #PH-REV-792 (ENTERPRISE-WEB-SETTINGS-HUB-AND-D1-CONFIG-SYNC)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import '../../pharoah_web_manager.dart';
import 'web_settings_sync_coordinator.dart';

class WebFinanceSettingsView extends StatefulWidget {
  final VoidCallback onBack;
  const WebFinanceSettingsView({super.key, required this.onBack});

  @override
  State<WebFinanceSettingsView> createState() => _WebFinanceSettingsViewState();
}

class _WebFinanceSettingsViewState extends State<WebFinanceSettingsView> {
  late bool showQrCode;
  String? qrCodePath;
  late TextEditingController nameC, bankC, numC, ifscC;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    showQrCode = webPh.appConfig.showQrCode;
    qrCodePath = webPh.appConfig.qrCodePath;
    nameC = TextEditingController(text: webPh.appConfig.bankAccName);
    bankC = TextEditingController(text: webPh.appConfig.bankNameBranch);
    numC = TextEditingController(text: webPh.appConfig.bankAccNumber);
    ifscC = TextEditingController(text: webPh.appConfig.bankIfsc);
  }

  @override
  void dispose() {
    nameC.dispose();
    bankC.dispose();
    numC.dispose();
    ifscC.dispose();
    super.dispose();
  }

  Future<void> _pickQr(PharoahWebManager webPh) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'png', 'jpeg', 'webp'],
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final base64String = "data:image/png;base64,${base64Encode(bytes)}";
        setState(() => qrCodePath = base64String);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ UPI QR Image loaded! Click Save to apply."), backgroundColor: Colors.teal),
          );
        }
      }
    } catch (e) {
      debugPrint("QR pick error: $e");
    }
  }

  Future<void> _save(PharoahWebManager webPh) async {
    setState(() => isSaving = true);
    final cfg = webPh.appConfig;
    cfg.showQrCode = showQrCode;
    cfg.qrCodePath = qrCodePath;
    cfg.bankAccName = nameC.text.trim().toUpperCase();
    cfg.bankNameBranch = bankC.text.trim().toUpperCase();
    cfg.bankAccNumber = numC.text.trim();
    cfg.bankIfsc = ifscC.text.trim().toUpperCase();

    bool synced = await WebSettingsSyncCoordinator.saveAndBroadcastConfig(
      webPh: webPh,
      updatedConfig: cfg,
    );
    setState(() => isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(synced
              ? "✅ Finance & Bank Settings Synced to Cloud & App!"
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
              const Icon(Icons.account_balance_rounded, color: Colors.tealAccent, size: 24),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "PAYMENT GATEWAY & FINANCE",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  Text(
                    "Scan-To-Pay UPI QR Code and Bank Settlement Credentials",
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
                border: Border.all(color: Colors.tealAccent.withOpacity(0.3), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // UPI QR Switch
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: showQrCode ? Colors.teal.withOpacity(0.12) : Colors.black26,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: showQrCode ? Colors.tealAccent : Colors.white10),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("ENABLE SCAN-TO-PAY UPI QR ON BILLS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: const Text("Adds direct payment QR code block for customer UPI settlement", style: TextStyle(color: Colors.white54, fontSize: 10)),
                      value: showQrCode,
                      activeColor: Colors.tealAccent,
                      onChanged: (val) => setState(() => showQrCode = val),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.tealAccent),
                        foregroundColor: Colors.tealAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _pickQr(webPh),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: const Text("UPLOAD UPI QR IMAGE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                  if (qrCodePath != null && qrCodePath!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.tealAccent, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text("UPI QR configured & active", style: TextStyle(color: Colors.white70, fontSize: 11)),
                          ),
                          TextButton(
                            onPressed: () => setState(() => qrCodePath = null),
                            child: const Text("REMOVE", style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Divider(color: Colors.white10, height: 36),

                  const Text("BANK SETTLEMENT DETAILS", style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                  const SizedBox(height: 14),

                  _field("BENEFICIARY ACCOUNT HOLDER NAME", nameC, Icons.person_rounded, isCaps: true),
                  const SizedBox(height: 14),
                  _field("BANK NAME & BRANCH", bankC, Icons.account_balance_rounded, isCaps: true),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _field("ACCOUNT NUMBER", numC, Icons.pin_rounded, isNum: true)),
                      const SizedBox(width: 14),
                      Expanded(child: _field("IFSC CODE", ifscC, Icons.password_rounded, isCaps: true)),
                    ],
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: isSaving ? null : () => _save(webPh),
                      icon: isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        isSaving ? "SAVING FINANCE..." : "SAVE FINANCE SETTINGS",
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

  Widget _field(String label, TextEditingController ctrl, IconData icon, {bool isNum = false, bool isCaps = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.tealAccent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  keyboardType: isNum ? TextInputType.number : TextInputType.text,
                  textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
