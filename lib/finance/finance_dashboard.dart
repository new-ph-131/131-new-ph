// FILE: lib/finance/finance_dashboard.dart (Replacement Code - FIXED)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import 'pdc_entry_view.dart';
import 'outstanding_ageing_view.dart';
import 'collection_sheet_view.dart'; 
import 'bank_book_view.dart';

class FinanceDashboard extends StatelessWidget {
  const FinanceDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    // Logic: Calculate Live Market Outstanding
    double totalOutstanding = 0;
    for (var p in ph.parties) {
      if (p.name == "CASH") continue;
      totalOutstanding += _calculatePartyOutstanding(ph, p);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Finance & Recovery Hub"),
        backgroundColor: Colors.green.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 1. OVERALL OUTSTANDING SUMMARY ---
            _buildFinancialSummary(totalOutstanding),

            const SizedBox(height: 25),
            const Text(
              "PAYMENT AGEING ANALYSIS",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                _ageingBox("0-30 DAYS", Colors.green),
                const SizedBox(width: 10),
                _ageingBox("31-60 DAYS", Colors.orange),
                const SizedBox(width: 10),
                _ageingBox("60+ DAYS", Colors.red),
              ],
            ),

            const SizedBox(height: 30),
            const Text(
              "FINANCIAL TOOLS & REPORTS",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.2),
            ),
            const SizedBox(height: 15),

            // --- 3. FINANCE TOOLS GRID ---
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.2,
              children: [
                _toolCard(
                  context,
                  "OUTSTANDING", 
                  "Party-wise Udhaar", 
                  Icons.person_search_rounded, 
                  Colors.indigo, 
                  const OutstandingAgeingView()
                ),
                _toolCard(
                  context,
                  "NEW CHEQUE", 
                  "Post Dated Entry", 
                  Icons.add_card_rounded, 
                  const Color(0xFF00796B), 
                  const PdcEntryView()
                ),
                _toolCard(
                  context,
                  "COLLECTION", 
                  "Recovery Sheet", 
                  Icons.badge_rounded, 
                  Colors.blueGrey, 
                  const CollectionSheetView() 
                ),
                _toolCard(
                  context,
                  "BANK BOOK", 
                  "Passbook Ledger", 
                  Icons.account_balance_rounded, 
                  Colors.blue.shade800, 
                  const BankBookView()
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- HELPERS ---

  double _calculatePartyOutstanding(PharoahManager ph, Party p) {
    double bal = p.opBal;
    
    // 1. Add Active Sales
    for (var s in ph.sales.where((x) => x.partyName == p.name && x.status == "Active")) {
      bal += s.totalAmount;
    }
    
    // 2. Subtract Receipts (Vouchers)
    for (var v in ph.vouchers.where((x) => x.partyName == p.name && x.type == "Receipt")) {
      bal -= v.amount;
    }
    
    // 3. Subtract Sales Returns (Credit Notes)
    for (var r in ph.saleReturns.where((x) => x.partyName == p.name)) {
      bal -= r.totalAmount;
    }
    
    return bal;
  }

  Widget _buildFinancialSummary(double outstanding) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
      ),
      child: Column(
        children: [
          const Text("TOTAL MARKET OUTSTANDING", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text(
            "₹${outstanding.toStringAsFixed(2)}", 
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.indigo)
          ),
          const Divider(height: 30),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MiniStat(label: "Live Balance", value: "Checked", color: Colors.green),
              _MiniStat(label: "Recoveries", value: "Pending", color: Colors.blue),
            ],
          )
        ],
      ),
    );
  }

  Widget _ageingBox(String label, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: c.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: c)),
            const SizedBox(height: 5),
            Icon(Icons.trending_up, size: 14, color: c),
          ],
        ),
      ),
    );
  }

  Widget _toolCard(BuildContext context, String title, String sub, IconData icon, Color color, Widget target) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => target)),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(sub, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
