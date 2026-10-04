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
  final int initialTab; // 0 = Create, 1 = Connect Cloud

  const MultiSetupView({super.key, this.isFirstRun = false, this.initialTab = 0});

  @override
  State<MultiSetupView> createState() => _MultiSetupViewState();
}

class _MultiSetupViewState extends State<MultiSetupView> {
  int _activeTab = 0; // 0: Create New Store, 1: Connect Live Cloud Store

  // --- TAB 0: CREATE CONTROLLERS ---
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

  // --- TAB 1: CLOUD CONNECT CONTROLLERS ---
  final cloudStoreKeyC = TextEditingController();
  final cloudUsernameC = TextEditingController();
  final cloudPasswordC = TextEditingController();
  bool isCloudPassObscured = true;
  bool isCloudConnecting = false;
  String cloudErrorMessage = "";

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
    _activeTab = widget.initialTab;
    generatedID = "PH-C-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    selectedFY = AppDateLogic.getCurrentFYString();
    _checkHardware();
  }

  @override
  void dispose() {
    nameC.dispose();
    addressC.dispose();
    phoneC.dispose();
    emailC.dispose();
    gstinC.dispose();
    dlNoC.dispose();
    usernameC.dispose();
    passwordC.dispose();
    cloudStoreKeyC.dispose();
    cloudUsernameC.dispose();
    cloudPasswordC.dispose();
    super.dispose();
  }

  Future<void> _checkHardware() async {
    final auth = LocalAuthentication();
    bool canCheck = await auth.canCheckBiometrics || await auth.isDeviceSupported();
    if (mounted) setState(() => canDeviceDoBiometrics = canCheck);
  }

  String _generateRecoveryKey() {
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    Random rnd = Random();
    String parts(int len) => String.fromCharCodes(Iterable.generate(len, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    return "${parts(4)}-${parts(4)}-${parts(4)}-${parts(4)}";
  }

  // ===========================================================================
  // 🛡️ STEP 1: VALIDATION & DIALOG TRIGGER (CREATE NEW STORE)
  // ===========================================================================
  void _handleCreateCompany() {
    if (nameC.text.trim().isEmpty || usernameC.text.trim().isEmpty || passwordC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Firm Name, Username and Password are mandatory!"), backgroundColor: Colors.red),
      );
      return;
    }
    String finalRecoveryKey = _generateRecoveryKey();
    _showRecoveryKeyDialog(finalRecoveryKey);
  }

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
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(key, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.deepOrange)),
                  IconButton(icon: const Icon(Icons.copy, size: 18), onPressed: () {
                    Clipboard.setData(ClipboardData(text: key));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Recovery Key Copied!")));
                  })
                ],
              ),
            )
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(c);
              _finalizeSetup(key);
            },
            child: const Text("I HAVE SAVED IT -> PROCEED"),
          )
        ],
      ),
    );
  }

  Future<void> _finalizeSetup(String recoveryKey) async {
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
      email: emailC.text.trim(),
      adminUser: usernameC.text.trim().toLowerCase(),
      password: passwordC.text.trim(),
      isBiometricEnabled: useFingerprint,
      recoveryKey: recoveryKey,
      autoLockMinutes: lockMinutes,
      fYears: [selectedFY],
    );

    await ph.setupNewCompanyEnvironment(newComp, selectedFY);
    
    if (mounted) {
      setState(() => isLoading = false);
      if (!widget.isFirstRun) {
        Navigator.pop(context);
      }
    }
  }

  // ===========================================================================
  // ☁️ STEP 2: CONNECT & RESTORE FROM CLOUD RELAY
  // ===========================================================================
  Future<void> _handleConnectCloudStore() async {
    final token = cloudStoreKeyC.text.trim().toUpperCase();
    final user = cloudUsernameC.text.trim().toLowerCase();
    final pass = cloudPasswordC.text.trim();

    if (token.isEmpty || user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Store Access Key, Username and Password are required!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      isCloudConnecting = true;
      cloudErrorMessage = "";
    });

    final ph = Provider.of<PharoahManager>(context, listen: false);
    final result = await ph.restoreCompanyFromCloud(
      storeToken: token,
      username: user,
      password: pass,
    );

    if (!mounted) return;

    setState(() {
      isCloudConnecting = false;
    });

    if (result["success"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(result["message"] ?? "Store Restored Successfully!")),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
      if (!widget.isFirstRun) {
        Navigator.of(context).pop();
      }
    } else {
      setState(() {
        cloudErrorMessage = result["message"] ?? "Failed to connect to Cloud Store.";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cloudErrorMessage),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: Text(
          widget.isFirstRun ? "Pharoah ERP Gateway Setup" : "Add or Connect Business",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !widget.isFirstRun,
      ),
      body: isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF0D47A1)),
                  SizedBox(height: 20),
                  Text("Initializing Store Environment...", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                children: [
                  // --- TOP MODE SELECTOR (2 TABS) ---
                  _buildModeSelector(),
                  const SizedBox(height: 20),

                  if (_activeTab == 0) ...[
                    // TAB 0: CREATE NEW STORE
                    _buildIdentityHeader(),
                    const SizedBox(height: 20),

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

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D47A1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 3,
                        ),
                        onPressed: _handleCreateCompany,
                        icon: const Icon(Icons.rocket_launch_rounded),
                        label: const Text("GENERATE KEY & CREATE STORE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ] else ...[
                    // TAB 1: CONNECT LIVE CLOUD STORE
                    _buildCloudRestoreCard(),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // ===========================================================================
  // 🔀 2-TAB SWITCHER
  // ===========================================================================
  Widget _buildModeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _activeTab = 0),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _activeTab == 0 ? const Color(0xFF0D47A1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_business_rounded,
                      size: 18,
                      color: _activeTab == 0 ? Colors.white : Colors.blueGrey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "CREATE NEW",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: _activeTab == 0 ? Colors.white : Colors.blueGrey,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _activeTab = 1),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _activeTab == 1 ? const Color(0xFF0284C7) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_download_rounded,
                      size: 18,
                      color: _activeTab == 1 ? Colors.white : Colors.blueGrey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "CONNECT CLOUD",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: _activeTab == 1 ? Colors.white : Colors.blueGrey,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ☁️ LIVE CLOUD RESTORE CARD UI
  // ===========================================================================
  Widget _buildCloudRestoreCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0284C7).withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.cloud_sync_rounded, color: Color(0xFF0284C7), size: 30),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "RESTORE LIVE CLOUD STORE",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: Color(0xFF0F172A),
                        letterSpacing: 0.6,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      "Fetch full data, medicines, parties & stock from cloud",
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 30),

          if (cloudErrorMessage.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 15),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      cloudErrorMessage,
                      style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Text(
            "Enter your Store Access Key & Admin Credentials to link this device directly with your active cloud store:",
            style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
          ),
          const SizedBox(height: 20),

          // 1. STORE KEY
          _inputField(
            cloudStoreKeyC,
            "STORE ACCESS KEY *",
            Icons.vpn_key_rounded,
            isCaps: true,
          ),

          // 2. USERNAME
          _inputField(
            cloudUsernameC,
            "ADMIN USERNAME *",
            Icons.person_rounded,
          ),

          // 3. PASSWORD
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: TextField(
              controller: cloudPasswordC,
              obscureText: isCloudPassObscured,
              decoration: InputDecoration(
                labelText: "LOGIN PASSWORD *",
                prefixIcon: const Icon(Icons.lock_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(isCloudPassObscured ? Icons.visibility_off : Icons.visibility, size: 20),
                  onPressed: () => setState(() => isCloudPassObscured = !isCloudPassObscured),
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
              ),
            ),
          ),

          // ACTION BUTTON
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 4,
              ),
              onPressed: isCloudConnecting ? null : _handleConnectCloudStore,
              icon: isCloudConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(
                isCloudConnecting ? "FETCHING & RESTORING DATA..." : "CONNECT & RESTORE LIVE DATA",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.6),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // NOTICE BANNER
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: Color(0xFF0284C7)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Note: Aapka Store Access Key Web Workstation Login screen ya App settings mein mil jayega. Ye saari files aur real-time balance automatically download karke setup kar dega.",
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF0D47A1).withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("SYSTEM ID", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1)),
              Text("(LOCKED FOR FILES)", style: TextStyle(fontSize: 8, color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
          Text(generatedID, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0D47A1), fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: const Color(0xFF0D47A1)),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1), letterSpacing: 1)),
              ],
            ),
            const Divider(height: 30),
            child,
          ],
        ),
      ),
    );
  }

  Widget _dropdownLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
      );

  Widget _inputField(TextEditingController ctrl, String label, IconData icon, {bool isNum = false, bool isPass = false, bool isCaps = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: ctrl,
        obscureText: isPass,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        textCapitalization: isCaps ? TextCapitalization.characters : (isPass ? TextCapitalization.none : TextCapitalization.words),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        ),
      ),
    );
  }
}
