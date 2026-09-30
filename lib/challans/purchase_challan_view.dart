// FILE: lib/challans/purchase_challan_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../logic/pharoah_numbering_engine.dart';
import '../party_master.dart';
import '../pharoah_date_controller.dart';
import 'purchase_challan_billing_view.dart'; // Nayi file jo hum aage banayenge

class PurchaseChallanView extends StatefulWidget {
  final PurchaseChallan? existingRecord;
  final bool isReadOnly;

  const PurchaseChallanView({super.key, this.existingRecord, this.isReadOnly = false});

  @override
  State<PurchaseChallanView> createState() => _PurchaseChallanViewState();
}

class _PurchaseChallanViewState extends State<PurchaseChallanView> {
  final supplierChallanNoC = TextEditingController();
  final internalNoC = TextEditingController();
  DateTime selectedDate = DateTime.now();
  Party? selectedDistributor;
  String searchQuery = "";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initInwardFlow();
  }

  void _initInwardFlow() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);

    if (widget.existingRecord != null) {
      final ex = widget.existingRecord!;
      internalNoC.text = ex.internalNo;
      supplierChallanNoC.text = ex.billNo;
      selectedDate = ex.date;
      
      try {
        selectedDistributor = ph.parties.firstWhere((p) => p.name == ex.distributorName);
      } catch (e) {
        selectedDistributor = Party(id: "0", name: ex.distributorName);
      }
      setState(() => isLoading = false);
    } else {
      if (ph.activeCompany != null) {
        String nextNo = await PharoahNumberingEngine.getNextNumber(
          type: "CHALLAN_PUR", // <--- Ise badal kar "CHALLAN_PUR" kar dein
          companyID: ph.activeCompany!.id,
          prefix: "PCH-", 
          startFrom: 1,
          currentList: ph.purchaseChallans,
        );
        setState(() {
          internalNoC.text = nextNo;
          selectedDate = PharoahDateController.getInitialBillDate(ph.currentFY);
          isLoading = false;
        });
      }
    }
  }

  Future<void> _handleQuickAddSupplier() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (c) => const PartyMasterView(isSelectionMode: true)),
    );
    if (result != null && result is Party) {
      setState(() { selectedDistributor = result; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "View Purchase Challan" : (widget.existingRecord != null ? "Modify Purchase Challan" : "New Purchase Challan")),
        backgroundColor: widget.isReadOnly ? Colors.purple.shade700 : Colors.amber.shade900,
        foregroundColor: Colors.white,
      ),
      body: IgnorePointer(
        ignoring: widget.isReadOnly,
        child: Column(
          children: [
            // --- HEADER: CHALLAN NO & DATE ---
            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.white,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: internalNoC, 
                          readOnly: true, 
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                          decoration: const InputDecoration(labelText: "INWARD ID", border: OutlineInputBorder(), filled: true, fillColor: Color(0xFFF5F5F5))
                        )
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: supplierChallanNoC, 
                          textCapitalization: TextCapitalization.characters, 
                          decoration: const InputDecoration(labelText: "SUPPLIER REF NO", border: OutlineInputBorder(), filled: true, fillColor: Colors.white)
                        )
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  InkWell(
                    onTap: () async {
                      DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: ph.currentFY, initialDate: selectedDate);
                      if (p != null) setState(() => selectedDate = p);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(5)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("DATE: ${DateFormat('dd/MM/yyyy').format(selectedDate)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Icon(Icons.calendar_month, color: Colors.amber, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("SELECT DISTRIBUTOR / SUPPLIER", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 12, letterSpacing: 1))
              ),
            ),

            // --- DISTRIBUTOR SELECTION ---
            Expanded(
              child: selectedDistributor != null 
                ? _buildSupplierCard() 
                : _buildSupplierList(ph),
            ),

            // --- PROCEED BUTTON ---
            if (selectedDistributor != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                    backgroundColor: widget.isReadOnly ? Colors.purple : Colors.amber.shade900,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  onPressed: () {
                    if (supplierChallanNoC.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter Supplier Ref No!"), backgroundColor: Colors.red));
                      return;
                    }
                    Navigator.push(context, MaterialPageRoute(builder: (c) => PurchaseChallanBillingView(
                      distributor: selectedDistributor!,
                      internalNo: internalNoC.text,
                      supplierChallanNo: supplierChallanNoC.text.trim(),
                      challanDate: selectedDate,
                      existingRecord: widget.existingRecord,
                      isReadOnly: widget.isReadOnly,
                    )));
                  },
                  child: Text(widget.isReadOnly ? "VIEW ITEMS LIST" : "PROCEED TO ITEM ENTRY", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierCard() => Card(
    elevation: 4, margin: const EdgeInsets.symmetric(horizontal: 15),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.amber.shade200, width: 1)),
    child: ListTile(
      contentPadding: const EdgeInsets.all(15),
      leading: const CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.business, color: Colors.white)),
      title: Text(selectedDistributor!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), 
      subtitle: Text("${selectedDistributor!.city} | GST: ${selectedDistributor!.gst}"), 
      trailing: widget.isReadOnly ? null : IconButton(icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 28), onPressed: () => setState(() => selectedDistributor = null))
    )
  );

  Widget _buildSupplierList(PharoahManager ph) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Search Distributor...", 
                  prefixIcon: const Icon(Icons.search, color: Colors.amber), 
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true, fillColor: Colors.white
                ), 
                onChanged: (v) => setState(() => searchQuery = v)
              )
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: _handleQuickAddSupplier, 
              icon: const Icon(Icons.person_add_alt_1), 
              style: IconButton.styleFrom(backgroundColor: Colors.amber.shade900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))
            ),
          ]
        )
      ),
      const SizedBox(height: 10),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: ph.parties.where((p) => p.group == "Sundry Creditors" && p.name.toLowerCase().contains(searchQuery.toLowerCase())).map((p) => ListTile(
            leading: const Icon(Icons.business_outlined, color: Colors.grey),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(p.city),
            onTap: () => setState(() => selectedDistributor = p),
          )).toList(),
        ),
      )
    ],
  );
}
