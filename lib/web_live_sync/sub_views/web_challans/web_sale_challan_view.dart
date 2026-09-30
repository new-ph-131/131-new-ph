// FILE: lib/web_live_sync/sub_views/web_challans/web_sale_challan_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../web_app_date_logic.dart';
import '../../web_pharoah_numbering_engine.dart';
import '../web_billing/quick_add_party_modal.dart';
import 'web_sale_challan_billing_view.dart';

class WebSaleChallanView extends StatefulWidget {
  final SaleChallan? existingRecord;
  final bool isReadOnly;

  const WebSaleChallanView({super.key, this.existingRecord, this.isReadOnly = false});

  @override
  State<WebSaleChallanView> createState() => _WebSaleChallanViewState();
}

class _WebSaleChallanViewState extends State<WebSaleChallanView> {
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

  void _initChallanFlow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final webPh = Provider.of<PharoahWebManager>(context, listen: false);

      if (widget.existingRecord != null) {
        final ex = widget.existingRecord!;
        challanNoC.text = ex.billNo;
        selectedDate = ex.date;
        try {
          selectedParty = webPh.parties.firstWhere((p) => p.name == ex.partyName);
        } catch (e) {
          selectedParty = Party(id: "0", name: ex.partyName);
        }
        setState(() => isLoading = false);
      } else {
        String nextNo = WebPharoahNumberingEngine.getNextNumber(
          prefix: "SCH-",
          startFrom: 101,
          currentList: webPh.saleChallans,
        );
        setState(() {
          challanNoC.text = nextNo;
          selectedDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
          isLoading = false;
        });
      }
    });
  }

  void _openQuickAddCustomer(PharoahWebManager webPh) {
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        onPartyCreated: (newParty) {
          setState(() => selectedParty = newParty);
        },
      ),
    );
  }

  @override
  void dispose() {
    challanNoC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    if (isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF2DD4BF))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "View Sale Challan" : (widget.existingRecord != null ? "Modify Sale Challan" : "New Outward Challan")),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.white10, height: 1.0),
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              const SizedBox(height: 20),
              
              // --- 1. HEADER (CHALLAN NO & DATE) ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: challanNoC,
                        readOnly: true,
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2DD4BF), fontSize: 14),
                        decoration: InputDecoration(
                          labelText: "CHALLAN NUMBER",
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: InkWell(
                        onTap: widget.isReadOnly ? null : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: WebAppDateLogic.getFYStart(webPh.financialYear),
                            lastDate: WebAppDateLogic.getFYEnd(webPh.financialYear),
                          );
                          if (picked != null) setState(() => selectedDate = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("CHALLAN DATE", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(DateFormat('dd/MM/yyyy').format(selectedDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                              const Icon(Icons.calendar_month_rounded, color: Color(0xFF2DD4BF), size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("SELECT CUSTOMER / CONSIGNEE", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
              const SizedBox(height: 10),

              // --- 2. PARTY SELECTION ---
              Expanded(
                child: selectedParty != null ? _buildPartyCard() : _buildPartyList(webPh),
              ),

              // --- 3. PROCEED BUTTON ---
              if (selectedParty != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.isReadOnly ? Colors.purple : const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => WebSaleChallanBillingView(
                            party: selectedParty!,
                            challanNo: challanNoC.text,
                            challanDate: selectedDate,
                            existingRecord: widget.existingRecord,
                            isReadOnly: widget.isReadOnly,
                          ),
                        ),
                      );
                    },
                    icon: Icon(widget.isReadOnly ? Icons.visibility : Icons.arrow_forward_rounded, size: 20),
                    label: Text(
                      widget.isReadOnly ? "VIEW CHALLAN ITEMS" : "PROCEED TO ITEM ENTRY",
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPartyCard() => Card(
    color: const Color(0xFF1E293B),
    elevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF2DD4BF), width: 1.5)),
    child: ListTile(
      contentPadding: const EdgeInsets.all(20),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(color: Color(0x332DD4BF), shape: BoxShape.circle),
        child: const Icon(Icons.person_rounded, color: Color(0xFF2DD4BF)),
      ),
      title: Text(selectedParty!.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      subtitle: Text("${selectedParty!.city} | GST: ${selectedParty!.gst}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: widget.isReadOnly
          ? null
          : IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 28),
              onPressed: () => setState(() => selectedParty = null),
            ),
    ),
  );

  Widget _buildPartyList(PharoahWebManager webPh) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: "Search Customer by Name...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF2DD4BF)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _openQuickAddCustomer(webPh),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text("NEW CUSTOMER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: webPh.parties
                .where((p) => p.group == "Sundry Debtors" && p.name.toLowerCase().contains(searchQuery.toLowerCase()))
                .map((p) => Container(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                      child: ListTile(
                        leading: const Icon(Icons.business_outlined, color: Colors.white38),
                        title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(p.city, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        onTap: () => setState(() => selectedParty = p),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    ],
  );
}
