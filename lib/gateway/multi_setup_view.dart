// FILE: lib/gateway/multi_setup_view.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../pharoah_manager.dart';
import '../app_date_logic.dart';
import 'company_registry_model.dart';
import 'package:local_auth/local_auth.dart'; 

class MultiSetupView extends StatefulWidget {
  final bool isFirstRun; 
  const MultiSetupView({super.key, this.isFirstRun = false});

  @override
  State<MultiSetupView> createState() => _MultiSetupViewState();
}

class _MultiSetupViewState extends State<MultiSetupView> {
  final nameC = TextEditingController();
  final addressC = TextEditingController();
  final phoneC = TextEditingController();
  final emailC = TextEditingController();
  final gstinC = TextEditingController();
  final dlNoC = TextEditingController();
  final usernameC = TextEditingController();
  final passwordC = TextEditingController();

  String selectedType = "WHOLESALE";
  String selectedState = "Rajasthan";
  String selectedFY = "";
  String generatedID = "";
  bool isLoading = false;

  bool useFingerprint = false;
  int lockMinutes = 5;
  bool canDeviceDoBiometrics = false;

  final List<String> states = [
    "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh", 
    "Goa", "Gujarat", "Haryana", "Himachal Pradesh", "Jharkhand", "Karnataka", 
    "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya", "Mizoram", 
    "Nagaland", "Odisha", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", 
    "Telangana", "Tripura", "Uttar Pradesh", "Uttarakhand", "West Bengal"
  ];

  @override
  void initState() {
    super.initState();
    generatedID = "PH-C-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    selectedFY = AppDateLogic.getCurrentFYString();
    _checkHardware();
  }

  Future<void> _checkHardware() async {
    final auth = LocalAuthentication();
    bool canCheck = await auth.canCheckBiometrics || await auth.isDeviceSupported();
    setState(() => canDeviceDoBiometrics = canCheck);
  }

  String _generateRecoveryKey() {
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    Random rnd = Random();
    String parts(int len) => String.fromCharCodes(Iterable.generate(len, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    return "${parts(4)}-${parts(4)}-${parts(4)}-${parts(4)}";
  }

  // ===========================================================================
  // 🛡️ STEP 1: VALIDATION & DIALOG TRIGGER
  // ===========================================================================
  void _handleCreateCompany() {
    if (nameC.text.trim().isEmpty || usernameC.text.trim().isEmpty || passwordC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Firm Name, Username and Password are mandatory!"), backgroundColor: Colors.red),
      );
      return;
    }

    // Pehle Key generate karo
    String finalRecoveryKey = _generateRecoveryKey();

    // Pehle Dialog dikhao (Setup abhi shuru nahi hua)
    _showRecoveryKeyDialog(finalRecoveryKey);
  }

  // ===========================================================================
  // 🛡️ STEP 2: THE KEY DIALOG (REGISTRATION HAPPENS HERE)
  // ===========================================================================
  void _showRecoveryKeyDialog(String key) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Row(children: [Icon(Icons.vpn_key, color: Colors.orange), SizedBox(width: 10), Text("SAVE RECOVERY KEY")]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Ye 16-digit key aapke password recovery ke liye hai. Ise kahin safe likh lein.", style: TextStyle(fontSize: 12)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blueGrey.shade200)),
              child: SelectableText(key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.indigo)),
            ),
            const SizedBox(height: 15),
            TextButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: key)); }, icon: const Icon(Icons.copy), label: const Text("Copy to Clipboard")),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async { 
              // --- ASLI REGISTRATION AB SHURU HOGI ---
              Navigator.pop(c); // Close Dialog
              setState(() => isLoading = true);

              final ph = Provider.of<PharoahManager>(context, listen: false);

              final newComp = CompanyProfile(
                id: generatedID,
                name: nameC.text.trim().toUpperCase(),
                businessType: selectedType,
                createdAt: DateTime.now(),
                address: addressC.text.trim(),
                state: selectedState,
                gstin: gstinC.text.trim().isEmpty ? "N/A" : gstinC.text.trim().toUpperCase(),
                dlNo: dlNoC.text.trim().isEmpty ? "N/A" : dlNoC.text.trim().toUpperCase(),
                phone: phoneC.text.trim(),
                email: emailC.text.trim().toLowerCase(),
                adminUser: usernameC.text.trim().toLowerCase(),
                password: passwordC.text.trim(),
                isBiometricEnabled: useFingerprint,
                recoveryKey: key, // Storing confirmed key
                autoLockMinutes: lockMinutes,
                fYears: [selectedFY], 
              );

              // Registration logic
              await ph.setupNewCompanyEnvironment(newComp, selectedFY);

              if (mounted) {
                setState(() => isLoading = false);
                // First run hai toh navigation manager handle karega, varna pop
                if (!widget.isFirstRun) Navigator.pop(context); 
              }
            }, 
            child: const Text("I HAVE SAVED THE KEY")
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text(widget.isFirstRun ? "Initial ERP Setup" : "Add New Company"),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading 
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 20), Text("Setting up Environment... Please wait.")]))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIdentityHeader(),
                const SizedBox(height: 25),
                _buildSectionCard(
                  title: "NATURE OF BUSINESS",
                  icon: Icons.category_rounded,
                  child: Column(
                    children: [
                      _dropdownLabel("Business Type"),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.storefront)),
                        items: ["WHOLESALE", "RETAIL"].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                        onChanged: (v) => setState(() => selectedType = v!),
                      ),
                      const SizedBox(height: 15),
                      _dropdownLabel("Base Financial Year"),
                      DropdownButtonFormField<String>(
                        value: selectedFY,
                        decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                        items: ["2024-25", "2025-26", "2026-27"].map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                        onChanged: (v) => setState(() => selectedFY = v!),
                      ),
                    ],
                  ),
                ),
                _buildSectionCard(
                  title: "COMPANY PROFILE",
                  icon: Icons.business_rounded,
                  child: Column(
                    children: [
                      _inputField(nameC, "Firm / Shop Name *", Icons.business, isCaps: true),
                      _inputField(addressC, "Full Office Address", Icons.location_on),
                      _dropdownLabel("Shop State (For GST)"),
                      DropdownButtonFormField<String>(
                        value: selectedState,
                        decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.map)),
                        items: states.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (v) => setState(() => selectedState = v!),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(child: _inputField(phoneC, "Mobile No", Icons.phone, isNum: true)),
                          const SizedBox(width: 10),
                          Expanded(child: _inputField(emailC, "Business Email", Icons.email)),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildSectionCard(
                  title: "STATUTORY & TAX",
                  icon: Icons.receipt_long_rounded,
                  child: Column(
                    children: [
                      _inputField(gstinC, "GSTIN Number", Icons.fingerprint, isCaps: true),
                      _inputField(dlNoC, "Drug License (DL)", Icons.medical_services_outlined, isCaps: true),
                    ],
                  ),
                ),
                _buildSectionCard(
                  title: "SECURITY PREFERENCES",
                  icon: Icons.security_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: const Text("Fingerprint Login", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(canDeviceDoBiometrics ? "Fast login enabled" : "Sensor not found on this phone"),
                        value: useFingerprint,
                        activeColor: Colors.indigo,
                        onChanged: canDeviceDoBiometrics ? (v) => setState(() => useFingerprint = v) : null,
                      ),
                      const Divider(),
                      const Text("Auto-Lock App (Inactivity)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      const SizedBox(height: 10),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text("OFF")),
                          ButtonSegment(value: 5, label: Text("5 Min")),
                          ButtonSegment(value: 10, label: Text("10 Min")),
                        ],
                        selected: {lockMinutes},
                        onSelectionChanged: (v) => setState(() => lockMinutes = v.first),
                      ),
                    ],
                  ),
                ),
                _buildSectionCard(
                  title: "ADMIN ACCESS",
                  icon: Icons.admin_panel_settings_rounded,
                  child: Column(
                    children: [
                      _inputField(usernameC, "Set Admin Username *", Icons.person_add_alt_1),
                      _inputField(passwordC, "Set Login Password *", Icons.lock_outline, isPass: true),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 5),
                    onPressed: _handleCreateCompany,
                    child: const Text("GENERATE KEY & CREATE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
    );
  }

  Widget _buildIdentityHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF0D47A1).withOpacity(0.1)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("SYSTEM ID", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1)), Text("(LOCKED FOR FILES)", style: TextStyle(fontSize: 8, color: Colors.red, fontWeight: FontWeight.bold))]),
          Text(generatedID, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0D47A1), fontSize: 18)),
      ]),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    return Card(elevation: 0, margin: const EdgeInsets.only(bottom: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade200)), child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, size: 18, color: const Color(0xFF0D47A1)), const SizedBox(width: 10), Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1), letterSpacing: 1))]), const Divider(height: 30), child])));
  }

  Widget _dropdownLabel(String t) => Padding(padding: const EdgeInsets.only(bottom: 8, left: 4), child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)));

  Widget _inputField(TextEditingController ctrl, String label, IconData icon, {bool isNum = false, bool isPass = false, bool isCaps = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: ctrl, obscureText: isPass,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        textCapitalization: isCaps ? TextCapitalization.characters : (isPass ? TextCapitalization.none : TextCapitalization.words),
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20), border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15)),
      ),
    );
  }
}
