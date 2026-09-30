// FILE: lib/accounts_menu_view.dart

import 'package:flutter/material.dart';
import 'widgets.dart';
import 'accounting_views.dart'; 
import 'finance/statement_hub.dart';
import 'daybook_view.dart'; 
import 'ledger_reports_view.dart'; 
import 'payment_receipt_history.dart'; // 🔥 Naya Import

class AccountsMenuView extends StatelessWidget {
  const AccountsMenuView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Accounts & Cash Management"),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "DAILY VOUCHERS",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey, letterSpacing: 1.2),
            ),
            const SizedBox(height: 15),
            
            // --- SECTION 1: VOUCHER ENTRIES ---
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.1,
              children: [
                ActionIconBtn(
                  title: "Receipt (Cash In)",
                  icon: Icons.add_chart_rounded,
                  color: Colors.green.shade700,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const VoucherEntryView(type: "RECEIPT"))),
                ),
                ActionIconBtn(
                  title: "Payment (Cash Out)",
                  icon: Icons.analytics_rounded,
                  color: Colors.red.shade700,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const VoucherEntryView(type: "PAYMENT"))),
                ),
                ActionIconBtn(
                  title: "Contra (Bank)",
                  icon: Icons.sync_alt_rounded,
                  color: Colors.orange.shade800,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const VoucherEntryView(type: "Contra"))),
                ),
                ActionIconBtn(
                  title: "Expenses",
                  icon: Icons.money_off_rounded,
                  color: Colors.brown,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const VoucherEntryView(type: "Expense"))),
                ),
              ],
            ),

            const SizedBox(height: 35),
            
           const Text(
              "AUDIT & STATEMENTS",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey, letterSpacing: 1.2),
            ),
            const SizedBox(height: 15),

            // 🔥 NAYA: STATEMENT HUB BUTTON (FULL WIDTH)
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const StatementHubView())),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.analytics_rounded, color: Colors.white, size: 32),
                    SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("STATEMENTS HUB", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          Text("Ledgers, Stock Flow & Expiry Reports", style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 18),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30), // Gap before next section

            const Text(
              "STANDARD QUICK REPORTS",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey, letterSpacing: 1.2),
            ),
            // ... (Niche ka Row/Standard reports code same rahega)
            const Text(
              "REPORTS & STATEMENTS",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey, letterSpacing: 1.2),
            ),
            const SizedBox(height: 15),

            // --- SECTION 2: STANDARD REPORTS ---
            Row(
              children: [
                Expanded(
                  child: _reportCard(
                    context, 
                    "Daybook", 
                    "Daily Summary", 
                    Icons.menu_book_rounded, 
                    Colors.blueGrey, 
                    const DaybookView()
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _reportCard(
                    context, 
                    "Ledgers", 
                    "Party Balances", 
                    Icons.people_alt_rounded, 
                    Colors.indigo, 
                    const LedgerReportsView()
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            // --- SECTION 3: ADVANCED AUDIT (NICHE LAGAYA GAYA HAI) ---
            const Text(
              "ADVANCED AUDIT TOOLS",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blueGrey, letterSpacing: 1.5),
            ),
            const SizedBox(height: 12),

            // 🔥 PROFESSIONAL HISTORY BUTTON (FULL WIDTH)
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const PaymentReceiptHistory())),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade900, Colors.orange.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    )
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.history_edu_rounded, color: Colors.white, size: 32),
                    SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Payment or Receipt History", 
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Full Audit, Edit, Sync & A6 Printing", 
                            style: TextStyle(color: Colors.white70, fontSize: 11)
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 18),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 100), // Scrolling safety space
          ],
        ),
      ),
    );
  }

  // Helper Widget for Daybook/Ledger Cards
  Widget _reportCard(BuildContext context, String title, String sub, IconData icon, Color color, Widget target) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => target)),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
          border: Border.all(color: Colors.grey.shade100)
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
