// FILE: lib/finance/pdc_entry_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../pharoah_date_controller.dart';
import '../logic/pharoah_numbering_engine.dart'; // NAYA

class PdcEntryView extends StatefulWidget {
  const PdcEntryView({super.key});

  @override
  State<PdcEntryView> createState() => _PdcEntryViewState();
}

class _PdcEntryViewState extends State<PdcEntryView> {
  final amountC = TextEditingController();
  final chequeNoC = TextEditingController();
  final customerBankC = TextEditingController();
  
  Party? selectedParty;
  String? selectedBillNo;
  Bank? depositBank; 
  DateTime chequeDate = DateTime.now();
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("New Cheque / PDC Entry"),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle("1. RECEIVE FROM (CUSTOMER)"),
            if (selectedParty == null)
              _buildPartySearch(ph)
            else
              _buildSelectedPartyCard(),

            const SizedBox(height: 20),

            if (selectedParty != null) ...[
              _sectionTitle("2. ADJUST AGAINST BILL"),
              _buildPendingBillsList(ph),
              const SizedBox(height: 20),
            ],

            _sectionTitle("3. CHEQUE INFORMATION"),
            Row(
              children: [
                Expanded(child: _input(amountC, "Amount (₹)", Icons.currency_rupee, isNum: true)),
                const SizedBox(width: 10),
                Expanded(child: _input(chequeNoC, "Cheque No.", Icons.numbers)),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _input(customerBankC, "Customer Bank", Icons.account_balance)),
                const SizedBox(width: 10),
                Expanded(child: _dateTile(ph)),
              ],
            ),

            const SizedBox(height: 25),
            _sectionTitle("4. DEPOSIT IN (OUR BANK)"),
            const SizedBox(height: 10),
            _buildDepositBankDropdown(ph),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade800,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: () => _handleSave(ph),
                child: const Text("SAVE & LINK CHEQUE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartySearch(PharoahManager ph) {
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(hintText: "Type Customer Name...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
          onChanged: (v) => setState(() => searchQuery = v),
        ),
        Container(
          height: 150,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
          child: ListView(
            children: ph.parties.where((p) => p.group == "Sundry Debtors" && p.name.toLowerCase().contains(searchQuery.toLowerCase())).map((p) => ListTile(
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text(p.city, style: const TextStyle(fontSize: 11)),
              onTap: () => setState(() { selectedParty = p; searchQuery = ""; }),
            )).toList(),
          ),
        )
      ],
    );
  }

  Widget _buildSelectedPartyCard() {
    return Card(
      color: Colors.teal.shade50,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.teal.shade200)),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.person, color: Colors.white)),
        title: Text(selectedParty!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(selectedParty!.city),
        trailing: IconButton(icon: const Icon(Icons.edit_note, color: Colors.blue), onPressed: () => setState(() { selectedParty = null; selectedBillNo = null; })),
      ),
    );
  }

  Widget _buildPendingBillsList(PharoahManager ph) {
    final partyBills = ph.sales.where((s) => s.partyName == selectedParty!.name && s.status == "Active").toList();
    if (partyBills.isEmpty) return const Padding(padding: EdgeInsets.all(10), child: Text("No pending bills.", style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)));

    return Container(
      height: 120,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(10),
        itemCount: partyBills.length,
        itemBuilder: (c, i) {
          final b = partyBills[i];
          bool isSelected = selectedBillNo == b.billNo;
          return GestureDetector(
            onTap: () => setState(() => selectedBillNo = b.billNo),
            child: Container(
              width: 130, margin: const EdgeInsets.only(right: 10), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: isSelected ? Colors.teal : Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: isSelected ? Colors.teal : Colors.grey.shade300)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(b.billNo, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87, fontSize: 12)),
                const SizedBox(height: 5),
                Text("₹${b.totalAmount.toInt()}", style: TextStyle(fontWeight: FontWeight.w900, color: isSelected ? Colors.white : Colors.teal.shade900, fontSize: 15)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDepositBankDropdown(PharoahManager ph) {
    return DropdownButtonFormField<Bank>(
      value: depositBank,
      decoration: const InputDecoration(border: OutlineInputBorder(), filled: true, fillColor: Colors.white, prefixIcon: Icon(Icons.account_balance_wallet)),
      hint: const Text("Select Our Bank Account"),
      items: ph.banks.map((b) => DropdownMenuItem(value: b, child: Text("${b.name} (${b.branch})"))).toList(),
      onChanged: (v) => setState(() => depositBank = v),
    );
  }

  Widget _dateTile(PharoahManager ph) {
    return InkWell(
      onTap: () async {
        DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: ph.currentFY, initialDate: chequeDate);
        if (p != null) setState(() => chequeDate = p);
      },
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(5), color: Colors.white),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(DateFormat('dd/MM/yy').format(chequeDate), style: const TextStyle(fontWeight: FontWeight.bold)),
          const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
        ]),
      ),
    );
  }

  Widget _input(TextEditingController ctrl, String label, IconData icon, {bool isNum = false}) => TextField(
    controller: ctrl,
    keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20), border: const OutlineInputBorder(), filled: true, fillColor: Colors.white),
  );

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1)),
  );

  void _handleSave(PharoahManager ph) {
    if (selectedParty == null || amountC.text.isEmpty || depositBank == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All fields are mandatory!"), backgroundColor: Colors.red));
      return;
    }

    final entry = ChequeEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      partyName: selectedParty!.name,
      billNo: selectedBillNo ?? "ADVANCE",
      amount: double.tryParse(amountC.text) ?? 0,
      chequeNo: chequeNoC.text,
      date: DateTime.now(),
      chequeDate: chequeDate,
      partyBank: customerBankC.text.toUpperCase(),
      depositBank: depositBank!.name,
      status: "Received",
    );

    ph.addCheque(entry);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Cheque Saved Successfully!"), backgroundColor: Colors.green));
  }
}
