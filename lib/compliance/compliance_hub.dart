// FILE: lib/compliance/compliance_hub.dart (Replace Full)

import 'package:flutter/material.dart';
import 'registers_view.dart';

class ComplianceHub extends StatelessWidget {
  const ComplianceHub({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Legal & Compliance Hub"),
        backgroundColor: Colors.teal.shade900,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(),
            const SizedBox(height: 30),
            const Text("STATUTORY REGISTERS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5)),
            const SizedBox(height: 15),
            
            _complianceMenuCard(
              context, 
              "SCHEDULE H1 REGISTER", 
              "Automatic tracking of Antibiotics & habit-forming drugs.", 
              Icons.menu_book_rounded, 
              Colors.teal,
              () => Navigator.push(context, MaterialPageRoute(builder: (c) => const RegistersView(registerType: "H1")))
            ),
            
            const SizedBox(height: 15),
            
            _complianceMenuCard(
              context, 
              "NARCOTIC (NDPS) REGISTER", 
              "Restricted drug inventory and sale tracking.", 
              Icons.lock_person_rounded, 
              Colors.red.shade900,
              () => Navigator.push(context, MaterialPageRoute(builder: (c) => const RegistersView(registerType: "Narcotic")))
            ),

            const SizedBox(height: 15),

            _complianceMenuCard(
              context, 
              "DL WATCHDOG", 
              "Check Party Drug License validity status.", 
              Icons.verified_user_rounded, 
              Colors.blue.shade900,
              () { /* Future: DL Expiry logic */ }
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.teal.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: const Row(
        children: [
          Icon(Icons.gavel_rounded, color: Colors.orange, size: 35),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Auto-Compliance Active", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text("System automatically extracts data based on Medicine Master flags.", style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _complianceMenuCard(BuildContext context, String title, String sub, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(sub, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
