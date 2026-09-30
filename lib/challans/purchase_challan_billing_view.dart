// FILE: lib/challans/purchase_challan_billing_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../purchase/purchase_billing_view.dart'; 
import '../product_master.dart';
import '../pdf/pdf_router_service.dart'; 

class PurchaseChallanBillingView extends StatefulWidget {
  final Party distributor;
  final String internalNo;
  final String supplierChallanNo;
  final DateTime challanDate;
  final PurchaseChallan? existingRecord;
  final bool isReadOnly;

  const PurchaseChallanBillingView({
    super.key,
    required this.distributor,
    required this.internalNo,
    required this.supplierChallanNo,
    required this.challanDate,
    this.existingRecord,
    this.isReadOnly = false,
  });

  @override
  State<PurchaseChallanBillingView> createState() => _PurchaseChallanBillingViewState();
}

class _PurchaseChallanBillingViewState extends State<PurchaseChallanBillingView> {
  List<PurchaseItem> items = [];
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

  void _showItemSearchSheet(PharoahManager ph, {PurchaseItem? itemToEdit}) {
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
                color: Color(0xFFFFF8E1),
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
                                hintText: "Search Product for Inward...",
                                prefixIcon: const Icon(Icons.search, color: Colors.amber),
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
                                MaterialPageRoute(builder: (c) => const ProductMasterView(isSelectionMode: true)),
                              );
                              if (result != null && result is Medicine) {
                                setSheetState(() => selectedMed = result);
                              }
                            },
                            icon: const Icon(Icons.library_add_rounded),
                            style: IconButton.styleFrom(backgroundColor: Colors.amber.shade900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          )
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredMeds.length,
                        itemBuilder: (c, i) => ListTile(
                          leading: const Icon(Icons.inventory_2, color: Colors.amber),
                          title: Text(filteredMeds[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("Pack: ${filteredMeds[i].packing} | Stock: ${filteredMeds[i].stock}"),
                          onTap: () => setSheetState(() => selectedMed = filteredMeds[i]),
                        ),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: SingleChildScrollView(
                        child: PurchaseItemEntryCard(
                          med: selectedMed!,
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
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "View Items" : "Inward Note: ${widget.internalNo}"),
        backgroundColor: widget.isReadOnly ? Colors.purple.shade700 : Colors.amber.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded),
            onPressed: items.isEmpty ? null : () async {
              if (ph.activeCompany != null) {
                final tempChallan = PurchaseChallan(
                  id: "temp", 
                  internalNo: widget.internalNo, 
                  billNo: widget.supplierChallanNo, 
                  partyId: widget.distributor.id,
                  date: widget.challanDate, 
                  distributorName: widget.distributor.name, 
                  items: items, 
                  totalAmount: totalAmt, 
                  remarks: remarksC.text.trim()
                );
                await PdfRouterService.printChallan(
                  challan: tempChallan, 
                  party: widget.distributor, 
                  ph: ph, 
                  isSaleChallan: false 
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
            Text(widget.distributor.name, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
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
            border: Border.all(color: Colors.amber.shade400, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.amber.shade800),
              const SizedBox(width: 10),
              Text("Tap here to search & add inward stock...", style: TextStyle(color: Colors.brown.shade600, fontSize: 14)),
              const Spacer(),
              Icon(Icons.add_circle, color: Colors.amber.shade800),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemCard(PurchaseItem it, int index, PharoahManager ph) {
    final card = Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: Colors.amber.shade50, child: Text("${it.srNo}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900))),
        title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
        subtitle: Text("Batch: ${it.batch} | Qty: ${it.qty.toInt()} | Rate: ₹${it.purchaseRate.toStringAsFixed(2)}"),
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
                hintText: "Enter transport details or condition...",
                prefixIcon: const Icon(Icons.notes, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("NET INWARD VALUE", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("₹${totalAmt.toStringAsFixed(2)}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: widget.isReadOnly ? Colors.purple.shade900 : Colors.amber.shade900)),
              ],
            ),
          ],
        ),
      );

  void _handleSave(PharoahManager ph) {
    if (widget.existingRecord != null) {
      ph.deletePurchaseChallan(widget.existingRecord!.id);
    }
    ph.finalizePurchaseChallan(
      billNo: widget.supplierChallanNo,
      internalNo: widget.internalNo,
      date: widget.challanDate,
      party: widget.distributor,
      items: items,
      total: totalAmt,
      remarks: remarksC.text.trim(),
      partyId: widget.distributor.id,
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Purchase Challan Saved Successfully!"), backgroundColor: Colors.green));
  }
}
