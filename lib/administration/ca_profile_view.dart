// FILE: lib/administration/ca_profile_view.dart (FINAL AUDIT NEXUS VERSION)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';

class CaProfileView extends StatefulWidget {
  const CaProfileView({super.key});

  @override
  State<CaProfileView> createState() => _CaProfileViewState();
}

class _CaProfileViewState extends State<CaProfileView> {
  final nameC = TextEditingController();
  final mailC = TextEditingController(); // Name updated from emailC
  final phoneC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCurrentCaSettings();
  }

  // Settings Load karna (Updated variables)
  void _loadCurrentCaSettings() {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    nameC.text = ph.config.caName;
    mailC.text = ph.config.caMailID; // Updated from caEmail
    phoneC.text = ph.config.caPhone;
  }

  // Save Logic
  Future<void> _saveAllDetails() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);

    if (nameC.text.trim().isEmpty || mailC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("CA Name and Mail ID are mandatory!"), backgroundColor: Colors.red),
      );
      return;
    }

    // 1. Config Object Update
    ph.config.caName = nameC.text.trim().toUpperCase();
    ph.config.caMailID = mailC.text.trim().toLowerCase(); // Updated from caEmail
    ph.config.caPhone = phoneC.text.trim();
    
    // 2. Sync with Manager & Save
    ph.updateAppConfig(ph.config);
    await ph.save();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ CA Profile & Dispatch Route Updated!"), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Audit & CA Configuration"),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // --- SECTION: MASTER TOGGLE (REDIRECTION LOGIC) ---
          _buildSectionHeader("SYSTEM AUDIT MODE", Icons.security_rounded, Colors.orange.shade900),
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: ph.config.isAuditMode ? Colors.orange.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ph.config.isAuditMode ? Colors.orange : Colors.grey.shade300),
            ),
            child: SwitchListTile(
              title: const Text("REDIRECT ALL MAILS TO CA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(ph.config.isAuditMode ? "Mode: ACTIVE (Audit Redirection)" : "Mode: NORMAL (Customer Direct)", 
                  style: const TextStyle(fontSize: 10)),
              value: ph.config.isAuditMode,
              activeColor: Colors.orange.shade900,
              onChanged: (v) {
                setState(() => ph.config.isAuditMode = v);
                ph.updateAppConfig(ph.config);
                ph.save();
              },
            ),
          ),

          // --- 🔥 SMART WARNING BANNER ---
          if (ph.config.isAuditMode)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text("All transaction mails will now be sent to ${ph.config.caMailID.isEmpty ? 'CA' : ph.config.caMailID} instead of customers.", 
                  style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold))),
              ]),
            ),

          // --- SECTION: CA IDENTITY ---
          _buildSectionHeader("AUDITOR / CA PROFILE", Icons.assignment_ind_rounded, const Color(0xFF1A237E)),
          _inputField(nameC, "CA Full Name / Firm Name"),
          _inputField(mailC, "CA Mail ID (Redirection Target)"), // Label updated
          _inputField(phoneC, "CA Mobile Number", isNum: true),

          const SizedBox(height: 30),

          // --- SAVE BUTTON ---
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saveAllDetails,
              child: const Text("SAVE CA SETTINGS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),

          const SizedBox(height: 40),

          // --- SECTION: DISPATCH HISTORY ---
          _buildSectionHeader("RECENT AUDIT LOGS", Icons.history_edu_rounded, Colors.blueGrey),
          ...ph.logs.reversed.where((l) => l.action == "AUDIT").take(5).map((log) => Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.mark_email_read_rounded, color: Colors.green, size: 18),
              title: Text(log.details, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              subtitle: Text(DateFormat('dd MMM yyyy, hh:mm a').format(log.time), style: const TextStyle(fontSize: 9)),
            ),
          )).toList(),
          
          if (ph.logs.where((l) => l.action == "AUDIT").isEmpty)
            const Center(child: Text("No audit history found.", style: TextStyle(fontSize: 11, color: Colors.grey))),

          const SizedBox(height: 50),
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
}
