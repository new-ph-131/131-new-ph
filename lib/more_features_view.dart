import 'package:flutter/material.dart';
import 'gst_menu_view.dart';
import 'system_menu_view.dart';
import 'item_ledger_view.dart'; // Naya import

class MoreFeaturesView extends StatelessWidget {
  final VoidCallback onLogout;
  const MoreFeaturesView({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Advanced Tools"),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. Stock Ledger & Batch Tracker (Naya Button)
              _buildLargeMenuCard(
                context,
                title: "STOCK LEDGER & BATCH TRACKER",
                subtitle: "Track item history (In/Out), expiry, and batch traceability.",
                icon: Icons.manage_search_rounded,
                color: Colors.teal.shade700,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ItemLedgerSearchView())),
              ),
              const SizedBox(height: 20),
              // 2. GST & Taxation
              _buildLargeMenuCard(
                context,
                title: "GST & TAXATION",
                subtitle: "GSTR-1, GSTR-3B, HSN Summary & JSON Export for portal.",
                icon: Icons.account_balance_rounded,
                color: Colors.green.shade700,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const GSTMenuView())),
              ),
              const SizedBox(height: 20),
              // 3. System & Admin
              _buildLargeMenuCard(
                context,
                title: "SYSTEM & ADMIN",
                subtitle: "Company setup, database backup, audit logs & system reset.",
                icon: Icons.settings_suggest_rounded,
                color: Colors.blue.shade800,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => SystemMenuView(onLogout: onLogout))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLargeMenuCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))], border: Border.all(color: color.withOpacity(0.1), width: 1.5)),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 35, color: color)),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color.withOpacity(0.9), letterSpacing: 0.5)),
            const SizedBox(height: 5),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.4)),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, color: color.withOpacity(0.3), size: 16),
        ]),
      ),
    );
  }
}
