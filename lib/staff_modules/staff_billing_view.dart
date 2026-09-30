// FILE: lib/staff_modules/staff_billing_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import 'staff_item_entry_card.dart';
import '../pdf/pdf_router_service.dart'; // NAYA: Central Router Import

class StaffBillingView extends StatefulWidget {
  final Party party;
  final String billNo;
  final DateTime billDate;
  final String mode;

  const StaffBillingView({
    super.key,
    required this.party,
    required this.billNo,
    required this.billDate,
    required this.mode,
  });

  @override
  State<StaffBillingView> createState() => _StaffBillingViewState();
}

class _StaffBillingViewState extends State<StaffBillingView> {
  List<BillItem> items = [];
  double get totalAmt => items.fold(0, (sum, it) => sum + it.total);

  // NAYA: Serial Number Auto-Fixer for Staff
  void _recalculateSR() {
    setState(() {
      for (int i = 0; i < items.length; i++) {
        items[i] = items[i].copyWith(srNo: i + 1);
      }
    });
  }

  void _showItemSearch(PharoahManager ph, {BillItem? itemToEdit}) {
    String localSearch = "";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filteredMeds = ph.medicines
              .where((m) => m.name.toLowerCase().contains(localSearch.toLowerCase()))
              .toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F8E9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                      hintText: "Search Product for billing...",
                      prefixIcon: const Icon(Icons.search),
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
                      leading: const Icon(Icons.medication, color: Colors.teal),
                      title: Text(filteredMeds[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Pack: ${filteredMeds[i].packing} | Stock: ${filteredMeds[i].stock}"),
                      onTap: () {
                        Navigator.pop(context);
                        _showEntryCard(filteredMeds[i], itemToEdit);
                      },
                    ),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEntryCard(Medicine med, BillItem? itemToEdit) {
    showDialog(
      context: context,
      builder: (c) => StaffItemEntryCard(
        med: med,
        srNo: itemToEdit != null ? itemToEdit.srNo : items.length + 1,
        existingItem: itemToEdit,
        onAdd: (newItem) {
          setState(() {
            if (itemToEdit != null) {
              int idx = items.indexWhere((it) => it.id == itemToEdit.id);
              items[idx] = newItem;
            } else {
              items.add(newItem);
            }
          });
          Navigator.pop(context);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: Text("Invoice: ${widget.billNo}"),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: items.isEmpty ? null : () => _handleFinish(ph),
            child: const Text("FINISH & SAVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          _buildSearchBarTrigger(ph),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text("Cart is empty. Tap above to add items."))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    itemCount: items.length,
                    itemBuilder: (c, i) => _buildItemCard(items[i], i, ph),
                  ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  // --- UI COMPONENTS ---
  Widget _buildHeader() => Container(
    padding: const EdgeInsets.all(15), margin: const EdgeInsets.fromLTRB(10, 10, 10, 5),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(widget.party.name, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
      Text(DateFormat('dd/MM/yy').format(widget.billDate), style: const TextStyle(fontWeight: FontWeight.bold)),
    ]),
  );

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
            border: Border.all(color: Colors.teal.shade300, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.teal.shade700),
              const SizedBox(width: 10),
              Text("Tap here to search & add product...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
              const Spacer(),
              Icon(Icons.add_circle, color: Colors.teal.shade700),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemCard(BillItem it, int index, PharoahManager ph) {
    final card = Card(
      elevation: 2, margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: Colors.teal.shade50, child: Text("${it.srNo}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
        subtitle: Text("Batch: ${it.batch} | Qty: ${it.qty.toInt()} | Rate: ₹${it.rate.toStringAsFixed(2)}"),
        trailing: Text("₹${it.total.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
        onTap: () => _showItemSearch(ph, itemToEdit: it),
      ),
    );

    return Dismissible(
      key: Key(it.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
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

  Widget _buildFooter() => Container(
    padding: const EdgeInsets.all(20), color: Colors.white,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("GRAND TOTAL", style: TextStyle(fontWeight: FontWeight.bold)),
        Text("₹${totalAmt.toStringAsFixed(2)}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal)),
      ],
    ),
  );

  // REPLACE IN lib/staff_modules/staff_billing_view.dart -> _handleFinish() function
  void _handleFinish(PharoahManager ph) async {
    final newSale = Sale(
      id: DateTime.now().toString(),
      billNo: widget.billNo,
      partyId: widget.party.id, // ID Link
      date: widget.billDate,
      partyName: widget.party.name,
      partyGstin: widget.party.gst, 
      partyState: widget.party.state,
      items: items,
      totalAmount: totalAmt,
      paymentMode: widget.mode,
    );
    // ... baki code same rahega

    // 2. Finalize in Database
    await ph.finalizeSale(
      billNo: widget.billNo,
      date: widget.billDate,
      party: widget.party,
      items: items,
      total: totalAmt,
      mode: widget.mode,
    );

    // 3. NAYA: Prompt for Immediate Print (Router Integrated)
    if (mounted) {
      bool? doPrint = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Bill Saved!"),
          content: const Text("Do you want to print/share the invoice now?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("NO, LATER")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(c, true), 
              child: const Text("YES, PRINT")
            ),
          ],
        ),
      );

      if (doPrint == true) {
        // Universal Router Call: Automatically handles Thermal/Architect
        await PdfRouterService.printSale(
          sale: newSale, 
          party: widget.party, 
          ph: ph
        );
      }
    }

    Navigator.pop(context); // Close billing view
    Navigator.pop(context); // Close entry setup view
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Bill Processed Successfully!"), backgroundColor: Colors.green));
  }
}
