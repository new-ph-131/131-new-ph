// FILE: lib/web_live_sync/sub_views/web_challans/web_sale_challan_billing_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../web_pdf_router_service.dart';
import '../web_billing/web_item_entry_card.dart';
import '../web_billing/quick_add_product_modal.dart';

class WebSaleChallanBillingView extends StatefulWidget {
  final Party party;
  final String challanNo;
  final DateTime challanDate;
  final SaleChallan? existingRecord;
  final bool isReadOnly;

  const WebSaleChallanBillingView({
    super.key,
    required this.party,
    required this.challanNo,
    required this.challanDate,
    this.existingRecord,
    this.isReadOnly = false,
  });

  @override
  State<WebSaleChallanBillingView> createState() => _WebSaleChallanBillingViewState();
}

class _WebSaleChallanBillingViewState extends State<WebSaleChallanBillingView> {
  List<BillItem> items = [];
  final remarksC = TextEditingController();
  final productSearchC = TextEditingController();
  bool isSaving = false;

  double get totalAmt => items.fold(0.0, (sum, it) => sum + it.total);

  @override
  void initState() {
    super.initState();
    if (widget.existingRecord != null) {
      items = List.from(widget.existingRecord!.items);
      remarksC.text = widget.existingRecord!.remarks;
    }
  }

  @override
  void dispose() {
    remarksC.dispose();
    productSearchC.dispose();
    super.dispose();
  }

  void _recalculateSR() {
    setState(() {
      for (int i = 0; i < items.length; i++) {
        items[i] = items[i].copyWith(srNo: i + 1);
      }
    });
  }

  void _openItemEntry(Medicine med, {BillItem? itemToEdit, int? editIndex}) {
    if (widget.isReadOnly) return;

    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    String shopState = (webPh.companyProfile['state'] ?? 'Rajasthan').toString();
    String partyState = widget.party.state;
    List<BatchInfo> batches = webPh.batchHistory[med.identityKey] ?? [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => WebItemEntryCard(
        med: med,
        srNo: itemToEdit != null ? itemToEdit.srNo : items.length + 1,
        partyState: partyState,
        shopState: shopState,
        availableBatches: batches,
        existingItem: itemToEdit,
        onAdd: (newItem) {
          setState(() {
            if (editIndex != null) {
              items[editIndex] = newItem;
            } else {
              items.add(newItem);
            }
          });
          Navigator.pop(context);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  void _openQuickAddProduct(PharoahWebManager webPh) {
    if (widget.isReadOnly) return;
    showDialog(
      context: context,
      builder: (c) => QuickAddProductModal(
        webPh: webPh,
        onProductCreated: (newMedMap) {
          final medObj = Medicine.fromMap(newMedMap);
          _openItemEntry(medObj);
        },
      ),
    );
  }

  void _saveSaleChallan(PharoahWebManager webPh, {bool andPrint = false}) async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Challan cannot be empty!"), backgroundColor: Colors.orange));
      return;
    }

    setState(() => isSaving = true);

    final newChallan = SaleChallan(
      id: widget.existingRecord?.id ?? "SCH-WEB-${DateTime.now().millisecondsSinceEpoch}",
      billNo: widget.challanNo,
      partyId: widget.party.id,
      partyName: widget.party.name,
      partyGstin: widget.party.gst,
      partyState: widget.party.state,
      date: widget.challanDate,
      items: List.from(items),
      totalAmount: totalAmt,
      status: widget.existingRecord?.status ?? "Pending",
      remarks: remarksC.text.trim(),
    );

    if (widget.existingRecord != null) {
      webPh.deleteSaleChallan(widget.existingRecord!.id);
    }
    
    webPh.saleChallans.add(newChallan);

    // 2-Way Batch Sync
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        final med = webPh.medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey;
      } catch (_) {}

      webPh.registerBatchActivity(
        productKey: resolvedKey,
        batchNo: item.batch,
        exp: item.exp,
        packing: item.packing,
        mrp: item.mrp,
        rate: item.rate,
        rateA: item.appliedRateType == "A" ? item.rate : 0.0,
        rateB: item.appliedRateType == "B" ? item.rate : 0.0,
        rateC: item.appliedRateType == "C" ? item.rate : 0.0,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
      );
    }

    await webPh.pushUpdatedDataToCloud();
    setState(() => isSaving = false);

    if (andPrint) {
      final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);
      await WebPdfRouterService.printSaleChallan(challan: newChallan, party: widget.party, shop: shopProfile);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ Delivery Challan ${widget.challanNo} Saved!"), backgroundColor: Colors.green));
      // Pop Back to Hub (which will be at root due to Gateway)
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "View Items" : "Challan: ${widget.challanNo}"),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.white10, height: 1.0),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header Info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_rounded, color: Color(0xFF2DD4BF), size: 24),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.party.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                          Text("${widget.party.city} | GST: ${widget.party.gst}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: Text("DATE: ${DateFormat('dd/MM/yyyy').format(widget.challanDate)}", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Product Search Bar
            if (!widget.isReadOnly) _buildProductSearchCard(webPh),
            if (!widget.isReadOnly) const SizedBox(height: 16),

            // Cart Table
            Expanded(child: _buildCartTable(webPh)),
            const SizedBox(height: 16),

            // Footer
            _buildFooter(webPh),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSearchCard(PharoahWebManager webPh) {
    final query = productSearchC.text.trim().toLowerCase();
    final matchingMeds = query.isEmpty
        ? <Medicine>[]
        : webPh.medicines
            .where((m) =>
                m.name.toLowerCase().contains(query) ||
                m.systemId.toLowerCase().contains(query))
            .take(5)
            .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x662DD4BF), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: productSearchC,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: "SEARCH PRODUCT TO DISPATCH",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                    hintText: "Type medicine name...",
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF2DD4BF), size: 18),
                    suffixIcon: productSearchC.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                            onPressed: () => setState(() => productSearchC.clear()),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: (v) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _openQuickAddProduct(webPh),
                icon: const Icon(Icons.add_box_rounded, size: 18),
                label: const Text("+ PRODUCT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ],
          ),

          if (matchingMeds.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x332DD4BF)),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: matchingMeds.length,
                itemBuilder: (context, idx) {
                  final med = matchingMeds[idx];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.medication_rounded, color: Color(0xFF2DD4BF), size: 18),
                    title: Row(
                      children: [
                        Text(med.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                        const SizedBox(width: 8),
                        Text("(${med.packing})", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        const Spacer(),
                        Text(
                          "Stock: ${med.stock.toInt()}",
                          style: TextStyle(color: med.stock > 0 ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ],
                    ),
                    subtitle: Text("MRP: ₹${med.mrp.toStringAsFixed(2)} | Rate A: ₹${med.rateA.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    onTap: () {
                      setState(() => productSearchC.clear());
                      _openItemEntry(med);
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCartTable(PharoahWebManager webPh) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, color: Color(0xFF2DD4BF), size: 18),
              const SizedBox(width: 8),
              Text("DISPATCH ITEMS (${items.length})", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
          const Divider(color: Colors.white10, height: 20),
          if (items.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("Challan is empty. Search products above.", style: TextStyle(color: Colors.white38, fontSize: 12))))
          else
            Expanded(
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: const {
                    0: FixedColumnWidth(40),
                    1: FlexColumnWidth(3),
                    2: FixedColumnWidth(70),
                    3: FixedColumnWidth(80),
                    4: FixedColumnWidth(60),
                    5: FixedColumnWidth(70),
                    6: FixedColumnWidth(70),
                    7: FixedColumnWidth(85),
                    8: FixedColumnWidth(70),
                  },
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                      children: [_th("SN"), _th("PRODUCT NAME", isLeft: true), _th("PACK"), _th("BATCH"), _th("EXP"), _th("QTY"), _th("RATE"), _th("TOTAL"), _th("ACT")],
                    ),
                    ...items.asMap().entries.map((entry) {
                      int idx = entry.key; BillItem it = entry.value;
                      String qtyDisp = "${it.qty.toInt()}${it.freeQty > 0 ? ' + ${it.freeQty.toInt()}' : ''}";
                      return TableRow(
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                        children: [
                          _td("${idx + 1}"), _td(it.name, isLeft: true, isBold: true), _td(it.packing), _td(it.batch), _td(it.exp),
                          _td(qtyDisp, isBold: true, color: Colors.cyanAccent), _td("₹${it.rate.toStringAsFixed(2)}"),
                          _td("₹${it.total.toStringAsFixed(2)}", isBold: true, color: Colors.greenAccent),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!widget.isReadOnly) IconButton(icon: const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF38BDF8)), onPressed: () { final med = webPh.medicines.firstWhere((m) => m.id == it.medicineID); _openItemEntry(med, itemToEdit: it, editIndex: idx); }),
                              if (!widget.isReadOnly) IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent), onPressed: () => setState(() { items.removeAt(idx); _recalculateSR(); })),
                            ],
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter(PharoahWebManager webPh) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: TextField(
              controller: remarksC,
              readOnly: widget.isReadOnly,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                labelText: "DISPATCH REMARKS / VEHICLE INFO",
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                prefixIcon: const Icon(Icons.note_alt_outlined, color: Colors.white54, size: 18),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 40),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text("NET CHALLAN VALUE", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              Text("₹${totalAmt.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 24, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(width: 30),
          if (!widget.isReadOnly) ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: isSaving ? null : () => _saveSaleChallan(webPh, andPrint: false),
              icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(isSaving ? "SAVING..." : "SAVE CHALLAN", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2DD4BF), side: const BorderSide(color: Color(0xFF2DD4BF), width: 1.5), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: isSaving ? null : () => _saveSaleChallan(webPh, andPrint: true),
              icon: const Icon(Icons.print_rounded, size: 18),
              label: const Text("SAVE & PRINT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ] else ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2DD4BF), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                final tempChallan = SaleChallan(id: "temp", billNo: widget.challanNo, partyId: widget.party.id, partyName: widget.party.name, partyGstin: widget.party.gst, partyState: widget.party.state, date: widget.challanDate, items: items, totalAmount: totalAmt, remarks: remarksC.text.trim());
                await WebPdfRouterService.printSaleChallan(challan: tempChallan, party: widget.party, shop: CompanyProfile.fromMap(webPh.companyProfile));
              },
              icon: const Icon(Icons.print_rounded, size: 18),
              label: const Text("PRINT CHALLAN", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ]
        ],
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6), child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)));
  Widget _td(String t, {bool isLeft = false, bool isBold = false, Color color = Colors.white}) => Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6), child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)));
}
