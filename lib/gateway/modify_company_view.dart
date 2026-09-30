// FILE: lib/gateway/modify_company_view.dart (FULL PROFILE EDITOR)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pharoah_manager.dart';
import 'company_registry_model.dart';

class ModifyCompanyView extends StatefulWidget {
  final CompanyProfile comp;
  const ModifyCompanyView({super.key, required this.comp});

  @override
  State<ModifyCompanyView> createState() => _ModifyCompanyViewState();
}

class _ModifyCompanyViewState extends State<ModifyCompanyView> {
  // --- CONTROLLERS ---
  late TextEditingController nameC, addressC, phoneC, emailC, gstinC, dlNoC, usernameC, passwordC;
  late String selectedType, selectedState;
  late bool useFingerprint;
  late int lockMinutes;

  final List<String> states = [
    "Andhra Pradesh", "Assam", "Bihar", "Chhattisgarh", "Goa", "Gujarat", "Haryana", 
    "Himachal Pradesh", "Jharkhand", "Karnataka", "Kerala", "Madhya Pradesh", 
    "Maharashtra", "Manipur", "Meghalaya", "Mizoram", "Nagaland", "Odisha", 
    "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura", 
    "Uttar Pradesh", "Uttarakhand", "West Bengal", "Delhi"
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.comp;
    // Pre-filling existing data
    nameC = TextEditingController(text: c.name);
    addressC = TextEditingController(text: c.address);
    phoneC = TextEditingController(text: c.phone);
    emailC = TextEditingController(text: c.email);
    gstinC = TextEditingController(text: c.gstin);
    dlNoC = TextEditingController(text: c.dlNo);
    usernameC = TextEditingController(text: c.adminUser);
    passwordC = TextEditingController(text: c.password);
    selectedType = c.businessType;
    selectedState = c.state;
    useFingerprint = c.isBiometricEnabled;
    lockMinutes = c.autoLockMinutes;
  }

  void _handleUpdate() async {
    if (nameC.text.trim().isEmpty || passwordC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name and Password are mandatory!")));
      return;
    }

    final ph = Provider.of<PharoahManager>(context, listen: false);
    int idx = ph.companiesRegistry.indexWhere((c) => c.id == widget.comp.id);
    
    if (idx != -1) {
      // Create Updated Profile Object
      final updatedProfile = CompanyProfile(
        id: widget.comp.id, // System ID locked
        name: nameC.text.trim().toUpperCase(),
        businessType: widget.comp.businessType, // 👈 सीधे डेटाबेस से ओरिजिनल प्रकार का उपयोग करें
        createdAt: widget.comp.createdAt,
        address: addressC.text.trim(),
        state: selectedState,
        gstin: gstinC.text.trim().toUpperCase(),
        dlNo: dlNoC.text.trim().toUpperCase(),
        phone: phoneC.text.trim(),
        email: emailC.text.trim().toLowerCase(),
        adminUser: usernameC.text.trim().toLowerCase(),
        password: passwordC.text.trim(),
        isBiometricEnabled: useFingerprint,
        recoveryKey: widget.comp.recoveryKey, // Recovery key locked
        autoLockMinutes: lockMinutes,
        fYears: widget.comp.fYears,
      );

      ph.companiesRegistry[idx] = updatedProfile;
      ph.activeCompany = updatedProfile; 
      await ph.saveRegistry();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Business Profile Updated!"), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Modify Business Profile"),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel("PRIMARY IDENTITY"),
            _inputField(nameC, "Firm Name", Icons.business, isCaps: true),
            
          _inputLabel("Nature of Business (Locked after Creation)"),
Container(
  width: double.infinity,
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  decoration: BoxDecoration(
    color: const Color(0xFFF8FAFC), // साफ़-सुथरा लाइट ग्रे बैकग्राउंड
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
  ),
  child: Row(
    children: [
      // लॉक सुरक्षा आइकॉन
      const Icon(Icons.lock_outline_rounded, color: Color(0xFF64748B), size: 20),
      const SizedBox(width: 12),
      
      // वर्तमान टाइप का प्रदर्शन
      Expanded(
        child: Text(
          selectedType, // WHOLESALE या RETAIL प्रदर्शित करेगा
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
            letterSpacing: 0.5,
          ),
        ),
      ),
      
      // विज़ुअल सुरक्षा बैच
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
        ),
        child: const Text(
          "SECURE",
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: Color(0xFF475569),
            letterSpacing: 0.5,
          ),
        ),
      ),
    ],
  ),
),
            const SizedBox(height: 25),

            _sectionLabel("LOCATION & CONTACT"),
            _inputField(addressC, "Office Address", Icons.location_on),
            _inputLabel("Business State"),
            DropdownButtonFormField<String>(
              value: selectedState,
              decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.map)),
              items: states.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => selectedState = v!),
            ),
            const SizedBox(height: 15),
            Row(children: [
              Expanded(child: _inputField(phoneC, "Mobile", Icons.phone, isNum: true)),
              const SizedBox(width: 10),
              Expanded(child: _inputField(emailC, "Email", Icons.email)),
            ]),

            _sectionLabel("STATUTORY DETAILS"),
            Row(children: [
              Expanded(child: _inputField(gstinC, "GSTIN", Icons.receipt_long, isCaps: true)),
              const SizedBox(width: 10),
              Expanded(child: _inputField(dlNoC, "Drug License", Icons.medical_services, isCaps: true)),
            ]),

            _sectionLabel("SECURITY & ACCESS"),// Modify_company_view.dart mein Line 141 ko dhundiye aur badal dijiye:
_inputField(usernameC, "Admin Username", Icons.lock_person),
            _inputField(passwordC, "Login Password", Icons.key),
            
            SwitchListTile(
              title: const Text("Enable Biometric Login", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              value: useFingerprint,
              activeColor: Colors.blue.shade900,
              onChanged: (v) => setState(() => useFingerprint = v),
            ),
            
            const Divider(),
            const Text("Auto-Lock Timer (Minutes)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const SizedBox(height: 10),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text("OFF")),
                ButtonSegment(value: 5, label: Text("5m")),
                ButtonSegment(value: 10, label: Text("10m")),
              ],
              selected: {lockMinutes},
              onSelectionChanged: (v) => setState(() => lockMinutes = v.first),
            ),

            const SizedBox(height: 50),
            SizedBox(
              width: double.infinity, height: 60,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                onPressed: _handleUpdate,
                child: const Text("SAVE UPDATED PROFILE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String t) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 10, left: 4), child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5)));
  Widget _inputLabel(String t) => Padding(padding: const EdgeInsets.only(bottom: 8, left: 4), child: Text(t, style: const TextStyle(fontSize: 11, color: Colors.grey)));
  Widget _inputField(TextEditingController c, String l, IconData i, {bool isNum = false, bool isCaps = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: TextField(
      controller: c, keyboardType: isNum ? TextInputType.number : TextInputType.text,
      textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
      decoration: InputDecoration(labelText: l, prefixIcon: Icon(i, size: 20), border: const OutlineInputBorder(), filled: true, fillColor: Colors.white),
    ),
  );
}
