// FILE: lib/administration/architect_control_view.dart (FULLY RESOLVED PRODUCTION CODE)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart'; 
import '../../pharoah_manager.dart';
import '../logic/app_settings_model.dart';
import 'series_master_view.dart';

class ArchitectControlView extends StatefulWidget {
  const ArchitectControlView({super.key});

  @override
  State<ArchitectControlView> createState() => _ArchitectControlViewState();
}

class _ArchitectControlViewState extends State<ArchitectControlView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Controllers
  late TextEditingController labelC, nameC, numC, ifscC, bankC, termsC;
  late TextEditingController emailC, passC, hostC, portC;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    final ph = Provider.of<PharoahManager>(context, listen: false);
    
    labelC = TextEditingController(text: ph.config.signLabel);
    nameC = TextEditingController(text: ph.config.bankAccName);
    numC = TextEditingController(text: ph.config.bankAccNumber);
    ifscC = TextEditingController(text: ph.config.bankIfsc);
    bankC = TextEditingController(text: ph.config.bankNameBranch);
    termsC = TextEditingController(text: ph.config.termsAndConditions);
    
    emailC = TextEditingController(text: ph.config.smtpMailID);
    passC = TextEditingController(text: ph.config.smtpMailPass);
    hostC = TextEditingController(text: ph.config.smtpHost);
    portC = TextEditingController(text: ph.config.smtpPort.toString());
  }

  @override
  void dispose() {
    labelC.dispose();
    nameC.dispose();
    numC.dispose();
    ifscC.dispose();
    bankC.dispose();
    termsC.dispose();
    emailC.dispose();
    passC.dispose();
    hostC.dispose();
    portC.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _launchGmailSecurity() async {
    final Uri url = Uri.parse('https://myaccount.google.com/apppasswords');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open browser. Check Internet.")));
      }
    }
  }

  void _showEmailSetupGuide() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Row(children: [Icon(Icons.auto_awesome, color: Colors.orange), SizedBox(width: 10), Text("Quick Mail Setup")]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Google security requires an 'App Password' for ERP billing. Regular passwords won't work.", style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _stepRow("1", "Go to your Google Account > Security."),
            _stepRow("2", "Enable '2-Step Verification' (If OFF)."),
            _stepRow("3", "Search for 'App Passwords' in Search Bar."),
            _stepRow("4", "Type 'Pharoah ERP' as App Name."),
            _stepRow("5", "Copy the 16-digit code & paste it here."),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("GOT IT")),
          ElevatedButton(onPressed: () { Navigator.pop(c); _launchGmailSecurity(); }, child: const Text("OPEN LINK")),
        ],
      ),
    );
  }

  Widget _stepRow(String num, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(radius: 9, backgroundColor: Colors.indigo, child: Text(num, style: const TextStyle(fontSize: 9, color: Colors.white))),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.black87))),
    ]),
  );

  void _saveSettings(PharoahManager ph) {
    final updated = ph.config;
    updated.signLabel = labelC.text.trim();
    updated.bankAccName = nameC.text.trim();
    updated.bankAccNumber = numC.text.trim();
    updated.bankIfsc = ifscC.text.trim();
    updated.bankNameBranch = bankC.text.trim();
    updated.termsAndConditions = termsC.text.trim();
    
    updated.smtpMailID = emailC.text.trim();
    updated.smtpMailPass = passC.text.trim();
    updated.smtpHost = hostC.text.trim();
    updated.smtpPort = int.tryParse(portC.text) ?? 587;

    ph.updateAppConfig(updated); 
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("✅ All Settings Synchronized!"),
      backgroundColor: Colors.indigo,
    ));
  }

  Future<void> _pickImage(PharoahManager ph, bool isLogo) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      if (isLogo) {
        ph.config.logoPath = image.path;
      } else {
        ph.config.qrCodePath = image.path;
      }
      ph.updateAppConfig(ph.config);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    bool isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), 
      appBar: AppBar(
        title: const Text("Architect Series Control", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
        backgroundColor: const Color(0xFF1E1B4B),
        elevation: 0,
        actions: [
          Switch(
            value: ph.config.isArchitectMode,
            activeColor: Colors.cyanAccent,
            onChanged: (v) {
              ph.config.isArchitectMode = v;
              ph.updateAppConfig(ph.config);
            },
          ),
          const Center(child: Padding(
            padding: EdgeInsets.only(right: 15),
            child: Text("ARCHITECT SYSTEM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.cyanAccent)),
          )),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: isWide ? 6 : 10,
            child: _buildSettingsHub(ph),
          ),
          if (isWide)
            Expanded(
              flex: 4,
              child: _buildLiveInvoicePreview(ph),
            ),
        ],
      ),
      bottomNavigationBar: _buildSaveBar(ph),
    );
  }

  Widget _buildSettingsHub(PharoahManager ph) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF1E1B4B),
          child: TabBar(
            controller: _tabController,
            indicatorColor: Colors.cyanAccent,
            labelColor: Colors.cyanAccent,
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(icon: Icon(Icons.palette_rounded, size: 20), text: "Branding"),
              Tab(icon: Icon(Icons.security, size: 20), text: "Signatures"),
              Tab(icon: Icon(Icons.account_balance_rounded, size: 20), text: "Finance"),
              Tab(icon: Icon(Icons.alternate_email_rounded, size: 20), text: "Mail Setup"),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildBrandingTab(ph),
              _buildSignaturesTab(ph),
              _buildFinanceTab(ph),
              _buildMailSetupTab(ph),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBrandingTab(PharoahManager ph) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildCardHeader("BRANDING & DOCUMENT STYLE", Icons.palette_rounded, Colors.purple),
        _buildSwitchTile("Show Shop Logo on PDF", "Toggles top branding block", ph.config.showLogo, (v) {
          ph.config.showLogo = v; ph.updateAppConfig(ph.config);
        }),
        const SizedBox(height: 15),
        _buildActionBtn("UPLOAD SHOP LOGO", Icons.add_a_photo_rounded, Colors.purple, () => _pickImage(ph, true)),
        if (ph.config.logoPath != null) _imageIndicator(ph.config.logoPath!),
        const SizedBox(height: 25),
        _buildSectionLabel("PRINTING FORMAT"),
        Row(
          children: [
            _buildFormatOption("A4 Landscape", "A4", Icons.description_outlined, ph),
            const SizedBox(width: 15),
            _buildFormatOption("80mm Thermal", "Thermal", Icons.receipt_long_rounded, ph),
          ],
        ),
        const SizedBox(height: 25),
        _buildSwitchTile("Enable Statutory Terms & Conditions", "Show rule list at invoice bottom", ph.config.showTerms, (v) {
          ph.config.showTerms = v; ph.updateAppConfig(ph.config);
        }),
        const SizedBox(height: 12),
        _buildInputField(termsC, "Terms & Conditions Rules", maxLines: 3),
      ],
    );
  }

  Widget _buildSignaturesTab(PharoahManager ph) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildCardHeader("SIGNATURE & SERIES AUDIT", Icons.security, Colors.blue),
        // Switch 1: showCustomerSignChallan (Challan Signature Step)
        _buildSwitchTile("Enable Staff Signature", "Toggles signature drawing screen in challans", ph.config.showCustomerSignChallan, (v) {
          ph.config.showCustomerSignChallan = v; ph.updateAppConfig(ph.config);
        }),
        // Switch 2: showStaffSign (Authorised Signatory Block)
        _buildSwitchTile("Show Authorised Signatory Block", "Requires receiver's stamp area on bills", ph.config.showStaffSign, (v) {
          ph.config.showStaffSign = v; ph.updateAppConfig(ph.config);
        }),
        const SizedBox(height: 15),
        _buildInputField(labelC, "Authorised Signatory Designation"),
        const Divider(color: Colors.white10, height: 40),
        _buildCardHeader("INVOICE NUMBERING SERIES", Icons.format_list_numbered, Colors.blue),
        const SizedBox(height: 5),
        Text("Default Billing Series: ${ph.getDefaultSeries("SALE").name}", style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        _buildActionBtn("MANAGE NUMBERING SCHEMES", Icons.settings, Colors.blue, () {
          Navigator.push(context, MaterialPageRoute(builder: (c) => const SeriesMasterView()));
        }),
      ],
    );
  }

  Widget _buildFinanceTab(PharoahManager ph) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildCardHeader("PAYMENT GATEWAY CONFIG", Icons.account_balance_rounded, Colors.teal),
        _buildSwitchTile("Enable Scan-To-Pay UPI QR", "Inserts instant scanning block in bills", ph.config.showQrCode, (v) {
          ph.config.showQrCode = v; ph.updateAppConfig(ph.config);
        }),
        const SizedBox(height: 15),
        _buildActionBtn("UPLOAD UPI QR IMAGE", Icons.qr_code_scanner, Colors.teal, () => _pickImage(ph, false)),
        if (ph.config.qrCodePath != null) _imageIndicator(ph.config.qrCodePath!),
        const Divider(color: Colors.white10, height: 40),
        _buildSectionLabel("BANK SETTLEMENT DETAILS"),
        _buildInputField(nameC, "Beneficiary Name"),
        _buildInputField(bankC, "Bank Name & Branch"),
        Row(
          children: [
            Expanded(child: _buildInputField(numC, "Account Number", isNum: true)),
            const SizedBox(width: 15),
            Expanded(child: _buildInputField(ifscC, "IFSC Code")),
          ],
        ),
      ],
    );
  }

  Widget _buildMailSetupTab(PharoahManager ph) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildCardHeader("SMTP MAIL AUTOMATION HUB", Icons.alternate_email_rounded, Colors.deepOrange),
        _buildSwitchTile("Active Silent Mail Dispatcher", "Mails transaction PDF directly to party", ph.config.isMailActive, (v) {
          ph.config.isMailActive = v; ph.updateAppConfig(ph.config);
        }),
        const SizedBox(height: 15),
        _buildInputField(emailC, "Sender Mail ID"),
        _buildInputField(passC, "Google App Password (16-Digit)", isPass: true),
        Row(
          children: [
            Expanded(child: _buildInputField(hostC, "SMTP Server Host")),
            const SizedBox(width: 15),
            Expanded(child: _buildInputField(portC, "Server Port", isNum: true)),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.deepOrange)), onPressed: _showEmailSetupGuide, icon: const Icon(Icons.help_outline, color: Colors.deepOrange), label: const Text("SETUP GUIDE", style: TextStyle(color: Colors.deepOrange)))),
            const SizedBox(width: 15),
            Expanded(child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange), onPressed: _launchGmailSecurity, icon: const Icon(Icons.open_in_new), label: const Text("GENERATE PASSWORD", style: TextStyle(color: Colors.white)))),
          ],
        )
      ],
    );
  }

  Widget _buildLiveInvoicePreview(PharoahManager ph) {
    bool isThermal = ph.config.printFormat == "Thermal";

    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.all(25),
      child: Center(
        child: Container(
          width: isThermal ? 280 : 380,
          height: 480,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 15, offset: Offset(0, 5))],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ph.config.showLogo)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.stars, color: Colors.indigo, size: 24),
                    Text(ph.activeCompany?.name ?? "SHOP NAME", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ],
                )
              else
                Center(child: Text(ph.activeCompany?.name ?? "SHOP NAME", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              
              const Divider(thickness: 1, height: 15),
              const Text("Invoice: INV-2026-0091", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              const Text("Date: 02/06/2026", style: TextStyle(fontSize: 9, color: Colors.grey)),
              const Spacer(),

              _previewItemRow("DOLO 650 MG", "10 Tab", "₹30.00"),
              _previewItemRow("PAN 40 MG", "15 Tab", "₹120.00"),
              const Divider(thickness: 0.5),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text("GRAND TOTAL", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  Text("₹150.00", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
              const SizedBox(height: 15),

              if (ph.config.showQrCode)
                Row(
                  children: [
                    Container(
                      width: 50, height: 50,
                      color: Colors.grey.shade100,
                      child: const Icon(Icons.qr_code, size: 40, color: Colors.black87),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Bank: ${ph.config.bankNameBranch}", style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold)),
                        Text("A/C: ${ph.config.bankAccNumber}", style: const TextStyle(fontSize: 7)),
                        Text("IFSC: ${ph.config.bankIfsc}", style: const TextStyle(fontSize: 7)),
                      ],
                    ))
                  ],
                ),
              
              const SizedBox(height: 10),

              if (ph.config.showTerms)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(5),
                  color: Colors.grey.shade50,
                  child: Text(ph.config.termsAndConditions, style: const TextStyle(fontSize: 6, color: Colors.grey)),
                ),

              const Spacer(),

              if (ph.config.showStaffSign)
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("[Digital Seal verified]", style: TextStyle(fontSize: 6, color: Colors.green, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 15),
                      Text("---------------------------------", style: TextStyle(fontSize: 8, color: Colors.grey.shade400)),
                      Text(ph.config.signLabel.toUpperCase(), style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.indigo)),
                    ],
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewItemRow(String name, String qty, String price) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
          Text(qty, style: const TextStyle(fontSize: 8)),
          Text(price, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCardHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildSwitchTile(String title, String sub, bool val, ValueChanged<bool> onChange) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      value: val,
      onChanged: onChange,
      activeColor: Colors.cyanAccent,
    );
  }

  Widget _buildActionBtn(String label, IconData icon, Color color, VoidCallback tap) {
    return Container(
      width: double.infinity,
      height: 44,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: TextButton.icon(
        onPressed: tap,
        icon: Icon(icon, color: Colors.white, size: 18),
        label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
      ),
    );
  }

  Widget _buildInputField(TextEditingController ctrl, String label, {bool isNum = false, bool isPass = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        obscureText: isPass,
        maxLines: maxLines,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildFormatOption(String label, String value, IconData icon, PharoahManager ph) {
    bool isSel = ph.config.printFormat == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          ph.config.printFormat = value;
          ph.updateAppConfig(ph.config);
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSel ? Colors.purple.shade900 : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSel ? Colors.purple : Colors.white10),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSel ? Colors.cyanAccent : Colors.white54),
              const SizedBox(height: 5),
              Text(label, style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 0.5)),
    );
  }

  Widget _imageIndicator(String path) {
    return Padding(
      padding: const EdgeInsets.only(top: 8), 
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 14), 
          const SizedBox(width: 5), 
          Text("Selected: ${path.split('/').last}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey))
        ]
      )
    );
  }

  Widget _buildSaveBar(PharoahManager ph) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF1E1B4B),
      child: Row(
        children: [
          const Expanded(child: Text("Live Preview changes show immediately. To sync changes permanently tap save.", style: TextStyle(color: Colors.white54, fontSize: 11))),
          const SizedBox(width: 15),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => _saveSettings(ph),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text("SAVE SETTINGS", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}
