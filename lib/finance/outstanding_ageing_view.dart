// FILE: lib/finance/outstanding_ageing_view.dart (Advanced Logic + Null Fixed)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';

class OutstandingAgeingView extends StatefulWidget {
  const OutstandingAgeingView({super.key});

  @override
  State<OutstandingAgeingView> createState() => _OutstandingAgeingViewState();
}

class _OutstandingAgeingViewState extends State<OutstandingAgeingView> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    // Filtered list based on Search
    final filteredParties = ph.parties.where((p) {
      if (p.name == "CASH") return false;
      return p.name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Outstanding & Ageing Analysis"),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // --- 1. SEARCH BAR ---
          _buildFilterBar(),

          // --- 2. GLOBAL AGEING INDICATORS ---
          _buildGlobalSummary(),

          // --- 3. PARTY LIST ---
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: filteredParties.length,
              itemBuilder: (c, i) {
                final party = filteredParties[i];
                final ageingData = _calculatePartyAgeing(ph, party);

                // FIXED: Null check added with '?? 0' to prevent build error
                if ((ageingData['total'] ?? 0) <= 0) return const SizedBox();

                return _partyAgeingCard(party, ageingData);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.indigo.shade800,
      child: TextField(
        style: const TextStyle(color: Colors.white),
        onChanged: (v) => setState(() => searchQuery = v),
        decoration: InputDecoration(
          hintText: "Search Party Name...",
          hintStyle: const TextStyle(color: Colors.white60),
          prefixIcon: const Icon(Icons.search, color: Colors.white70),
          filled: true, fillColor: Colors.white.withOpacity(0.1),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildGlobalSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _miniBox("0-30", Colors.green),
          _miniBox("31-60", Colors.orange),
          _miniBox("61-90", Colors.deepOrange),
          _miniBox("90+", Colors.red),
        ],
      ),
    );
  }

  Widget _miniBox(String days, Color c) {
    return Column(
      children: [
        Text(days, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c)),
        Container(height: 4, width: 30, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
      ],
    );
  }

  Widget _partyAgeingCard(Party p, Map<String, double> data) {
    double total = data['total'] ?? 0;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(p.city, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
                Text("₹${total.toStringAsFixed(0)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.indigo)),
              ],
            ),
            const Divider(height: 25),
            Row(
              children: [
                _ageingSegment("30", data['b1'] ?? 0, total, Colors.green),
                _ageingSegment("60", data['b2'] ?? 0, total, Colors.orange),
                _ageingSegment("90", data['b3'] ?? 0, total, Colors.deepOrange),
                _ageingSegment("90+", data['b4'] ?? 0, total, Colors.red),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Pending Recovery", style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
                const Icon(Icons.share_rounded, color: Colors.green, size: 20),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _ageingSegment(String label, double val, double total, Color c) {
    if (val <= 0 || total <= 0) return const SizedBox();
    return Expanded(
      flex: (val / total * 100).toInt(),
      child: Container(
        height: 25,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
        alignment: Alignment.center,
        child: Text(val.toInt().toString(), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Map<String, double> _calculatePartyAgeing(PharoahManager ph, Party p) {
    double b1 = 0; // 0-30
    double b2 = 0; // 31-60
    double b3 = 0; // 61-90
    double b4 = 0; // 90+
    double total = p.opBal;

    final partyBills = ph.sales.where((s) => s.partyName == p.name && s.status == "Active").toList();
    DateTime now = DateTime.now();

    for (var bill in partyBills) {
      int diff = now.difference(bill.date).inDays;
      double amt = bill.totalAmount;
      if (diff <= 30) b1 += amt;
      else if (diff <= 60) b2 += amt;
      else if (diff <= 90) b3 += amt;
      else b4 += amt;
      total += amt;
    }

    final receipts = ph.vouchers.where((v) => v.partyName == p.name && v.type == "Receipt").fold(0.0, (sum, v) => sum + v.amount);
    total -= receipts;

    return {'total': total, 'b1': b1, 'b2': b2, 'b3': b3, 'b4': b4};
  }
}
