// FILE: lib/business_hub/business_hub_view.dart

import 'package:flutter/material.dart';
import '../challans/sale_challan_register.dart';
import '../modifications/modify_hub_view.dart';
import '../finance/finance_dashboard.dart';
import '../inventory_intel/inventory_intel_view.dart';
import '../administration/system_user_master_view.dart';
import '../compliance/compliance_hub.dart';
import '../administration/series_master_view.dart'; // NAYA

class BusinessHubView extends StatelessWidget {
  const BusinessHubView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Advanced Business Hub", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 30),
            
            // --- SECTION 1: DAILY BUSINESS OPERATIONS ---
            _sectionLabel("BUSINESS MANAGEMENT MODULES"),
            const SizedBox(height: 15),
            GridView.count(
              shrinkWrap: true, 
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2, 
              crossAxisSpacing: 15, 
              mainAxisSpacing: 15, 
              childAspectRatio: 1.1,
              children: [
                _hubCard(context, "CHALLANS & RETURNS", "Notes & Conversion", Icons.receipt_long_rounded, Colors.orange.shade800, const SaleChallanRegister()),
                _hubCard(context, "MODIFICATION CENTER", "Universal Search & Edit", Icons.edit_note_rounded, Colors.blue.shade800, const ModifyHubView()),
                _hubCard(context, "FINANCE & RECOVERY", "Outstanding & PDC", Icons.account_balance_rounded, Colors.green.shade800, const FinanceDashboard()),
                _hubCard(context, "STOCK ANALYTICS", "Shortage & PO Builder", Icons.analytics_rounded, Colors.purple.shade700, const InventoryIntelView()),
              ],
            ),

            const SizedBox(height: 35),

            // --- SECTION 2: ADMIN, SECURITY & COMPLIANCE ---
            _sectionLabel("SYSTEM & COMPLIANCE HUB"),
            const SizedBox(height: 15),
            GridView.count(
              shrinkWrap: true, 
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2, 
              crossAxisSpacing: 15, 
              mainAxisSpacing: 15, 
              childAspectRatio: 1.1,
              children: [
                // NAYA CARD ADDED HERE
                _hubCard(context, "SERIES MASTER", "Parallel Numbering", Icons.format_list_numbered_rounded, Colors.indigo, const SeriesMasterView()),
                
                _hubCard(context, "SECURITY & STAFF", "User Permissions", Icons.admin_panel_settings_rounded, Colors.red.shade800, const SystemUserMasterView()),
                
                _hubCard(context, "COMPLIANCE HUB", "H1, Narcotic & DL", Icons.verified_user_rounded, Colors.teal.shade700, const ComplianceHub()),
              ],
            ),
            
            const SizedBox(height: 40),
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  // --- UI COMPONENTS ---

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.indigo.shade900, Colors.indigo.shade600]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        children: [
          Icon(Icons.stars_rounded, color: Colors.orange, size: 40),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Business Control Room", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text("All advanced tools in one place.", style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _hubCard(BuildContext context, String title, String sub, IconData icon, Color color, Widget target) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => target)),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            const SizedBox(height: 4),
            Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(15)),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blueGrey, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text("These modules handle specialized operations. Use main dashboard for daily billing.", style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontStyle: FontStyle.italic))),
        ],
      ),
    );
  }
}
