// FILE: lib/web_live_sync/sub_views/web_settings/web_mail_setup_view.dart
// Revision: #PH-REV-792 (ENTERPRISE-WEB-SETTINGS-HUB-AND-D1-CONFIG-SYNC)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../pharoah_web_manager.dart';
import 'web_settings_sync_coordinator.dart';

class WebMailSetupView extends StatefulWidget {
  final VoidCallback onBack;
  const WebMailSetupView({super.key, required this.onBack});

  @override
  State<WebMailSetupView> createState() => _WebMailSetupViewState();
}

class _WebMailSetupViewState extends State<WebMailSetupView> {
  late bool isMailActive;
  late TextEditingController emailC, passC, hostC, portC;
  bool isSaving = false;
  bool obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    isMailActive = webPh.appConfig.isMailActive;
    emailC = TextEditingController(text: webPh.appConfig.smtpMailID);
    passC = TextEditingController(text: webPh.appConfig.smtpMailPass);
    hostC = TextEditingController(text: webPh.appConfig.smtpHost.isNotEmpty ? webPh.appConfig.smtpHost : "smtp.gmail.com");
    portC = TextEditingController(text: webPh.appConfig.smtpPort.toString());
  }

  @override
  void dispose() {
    emailC.dispose();
    passC.dispose();
    hostC.dispose();
    portC.dispose();
    super.dispose();
  }

  Future<void> _launchGmailSecurity() async {
    final Uri url = Uri.parse('https://myaccount.google.com/apppasswords');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open browser. Please visit https://myaccount.google.com/apppasswords")),
        );
      }
    }
  }

  void _showEmailSetupGuide() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x33EA580C)),
        ),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFFFB923C)),
            SizedBox(width: 10),
            Text("Google SMTP Mail Setup Guide", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Google requires a 16-digit 'App Password' for automated ERP billing dispatch. Regular Gmail passwords will not work.",
              style: TextStyle(fontSize: 11.5, color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 16),
            _guideStep("1", "Go to your Google Account > Security settings."),
            _guideStep("2", "Enable '2-Step Verification' on your Google account if OFF."),
            _guideStep("3", "Search for 'App Passwords' in the search bar."),
            _guideStep("4", "Enter 'Pharoah ERP' as the app name & click Create."),
            _guideStep("5", "Copy the generated 16-character code and paste it below."),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CLOSE", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(c);
              _launchGmailSecurity();
            },
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text("OPEN GOOGLE APP PASSWORDS"),
          ),
        ],
      ),
    );
  }

  Widget _guideStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 9,
            backgroundColor: const Color(0xFFEA580C),
            child: Text(num, style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.white70))),
        ],
      ),
    );
  }

  /// Sanitizes email string (removes accidental interior/leading/trailing spaces)
  String _cleanEmail(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();
  }

  Future<void> _save(PharoahWebManager webPh) async {
    final cleanedEmail = _cleanEmail(emailC.text);
    if (isMailActive && cleanedEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sender Mail ID is required when Mailer is active!"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => isSaving = true);
    final cfg = webPh.appConfig;
    cfg.isMailActive = isMailActive;
    cfg.smtpMailID = cleanedEmail;
    cfg.smtpMailPass = passC.text.trim();
    cfg.smtpHost = hostC.text.trim().isNotEmpty ? hostC.text.trim() : "smtp.gmail.com";
    cfg.smtpPort = int.tryParse(portC.text.trim()) ?? 587;

    bool synced = await WebSettingsSyncCoordinator.saveAndBroadcastConfig(
      webPh: webPh,
      updatedConfig: cfg,
    );
    setState(() => isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(synced
              ? "✅ Mail & SMTP Automation Synced to Cloud & App!"
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
              const Icon(Icons.alternate_email_rounded, color: Color(0xFFFB923C), size: 24),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "SMTP MAIL & SMS AUTOMATION HUB",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  Text(
                    "Configure Sender Gmail, Google App Password and Silent Dispatch Protocols",
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
                border: Border.all(color: const Color(0x33EA580C), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Master Toggle
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isMailActive ? const Color(0x26EA580C) : Colors.black26,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isMailActive ? const Color(0xFFEA580C) : Colors.white10),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("ACTIVATE AUTOMATIC MAIL DISPATCHER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: const Text("Automatically send PDF invoices and ledger statements via email", style: TextStyle(color: Colors.white54, fontSize: 10)),
                      value: isMailActive,
                      activeColor: const Color(0xFFFB923C),
                      onChanged: (val) => setState(() => isMailActive = val),
                    ),
                  ),
                  const SizedBox(height: 18),

                  const Text("SENDER GMAIL / EMAIL ADDRESS *", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  _buildInput(emailC, Icons.email_rounded, hint: "e.g., yourcompany.billing@gmail.com"),

                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("GOOGLE APP PASSWORD (16-DIGIT CODE) *", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                      InkWell(
                        onTap: () => setState(() => obscurePassword = !obscurePassword),
                        child: Text(
                          obscurePassword ? "SHOW PASSWORD" : "HIDE PASSWORD",
                          style: const TextStyle(color: Color(0xFFFB923C), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _buildInput(passC, Icons.key_rounded, isPass: obscurePassword, hint: "xxxx xxxx xxxx xxxx"),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("SMTP SERVER HOST", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            _buildInput(hostC, Icons.dns_rounded, hint: "smtp.gmail.com"),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("PORT", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            _buildInput(portC, Icons.numbers_rounded, isNum: true, hint: "587"),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Guide Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFEA580C)),
                            foregroundColor: const Color(0xFFFB923C),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _showEmailSetupGuide,
                          icon: const Icon(Icons.help_outline_rounded, size: 16),
                          label: const Text("SETUP GUIDE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEA580C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _launchGmailSecurity,
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: const Text("GENERATE PASSWORD", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEA580C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: isSaving ? null : () => _save(webPh),
                      icon: isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        isSaving ? "SAVING MAIL CONFIG..." : "SAVE MAIL SETTINGS",
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

  Widget _buildInput(TextEditingController ctrl, IconData icon, {bool isPass = false, bool isNum = false, String hint = ""}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFB923C), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: ctrl,
              obscureText: isPass,
              keyboardType: isNum ? TextInputType.number : TextInputType.text,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
