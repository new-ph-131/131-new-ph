// FILE: lib/finance/bank_book_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import 'bank_transaction_model.dart';
import '../pharoah_date_controller.dart';

class BankBookView extends StatefulWidget {
  const BankBookView({super.key});

  @override
  State<BankBookView> createState() => _BankBookViewState();
}

class _BankBookViewState extends State<BankBookView> {
  Bank? selectedBank;
  DateTime fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime toDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    
    List<BankTransaction> txns = [];
    double openBal = 0;
    
    if (selectedBank != null) {
      // NAYA: Logic integrated directly for accurate statement
      txns = ph.getBankStatement(selectedBank!.name, fromDate, toDate);
      openBal = selectedBank!.openingBalance;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Bank Book / Ledger"),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildFilters(ph),
          if (selectedBank != null) _buildTableHeader(),
          Expanded(
            child: selectedBank == null
                ? const Center(child: Text("Select a bank account to view statement", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))
                : _buildTransactionList(txns, openBal),
          ),
          if (selectedBank != null) _buildFooter(txns, openBal),
        ],
      ),
    );
  }

  Widget _buildFilters(PharoahManager ph) {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: Column(
        children: [
          DropdownButtonFormField<Bank>(
            value: selectedBank,
            decoration: const InputDecoration(labelText: "Select Bank Account", border: OutlineInputBorder(), isDense: true),
            items: ph.banks.map((b) => DropdownMenuItem(value: b, child: Text(b.name))).toList(),
            onChanged: (v) => setState(() => selectedBank = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _dateTile("FROM", fromDate, (d) => setState(() => fromDate = d), ph.currentFY)),
              const SizedBox(width: 10),
              Expanded(child: _dateTile("TO", toDate, (d) => setState(() => toDate = d), ph.currentFY)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      color: Colors.grey.shade200,
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text("DATE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
          Expanded(flex: 4, child: Text("PARTICULARS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text("OUT (Dr)", textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red))),
          Expanded(flex: 2, child: Text("IN (Cr)", textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green))),
        ],
      ),
    );
  }

  Widget _buildTransactionList(List<BankTransaction> list, double openBal) {
    double currentBal = openBal;
    return ListView.builder(
      itemCount: list.length + 1,
      itemBuilder: (c, i) {
        if (i == 0) return _buildOpeningRow(openBal);
        final t = list[i - 1];
        currentBal += (t.amountIn - t.amountOut);
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
          child: Row(
            children: [
              Expanded(flex: 2, child: Text(DateFormat('dd/MM').format(t.date), style: const TextStyle(fontSize: 11))),
              Expanded(flex: 4, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.particulars, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  Text(t.reference, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                ],
              )),
              Expanded(flex: 2, child: Text(t.amountOut > 0 ? t.amountOut.toStringAsFixed(0) : "-", textAlign: TextAlign.right, style: const TextStyle(color: Colors.red, fontSize: 12))),
              Expanded(flex: 2, child: Text(t.amountIn > 0 ? t.amountIn.toStringAsFixed(0) : "-", textAlign: TextAlign.right, style: const TextStyle(color: Colors.green, fontSize: 12))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOpeningRow(double bal) => Container(
    padding: const EdgeInsets.all(10),
    color: Colors.blue.withOpacity(0.05),
    child: Row(children: [
      const Expanded(flex: 6, child: Text("OPENING BALANCE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
      Expanded(flex: 4, child: Text("₹${bal.toStringAsFixed(2)}", textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
    ]),
  );

  Widget _buildFooter(List<BankTransaction> list, double openBal) {
    double totalIn = list.fold(0, (sum, item) => sum + item.amountIn);
    double totalOut = list.fold(0, (sum, item) => sum + item.amountOut);
    double finalBal = openBal + totalIn - totalOut;

    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.indigo.shade900,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("CLOSING BALANCE:", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          Text("₹${finalBal.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _dateTile(String l, DateTime d, Function(DateTime) onPick, String fy) => InkWell(
    onTap: () async {
      DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: fy, initialDate: d);
      if (p != null) onPick(p);
    },
    child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(5)), child: Text("$l: ${DateFormat('dd/MM/yy').format(d)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
  );
}
