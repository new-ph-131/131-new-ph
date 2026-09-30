// FILE: lib/returns/purchase_return_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../logic/pharoah_numbering_engine.dart';
import '../purchase/purchase_billing_view.dart'; // Reusing Enterprise Entry Card
import '../product_master.dart';
import '../pharoah_date_controller.dart';
import '../app_date_logic.dart';
import '../pdf/pdf_router_service.dart';

class PurchaseReturnView extends StatefulWidget {
  final PurchaseReturn? existingRecord; 
  final bool isReadOnly; 

  const PurchaseReturnView({super.key, this.existingRecord, this.isReadOnly = false});

  @override
  State<PurchaseReturnView> createState() => _PurchaseReturnViewState();
}

class _PurchaseReturnViewState extends State<PurchaseReturnView> {
  final returnNoC = TextEditingController();
  final discountC = TextEditingController(text: "0"); 
  final medSearchC = TextEditingController(); // 🔥 FIX: Search UI Control (Point 1)
  
  DateTime selectedDate = DateTime.now();
  Party? selectedSupplier;
  
  List<PurchaseItem> items = []; 
  bool isBreakageMode = false; 
  String medSearch = "";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initReturnFlow();
  }

  @override
  void dispose() {
    medSearchC.dispose(); // Cleanup
    super.dispose();
  }

  void _initReturnFlow() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    if (widget.existingRecord != null) {
      final ex = widget.existingRecord!;
      returnNoC.text = ex.billNo;
      selectedDate = ex.date;
      items = List.from(ex.items);
      discountC.text = ex.extraDiscount.toString();
      try {
        selectedSupplier = ph.parties.firstWhere((p) => p.name == ex.distributorName);
      } catch (e) {
        selectedSupplier = Party(id: "0", name: ex.distributorName);
      }
      setState(() => isLoading = false);
    } else {
      if (ph.activeCompany != null) {
        String nextNo = await PharoahNumberingEngine.getNextNumber(
          type: "RETURN", companyID: ph.activeCompany!.id,
          prefix: "DN-", 
          startFrom: 1, currentList: ph.purchaseReturns,
        );
        setState(() {
          returnNoC.text = nextNo;
          selectedDate = AppDateLogic.getSmartDate(ph.currentFY);
          isLoading = false;
        });
      }
    }
  }

  // --- CALCULATIONS ---
  double get subTotal => items.fold(0, (sum, it) => sum + it.total);
  double get extraDiscount => double.tryParse(discountC.text) ?? 0.0;
  double get grandTotal => (subTotal - extraDiscount).roundToDouble();
  double get roundOff => double.parse((grandTotal - (subTotal - extraDiscount)).toStringAsFixed(2));

  // ===========================================================================
  // 🪄 THE PURCHASE MAGIC BOX (QTY+FREE & ALWAYS-ON MANUAL ENTRY)
  // ===========================================================================
  void _showMagicHistoryBox(Medicine med, PharoahManager ph) {
    if (selectedSupplier == null) return;
    final history = ph.getMedicineHistory(partyId: selectedSupplier!.id, medicineId: med.id, isSale: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(color: Color(0xFFFDF8F5), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(children: [
          Container(margin: const EdgeInsets.all(15), height: 5, width: 60, decoration: BoxDecoration(color: Colors.brown.withOpacity(0.2), borderRadius: BorderRadius.circular(10))),
          
          Text("INWARD TRANSACTION HISTORY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.brown.shade900, letterSpacing: 2)),
          const SizedBox(height: 5),
          Text(med.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown)),
          const Divider(),

          // HISTORY LIST (Point 2 Fix: Handle empty list without closing UI)
          Expanded(
            child: history.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.manage_search_rounded, size: 40, color: Colors.brown.shade200),
                  const Text("No inward records from this supplier.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: history.length,
                  itemBuilder: (c, i) {
                    final h = history[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 1,
                      child: ListTile(
                        onTap: widget.isReadOnly ? null : () { Navigator.pop(c); _showEntryCard(med, historyData: h); },
                        title: Text("Bill: ${h['billNo']} | ${DateFormat('dd MMM').format(h['date'])}"),
                        subtitle: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          _miniInfo("BATCH", h['batch']),
                          // 🔥 Qty + Free History View
                          _miniInfo("LAST INWARD", "${h['qty'].toInt()} + ${h['free'].toInt()}", isBold: true),
                          _miniInfo("RATE", "₹${h['rate']}"),
                          _miniInfo("MRP", "₹${h['mrp']}"),
                        ]),
                      ),
                    );
                  },
                ),
          ),
          
          // 🔥 ALWAYS VISIBLE MANUAL BUTTON (Point 2 Fix)
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity, height: 50,
              child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(c); _showEntryCard(med); },
                style: OutlinedButton.styleFrom(foregroundColor: Colors.brown, side: const BorderSide(color: Colors.brown), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.edit_note), label: const Text("NOT IN HISTORY? ENTER MANUALLY"),
              ),
            ),
          )
        ]),
      ),
    );
  }

  Widget _miniInfo(String l, String v, {bool isBold = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(l, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
    Text(v, style: TextStyle(fontSize: 11, fontWeight: isBold ? FontWeight.w900 : FontWeight.bold, color: isBold ? Colors.brown.shade900 : Colors.black87)),
  ]);

  void _showEntryCard(Medicine med, {PurchaseItem? existingItem, Map<String, dynamic>? historyData}) {
    PurchaseItem? preFilled = existingItem;
    
    if (historyData != null && existingItem == null) {
      preFilled = PurchaseItem(
        id: "temp", srNo: items.length + 1, medicineID: med.id, name: med.name, packing: med.packing,
        batch: historyData['batch'], exp: "12/26", hsn: med.hsnCode, mrp: (historyData['mrp'] as num).toDouble(),
        purchaseRate: (historyData['rate'] as num).toDouble(), gstRate: (historyData['gst'] as num).toDouble(), qty: 0, total: 0,
      );
    }

    showDialog(
      context: context,
      builder: (c) => PurchaseItemEntryCard(
        med: med,
        srNo: existingItem?.srNo ?? items.length + 1,
        existingItem: preFilled,
        allowExpired: true,
        onAdd: (newItem) {
          setState(() {
            if (existingItem != null) {
              int idx = items.indexWhere((it) => it.id == existingItem.id);
              items[idx] = newItem.copyWith(isBreakage: existingItem.isBreakage);
            } else {
              items.add(newItem.copyWith(isBreakage: isBreakageMode));
            }
          });
          Navigator.pop(context);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F3),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "Audit Debit Note" : (widget.existingRecord != null ? "Modify Debit Note" : "New Debit Note")),
        backgroundColor: Colors.brown.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.print_rounded), onPressed: items.isEmpty ? null : () => _handlePrint(ph)),
          if (!widget.isReadOnly && items.isNotEmpty) 
            IconButton(icon: const Icon(Icons.check_circle_rounded, size: 28), onPressed: () => _handleSave(ph)),
        ],
      ),
      body: IgnorePointer(
        ignoring: widget.isReadOnly,
        child: Column(children: [
          _buildHeader(ph),
          if (selectedSupplier != null) ...[
            _buildQuickModeToggle(),
            _buildLiveSearch(ph),
          ],
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text("No items added for return"))
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: items.length,
                    itemBuilder: (c, i) => _buildItemCard(items[i], i, ph),
                  ),
          ),
          _buildAdvancedFooter(),
        ]),
      ),
    );
  }

  // --- ITEM CARD (MODIFY & COLOUR FIX) ---
  Widget _buildItemCard(PurchaseItem it, int index, PharoahManager ph) {
    // 🔥 Colour Logic (Point 1 Fix)
    Color themeColor = it.isBreakage ? Colors.deepOrange.shade900 : Colors.blue.shade900;
    Color bgColor = it.isBreakage ? Colors.deepOrange.shade50 : Colors.blue.shade50;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: themeColor.withOpacity(0.2))),
      child: ListTile(
        // 🔥 Tapping Logic: Edit (Point 3 Fix)
        onTap: () {
          final med = ph.medicines.firstWhere((m) => m.id == it.medicineID);
          _showEntryCard(med, existingItem: it);
        },
        tileColor: bgColor,
        title: Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: themeColor, borderRadius: BorderRadius.circular(5)), child: Text(it.isBreakage ? "EXP" : "RET", style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        subtitle: Text("Batch: ${it.batch} | Exp: ${it.exp} | Qty: ${it.qty.toInt()} + ${it.freeQty.toInt()}"),
        trailing: Text("₹${it.total.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.w900, color: themeColor)),
        onLongPress: () => setState(() => items.removeAt(index)),
      ),
    );
  }

  // --- UI BUILDING BLOCKS ---
  Widget _buildHeader(PharoahManager ph) => Container(
    padding: const EdgeInsets.all(15), color: Colors.white,
    child: Column(children: [
        if (selectedSupplier == null) ...[
          TextField(
            decoration: const InputDecoration(hintText: "Search Supplier for Debit Note...", prefixIcon: Icon(Icons.business_rounded), border: OutlineInputBorder()),
            onChanged: (v) => setState(() => medSearch = v), // Temp reuse
          ),
          Container(
            height: 150, margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(10)),
            child: ListView(children: ph.parties.where((p) => p.group == "Sundry Creditors" && p.name.toLowerCase().contains(medSearch.toLowerCase())).map((p) => ListTile(
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { setState(() { selectedSupplier = p; medSearch = ""; }); }
            )).toList()),
          )
        ] else
          ListTile(
            tileColor: Colors.brown.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Text(selectedSupplier!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Debit Note ID: ${returnNoC.text}"),
            trailing: widget.isReadOnly ? null : IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() => selectedSupplier = null)),
          ),
    ]),
  );

  Widget _buildQuickModeToggle() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    child: Row(children: [
        _modeBtn("SELLABLE RETURN", !isBreakageMode, Colors.blue.shade800, () => setState(() => isBreakageMode = false)),
        const SizedBox(width: 10),
        _modeBtn("BREAKAGE / EXPIRY", isBreakageMode, Colors.deepOrange.shade900, () => setState(() => isBreakageMode = true)),
    ]),
  );

  Widget _modeBtn(String l, bool act, Color c, VoidCallback tap) => Expanded(child: InkWell(onTap: tap, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: act ? c : Colors.grey.shade200, borderRadius: BorderRadius.circular(10)), child: Text(l, textAlign: TextAlign.center, style: TextStyle(color: act ? Colors.white : Colors.black54, fontWeight: FontWeight.bold, fontSize: 10)))));

  Widget _buildLiveSearch(PharoahManager ph) => Padding(
    padding: const EdgeInsets.all(10),
    child: Column(children: [
        TextField(
          controller: medSearchC, // 🔥 FIX: Controller (Point 1)
          decoration: InputDecoration(
            hintText: "Search product to return...",
            prefixIcon: const Icon(Icons.search),
            suffixIcon: medSearch.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() { medSearchC.clear(); medSearch = ""; })) : null,
            border: const OutlineInputBorder(), filled: true, fillColor: Colors.white
          ),
          onChanged: (v) => setState(() => medSearch = v),
        ),
        if (medSearch.isNotEmpty)
          Container(
            height: 200, decoration: BoxDecoration(color: Colors.white, boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 10)]),
            child: ListView(children: ph.medicines.where((m) => m.name.toLowerCase().contains(medSearch.toLowerCase())).map((m) => ListTile(
              title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { 
                setState(() { medSearch = ""; medSearchC.clear(); }); // 🔥 UI Clear
                _showMagicHistoryBox(m, ph); 
              },
            )).toList()),
          )
    ]),
  );

  Widget _buildAdvancedFooter() => Container(
    padding: const EdgeInsets.all(15), color: Colors.white,
    child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Extra Discount (-)", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          SizedBox(width: 100, child: TextField(controller: discountC, keyboardType: TextInputType.number, textAlign: TextAlign.right, onChanged: (v) => setState(() {}), decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()))),
        ]),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("NET DEBIT TOTAL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            Text("₹${grandTotal.toStringAsFixed(2)}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.brown.shade900)),
          ]),
          Text("R/O: ${roundOff.toStringAsFixed(2)}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
    ]),
  );

  void _handleSave(PharoahManager ph) {
    if (selectedSupplier == null) return;
    if (widget.existingRecord != null) {
      ph.updatePurchaseReturn(id: widget.existingRecord!.id, billNo: returnNoC.text, date: selectedDate, party: selectedSupplier!, items: items, total: grandTotal, extraDiscount: extraDiscount, roundOff: roundOff);
    } else {
      ph.finalizePurchaseReturn(billNo: returnNoC.text, date: selectedDate, party: selectedSupplier!, items: items, total: grandTotal, extraDiscount: extraDiscount, roundOff: roundOff);
    }
    Navigator.pop(context);
  }

  void _handlePrint(PharoahManager ph) async {
    if (selectedSupplier == null) return;
    final returnObj = PurchaseReturn(id: "temp", billNo: returnNoC.text, date: selectedDate, distributorName: selectedSupplier!.name, items: items, totalAmount: grandTotal, extraDiscount: extraDiscount, roundOff: roundOff);
    await PdfRouterService.printDebitNote(returnObj: returnObj, supplier: selectedSupplier!, ph: ph);
  }
}
