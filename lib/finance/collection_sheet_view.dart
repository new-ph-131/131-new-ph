// FILE: lib/finance/collection_sheet_view.dart (Replacement Code - FIXED)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';

class CollectionSheetView extends StatefulWidget {
  const CollectionSheetView({super.key});

  @override
  State<CollectionSheetView> createState() => _CollectionSheetViewState();
}

class _CollectionSheetViewState extends State<CollectionSheetView> {
  String searchQuery = "";
  String? selectedRoute;

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    // 1. Logic: Filter and Sort Alphabetically
    List<Party> list = ph.parties.where((p) {
      if (p.name == "CASH") return false;
      bool matchesRoute = selectedRoute == null || p.route == selectedRoute;
      bool matchesSearch = p.name.toLowerCase().contains(searchQuery.toLowerCase());
      return matchesRoute && matchesSearch;
    }).toList();

    // Alphabetical Sorting
    list.sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Collection / Recovery List"),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // --- 1. SEARCH & ROUTE SELECTOR ---
          _buildFilterHeader(ph),

          // --- 2. PARTY LIST ---
          Expanded(
            child: list.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final p = list[i];
                      double balance = _calcOutstanding(ph, p);
                      
                      // Skip zero balance parties for recovery sheet
                      if (balance <= 0) return const SizedBox();

                      return _buildPartyCard(p, balance);
                    },
                  ),
          ),

          // --- 3. TOTAL FOOTER ---
          _buildSummaryFooter(ph, list),
        ],
      ),
    );
  }

  Widget _buildFilterHeader(PharoahManager ph) {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.indigo.shade900,
      child: Column(
        children: [
          // Search Bar
          TextField(
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => searchQuery = v),
            decoration: InputDecoration(
              hintText: "Search Party Name...",
              hintStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(Icons.search, color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 10),
          // Route Dropdown
          DropdownButtonFormField<String>(
            value: selectedRoute,
            dropdownColor: Colors.indigo.shade800,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              labelText: "Filter by Route / Area",
              labelStyle: TextStyle(color: Colors.white70, fontSize: 10),
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text("ALL ROUTES")),
              ...ph.routes.map((r) => DropdownMenuItem(value: r.name, child: Text(r.name.toUpperCase()))),
            ],
            onChanged: (v) => setState(() => selectedRoute = v),
          ),
        ],
      ),
    );
  }

  Widget _buildPartyCard(Party p, double balance) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("${p.city} | ${p.route}", style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 5),
            Row(
              children: [
                const Icon(Icons.phone, size: 12, color: Colors.green),
                const SizedBox(width: 5),
                Text(p.phone.isEmpty ? "No Number" : p.phone, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text("₹${balance.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.red)),
            const Text("OUTSTANDING", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryFooter(PharoahManager ph, List<Party> list) {
    double total = 0;
    for (var p in list) { total += _calcOutstanding(ph, p); }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("TOTAL RECOVERY DUE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            Text("₹${total.toStringAsFixed(2)}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.indigo.shade900)),
          ]),
          const Icon(Icons.share_rounded, color: Colors.green),
        ],
      ),
    );
  }

  // --- LOGIC: CALCULATION (FIXED) ---
  double _calcOutstanding(PharoahManager ph, Party p) {
    double bal = p.opBal;
    
    // 1. Add Active Sales
    for (var s in ph.sales.where((x) => x.partyName == p.name && x.status == "Active")) {
      bal += s.totalAmount;
    }
    
    // 2. Subtract Receipts
    for (var v in ph.vouchers.where((x) => x.partyName == p.name && x.type == "Receipt")) {
      bal -= v.amount;
    }
    
    // 3. Subtract Sales Returns (FIXED TYPE CASTING)
    for (var r in ph.saleReturns.where((x) => x.partyName == p.name)) {
      bal -= r.totalAmount;
    }
    
    return bal;
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_outline, size: 60, color: Colors.grey.shade300), const Text("No outstanding in this area!", style: TextStyle(color: Colors.grey))]));
  }
}
