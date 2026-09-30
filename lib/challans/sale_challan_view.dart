// FILE: lib/challans/sale_challan_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../logic/pharoah_numbering_engine.dart';
import '../party_master.dart';
import '../pharoah_date_controller.dart';
import 'sale_challan_billing_view.dart'; // Nayi file jo hum agle step me banayenge

class SaleChallanView extends StatefulWidget {
  final SaleChallan? existingRecord; 
  final bool isReadOnly;

  const SaleChallanView({super.key, this.existingRecord, this.isReadOnly = false});

  @override
  State<SaleChallanView> createState() => _SaleChallanViewState();
}

class _SaleChallanViewState extends State<SaleChallanView> {
  final challanNoC = TextEditingController();
  DateTime selectedDate = DateTime.now();
  Party? selectedParty;
  String searchQuery = "";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initChallanFlow();
  }

  void _initChallanFlow() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    
    if (widget.existingRecord != null) {
      final ex = widget.existingRecord!;
      challanNoC.text = ex.billNo;
      selectedDate = ex.date;
      
      try {
        selectedParty = ph.parties.firstWhere((p) => p.name == ex.partyName);
      } catch (e) {
        selectedParty = Party(id: "0", name: ex.partyName);
      }
      setState(() => isLoading = false);
    } else {
      if (ph.activeCompany != null) {
        var series = ph.getDefaultSeries("CHALLAN");
        
        String nextNo = await PharoahNumberingEngine.getNextNumber(
          type: "CHALLAN",
          companyID: ph.activeCompany!.id,
          prefix: series.prefix,
          startFrom: series.startNumber,
          currentList: ph.saleChallans,
        );
        
        setState(() {
          challanNoC.text = nextNo;
          selectedDate = PharoahDateController.getInitialBillDate(ph.currentFY);
          isLoading = false;
        });
      }
    }
  }

  Future<void> _handleQuickAddParty() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (c) => const PartyMasterView(isSelectionMode: true)),
    );
    if (result != null && result is Party) {
      setState(() { selectedParty = result; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "View Sale Challan" : (widget.existingRecord != null ? "Modify Sale Challan" : "New Outward Challan")),
        backgroundColor: widget.isReadOnly ? Colors.purple.shade700 : Colors.blueGrey.shade800,
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: challanNoC,
                      readOnly: true, 
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                      decoration: const InputDecoration(
                        labelText: "CHALLAN NO", 
                        border: OutlineInputBorder(), 
                        filled: true,
                        fillColor: Color(0xFFF5F5F5)
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: InkWell(
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
                            Text(DateFormat('dd/MM/yyyy').format(selectedDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                            const Icon(Icons.calendar_month, color: Colors.blueGrey, size: 18),
                          ],
                        ),
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
                child: Text("SELECT PARTY / CUSTOMER", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12, letterSpacing: 1))
              ),
            ),

            // --- PARTY SELECTION ---
            Expanded(
              child: selectedParty != null 
                ? _buildPartyCard() 
                : _buildPartyList(ph),
            ),

            // --- PROCEED BUTTON ---
            if (selectedParty != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                    backgroundColor: widget.isReadOnly ? Colors.purple : Colors.blueGrey.shade800,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => SaleChallanBillingView(
                      party: selectedParty!,
                      challanNo: challanNoC.text,
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

  Widget _buildPartyCard() => Card(
    elevation: 4, margin: const EdgeInsets.symmetric(horizontal: 15),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.blueGrey.shade200, width: 1)),
    child: ListTile(
      contentPadding: const EdgeInsets.all(15),
      leading: const CircleAvatar(backgroundColor: Colors.blueGrey, child: Icon(Icons.person, color: Colors.white)),
      title: Text(selectedParty!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), 
      subtitle: Text("${selectedParty!.city} | GST: ${selectedParty!.gst}"), 
      trailing: widget.isReadOnly ? null : IconButton(icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 28), onPressed: () => setState(() => selectedParty = null))
    )
  );

  Widget _buildPartyList(PharoahManager ph) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Search Party by Name...", 
                  prefixIcon: const Icon(Icons.search, color: Colors.blueGrey), 
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true, fillColor: Colors.white
                ), 
                onChanged: (v) => setState(() => searchQuery = v)
              )
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: _handleQuickAddParty, 
              icon: const Icon(Icons.person_add_alt_1), 
              style: IconButton.styleFrom(backgroundColor: Colors.blueGrey.shade800, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))
            ),
          ]
        )
      ),
      const SizedBox(height: 10),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: ph.parties.where((p) => p.name.toLowerCase().contains(searchQuery.toLowerCase())).map((p) => ListTile(
            leading: const Icon(Icons.business_outlined, color: Colors.grey),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(p.city),
            onTap: () => setState(() => selectedParty = p),
          )).toList(),
        ),
      )
    ],
  );
}
