// FILE: lib/user_master_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'gateway/company_registry_model.dart';

class UserMasterView extends StatefulWidget {
  final VoidCallback onLogout;
  const UserMasterView({super.key, required this.onLogout});

  @override
  State<UserMasterView> createState() => _UserMasterViewState();
}

class _UserMasterViewState extends State<UserMasterView> {
  // --- FORM CONTROLLERS ---
  final nameC = TextEditingController();
  final addressC = TextEditingController();
  final gstinC = TextEditingController();
  final dlNoC = TextEditingController();
  final phoneC = TextEditingController();
  final emailC = TextEditingController();
  final usernameC = TextEditingController();
  final passwordC = TextEditingController();
  
  String selectedState = "Rajasthan";

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
    _loadActiveCompanyDetails();
  }

  // NAYA: Active company ki details controllers mein bharna
  void _loadActiveCompanyDetails() {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final comp = ph.activeCompany;
    
    if (comp != null) {
      nameC.text = comp.name;
      addressC.text = comp.address;
      selectedState = comp.state;
      gstinC.text = comp.gstin;
      dlNoC.text = comp.dlNo;
      phoneC.text = comp.phone;
      emailC.text = comp.email;
      usernameC.text = comp.adminUser;
      passwordC.text = comp.password;
    }
  }

  // NAYA: Registry ko update karke save karna
  Future<void> _saveAllDetails() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final comp = ph.activeCompany;

    if (comp == null) return;

    if (nameC.text.trim().isEmpty || usernameC.text.trim().isEmpty || passwordC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Firm Name, Username and Password are mandatory!"), backgroundColor: Colors.red)
      );
      return;
    }

    // 1. Naya profile object banana purani ID ke saath
    final updatedProfile = CompanyProfile(
      id: comp.id, // ID hamesha locked rahegi
      name: nameC.text.trim().toUpperCase(),
      businessType: comp.businessType,
      createdAt: comp.createdAt,
      address: addressC.text.trim(),
      state: selectedState,
      gstin: gstinC.text.trim().toUpperCase(),
      dlNo: dlNoC.text.trim().toUpperCase(),
      phone: phoneC.text.trim(),
      email: emailC.text.trim().toLowerCase(),
      adminUser: usernameC.text.trim().toLowerCase(),
      password: passwordC.text.trim(),
      fYears: comp.fYears,
    );

    // 2. Registry list mein update karna
    int idx = ph.companiesRegistry.indexWhere((c) => c.id == comp.id);
    if (idx != -1) {
      ph.companiesRegistry[idx] = updatedProfile;
      ph.activeCompany = updatedProfile; // Active session bhi update karo
      await ph.saveRegistry();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Shop Profile Updated Successfully!"), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Edit Shop Profile"),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSectionHeader("BUSINESS IDENTITY", Icons.business_rounded, const Color(0xFF0D47A1)),
          _inputField(nameC, "Firm / Shop Name"),
          _inputField(addressC, "Full Office Address"),
          
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: selectedState,
            decoration: const InputDecoration(labelText: "Shop State (For GST)", border: OutlineInputBorder()),
            items: states.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) => setState(() => selectedState = v!),
          ),
          const SizedBox(height: 15),

          Row(
            children: [
              Expanded(child: _inputField(gstinC, "GSTIN Number")),
              const SizedBox(width: 10),
              Expanded(child: _inputField(dlNoC, "Drug License")),
            ],
          ),
          Row(
            children: [
              Expanded(child: _inputField(phoneC, "Phone No.", isNum: true)),
              const SizedBox(width: 10),
              Expanded(child: _inputField(emailC, "Business Email")),
            ],
          ),

          const SizedBox(height: 30),

          _buildSectionHeader("ADMIN SECURITY", Icons.admin_panel_settings_rounded, Colors.red.shade800),
          _inputField(usernameC, "Login Username"),
          _inputField(passwordC, "Login Password"), 

          const SizedBox(height: 30),

          // --- UPDATE BUTTON ---
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saveAllDetails,
              child: const Text("SAVE CHANGES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),

          const SizedBox(height: 15),

          // --- LOGOUT BUTTON ---
          SizedBox(
            width: double.infinity,
            height: 55,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _confirmLogout(context),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded),
                  SizedBox(width: 10),
                  Text("LOGOUT & EXIT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // --- UI HELPERS ---

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15, top: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
        ],
      ),
    );
  }

  Widget _inputField(TextEditingController ctrl, String label, {bool isNum = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: ctrl,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Logout?"),
        content: const Text("Exit current shop and return to Selection screen?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          TextButton(onPressed: () {
            Navigator.pop(c);
            widget.onLogout();
          }, child: const Text("LOGOUT", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}
