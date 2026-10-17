// FILE: lib/purchase/purchase_entry_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../party_master.dart';
import '../pharoah_date_controller.dart'; 
import '../logic/pharoah_numbering_engine.dart';
import 'purchase_billing_view.dart';

class PurchaseEntryView extends StatefulWidget {
  final Purchase? existingPurchase;
  final bool isReadOnly; 

  const PurchaseEntryView({super.key, this.existingPurchase, this.isReadOnly = false});

  @override State<PurchaseEntryView> createState() => _PurchaseEntryViewState();
}

class _PurchaseEntryViewState extends State<PurchaseEntryView> {
  final supplierBillNoC = TextEditingController(); 
  final internalEntryNoC = TextEditingController();
  DateTime selectedBillDate = DateTime.now(); 
  DateTime selectedEntryDate = DateTime.now();
  String paymentMode = "CREDIT"; 
  Party? selectedDistributor; 
  String distSearchQuery = "";
  bool isLoading = true;

  @override void initState() {
    super.initState();
    _initializePurchaseSession();
  }

  // ===========================================================================
  // SESSION INITIALIZATION (Smart Numbering & Date)
  // ===========================================================================
  void _initializePurchaseSession() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ph = Provider.of<PharoahManager>(context, listen: false);
      
      if (widget.existingPurchase != null) {
        // CASE: Modification Mode
        setState(() {
          supplierBillNoC.text = widget.existingPurchase!.billNo;
          internalEntryNoC.text = widget.existingPurchase!.internalNo;
          selectedBillDate = widget.existingPurchase!.date;
          selectedEntryDate = widget.existingPurchase!.entryDate;
          paymentMode = widget.existingPurchase!.paymentMode;
          try {
            selectedDistributor = ph.parties.firstWhere(
              (p) => (widget.existingPurchase!.partyId.isNotEmpty && p.id == widget.existingPurchase!.partyId) ||
                     p.name.trim().toUpperCase() == widget.existingPurchase!.distributorName.trim().toUpperCase()
            );
          } catch(e) {
            selectedDistributor = Party(
              id: widget.existingPurchase!.partyId.isNotEmpty ? widget.existingPurchase!.partyId : '0',
              name: widget.existingPurchase!.distributorName,
              group: "Sundry Creditors",
            );
          }
          isLoading = false;
        });
      } else {
        // CASE: New Entry Mode (Get Next Sequential ID)
        if (ph.activeCompany != null) {
          String nextPurNo = await PharoahNumberingEngine.getNextNumber(
            type: "PURCHASE",
            companyID: ph.activeCompany!.id,
            prefix: "PUR-", // Purchase always uses internal sequence
            startFrom: 1,
            currentList: ph.purchases,
          );
          
          DateTime smartDate = PharoahDateController.getInitialBillDate(ph.currentFY);
          setState(() {
            internalEntryNoC.text = nextPurNo;
            selectedBillDate = smartDate;
            selectedEntryDate = smartDate;
            isLoading = false;
          });
        }
      }
    });
  }

  bool showOnlyCreditors = false;

  Future<void> _handleQuickAddSupplier() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => const PartyMasterView(
          isSelectionMode: true,
          preFillData: {'group': 'Sundry Creditors'},
        ),
      ),
    );
    if (result != null && result is Party) {
      setState(() {
        selectedDistributor = result;
      });
    }
  }

  @override Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "View Purchase" : (widget.existingPurchase != null ? "Modify Purchase" : "Purchase Inward Entry")), 
        backgroundColor: widget.isReadOnly ? Colors.purple.shade700 : Colors.orange.shade800, 
        foregroundColor: Colors.white
      ),
      body: IgnorePointer(
        ignoring: widget.isReadOnly,
        child: Column(children: [
          // --- HEADER SECTION: IDS & DATES ---
          Container(padding: const EdgeInsets.all(20), color: Colors.white, child: Column(children: [
            Row(children: [
              Expanded(child: TextField(controller: internalEntryNoC, readOnly: true, decoration: const InputDecoration(labelText: "INTERNAL ID", border: OutlineInputBorder(), filled: true, fillColor: Color(0xFFF5F5F5)))),
              const SizedBox(width: 15),
              Expanded(child: TextField(controller: supplierBillNoC, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: "SUPPLIER BILL NO", border: OutlineInputBorder(), hintText: "Enter Bill #"))),
            ]),
            const SizedBox(height: 15),
            Row(children: [
              Expanded(child: InkWell(
                onTap: () async { 
                  DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: ph.currentFY, initialDate: selectedBillDate);
                  if (p != null) setState(() => selectedBillDate = p); 
                }, 
                child: _dateDisplay("BILL DATE", selectedBillDate, Colors.orange)
              )),
              const SizedBox(width: 10),
              Expanded(child: InkWell(
                onTap: () async { 
                  DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: ph.currentFY, initialDate: selectedEntryDate);
                  if (p != null) setState(() => selectedEntryDate = p); 
                }, 
                child: _dateDisplay("STOCK ENTRY DATE", selectedEntryDate, Colors.blue)
              )),
            ]),
          ])),

          // --- PAYMENT MODE ---
          Padding(
            padding: const EdgeInsets.all(15),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'CASH', label: Text('CASH'), icon: Icon(Icons.money)), 
                ButtonSegment(value: 'CREDIT', label: Text('CREDIT'), icon: Icon(Icons.credit_card))
              ], 
              selected: {paymentMode}, 
              onSelectionChanged: (v) => setState(() => paymentMode = v.first)
            ),
          ),

          // --- SUPPLIER SELECTION ---
          Expanded(child: selectedDistributor != null ? _buildSupplierCard() : _buildSearchList(ph)),

          if (selectedDistributor != null) Padding(
            padding: const EdgeInsets.all(20), 
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60), backgroundColor: widget.isReadOnly ? Colors.purple : Colors.orange.shade800, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), 
              onPressed: () {
                  if (supplierBillNoC.text.isEmpty) {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Supplier Bill No is required!"), backgroundColor: Colors.red));
                     return;
                  }
                  Navigator.push(context, MaterialPageRoute(builder: (c) => PurchaseBillingView(
                    distributor: selectedDistributor!, 
                    internalNo: internalEntryNoC.text, 
                    distBillNo: supplierBillNoC.text.trim(), 
                    billDate: selectedBillDate, 
                    entryDate: selectedEntryDate, 
                    mode: paymentMode, 
                    existingItems: widget.existingPurchase?.items, 
                    modifyPurchaseId: widget.existingPurchase?.id,
                    isReadOnly: widget.isReadOnly,
                    // NAYA: Purane bill se challan links utha kar aage bhej rahe hain
                    linkedChallanIds: widget.existingPurchase?.linkedChallanIds, 
                  )));
                }, 
              child: Text(widget.isReadOnly ? "VIEW PURCHASED ITEMS" : "PROCEED TO ITEM ENTRY", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
            )
          )
        ]),
      ),
    );
  }

  Widget _dateDisplay(String l, DateTime d, Color c) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(5)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: TextStyle(fontSize: 8, color: c, fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text(DateFormat('dd/MM/yyyy').format(d), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))]));
  
  Widget _buildSupplierCard() => Card(
    margin: const EdgeInsets.symmetric(horizontal: 15), elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.orange.shade100, width: 1)),
    child: ListTile(
      leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.business, color: Colors.white)),
      title: Text(selectedDistributor!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
      subtitle: Text("${selectedDistributor!.city} | GST: ${selectedDistributor!.gst}"), 
      trailing: widget.isReadOnly ? null : IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() => selectedDistributor = null))
    )
  );

  bool _isCreditorGroup(String group) {
    final g = group.trim().toLowerCase();
    return g.contains("creditor") || g.contains("supplier") || g.contains("vendor") || g.contains("distributor");
  }

  bool _isSystemNonParty(Party p) {
    final nameUpper = p.name.trim().toUpperCase();
    final grpLower = p.group.trim().toLowerCase();
    if (nameUpper == "CASH") return true;
    if (grpLower == "bank accounts" || grpLower == "cash in hand" || grpLower == "expenses") return true;
    return false;
  }

  Widget _buildSearchList(PharoahManager ph) {
    final q = distSearchQuery.trim().toLowerCase();
    final filteredParties = ph.parties.where((p) {
      if (_isSystemNonParty(p)) return false;
      if (showOnlyCreditors && !_isCreditorGroup(p.group)) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
             p.city.toLowerCase().contains(q) ||
             p.gst.toLowerCase().contains(q) ||
             p.group.toLowerCase().contains(q);
    }).toList();

    // Sort so Sundry Creditors always appear first, then alphabetical by name
    filteredParties.sort((a, b) {
      final aCred = _isCreditorGroup(a.group);
      final bCred = _isCreditorGroup(b.group);
      if (aCred != bCred) return aCred ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: "Search Supplier / Party by Name, City or GST...",
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => distSearchQuery = v),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(
                  showOnlyCreditors ? "Creditors Only" : "All Parties (${filteredParties.length})",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: showOnlyCreditors ? Colors.white : Colors.orange.shade900,
                  ),
                ),
                selected: showOnlyCreditors,
                selectedColor: Colors.orange.shade800,
                checkmarkColor: Colors.white,
                backgroundColor: Colors.orange.shade50,
                onSelected: (val) => setState(() => showOnlyCreditors = val),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _handleQuickAddSupplier,
                icon: const Icon(Icons.group_add_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: filteredParties.isEmpty
              ? Center(
                  child: Text(
                    "No matching supplier/party found in Party Register.",
                    style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  itemCount: filteredParties.length,
                  itemBuilder: (context, index) {
                    final p = filteredParties[index];
                    final isCred = _isCreditorGroup(p.group);
                    return Card(
                      elevation: 0.5,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: isCred ? Colors.orange.shade100 : Colors.indigo.shade50,
                          child: Icon(
                            isCred ? Icons.local_shipping_rounded : Icons.storefront_rounded,
                            size: 16,
                            color: isCred ? Colors.orange.shade900 : Colors.indigo,
                          ),
                        ),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(
                          "${p.city.isNotEmpty ? p.city : p.state} | GST: ${p.gst.isNotEmpty ? p.gst : 'N/A'}",
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isCred ? Colors.orange.shade50 : Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isCred ? Colors.orange.shade300 : Colors.indigo.shade200,
                            ),
                          ),
                          child: Text(
                            isCred ? "CREDITOR" : "DEBTOR",
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: isCred ? Colors.orange.shade900 : Colors.indigo.shade800,
                            ),
                          ),
                        ),
                        onTap: () => setState(() => selectedDistributor = p),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
