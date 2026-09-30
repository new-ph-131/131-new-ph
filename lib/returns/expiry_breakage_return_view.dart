// FILE: lib/returns/expiry_breakage_return_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../logic/pharoah_numbering_engine.dart';
import '../item_entry_card.dart';
import '../pharoah_date_controller.dart';

class ExpiryBreakageReturnView extends StatefulWidget {
  const ExpiryBreakageReturnView({super.key});

  @override
  State<ExpiryBreakageReturnView> createState() => _ExpiryBreakageReturnViewState();
}

class _ExpiryBreakageReturnViewState extends State<ExpiryBreakageReturnView> {
  final returnNoC = TextEditingController();
  DateTime selectedDate = DateTime.now();
  Party? selectedParty;
  List<BillItem> items = [];
  String searchQuery = "";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initBreakage();
  }

  void _initBreakage() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    if (ph.activeCompany != null) {
      var defaultRetSeries = ph.getDefaultSeries("RETURN");
      
      String nextNo = await PharoahNumberingEngine.getNextNumber(
        type: "RETURN",
        companyID: ph.activeCompany!.id,
        prefix: defaultRetSeries.prefix,
        startFrom: defaultRetSeries.startNumber,
        currentList: ph.saleReturns,
      );
      
      setState(() {
        returnNoC.text = nextNo;
        selectedDate = PharoahDateController.getInitialBillDate(ph.currentFY);
        isLoading = false;
      });
    }
  }

  double get totalAmt => items.fold(0, (sum, it) => sum + it.total);

  void _recalculateSR() {
    setState(() {
      for (int i = 0; i < items.length; i++) {
        items[i] = items[i].copyWith(srNo: i + 1);
      }
    });
  }

  void _showItemSearch(PharoahManager ph) {
    String localSearch = "";
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filteredMeds = ph.medicines
              .where((m) => m.name.toLowerCase().contains(localSearch.toLowerCase()))
              .toList();
              
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
                  height: 5, width: 50,
                  decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10)),
                ),
                Padding(
                  padding: const EdgeInsets.all(15), 
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: "Search expired/breakage item...",
                      prefixIcon: const Icon(Icons.search, color: Colors.red),
                      filled: true, fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) => setSheetState(() => localSearch = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredMeds.length,
                    itemBuilder: (c, i) => ListTile(
                      leading: const Icon(Icons.delete_sweep, color: Colors.red),
                      title: Text(filteredMeds[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Pack: ${filteredMeds[i].packing} | Current Stock: ${filteredMeds[i].stock}"),
                      onTap: () {
                        Navigator.pop(context);
                        _showQuantityEntry(filteredMeds[i]);
                      },
                    ),
                  ),
                )
              ],
            ),
          );
        }
      ),
    );
  }

  void _showQuantityEntry(Medicine med) {
    showDialog(
      context: context,
      builder: (c) => ItemEntryCard(
        med: med,
        srNo: items.length + 1,
        partyState: selectedParty?.state ?? "Rajasthan", // NAYA: Added partyState parameter
        onAdd: (newItem) {
          setState(() { items.add(newItem); });
          Navigator.pop(context);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFFFEBEE), 
      appBar: AppBar(
        title: const Text("Expiry / Breakage Return"),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => _handleSave(ph),
              child: const Text("SAVE AS BREAKAGE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          _buildWarningBanner(), 
          Expanded(
            child: selectedParty == null 
              ? _buildPartyPicker(ph) 
              : _buildReturnItemsList(ph),
          ),
          if (selectedParty != null) _buildSummaryFooter(),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 15),
      color: Colors.red.shade100,
      child: Row(
        children: [
          Icon(Icons.report_problem, size: 16, color: Colors.red.shade900),
          const SizedBox(width: 10),
          const Text("Items added here will NOT be added to Sellable Stock.", 
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(child: TextField(controller: returnNoC, decoration: const InputDecoration(labelText: "BREAKAGE NO", border: OutlineInputBorder(), isDense: true))),
          const SizedBox(width: 15),
          Expanded(
            child: InkWell(
              onTap: () async {
                DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: Provider.of<PharoahManager>(context, listen: false).currentFY, initialDate: selectedDate);
                if (p != null) setState(() => selectedDate = p);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(5)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat('dd/MM/yyyy').format(selectedDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Icon(Icons.calendar_today, color: Colors.red, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartyPicker(PharoahManager ph) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(15),
          child: TextField(
            decoration: const InputDecoration(hintText: "Customer Name...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            onChanged: (v) => setState(() => searchQuery = v),
          ),
        ),
        Expanded(
          child: ListView(
            children: ph.parties.where((p) => p.name.toLowerCase().contains(searchQuery.toLowerCase())).map((p) => ListTile(
              leading: const Icon(Icons.person),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => setState(() => selectedParty = p),
            )).toList(),
          ),
        )
      ],
    );
  }

  Widget _buildReturnItemsList(PharoahManager ph) {
    return Column(
      children: [
        ListTile(
          tileColor: Colors.red.withOpacity(0.05),
          title: Text(selectedParty!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          trailing: IconButton(onPressed: () => setState(() => selectedParty = null), icon: const Icon(Icons.close)),
        ),
        
        _buildSearchBarTrigger(ph),

        Expanded(
          child: items.isEmpty 
            ? const Center(child: Text("No items selected for return."))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                itemCount: items.length,
                itemBuilder: (c, i) => _buildItemCard(items[i], i),
              ),
        ),
      ],
    );
  }

  Widget _buildSearchBarTrigger(PharoahManager ph) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: InkWell(
        onTap: () => _showItemSearch(ph),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade300, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.red.shade700),
              const SizedBox(width: 10),
              Text("Tap here to search breakage item...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
              const Spacer(),
              Icon(Icons.add_circle, color: Colors.red.shade700),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemCard(BillItem it, int index) {
    final card = Card(
      elevation: 2, margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: Colors.red.shade50, child: Text("${it.srNo}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade900))),
        title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("Batch: ${it.batch} | Reason: Expiry/Breakage"),
        trailing: Text("₹${it.total.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      ),
    );

    return Dismissible(
      key: Key(it.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: Colors.red.shade900, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white, size: 28),
      ),
      onDismissed: (direction) {
        setState(() { items.removeAt(index); });
        _recalculateSR(); 
      },
      child: card,
    );
  }

  Widget _buildSummaryFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("NON-SELLABLE TOTAL:", style: TextStyle(fontWeight: FontWeight.bold)),
          Text("₹${totalAmt.toStringAsFixed(2)}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.red.shade900)),
        ],
      ),
    );
  }

  void _handleSave(PharoahManager ph) {
    ph.finalizeSaleReturn(
      billNo: returnNoC.text,
      date: selectedDate,
      party: selectedParty!,
      items: items,
      total: totalAmt,
      // type: "Breakage", <-- Ise delete kar dein ya rehne dein agar Manager update kar liya hai
    );
    
    if (ph.activeCompany != null) {
      PharoahNumberingEngine.updateSeriesCounter(
        type: "RETURN", 
        companyID: ph.activeCompany!.id, 
        usedNumber: returnNoC.text, 
        prefix: ph.getDefaultSeries("RETURN").prefix
      );
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("⚠️ Saved to Breakage/Expiry Stock!"), 
      backgroundColor: Colors.red.shade900
    ));
  }
}
