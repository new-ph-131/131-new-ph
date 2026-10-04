// FILE: lib/web_live_sync/sub_views/web_purchase/ui/web_purchase_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:pharoah_erp/web_live_sync/web_models.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/web_app_date_logic.dart';
import 'package:pharoah_erp/web_live_sync/web_pharoah_numbering_engine.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_billing/quick_add_party_modal.dart';
import 'web_purchase_billing_screen.dart';

class WebPurchaseEntryScreen extends StatefulWidget {
  final VoidCallback onBack;
  final Purchase? existingPurchase;
  final bool isReadOnly;

  const WebPurchaseEntryScreen({
    super.key,
    required this.onBack,
    this.existingPurchase,
    this.isReadOnly = false,
  });

  @override
  State<WebPurchaseEntryScreen> createState() => _WebPurchaseEntryScreenState();
}

class _WebPurchaseEntryScreenState extends State<WebPurchaseEntryScreen> {
  final internalNoC = TextEditingController();
  final supplierBillNoC = TextEditingController();
  final searchController = TextEditingController();

  DateTime selectedBillDate = DateTime.now();
  DateTime selectedEntryDate = DateTime.now();
  String paymentMode = "CREDIT";
  Party? selectedSupplier;
  String searchQuery = "";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  void _initSession() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final webPh = Provider.of<PharoahWebManager>(context, listen: false);

      if (widget.existingPurchase != null) {
        final p = widget.existingPurchase!;
        internalNoC.text = p.internalNo;
        supplierBillNoC.text = p.billNo;
        selectedBillDate = p.date;
        selectedEntryDate = p.entryDate;
        paymentMode = p.paymentMode;
        try {
          selectedSupplier = webPh.parties.firstWhere((pt) => pt.id == p.partyId || pt.name == p.distributorName);
        } catch (_) {
          selectedSupplier = Party(id: p.partyId, name: p.distributorName, group: "Sundry Creditors");
        }
      } else {
        internalNoC.text = webPh.getNextBillNumber("PURCHASE", "PUR-", 1);
        selectedBillDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
        selectedEntryDate = DateTime.now();
      }

      setState(() => isLoading = false);
    });
  }

  void _openQuickAddSupplier(PharoahWebManager webPh) {
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        preFillData: const {'group': 'Sundry Creditors'},
        onPartyCreated: (newParty) {
          setState(() => selectedSupplier = newParty);
        },
      ),
    );
  }

  @override
  void dispose() {
    internalNoC.dispose();
    supplierBillNoC.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    if (isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(50), child: CircularProgressIndicator(color: Color(0xFFF59E0B))));
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 860),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.downloading_rounded, color: Color(0xFFF59E0B), size: 24),
              const SizedBox(width: 10),
              Text(
                widget.isReadOnly ? "VIEW PURCHASE ENTRY" : (widget.existingPurchase != null ? "MODIFY PURCHASE ENTRY" : "PURCHASE INWARD ENTRY (STEP 1)"),
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Header Box: Internal ID, Supplier Bill No & Dates
          Container(
            padding: const EdgeInsets.all(18),
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
                          labelText: "INTERNAL ENTRY NO",
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
                        controller: supplierBillNoC,
                        readOnly: widget.isReadOnly,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: "SUPPLIER BILL NO *",
                          hintText: "Enter Supplier Bill No",
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
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
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: widget.isReadOnly ? null : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedBillDate,
                            firstDate: WebAppDateLogic.getFYStart(webPh.financialYear),
                            lastDate: WebAppDateLogic.getFYEnd(webPh.financialYear),
                          );
                          if (picked != null) setState(() => selectedBillDate = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("SUPPLIER BILL DATE", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(DateFormat('dd/MM/yyyy').format(selectedBillDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                              const Icon(Icons.calendar_month_rounded, color: Color(0xFFF59E0B), size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: widget.isReadOnly ? null : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedEntryDate,
                            firstDate: WebAppDateLogic.getFYStart(webPh.financialYear),
                            lastDate: WebAppDateLogic.getFYEnd(webPh.financialYear),
                          );
                          if (picked != null) setState(() => selectedEntryDate = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("STOCK INWARD DATE", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(DateFormat('dd/MM/yyyy').format(selectedEntryDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                              const Icon(Icons.event_available_rounded, color: Colors.greenAccent, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'CASH', label: Text('CASH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                        ButtonSegment(value: 'CREDIT', label: Text('CREDIT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                      ],
                      selected: {paymentMode},
                      onSelectionChanged: widget.isReadOnly ? null : (v) => setState(() => paymentMode = v.first),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            "SELECT DISTRIBUTOR / SUPPLIER",
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),

          if (selectedSupplier != null)
            _buildSupplierCard()
          else
            _buildSupplierList(webPh),

          // Proceed to Step 2 Button
          if (selectedSupplier != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 18),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () {
                  if (supplierBillNoC.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Supplier Bill Number is mandatory to proceed!"), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => WebPurchaseBillingScreen(
                        supplier: selectedSupplier!,
                        internalNo: internalNoC.text.trim(),
                        supplierBillNo: supplierBillNoC.text.trim(),
                        billDate: selectedBillDate,
                        entryDate: selectedEntryDate,
                        paymentMode: paymentMode,
                        existingPurchase: widget.existingPurchase,
                        isReadOnly: widget.isReadOnly,
                        onCompleted: widget.onBack,
                      ),
                    ),
                  );
                },
                icon: Icon(widget.isReadOnly ? Icons.visibility : Icons.arrow_forward_rounded, size: 20),
                label: Text(
                  widget.isReadOnly ? "VIEW PURCHASED ITEMS ➔" : "PROCEED TO ITEM ENTRY (STEP 2) ➔",
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSupplierCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(color: Color(0x33F59E0B), shape: BoxShape.circle),
          child: const Icon(Icons.business_rounded, color: Color(0xFFF59E0B), size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(selectedSupplier!.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 4),
              Text("${selectedSupplier!.city} | GST: ${selectedSupplier!.gst}", style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
            ],
          ),
        ),
        if (!widget.isReadOnly)
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 28),
            onPressed: () => setState(() => selectedSupplier = null),
          ),
      ],
    ),
  );

  Widget _buildSupplierList(PharoahWebManager webPh) {
    final query = searchQuery.trim().toLowerCase();
    final matchingSuppliers = webPh.parties.where((p) {
      if (query.isEmpty) return p.group == "Sundry Creditors";
      return p.group == "Sundry Creditors" &&
          (p.name.toLowerCase().contains(query) ||
           p.city.toLowerCase().contains(query) ||
           p.gst.toLowerCase().contains(query));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: searchController,
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: "Search Distributor by Name, City or GST...",
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFF59E0B), size: 18),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 16),
                          onPressed: () {
                            searchController.clear();
                            setState(() => searchQuery = "");
                          },
                        )
                      : null,
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
              onPressed: () => _openQuickAddSupplier(webPh),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text("NEW SUPPLIER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(minHeight: 180, maxHeight: 360),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: matchingSuppliers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      searchQuery.isEmpty ? "No suppliers registered under Sundry Creditors." : "No supplier found matching '$searchQuery'.",
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: matchingSuppliers.length,
                  itemBuilder: (context, idx) {
                    final p = matchingSuppliers[idx];
                    return Container(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: const BoxDecoration(
                            color: Color(0x26F59E0B),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.business_outlined, color: Color(0xFFF59E0B), size: 16),
                        ),
                        title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text("${p.city.isEmpty ? 'No City' : p.city} | GST: ${p.gst.isEmpty ? 'N/A' : p.gst}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 13),
                        onTap: () => setState(() => selectedSupplier = p),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
