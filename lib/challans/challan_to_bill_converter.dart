// FILE: lib/challans/challan_to_bill_converter.dart (Replacement Code - FIXED)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../logic/pharoah_numbering_engine.dart';
import '../pharoah_date_controller.dart';

class ChallanToBillConverter extends StatefulWidget {
  const ChallanToBillConverter({super.key});

  @override
  State<ChallanToBillConverter> createState() => _ChallanToBillConverterState();
}

class _ChallanToBillConverterState extends State<ChallanToBillConverter> {
  Party? selectedParty;
  List<String> selectedChallanIds = [];
  String searchQuery = "";
  DateTime billDate = DateTime.now();
  String payMode = "CREDIT";

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Challan to Bill Converter"),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildPartyHeader(ph),

          if (selectedParty != null) ...[
            _buildChallanSelectionList(ph),
            if (selectedChallanIds.isNotEmpty) _buildActionBar(ph),
          ] else
            Expanded(child: _buildEmptyState("Please select a party to see pending challans")),
        ],
      ),
    );
  }

  Widget _buildPartyHeader(PharoahManager ph) {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: selectedParty == null
          ? TextField(
              decoration: const InputDecoration(
                hintText: "Search Party...", 
                prefixIcon: Icon(Icons.search), 
                border: OutlineInputBorder()
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            )
          : ListTile(
              tileColor: Colors.indigo.withOpacity(0.05),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.indigo)),
              leading: const Icon(Icons.person, color: Colors.indigo),
              title: Text(selectedParty!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() { selectedParty = null; selectedChallanIds.clear(); })),
            ),
    );
  }

  Widget _buildChallanSelectionList(PharoahManager ph) {
    // Properly typed filtering
    List<SaleChallan> partyChallans = ph.saleChallans.where((c) => c.partyName == selectedParty!.name && c.status == "Pending").toList();

    if (partyChallans.isEmpty) return Expanded(child: _buildEmptyState("No pending challans for this party."));

    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("SELECT CHALLANS TO MERGE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1)),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (selectedChallanIds.length == partyChallans.length) selectedChallanIds.clear();
                      else selectedChallanIds = partyChallans.map((c) => c.id).toList();
                    });
                  },
                  child: Text(selectedChallanIds.length == partyChallans.length ? "UNSELECT ALL" : "SELECT ALL"),
                )
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: partyChallans.length,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemBuilder: (c, i) {
                final ch = partyChallans[i];
                final isSelected = selectedChallanIds.contains(ch.id);
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isSelected ? Colors.indigo : Colors.grey.shade200)),
                  child: CheckboxListTile(
                    value: isSelected,
                    activeColor: Colors.indigo,
                    title: Text(ch.billNo, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Date: ${DateFormat('dd/MM/yy').format(ch.date)} | Amt: ₹${ch.totalAmount.toStringAsFixed(2)}"),
                    onChanged: (v) {
                      setState(() { v! ? selectedChallanIds.add(ch.id) : selectedChallanIds.remove(ch.id); });
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(PharoahManager ph) {
    double total = ph.saleChallans
        .where((c) => selectedChallanIds.contains(c.id))
        .fold(0, (sum, item) => sum + item.totalAmount);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("${selectedChallanIds.length} Challans Selected", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              Text("Total: ₹${total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.indigo)),
            ],
          ),
          const SizedBox(height: 15),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => _showPreviewAndOptions(ph),
            child: const Text("PROCEED TO BILL OPTIONS", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showPreviewAndOptions(PharoahManager ph) {
    List<BillItem> combinedItems = [];
    for (var cid in selectedChallanIds) {
      var ch = ph.saleChallans.firstWhere((x) => x.id == cid);
      for (var item in ch.items) {
        combinedItems.add(item.copyWith(sourceChallanNo: ch.billNo));
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => StatefulBuilder(builder: (context, setModalState) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("FINAL BILL PREVIEW", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              Row(
                children: [
                  Expanded(child: ListTile(
                    title: const Text("Bill Date", style: TextStyle(fontSize: 10)),
                    subtitle: Text(DateFormat('dd/MM/yyyy').format(billDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.calendar_today, size: 16),
                    onTap: () async {
                      DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: ph.currentFY, initialDate: billDate);
                      if (p != null) setModalState(() => billDate = p);
                    },
                  )),
                  Expanded(child: DropdownButtonFormField<String>(
                    value: payMode,
                    decoration: const InputDecoration(labelText: "Pay Mode", border: OutlineInputBorder()),
                    items: ["CASH", "CREDIT"].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (v) => setModalState(() => payMode = v!),
                  )),
                ],
              ),
              const SizedBox(height: 15),
              Expanded(
                child: ListView.builder(
                  itemCount: combinedItems.length,
                  itemBuilder: (c, i) {
                    final it = combinedItems[i];
                    return ListTile(
                      dense: true,
                      title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Qty: ${it.qty.toInt()} | Ref: ${it.sourceChallanNo}"),
                      trailing: Text("₹${it.total.toStringAsFixed(2)}"),
                    );
                  },
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55)),
                onPressed: () => _finalizeConversion(ph, combinedItems),
                child: const Text("GENERATE FINAL GST BILL", style: TextStyle(fontWeight: FontWeight.bold)),
              )
            ],
          ),
        );
      }),
    );
  }

  void _finalizeConversion(PharoahManager ph, List<BillItem> items) async {
    // Get next bill number from engine
    var series = ph.getDefaultSeries("SALE");
    String nextBillNo = await PharoahNumberingEngine.getNextNumber(
      type: "SALE",
      companyID: ph.activeCompany!.id,
      prefix: series.prefix,
      startFrom: series.startNumber,
      currentList: ph.sales,
    );

    // Update challan status to Billed
    for (var id in selectedChallanIds) {
      int idx = ph.saleChallans.indexWhere((c) => c.id == id);
      if (idx != -1) ph.saleChallans[idx].status = "Billed";
    }

    ph.finalizeSale(
      billNo: nextBillNo, 
      date: billDate, 
      party: selectedParty!, 
      items: items, 
      total: items.fold(0, (sum, it) => sum + it.total), 
      mode: payMode,
      linkedIds: selectedChallanIds, // <--- YE LINK HONA ZAROORI HAI
    );

    if (mounted) {
      Navigator.pop(context); // Close Preview
      Navigator.pop(context); // Close Converter
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ Bill $nextBillNo Created!"), backgroundColor: Colors.green));
    }
  }

  Widget _buildEmptyState(String msg) => Center(child: Text(msg, style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)));
}
