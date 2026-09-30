import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'pharoah_manager.dart';
import 'models.dart';

class ProfitLossView extends StatefulWidget {
  const ProfitLossView({super.key});
  @override State<ProfitLossView> createState() => _ProfitLossViewState();
}

class _ProfitLossViewState extends State<ProfitLossView> {
  DateTime fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime toDate = DateTime.now();

  @override Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    double sales = 0, cogs = 0, expenses = 0;

    for (var s in ph.sales.where((s) => s.status == "Active" && s.date.isAfter(fromDate.subtract(const Duration(days: 1))) && s.date.isBefore(toDate.add(const Duration(days: 1))))) {
      sales += s.totalAmount;
      for (var it in s.items) {
        var m = ph.medicines.firstWhere((med) => med.id == it.medicineID, orElse: () => Medicine(id: '0', name: '', packing: '', mrp: 0, rateA: 0, rateB: 0, rateC: 0));
        cogs += (m.purRate * (it.qty + it.freeQty));
      }
    }
    for (var v in ph.vouchers.where((v) => v.type == "Expense" && v.date.isAfter(fromDate.subtract(const Duration(days: 1))) && v.date.isBefore(toDate.add(const Duration(days: 1))))) {
       expenses += v.amount;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(title: const Text("Profit & Loss Statement"), backgroundColor: Colors.indigo.shade900, foregroundColor: Colors.white),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(15), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("Period: ${DateFormat('dd/MM').format(fromDate)} to ${DateFormat('dd/MM').format(toDate)}"),
          IconButton(icon: const Icon(Icons.date_range), onPressed: () async {
            var p = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (p != null) setState(() { fromDate = p.start; toDate = p.end; });
          })
        ])),
        Expanded(child: ListView(padding: const EdgeInsets.all(20), children: [
          _row("TOTAL SALES", sales, isBold: true),
          _row("LESS: COST OF GOODS (COGS)", -cogs, color: Colors.red),
          const Divider(),
          _row("GROSS PROFIT", sales - cogs, color: Colors.green, isBold: true),
          const SizedBox(height: 20),
          _row("TOTAL OPERATING EXPENSES", -expenses, color: Colors.red),
          const Divider(thickness: 2),
          _row("NET PROFIT / LOSS", (sales - cogs) - expenses, isBold: true, color: Colors.blue.shade900),
        ]))
      ]),
    );
  }
  Widget _row(String l, double v, {bool isBold = false, Color? color}) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)), Text("₹${v.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, color: color))]));
}
