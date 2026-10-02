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
  final VoidCallback onBack;
  final PurchaseChallan? existingRecord;
  final bool isReadOnly;

  const WebPurchaseChallanView({
    super.key,
    required this.onBack,
    this.existingRecord,
    this.isReadOnly = false,
  });

  @override
  State<WebPurchaseChallanView> createState() => _WebPurchaseChallanViewState();
}

class _WebPurchaseChallanViewState extends State<WebPurchaseChallanView> {
  final internalNoC = TextEditingController();
  final supplierRefC = TextEditingController();
  final searchController = TextEditingController();
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
        } catch (_) {
          selectedSupplier = Party(id: ex.partyId, name: ex.distributorName);
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
    supplierRefC.dispose();
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
                label: const Text("BACK TO CHALLANS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.inventory_2_rounded, color: Color(0xFFF59E0B), size: 24),
              const SizedBox(width: 10),
              Text(
                widget.isReadOnly ? "VIEW INWARD CHALLAN" : (widget.existingRecord != null ? "MODIFY INWARD CHALLAN" : "NEW INWARD PURCHASE CHALLAN"),
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Header (Challan ID & Supplier Ref No)
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
                          labelText: "INWARD ID",
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
                          labelText: "SUPPLIER REF NO *",
                          hintText: "Enter Supplier Bill / Challan No",
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

          const Text(
            "SELECT DISTRIBUTOR / SUPPLIER",
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),

          if (selectedSupplier != null) 
            _buildSupplierCard() 
          else 
            _buildSupplierList(webPh),

          // Bottom Gateway Button
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
                  if (supplierRefC.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Supplier Ref / Challan No is required!"), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => WebPurchaseChallanBillingView(
                        supplier: selectedSupplier!,
                        internalNo: internalNoC.text.trim(),
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
                  widget.isReadOnly ? "VIEW INWARD ITEMS ➔" : "PROCEED TO INWARD ENTRY ➔",
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
                      searchQuery.isEmpty 
                        ? "No suppliers registered under Sundry Creditors." 
                        : "No supplier found matching '$searchQuery'.",
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
