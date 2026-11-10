// FILE: lib/web_live_sync/sub_views/web_settings/web_settings_view.dart
// Revision: #PH-REV-792 (ENTERPRISE-WEB-SETTINGS-HUB-AND-D1-CONFIG-SYNC)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../pharoah_web_manager.dart';
import 'web_branding_settings_view.dart';
import 'web_signatures_settings_view.dart';
import 'web_finance_settings_view.dart';
import 'web_mail_setup_view.dart';
import '../../web_ca_profile_view.dart';

class WebSettingsView extends StatefulWidget {
  final VoidCallback onBack;
  const WebSettingsView({super.key, required this.onBack});

  @override
  State<WebSettingsView> createState() => _WebSettingsViewState();
}

class _WebSettingsViewState extends State<WebSettingsView> {
  // Current active sub-setting screen. "MAIN" displays all individual setting buttons.
  String activeSubView = "MAIN";

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    if (activeSubView == "BRANDING") {
      return WebBrandingSettingsView(onBack: () => setState(() => activeSubView = "MAIN"));
    }
    if (activeSubView == "SIGNATURES") {
      return WebSignaturesSettingsView(onBack: () => setState(() => activeSubView = "MAIN"));
    }
    if (activeSubView == "FINANCE") {
      return WebFinanceSettingsView(onBack: () => setState(() => activeSubView = "MAIN"));
    }
    if (activeSubView == "MAIL_SETUP") {
      return WebMailSetupView(onBack: () => setState(() => activeSubView = "MAIN"));
    }
    if (activeSubView == "CA_PROFILE") {
      return WebCaProfileView(onBack: () => setState(() => activeSubView = "MAIN"));
    }

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
          // Header Bar
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
                label: const Text("DASHBOARD", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.settings_suggest_rounded, color: Color(0xFF38BDF8), size: 26),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "GLOBAL ERP SETTINGS HUB",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  Text(
                    "Select a dedicated configuration button below to manage store protocols and sync",
                    style: TextStyle(color: Colors.white54, fontSize: 10.5),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x2610B981),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.greenAccent, width: 0.7),
                ),
                child: const Text(
                  "D1 LIVE SYNC CONNECTED",
                  style: TextStyle(color: Colors.greenAccent, fontSize: 9.5, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 32),

          // 5 Distinct Actionable Settings Buttons
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                children: [
                  // BUTTON 1: BRANDING & DOCUMENT STYLE
                  _settingButtonCard(
                    title: "BRANDING & DOCUMENT STYLE",
                    subtitle: "Manage Shop Logo on Invoices, Default Print Layout (A4 Landscape / 80mm Thermal) and Statutory Terms & Conditions.",
                    icon: Icons.palette_rounded,
                    gradientColors: [const Color(0xFF581C87), const Color(0xFF7E22CE)],
                    accentColor: Colors.purpleAccent,
                    badgeText: webPh.appConfig.showLogo ? "LOGO ON" : "LOGO OFF",
                    onTap: () => setState(() => activeSubView = "BRANDING"),
                  ),
                  const SizedBox(height: 16),

                  // BUTTON 2: SIGNATURE & SERIES AUDIT
                  _settingButtonCard(
                    title: "SIGNATURE & INVOICE NUMBERING",
                    subtitle: "Configure Authorised Signatory Designation, Staff Signatures on Delivery Challans, and Default Billing Schemes.",
                    icon: Icons.security_rounded,
                    gradientColors: [const Color(0xFF1E3A8A), const Color(0xFF2563EB)],
                    accentColor: Colors.blueAccent,
                    badgeText: webPh.appConfig.signLabel.isNotEmpty ? webPh.appConfig.signLabel : "SIGNATORY READY",
                    onTap: () => setState(() => activeSubView = "SIGNATURES"),
                  ),
                  const SizedBox(height: 16),

                  // BUTTON 3: PAYMENT GATEWAY & FINANCE
                  _settingButtonCard(
                    title: "PAYMENT GATEWAY & BANK DETAILS",
                    subtitle: "Enable Scan-To-Pay UPI QR Code on Invoices, Beneficiary Name, Bank Branch, Account Number and IFSC settlement details.",
                    icon: Icons.account_balance_rounded,
                    gradientColors: [const Color(0xFF064E3B), const Color(0xFF0F766E)],
                    accentColor: Colors.tealAccent,
                    badgeText: webPh.appConfig.showQrCode ? "UPI QR ACTIVE" : "BANK READY",
                    onTap: () => setState(() => activeSubView = "FINANCE"),
                  ),
                  const SizedBox(height: 16),

                  // BUTTON 4: SMTP MAIL & SMS AUTOMATION HUB
                  _settingButtonCard(
                    title: "SMTP MAIL & SMS AUTOMATION HUB",
                    subtitle: "Configure Automated Silent Dispatcher, Sender Gmail ID, Google 16-Digit App Password, SMTP Server Host and Ports.",
                    icon: Icons.alternate_email_rounded,
                    gradientColors: [const Color(0xFF7C2D12), const Color(0xFFEA580C)],
                    accentColor: const Color(0xFFFB923C),
                    badgeText: webPh.appConfig.isMailActive ? "MAILER ACTIVE" : "MAILER OFF",
                    onTap: () => setState(() => activeSubView = "MAIL_SETUP"),
                  ),
                  const SizedBox(height: 16),

                  // BUTTON 5: AUDITOR / CA AUDIT NEXUS
                  _settingButtonCard(
                    title: "AUDITOR / CA PROFILE & DISPATCH ROUTE",
                    subtitle: "Chartered Accountant Profile, Redirect All Transaction Invoices to CA (Audit Mode), and review Dispatch History.",
                    icon: Icons.assignment_ind_rounded,
                    gradientColors: [const Color(0xFF831843), const Color(0xFFBE185D)],
                    accentColor: Colors.pinkAccent,
                    badgeText: webPh.appConfig.isAuditMode ? "AUDIT REDIRECTION ACTIVE" : "NORMAL DISPATCH",
                    onTap: () => setState(() => activeSubView = "CA_PROFILE"),
                  ),
                  const SizedBox(height: 24),

                  // SYSTEM INFORMATION CARD
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8), size: 18),
                            SizedBox(width: 8),
                            Text("SYSTEM & CLOUD SYNC INFORMATION", style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 24),
                        Row(
                          children: [
                            Expanded(child: _infoRow("Active Company", webPh.companyName.isNotEmpty ? webPh.companyName : "STORE WORKSTATION")),
                            Expanded(child: _infoRow("Active Financial Year", webPh.financialYear)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _infoRow("Config Version", "v${webPh.appConfig.version} (OCC Monotonic)")),
                            Expanded(child: _infoRow("ERP Build Series", "v1.1.0 (#PH-REV-792 Enterprise)")),
                          ],
                        ),
                      ],
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

  Widget _settingButtonCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required Color accentColor,
    required String badgeText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
          border: Border.all(color: Colors.white24, width: 1.0),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accentColor, size: 32),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: accentColor.withOpacity(0.6), width: 0.7),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(color: accentColor, fontSize: 8.5, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
      ],
    );
  }
}
