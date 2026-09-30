// FILE: lib/challans/sale_challan_billing_view.dart
import 'challan_signature_view.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../item_entry_card.dart';
import '../product_master.dart';
import '../pdf/pdf_router_service.dart';

class SaleChallanBillingView extends StatefulWidget {
  final Party party;
  final String challanNo;
  final DateTime challanDate;
  final SaleChallan? existingRecord;
  final bool isReadOnly;

  const SaleChallanBillingView({
    super.key,
    required this.party,
    required this.challanNo,
    required this.challanDate,
    this.existingRecord,
    this.isReadOnly = false,
  });

  @override
  State<SaleChallanBillingView> createState() => _SaleChallanBillingViewState();
}

class _SaleChallanBillingViewState extends State<SaleChallanBillingView> {
  List<BillItem> items = [];
  final remarksC = TextEditingController();

  double get totalAmt => items.fold(0, (sum, it) => sum + it.total);

  @override
  void initState() {
    super.initState();
    if (widget.existingRecord != null) {
      items = List.from(widget.existingRecord!.items);
      remarksC.text = widget.existingRecord!.remarks;
    }
  }

  void _recalculateSR() {
    setState(() {
      for (int i = 0; i < items.length; i++) {
        items[i] = items[i].copyWith(srNo: i + 1);
      }
    });
  }

  void _showItemSearchSheet(PharoahManager ph, {BillItem? itemToEdit}) {
    if (widget.isReadOnly) return;

    String localSearch = "";
    Medicine? selectedMed;
    if (itemToEdit != null) {
      try {
        selectedMed = ph.medicines.firstWhere((m) => m.id == itemToEdit.medicineID);
      } catch (e) { selectedMed = null; }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filteredMeds = ph.medicines
              .where((m) => m.name.toLowerCase().contains(localSearch.toLowerCase()))
              .toList();

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Color(0xFFECEFF1), 
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 10),
                    height: 5, width: 50,
                    decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10)),
                  ),
                  if (selectedMed == null) ...[
                    Padding(
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: "Search Product for Challan...",
                                prefixIcon: const Icon(Icons.search),
                                filled: true, fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onChanged: (v) => setSheetState(() => localSearch = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filled(
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (c) => ProductMasterView(isSelectionMode: true)),
                              );
                              if (result != null && result is Medicine) {
                                setSheetState(() => selectedMed = result);
                              }
                            },
                            icon: const Icon(Icons.add_box_rounded),
                            style: IconButton.styleFrom(backgroundColor: Colors.blueGrey.shade800, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          )
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredMeds.length,
                        itemBuilder: (c, i) => ListTile(
                          leading: const Icon(Icons.inventory, color: Colors.blueGrey),
                          title: Text(filteredMeds[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("Pack: ${filteredMeds[i].packing} | Stock: ${filteredMeds[i].stock}"),
                          onTap: () => setSheetState(() => selectedMed = filteredMeds[i]),
                        ),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: SingleChildScrollView(
                        child: ItemEntryCard(
                          med: selectedMed!,
                          srNo: itemToEdit != null ? itemToEdit.srNo : items.length + 1,
                          partyState: widget.party.state, // NAYA: Added partyState
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
                          onCancel: () => itemToEdit != null ? Navigator.pop(context) : setSheetState(() => selectedMed = null),
                        ),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFECEFF1),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "View Items" : "Challan: ${widget.challanNo}"),
        backgroundColor: widget.isReadOnly ? Colors.purple.shade700 : Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded),
            onPressed: items.isEmpty ? null : () async {
              if (ph.activeCompany != null) {
                final tempChallan = SaleChallan(
                  id: "temp", 
                  billNo: widget.challanNo, 
                  partyId: widget.party.id, // ID Link Added
                  date: widget.challanDate, 
                  partyName: widget.party.name, 
                  partyGstin: widget.party.gst, 
                  partyState: widget.party.state, 
                  items: items, 
                  totalAmount: totalAmt, 
                  remarks: remarksC.text.trim()
                );
                await PdfRouterService.printChallan(
                  challan: tempChallan, 
                  party: widget.party, 
                  ph: ph, 
                  isSaleChallan: true
                );
              }
            },
          ),
          if (!widget.isReadOnly)
            TextButton(
              onPressed: items.isEmpty ? null : () => _handleSave(ph),
              child: const Text("FINISH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          if (!widget.isReadOnly) _buildSearchBarTrigger(ph),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text("Cart is empty"))
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

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.all(15),
        margin: const EdgeInsets.fromLTRB(10, 10, 10, 5),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.party.name, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800)),
            Text(DateFormat('dd/MM/yyyy').format(widget.challanDate), style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _buildSearchBarTrigger(PharoahManager ph) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: InkWell(
        onTap: () => _showItemSearchSheet(ph),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blueGrey.shade300, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.blueGrey.shade700),
              const SizedBox(width: 10),
              Text("Tap here to add product...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
              const Spacer(),
              Icon(Icons.add_circle, color: Colors.blueGrey.shade700),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemCard(BillItem it, int index, PharoahManager ph) {
    final card = Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: Colors.blueGrey.shade50, child: Text("${it.srNo}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        subtitle: Text("Batch: ${it.batch} | Qty: ${it.qty.toInt()} | Rate: ₹${it.rate.toStringAsFixed(2)}"),
        trailing: Text("₹${it.total.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
        onTap: widget.isReadOnly ? null : () => _showItemSearchSheet(ph, itemToEdit: it),
      ),
    );

    if (widget.isReadOnly) return card;

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
        padding: const EdgeInsets.all(15),
        color: Colors.white,
        child: Column(
          children: [
            TextField(
              controller: remarksC,
              readOnly: widget.isReadOnly,
              decoration: InputDecoration(
                labelText: "Remarks / Notes (Optional)",
                hintText: "Enter dispatch details or vehicle info...",
                prefixIcon: const Icon(Icons.notes, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("NET CHALLAN VALUE", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("₹${totalAmt.toStringAsFixed(2)}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: widget.isReadOnly ? Colors.purple.shade900 : Colors.blueGrey.shade900)),
              ],
            ),
          ],
        ),
      );

void _handleSave(PharoahManager ph) async {
    if (widget.existingRecord != null) {
      ph.deleteSaleChallan(widget.existingRecord!.id);
    }

    // 🆕 TWO-WAY SYNC TRIGGER: Direct list add ke bajaye finalizer call karein
    ph.finalizeSaleChallan(
      billNo: widget.challanNo,
      date: widget.challanDate,
      party: widget.party,
      items: items,
      total: totalAmt,
      remarks: remarksC.text.trim(),
      partyId: widget.party.id,
    );

    // Dynamic fetch of newly created challan record
    final createdChallan = ph.saleChallans.last;

    if (ph.config.showCustomerSignChallan == true) {
      if (mounted) {
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (c) => ChallanSignatureView(
            challan: createdChallan, 
            party: widget.party
          ))
        );
      }
    } else {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Sale Challan Saved Successfully!"), backgroundColor: Colors.green)
        );
      }
    }
  }
}
