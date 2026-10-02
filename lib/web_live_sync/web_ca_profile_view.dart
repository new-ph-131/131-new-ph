// FILE: lib/web_live_sync/web_ca_profile_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_web_manager.dart';

class WebCaProfileView extends StatefulWidget {
  final VoidCallback onBack;

  const WebCaProfileView({super.key, required this.onBack});

  @override
  State<WebCaProfileView> createState() => _WebCaProfileViewState();
}

class _WebCaProfileViewState extends State<WebCaProfileView> {
  final nameC = TextEditingController();
  final mailC = TextEditingController();
  final phoneC = TextEditingController();

  bool isAuditMode = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    nameC.text = webPh.appConfig.caName;
    mailC.text = webPh.appConfig.caMailID;
    phoneC.text = webPh.appConfig.caPhone;
    isAuditMode = webPh.appConfig.isAuditMode;
  }

  @override
  void dispose() {
    nameC.dispose();
    mailC.dispose();
    phoneC.dispose();
    super.dispose();
  }

  Future<void> _saveCaSettings(PharoahWebManager webPh) async {
    if (nameC.text.trim().isEmpty || mailC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("CA Name and Email ID are mandatory!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    webPh.appConfig.caName = nameC.text.trim().toUpperCase();
    webPh.appConfig.caMailID = mailC.text.trim().toLowerCase();
    webPh.appConfig.caPhone = phoneC.text.trim();
    webPh.appConfig.isAuditMode = isAuditMode;

    bool synced = await webPh.pushUpdatedDataToCloud();
    setState(() => isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(synced 
            ? "✅ CA Profile & Audit Redirection Synced to Cloud!" 
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
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
                label: const Text("BACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.assignment_ind_rounded, color: Color(0xFFF97316), size: 24),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "AUDITOR / CA CONFIGURATION MASTER",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  Text(
                    "Manage Chartered Accountant credentials and automatic mail redirection",
                    style: TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 30),

          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x33F97316), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Master Audit Toggle Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isAuditMode ? const Color(0x26EA580C) : Colors.black26,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isAuditMode ? const Color(0xFFEA580C) : Colors.white10, width: 1.2),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        "REDIRECT ALL TRANSACTION MAILS TO CA",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          isAuditMode
                              ? "Status: ACTIVE (Audit Mode - All sales, purchases & returns redirect to CA)"
                              : "Status: NORMAL (Customer/Supplier direct dispatch)",
                          style: TextStyle(
                            color: isAuditMode ? const Color(0xFFFB923C) : Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      value: isAuditMode,
                      activeColor: const Color(0xFFFB923C),
                      onChanged: (val) {
                        setState(() => isAuditMode = val);
                      },
                    ),
                  ),

                  // Warning Notice
                  if (isAuditMode) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0x33DC2626),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "All invoice and report emails will now go directly to ${mailC.text.isNotEmpty ? mailC.text : 'CA email'} instead of party recipients.",
                              style: const TextStyle(color: Colors.redAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),
                  const Text(
                    "AUDITOR / CHARTERED ACCOUNTANT PROFILE",
                    style: TextStyle(color: Color(0xFFFB923C), fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                  const SizedBox(height: 12),

                  _inputField("CA / FIRM NAME *", nameC, Icons.business_rounded, isCaps: true),
                  const SizedBox(height: 14),
                  _inputField("CA EMAIL ID (REDIRECTION TARGET) *", mailC, Icons.email_rounded),
                  const SizedBox(height: 14),
                  _inputField("CA PHONE / MOBILE NUMBER", phoneC, Icons.phone_rounded, isNum: true),

                  const SizedBox(height: 25),
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
                      onPressed: isSaving ? null : () => _saveCaSettings(webPh),
                      icon: isSaving 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        isSaving ? "SAVING..." : "SAVE CA SETTINGS",
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

  Widget _inputField(String label, TextEditingController ctrl, IconData icon, {bool isNum = false, bool isCaps = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFFB923C), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  keyboardType: isNum ? TextInputType.phone : TextInputType.text,
                  textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 11),
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
