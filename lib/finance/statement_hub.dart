import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pharoah_manager.dart';
import 'company_stock_view.dart';
import 'company_expiry_audit_view.dart';
import 'party_wise_stock_view.dart';
import 'party_ledger_statement_view.dart';
import 'item_movement_ledger_view.dart'; // ✅ Fixed: Missing import added

class StatementHubView extends StatelessWidget {
  const StatementHubView({super.key});

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        title: const Text("Statements & Audit Hub", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeHeader(ph.activeCompany?.name ?? "Pharoah ERP"),
            const SizedBox(height: 30),
            const Text(
              "SELECT REPORT CATEGORY",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5),
            ),
            const SizedBox(height: 15),
            
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.1,
              children: [
                _hubCard(context, "Party Ledger\nStatement", "Dr/Cr Audit", Icons.account_balance_wallet_rounded, Colors.indigo, const PartyLedgerStatementView()),
                _hubCard(context, "Company Wise\nStock", "In-Out Flow", Icons.business_rounded, Colors.purple, const CompanyStockView()),
                _hubCard(context, "Party Wise\nStock", "Sales Analysis", Icons.person_search_rounded, Colors.teal, const PartyWiseStockView()),
                _hubCard(context, "Near Expiry\nStock", "Loss Prevention", Icons.event_busy_rounded, Colors.red, const CompanyExpiryAuditView()),
                
                // ✅ Fixed: Removed 'const' which was causing build error
                _hubCard(context, "Item Movement\nLedger", "In-Out Timeline", Icons.history_edu_rounded, Colors.blue, const ItemMovementLedgerView()),
                _hubCard(context, "Purchase Source\nHistory", "Price Tracking", Icons.shopping_cart_rounded, Colors.orange, const ItemMovementLedgerView()),
              ],
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader(String shopName) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Row(children: [
        CircleAvatar(backgroundColor: const Color(0xFF0D47A1).withOpacity(0.1), radius: 25, child: const Icon(Icons.analytics, color: Color(0xFF0D47A1))),
        const SizedBox(width: 15),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(shopName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const Text("Financial Integrity & Stock Reports", style: TextStyle(fontSize: 11, color: Colors.grey)),
        ])),
      ]),
    );
  }

  Widget _hubCard(BuildContext context, String t, String s, IconData i, Color c, Widget? target) {
    return InkWell(
      onTap: () => target != null ? Navigator.push(context, MaterialPageRoute(builder: (c) => target)) : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: c.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: c.withOpacity(0.1), shape: BoxShape.circle), child: Icon(i, color: c, size: 28)),
            const SizedBox(height: 12),
            Text(t, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Text(s, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
