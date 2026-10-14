// FILE: lib/returns/sale_return_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../logic/pharoah_numbering_engine.dart';
import '../item_entry_card.dart'; 
import '../pharoah_date_controller.dart';
import '../app_date_logic.dart';
import '../pdf/pdf_router_service.dart';

class SaleReturnView extends StatefulWidget {
  final SaleReturn? existingRecord; 
  final bool isReadOnly; 

  const SaleReturnView({super.key, this.existingRecord, this.isReadOnly = false});

  @override
  State<SaleReturnView> createState() => _SaleReturnViewState();
}

class _SaleReturnViewState extends State<SaleReturnView> {
  final returnNoC = TextEditingController();
  final discountC = TextEditingController(text: "0"); 
  final medSearchC = TextEditingController(); 
  
  DateTime selectedDate = DateTime.now();
  Party? selectedParty;
  
  List<BillItem> items = []; 
  bool isBreakageMode = false; 
  String medSearch = "";
  String partySearch = ""; // 🔥 FIXED: Added missing variable
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initReturnFlow();
  }

  @override
  void dispose() {
    medSearchC.dispose();
    returnNoC.dispose();
    discountC.dispose();
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
        selectedParty = ph.parties.firstWhere((p) => p.name == ex.partyName);
      } catch (e) {
        selectedParty = Party(id: "0", name: ex.partyName);
      }
      setState(() => isLoading = false);
    } else {
      if (ph.activeCompany != null) {
        var series = ph.getDefaultSeries("RETURN");
        String nextNo = await PharoahNumberingEngine.getNextNumber(
          type: "RETURN", companyID: ph.activeCompany!.id,
          prefix: series.prefix, startFrom: series.startNumber, currentList: ph.saleReturns,
        );
        setState(() {
          returnNoC.text = nextNo;
          selectedDate = AppDateLogic.getSmartDate(ph.currentFY);
          isLoading = false;
        });
      }
    }
  }

  double get subTotal => items.fold(0, (sum, it) => sum + it.total);
  double get extraDiscount => double.tryParse(discountC.text) ?? 0.0;
  double get grandTotal => (subTotal - extraDiscount).roundToDouble();
  double get roundOff => double.parse((grandTotal - (subTotal - extraDiscount)).toStringAsFixed(2));

  void _showMagicHistoryBox(Medicine med, PharoahManager ph) {
    if (selectedParty == null) return;
    final history = ph.getMedicineHistory(partyId: selectedParty!.id, medicineId: med.id, isSale: true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(color: Color(0xFFF8F9FA), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(children: [
          Container(margin: const EdgeInsets.all(15), height: 5, width: 60, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10))),
          Text("TRANSACTION HISTORY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blue.shade900, letterSpacing: 2)),
          const SizedBox(height: 5),
          Text(med.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          Expanded(
            child: history.isEmpty 
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.history_toggle_off, size: 40, color: Colors.grey.shade300),
                  const Text("No history for this party.", style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                        onTap: widget.isReadOnly ? null : () { Navigator.pop(c); _showEntryCard(med, existingItem: null, historyData: h); },
                        title: Text("Bill: ${h['billNo']} | ${DateFormat('dd/MM/yy').format(h['date'])}"),
                        subtitle: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          _miniInfo("BATCH", h['batch']),
                          _miniInfo("LAST QTY", "${h['qty'].toInt()} + ${h['free'].toInt()}", isBold: true),
                          _miniInfo("RATE", "₹${h['rate']}"),
                        ]),
                      ),
                    );
                  },
                ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity, height: 50,
              child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(c); _showEntryCard(med); },
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.blue), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.edit_document), label: const Text("NOT IN HISTORY? ENTER MANUALLY"),
              ),
            ),
          )
        ]),
      ),
    );
  }

  Widget _miniInfo(String l, String v, {bool isBold = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(l, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
    Text(v, style: TextStyle(fontSize: 11, fontWeight: isBold ? FontWeight.w900 : FontWeight.bold, color: isBold ? Colors.indigo : Colors.black87)),
  ]);

  void _showEntryCard(Medicine med, {BillItem? existingItem, Map<String, dynamic>? historyData}) {
    BillItem? preFilled = existingItem;
    if (historyData != null && existingItem == null) {
      preFilled = BillItem(
        id: "temp", srNo: items.length + 1, medicineID: med.id, name: med.name, packing: med.packing,
        batch: historyData['batch'], exp: "12/26", hsn: med.hsnCode, mrp: (historyData['mrp'] as num).toDouble(),
        rate: (historyData['rate'] as num).toDouble(), gstRate: (historyData['gst'] as num).toDouble(), qty: 0, total: 0,
      );
    }
    showDialog(
      context: context,
      builder: (c) => ItemEntryCard(
        med: med,
        srNo: existingItem?.srNo ?? items.length + 1,
        partyState: selectedParty?.state ?? "Rajasthan",
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
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "Audit Credit Note" : (widget.existingRecord != null ? "Modify Credit Note" : "New Credit Note")),
        backgroundColor: const Color(0xFFB71C1C),
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
          if (selectedParty != null) ...[
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

  Widget _buildItemCard(BillItem it, int index, PharoahManager ph) {
    Color themeColor = it.isBreakage ? Colors.orange.shade900 : Colors.green.shade800;
    Color bgColor = it.isBreakage ? Colors.orange.shade50 : Colors.green.shade50;
    return Card(
      elevation: 1, margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: themeColor.withOpacity(0.2))),
      child: ListTile(
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
        subtitle: Text("Batch: ${it.batch} | Qty: ${it.qty.toInt()} + ${it.freeQty.toInt()}"),
        trailing: Text("₹${it.total.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.w900, color: themeColor)),
        onLongPress: () => setState(() => items.removeAt(index)),
      ),
    );
  }

  Widget _buildHeader(PharoahManager ph) => Container(
    padding: const EdgeInsets.all(15), color: Colors.white,
    child: Column(children: [
        if (selectedParty == null) ...[
          TextField(
            decoration: const InputDecoration(hintText: "Search Customer for Credit Note...", prefixIcon: Icon(Icons.person_search), border: OutlineInputBorder()),
            onChanged: (v) => setState(() { partySearch = v; }), // FIXED SETTER
          ),
          Container(
            height: 150, margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(10)),
            child: ListView(children: ph.parties.where((p) => p.name.toLowerCase().contains(partySearch.toLowerCase())).toList().map((p) => ListTile(
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => setState(() => selectedParty = p),
            )).toList()),
          )
        ] else
          ListTile(
            tileColor: Colors.red.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Text(selectedParty!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Return Ref: ${returnNoC.text}"),
            trailing: widget.isReadOnly ? null : IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() => selectedParty = null)),
          ),
    ]),
  );

  Widget _buildQuickModeToggle() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    child: Row(children: [
        _modeBtn("SELLABLE RETURN", !isBreakageMode, Colors.green.shade700, () => setState(() => isBreakageMode = false)),
        const SizedBox(width: 10),
        _modeBtn("EXPIRY / BREAKAGE", isBreakageMode, Colors.orange.shade900, () => setState(() => isBreakageMode = true)),
    ]),
  );

  Widget _modeBtn(String l, bool act, Color c, VoidCallback tap) => Expanded(child: InkWell(onTap: tap, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: act ? c : Colors.grey.shade200, borderRadius: BorderRadius.circular(10)), child: Text(l, textAlign: TextAlign.center, style: TextStyle(color: act ? Colors.white : Colors.black54, fontWeight: FontWeight.bold, fontSize: 10)))));

  Widget _buildLiveSearch(PharoahManager ph) => Padding(
    padding: const EdgeInsets.all(10),
    child: Column(children: [
        TextField(
          controller: medSearchC, 
          decoration: InputDecoration(
            hintText: "Type product to return...",
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(), filled: true, fillColor: Colors.white
          ),
          onChanged: (v) => setState(() => medSearch = v),
        ),
        if (medSearch.isNotEmpty)
          Container(
            height: 200, decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
            child: ListView(children: ph.medicines.where((m) => m.name.toLowerCase().contains(medSearch.toLowerCase())).map((m) => ListTile(
              title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { 
                setState(() { medSearch = ""; medSearchC.clear(); }); 
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
            const Text("NET CREDIT VALUE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            Text("₹${grandTotal.toStringAsFixed(2)}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFB71C1C))),
          ]),
          Text("R/O: ${roundOff.toStringAsFixed(2)}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
    ]),
  );

  void _handleSave(PharoahManager ph) {
    if (selectedParty == null) return;
    if (widget.existingRecord != null) {
      ph.updateSaleReturn(id: widget.existingRecord!.id, billNo: returnNoC.text, date: selectedDate, party: selectedParty!, items: items, total: grandTotal, extraDiscount: extraDiscount, roundOff: roundOff);
    } else {
      ph.finalizeSaleReturn(billNo: returnNoC.text, date: selectedDate, party: selectedParty!, items: items, total: grandTotal, extraDiscount: extraDiscount, roundOff: roundOff);
    }
    Navigator.pop(context);
  }

  void _handlePrint(PharoahManager ph) async {
    if (selectedParty == null) return;
    final returnObj = SaleReturn(id: "temp", billNo: returnNoC.text, date: selectedDate, partyName: selectedParty!.name, items: items, totalAmount: grandTotal, extraDiscount: extraDiscount, roundOff: roundOff);
    await PdfRouterService.printCreditNote(returnObj: returnObj, party: selectedParty!, ph: ph);
  }
}
