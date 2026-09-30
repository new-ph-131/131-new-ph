import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'app_date_logic.dart'; // NAYA
import 'pharoah_date_controller.dart'; // NAYA

class DaybookView extends StatefulWidget {
  const DaybookView({super.key});
  @override State<DaybookView> createState() => _DaybookViewState();
}

class _DaybookViewState extends State<DaybookView> {
  DateTime selectedDate = DateTime.now();
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final ph = Provider.of<PharoahManager>(context, listen: false);
      // NAYA: Smart date initialization according to FY
      selectedDate = AppDateLogic.getSmartDate(ph.currentFY);
      _isInit = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    
    // --- TRANSACTION AGGREGATION LOGIC (Purana Logic preserved 100%) ---
    List<Map<String, dynamic>> allEntries = [];

    // 1. Sales
    for (var s in ph.sales.where((s) => _isSameDay(s.date, selectedDate) && s.status == "Active")) {
      allEntries.add({'time': s.date, 'type': 'SALE', 'party': s.partyName, 'ref': 'Bill #${s.billNo}', 'amount': s.totalAmount, 'isIn': true});
    }

    // 2. Purchases
    for (var p in ph.purchases.where((p) => _isSameDay(p.date, selectedDate))) {
      allEntries.add({'time': p.date, 'type': 'PURCHASE', 'party': p.distributorName, 'ref': 'Bill #${p.billNo}', 'amount': p.totalAmount, 'isIn': false});
    }

    // 3. Vouchers (Receipt, Payment, Contra, Expense)
    for (var v in ph.vouchers.where((v) => _isSameDay(v.date, selectedDate))) {
      allEntries.add({
        'time': v.date, 'type': v.type.toUpperCase(), 'party': v.partyName, 
        'ref': v.paymentMode, 'amount': v.amount, 
        'isIn': v.type == 'Receipt' || v.type == 'Contra'
      });
    }

    allEntries.sort((a, b) => b['time'].compareTo(a['time']));

    // --- SUMMARY CALCULATIONS ---
    double totalIn = allEntries.where((e) => e['isIn']).fold(0, (sum, e) => sum + e['amount']);
    double totalOut = allEntries.where((e) => !e['isIn']).fold(0, (sum, e) => sum + e['amount']);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Daybook Register"),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: () async {
              // NAYA: FY Locked Date Picker
              DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: ph.currentFY, initialDate: selectedDate);
              if (p != null) setState(() => selectedDate = p);
            },
          )
        ],
      ),
      body: Column(
        children: [
          // --- TOP SUMMARY PANEL (Aapka purana design separators ke sath) ---
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade900,
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(25), bottomRight: Radius.circular(25))
            ),
            child: Column(
              children: [
                Text(DateFormat('EEEE, dd MMMM yyyy').format(selectedDate), style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _summaryCol("TOTAL INFLOW", totalIn, Colors.greenAccent),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _summaryCol("TOTAL OUTFLOW", totalOut, Colors.orangeAccent),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _summaryCol("NET DAY", totalIn - totalOut, Colors.white),
                  ],
                ),
              ],
            ),
          ),

          // --- TRANSACTIONS LIST ---
          Expanded(
            child: allEntries.isEmpty
                ? Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 60, color: Colors.grey.shade400),
                      const SizedBox(height: 10),
                      Text("No transactions for ${DateFormat('dd/MM/yy').format(selectedDate)}", style: const TextStyle(color: Colors.grey)),
                    ],
                  ))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: allEntries.length,
                    itemBuilder: (c, i) {
                      final e = allEntries[i];
                      bool isIn = e['isIn'];

                      return Card(
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isIn ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                              shape: BoxShape.circle
                            ),
                            child: Icon(
                              isIn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                              color: isIn ? Colors.green : Colors.red,
                              size: 20,
                            ),
                          ),
                          title: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(5)),
                                child: Text(e['type'], style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700)),
                              ),
                              const Spacer(),
                              Text(e['ref'], style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(e['party'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                          ),
                          trailing: Text(
                            "₹${e['amount'].toStringAsFixed(2)}",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: isIn ? Colors.green.shade700 : Colors.red.shade700
                            ),
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

  bool _isSameDay(DateTime d1, DateTime d2) {
    return d1.day == d2.day && d1.month == d2.month && d1.year == d2.year;
  }

  Widget _summaryCol(String label, double val, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 5),
        Text("₹${val.toStringAsFixed(0)}", style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16)),
      ],
    );
  }
}
