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
  final VoidCallback onBack;
  final SaleChallan? existingRecord;
  final bool isReadOnly;

  const WebSaleChallanView({
    super.key,
    required this.onBack,
    this.existingRecord,
    this.isReadOnly = false,
  });

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
          selectedParty = webPh.parties.firstWhere((p) => p.id == ex.partyId || p.name == ex.partyName);
        } catch (_) {
          selectedParty = Party(id: ex.partyId, name: ex.partyName, gst: ex.partyGstin, state: ex.partyState);
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
      return const Center(child: CircularProgressIndicator(color: Color(0xFF2DD4BF)));
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 820),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Navigation
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK TO CHALLANS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.local_shipping_rounded, color: Color(0xFF2DD4BF), size: 24),
              const SizedBox(width: 10),
              Text(
                widget.isReadOnly ? "VIEW SALE CHALLAN" : (widget.existingRecord != null ? "MODIFY SALE CHALLAN" : "NEW OUTWARD CHALLAN"),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Header Box: Challan Number & Date
          Container(
            padding: const EdgeInsets.all(18),
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
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: widget.isReadOnly
                        ? null
                        : () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: WebAppDateLogic.getFYStart(webPh.financialYear),
                              lastDate: WebAppDateLogic.getFYEnd(webPh.financialYear),
                            );
                            if (picked != null) setState(() => selectedDate = picked);
                          },
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("DISPATCH DATE", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                              Text(DateFormat('dd/MM/yyyy').format(selectedDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
          const SizedBox(height: 22),

          const Text(
            "SELECT CUSTOMER / CONSIGNEE",
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),

          // Party Area
          Expanded(
            child: selectedParty != null ? _buildSelectedPartyCard() : _buildPartySearchList(webPh),
          ),

          // Bottom Gateway Button: PROCEED TO ITEM ENTRY
          if (selectedParty != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 15),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => WebSaleChallanBillingView(
                        party: selectedParty!,
                        challanNo: challanNoC.text.trim(),
                        challanDate: selectedDate,
                        existingRecord: widget.existingRecord,
                        isReadOnly: widget.isReadOnly,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: Text(
                  widget.isReadOnly ? "VIEW DISPATCH ITEMS ➔" : "PROCEED TO ITEM ENTRY ➔",
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedPartyCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF2DD4BF), width: 1.5),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(color: Color(0x332DD4BF), shape: BoxShape.circle),
          child: const Icon(Icons.person_rounded, color: Color(0xFF2DD4BF), size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(selectedParty!.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 4),
              Text("${selectedParty!.city} | GST: ${selectedParty!.gst} | State: ${selectedParty!.state}", style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
            ],
          ),
        ),
        if (!widget.isReadOnly)
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 26),
            tooltip: "Change Customer",
            onPressed: () => setState(() => selectedParty = null),
          ),
      ],
    ),
  );

  Widget _buildPartySearchList(PharoahWebManager webPh) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
              decoration: InputDecoration(
                hintText: "Search Customer by Name, City or GSTIN...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF2DD4BF), size: 18),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _openQuickAddCustomer(webPh),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text("NEW CUSTOMER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: webPh.parties
                .where((p) => p.group == "Sundry Debtors" && (p.name.toLowerCase().contains(searchQuery.toLowerCase()) || p.city.toLowerCase().contains(searchQuery.toLowerCase())))
                .map((p) => Container(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline_rounded, color: Colors.white38),
                        title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text("${p.city} | GST: ${p.gst}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
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
