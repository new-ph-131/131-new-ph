import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'pharoah_manager.dart';
import 'models.dart';

class GSTReconciliationView extends StatefulWidget {
  const GSTReconciliationView({super.key});
  @override State<GSTReconciliationView> createState() => _GSTReconciliationViewState();
}

class _GSTReconciliationViewState extends State<GSTReconciliationView> {
  DateTime selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    List<Purchase> monthlyPurchases = ph.purchases.where((p) => 
      p.date.month == selectedDate.month && p.date.year == selectedDate.year
    ).toList();

    int matchedCount = monthlyPurchases.where((p) => p.gstStatus == "Matched").length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(title: const Text("Portal Match (2A/2B)"), backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white, elevation: 0),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20), color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Select Month:", style: TextStyle(fontWeight: FontWeight.bold)),
                InkWell(
                  onTap: () async { DateTime? p = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (p != null) setState(() => selectedDate = p); },
                  child: Text(DateFormat('MMMM yyyy').format(selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                _badge("TOTAL", "${monthlyPurchases.length}", Colors.blueGrey),
                const SizedBox(width: 10),
                _badge("MATCHED", "$matchedCount", Colors.green),
              ],
            ),
          ),
          Expanded(
            child: monthlyPurchases.isEmpty 
              ? const Center(child: Text("No entries found."))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemCount: monthlyPurchases.length,
                  itemBuilder: (context, index) {
                    final p = monthlyPurchases[index];
                    bool isMatched = p.gstStatus == "Matched";
                    return Card(
                      child: ListTile(
                        title: Text(p.distributorName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Bill: ${p.billNo} | ₹${p.totalAmount.toStringAsFixed(2)}"),
                        trailing: Switch(
                          value: isMatched,
                          activeColor: Colors.green,
                          onChanged: (val) {
                            setState(() { p.gstStatus = val ? "Matched" : "Pending"; ph.save(); });
                          },
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String l, String v, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(l, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c)),
          // FIX: FontWeight.black changed to FontWeight.w900 for compatibility
          Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c)),
        ]),
      ),
    );
  }
}
