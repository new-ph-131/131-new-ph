// FILE: lib/web_live_sync/sub_views/web_challans/web_purchase_challan_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../web_app_date_logic.dart';
import '../../web_pharoah_numbering_engine.dart';
import '../web_billing/quick_add_party_modal.dart';
import 'web_purchase_challan_billing_view.dart';

class WebPurchaseChallanView extends StatefulWidget {
  final PurchaseChallan? existingRecord;
  final bool isReadOnly;

  const WebPurchaseChallanView({super.key, this.existingRecord, this.isReadOnly = false});

  @override
  State<WebPurchaseChallanView> createState() => _WebPurchaseChallanViewState();
}

class _WebPurchaseChallanViewState extends State<WebPurchaseChallanView> {
  final internalNoC = TextEditingController();
  final supplierRefC = TextEditingController();
  DateTime selectedDate = DateTime.now();
  Party? selectedSupplier;
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
        internalNoC.text = ex.internalNo;
        supplierRefC.text = ex.billNo;
        selectedDate = ex.date;
        try {
          selectedSupplier = webPh.parties.firstWhere((p) => p.name == ex.distributorName);
        } catch (e) {
          selectedSupplier = Party(id: "0", name: ex.distributorName);
        }
        setState(() => isLoading = false);
      } else {
        String nextNo = WebPharoahNumberingEngine.getNextNumber(
          prefix: "PCH-",
          startFrom: 1,
          currentList: webPh.purchaseChallans,
        );
        setState(() {
          internalNoC.text = nextNo;
          selectedDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
          isLoading = false;
        });
      }
    });
  }

  void _openQuickAddSupplier(PharoahWebManager webPh) {
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        onPartyCreated: (newParty) {
          setState(() => selectedSupplier = newParty);
        },
      ),
    );
  }

  @override
  void dispose() {
    internalNoC.dispose();
    supplierRefC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    if (isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "View Purchase Challan" : (widget.existingRecord != null ? "Modify Purchase Challan" : "New Inward Challan")),
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
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: internalNoC,
                            readOnly: true,
                            style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFF59E0B), fontSize: 14),
                            decoration: InputDecoration(
                              labelText: "INTERNAL INWARD ID",
                              labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                              filled: true,
                              fillColor: Colors.black26,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: TextField(
                            controller: supplierRefC,
                            readOnly: widget.isReadOnly,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: "SUPPLIER REF / CHALLAN NO *",
                              labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                              filled: true,
                              fillColor: widget.isReadOnly ? Colors.black26 : const Color(0x33F59E0B),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    InkWell(
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
                                const Text("INWARD DATE", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(DateFormat('dd/MM/yyyy').format(selectedDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const Icon(Icons.calendar_month_rounded, color: Color(0xFFF59E0B), size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("SELECT SUPPLIER / DISTRIBUTOR", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
              const SizedBox(height: 10),

              // --- 2. PARTY SELECTION ---
              Expanded(
                child: selectedSupplier != null ? _buildSupplierCard() : _buildSupplierList(webPh),
              ),

              // --- 3. PROCEED BUTTON ---
              if (selectedSupplier != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.isReadOnly ? Colors.purple : const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      if (supplierRefC.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Supplier Ref / Challan No is required!"), backgroundColor: Colors.red));
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => WebPurchaseChallanBillingView(
                            supplier: selectedSupplier!,
                            internalNo: internalNoC.text,
                            supplierRefNo: supplierRefC.text.trim(),
                            challanDate: selectedDate,
                            existingRecord: widget.existingRecord,
                            isReadOnly: widget.isReadOnly,
                          ),
                        ),
                      );
                    },
                    icon: Icon(widget.isReadOnly ? Icons.visibility : Icons.arrow_forward_rounded, size: 20),
                    label: Text(
                      widget.isReadOnly ? "VIEW INWARD ITEMS" : "PROCEED TO INWARD ENTRY",
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

  Widget _buildSupplierCard() => Card(
    color: const Color(0xFF1E293B),
    elevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5)),
    child: ListTile(
      contentPadding: const EdgeInsets.all(20),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(color: Color(0x33F59E0B), shape: BoxShape.circle),
        child: const Icon(Icons.business_rounded, color: Color(0xFFF59E0B)),
      ),
      title: Text(selectedSupplier!.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      subtitle: Text("${selectedSupplier!.city} | GST: ${selectedSupplier!.gst}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: widget.isReadOnly
          ? null
          : IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 28),
              onPressed: () => setState(() => selectedSupplier = null),
            ),
    ),
  );

  Widget _buildSupplierList(PharoahWebManager webPh) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: "Search Supplier by Name...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: Color(0xFFF59E0B)),
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
            onPressed: () => _openQuickAddSupplier(webPh),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text("NEW SUPPLIER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
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
                .where((p) => p.group == "Sundry Creditors" && p.name.toLowerCase().contains(searchQuery.toLowerCase()))
                .map((p) => Container(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                      child: ListTile(
                        leading: const Icon(Icons.business_outlined, color: Colors.white38),
                        title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(p.city, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        onTap: () => setState(() => selectedSupplier = p),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    ],
  );
}
