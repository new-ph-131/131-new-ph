// FILE: lib/inventory_intel/stock_health_reports.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';

class StockHealthReports extends StatefulWidget {
  const StockHealthReports({super.key});

  @override
  State<StockHealthReports> createState() => _StockHealthReportsState();
}

class _StockHealthReportsState extends State<StockHealthReports> {
  int nonMovingDays = 90; // Default: Quarterly (90 Days)
  String timeframeLabel = "Quarterly";

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    // 1. Logic: Filter Dumping Items (Stock > 0 and No Sale in X days)
    final dumpingItems = _getDumpingItems(ph);
    
    // 2. Logic: Group by Company
    Map<String, List<Medicine>> groupedItems = {};
    for (var med in dumpingItems) {
      String company = med.companyId.isEmpty ? "UNKNOWN COMPANY" : med.companyId;
      if (!groupedItems.containsKey(company)) groupedItems[company] = [];
      groupedItems[company]!.add(med);
    }

    double totalBlockedValue = dumpingItems.fold(0, (sum, m) => sum + (m.stock * m.purRate));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Dumping Stock Analysis"),
        backgroundColor: Colors.purple.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // --- 1. TIMEFRAME SELECTOR ---
          _buildTimeframeSelector(),

          // --- 2. SUMMARY RIBBON ---
          _buildSummaryRibbon(dumpingItems.length, totalBlockedValue),

          // --- 3. GROUPED LIST ---
          Expanded(
            child: dumpingItems.isEmpty
                ? _buildEmptyState()
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: groupedItems.entries.map((entry) => _buildCompanyGroup(entry.key, entry.value)).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeframeSelector() {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _filterBtn("Monthly", 30),
          _filterBtn("Quarterly", 90),
          _filterBtn("Custom", 0), // 0 indicates custom picker
        ],
      ),
    );
  }

  Widget _filterBtn(String label, int days) {
    bool isSel = timeframeLabel == label;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSel ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
      selected: isSel,
      selectedColor: Colors.purple.shade900,
      onSelected: (v) {
        if (label == "Custom") {
          _showCustomDaysDialog();
        } else {
          setState(() { timeframeLabel = label; nonMovingDays = days; });
        }
      },
    );
  }

  Widget _buildSummaryRibbon(int count, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      decoration: BoxDecoration(color: Colors.purple.shade50, border: Border(bottom: BorderSide(color: Colors.purple.shade100))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _stat("ITEMS", count.toString(), Colors.purple.shade900),
          _stat("BLOCKED CAPITAL (PUR)", "₹${value.toStringAsFixed(0)}", Colors.red.shade900),
        ],
      ),
    );
  }

  Widget _stat(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)), Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c))]);

  Widget _buildCompanyGroup(String companyName, List<Medicine> meds) {
    double companyValue = meds.fold(0, (sum, m) => sum + (m.stock * m.purRate));
    
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(15))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(companyName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                Text("Group Value: ₹${companyValue.toStringAsFixed(0)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ...meds.map((m) => ListTile(
            dense: true,
            title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Stock: ${m.stock.toInt()} ${m.packing} | Last Sold: ${_getLastSaleInfo(m)}"),
            trailing: Text("₹${(m.stock * m.purRate).toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
          )),
        ],
      ),
    );
  }

  // --- LOGIC: GET DUMPING LIST ---
  List<Medicine> _getDumpingItems(PharoahManager ph) {
    DateTime now = DateTime.now();
    return ph.medicines.where((m) {
      if (m.stock <= 0) return false;

      // Find last sale date for this medicine
      DateTime? lastSaleDate;
      for (var s in ph.sales) {
        if (s.items.any((it) => it.medicineID == m.id)) {
          if (lastSaleDate == null || s.date.isAfter(lastSaleDate)) {
            lastSaleDate = s.date;
          }
        }
      }

      if (lastSaleDate == null) return true; // Never sold = Dumping
      return now.difference(lastSaleDate).inDays >= nonMovingDays;
    }).toList();
  }

  String _getLastSaleInfo(Medicine m) {
    // Helper to display date or "Never"
    final ph = Provider.of<PharoahManager>(context, listen: false);
    DateTime? lastDate;
    for (var s in ph.sales) {
      if (s.items.any((it) => it.medicineID == m.id)) {
        if (lastDate == null || s.date.isAfter(lastDate)) lastDate = s.date;
      }
    }
    return lastDate == null ? "NEVER" : DateFormat('dd/MM/yy').format(lastDate);
  }

  void _showCustomDaysDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Custom Non-Moving Days"),
        content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "Enter days (e.g. 180)")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () {
            setState(() {
              timeframeLabel = "Custom";
              nonMovingDays = int.tryParse(controller.text) ?? 90;
            });
            Navigator.pop(c);
          }, child: const Text("APPLY")),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.verified_rounded, size: 60, color: Colors.green.withOpacity(0.3)), const Text("No dumping stock found. Great job!", style: TextStyle(color: Colors.grey))]));
  }
}
