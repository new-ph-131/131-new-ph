// FILE: lib/purchase/purchase_billing_view.dart

import '../pharoah_date_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../widgets.dart'; // Mapped safely for MargBatchLookupDialog
import '../product_master.dart'; 
import '../batch_sync_engine.dart'; 
import '../expiry_master.dart';    
import 'package:intl/intl.dart';
import '../pdf/pdf_router_service.dart';
import 'dart:ui';

class PurchaseBillingView extends StatefulWidget {
  final Party distributor;
  final String internalNo, distBillNo, mode;
  final DateTime billDate, entryDate;
  final List<PurchaseItem>? existingItems;
  final String? modifyPurchaseId;
  final bool isReadOnly; 
  final List<String>? linkedChallanIds; 

  const PurchaseBillingView({
    super.key,
    required this.distributor,
    required this.internalNo,
    required this.distBillNo,
    required this.billDate,
    required this.entryDate,
    required this.mode,
    this.existingItems,
    this.modifyPurchaseId,
    this.isReadOnly = false,
    this.linkedChallanIds,
  });

  @override
  State<PurchaseBillingView> createState() => _PurchaseBillingViewState();
}

class _PurchaseBillingViewState extends State<PurchaseBillingView> {
  late TextEditingController internalNoC;
  late TextEditingController distBillNoC;
  late DateTime selectedBillDate;
  final discountC = TextEditingController(text: "0"); // 🆕 Mapped for Purchase Extra Discount
  List<PurchaseItem> items = [];

  @override
  void initState() {
    super.initState();
    internalNoC = TextEditingController(text: widget.internalNo);
    distBillNoC = TextEditingController(text: widget.distBillNo);
    selectedBillDate = widget.billDate;
    if (widget.existingItems != null) items = List.from(widget.existingItems!);

    // If modifying an existing purchase, pull its extraDiscount value
    if (widget.modifyPurchaseId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ph = Provider.of<PharoahManager>(context, listen: false);
        try {
          final exPur = ph.purchases.firstWhere((p) => p.id == widget.modifyPurchaseId);
          discountC.text = exPur.extraDiscount.toString();
          setState(() {});
        } catch (_) {}
      });
    }
  }

  void _recalculateSR() {
    setState(() {
      for (int i = 0; i < items.length; i++) {
        items[i] = items[i].copyWith(srNo: i + 1);
      }
    });
  }

@override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    // 🆕 CENTRAL CALCULATIONS (Common for footer & print)
    double itemTotal = items.fold(0.0, (sum, it) => sum + it.total);
    double extraDisc = double.tryParse(discountC.text) ?? 0.0;
    double rawTotal = itemTotal - extraDisc;
    double finalGrandTotal = rawTotal.roundToDouble();
    double roundOffVal = finalGrandTotal - rawTotal;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        backgroundColor: widget.isReadOnly ? Colors.purple.shade700 : const Color(0xFFB45309),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.distributor.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          Text(widget.isReadOnly ? "VIEWING INWARD" : "ID: ${widget.internalNo} | Bill: ${widget.distBillNo}", style: const TextStyle(fontSize: 10))
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded),
            onPressed: items.isEmpty ? null : () async {
              final tempPurchase = Purchase(
                id: "temp", internalNo: internalNoC.text, billNo: distBillNoC.text.trim(), 
                partyId: widget.distributor.id, date: selectedBillDate, entryDate: widget.entryDate, 
                distributorName: widget.distributor.name, items: items, 
                totalAmount: finalGrandTotal, // 🆕 Passed correct net total
                paymentMode: widget.mode, 
                linkedChallanIds: widget.linkedChallanIds ?? [],
                extraDiscount: extraDisc,     // 🆕 Mapped
                roundOff: roundOffVal,         // 🆕 Mapped
              );
              await PdfRouterService.printPurchase(purchase: tempPurchase, supplier: widget.distributor, ph: ph);
            },
          ),
          if (!widget.isReadOnly) 
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: TextButton(
                onPressed: items.isEmpty ? null : () => _handleSave(ph, itemTotal, extraDisc, roundOffVal, finalGrandTotal), 
                child: const Text("FINISH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              ),
            )
        ],
      ),
      body: Column(children: [
        _buildHeader(),
        _buildSearchBarTrigger(ph),
        Expanded(child: items.isEmpty ? const Center(child: Text("Cart is empty")) : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 10), itemCount: items.length, itemBuilder: (c, i) => _buildItemCard(items[i], i, ph))),
        _buildFooter(itemTotal, extraDisc, roundOffVal, finalGrandTotal),
      ]),
    );
  }

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.all(15), 
    decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(child: Text(widget.distributor.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, overflow: TextOverflow.ellipsis))),
      InkWell(
        onTap: widget.isReadOnly ? null : () async {
          final phManager = Provider.of<PharoahManager>(context, listen: false);
          DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: phManager.currentFY, initialDate: selectedBillDate);
          if (p != null) setState(() => selectedBillDate = p);
        },
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8), color: Colors.grey.shade50), child: Row(children: [const Icon(Icons.calendar_month, size: 14, color: Color(0xFFB45309)), const SizedBox(width: 5), Text(DateFormat('dd/MM/yy').format(selectedBillDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))])),
      ),
    ]),
  );

  Widget _buildSearchBarTrigger(PharoahManager ph) {
    if (widget.isReadOnly) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: InkWell(
        onTap: () => _showItemSearchSheet(ph),
        child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange.shade300, width: 1)), child: Row(children: [const Icon(Icons.search, color: Color(0xFFB45309)), const SizedBox(width: 10), Text("Tap here to add items...", style: TextStyle(color: Colors.grey.shade600))])),
      ),
    );
  }

  Widget _buildItemCard(PurchaseItem it, int index, PharoahManager ph) {
    final card = Card(
      elevation: 1, margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
        subtitle: Text("Batch: ${it.batch} | Exp: ${it.exp} | Qty: ${it.qty.toInt()} + ${it.freeQty.toInt()}"),
        trailing: Text("₹${it.total.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        onTap: widget.isReadOnly ? null : () => _showItemSearchSheet(ph, itemToEdit: it),
      ),
    );
    if (widget.isReadOnly) return card;
    return Dismissible(key: Key(it.id), direction: DismissDirection.endToStart, background: Container(decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)), onDismissed: (d) { setState(() { items.removeAt(index); }); _recalculateSR(); }, child: card);
  }

  void _showItemSearchSheet(PharoahManager ph, {PurchaseItem? itemToEdit}) {
    if (widget.isReadOnly) return; 
    String localSearch = "";
    Medicine? selectedMed;
    if (itemToEdit != null) {
      try { selectedMed = ph.medicines.firstWhere((m) => m.id == itemToEdit.medicineID); } catch(e) {}
    }

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.transparent, 
      builder: (context) => StatefulBuilder(builder: (context, setSheetState) {
        final filteredMeds = ph.medicines.where((m) => m.name.toLowerCase().contains(localSearch.toLowerCase())).toList();
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), 
          child: Container(height: MediaQuery.of(context).size.height * 0.85, decoration: const BoxDecoration(color: Color(0xFFFDF8F6), borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Column(children: [
            Container(margin: const EdgeInsets.only(top: 15, bottom: 10), height: 5, width: 50, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            if (selectedMed == null) ...[
              Padding(padding: const EdgeInsets.all(20), child: TextField(autofocus: true, decoration: InputDecoration(hintText: "Search Product for Inward...", prefixIcon: const Icon(Icons.search, color: Color(0xFFB45309)), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)), onChanged: (v) => setSheetState(() => localSearch = v))),
              Expanded(child: ListView.builder(itemCount: filteredMeds.length, itemBuilder: (c, i) => ListTile(leading: const CircleAvatar(backgroundColor: Color(0xFFFFF7ED), child: Icon(Icons.inventory_2_rounded, size: 20, color: Color(0xFFB45309))), title: Text(filteredMeds[i].name, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text("Packing: ${filteredMeds[i].packing}"), onTap: () => setSheetState(() => selectedMed = filteredMeds[i]))))
            ] else ...[
              Expanded(child: SingleChildScrollView(child: PurchaseItemEntryCard(med: selectedMed!, srNo: itemToEdit != null ? itemToEdit.srNo : items.length + 1, existingItem: itemToEdit, onAdd: (newItem) { setState(() { if (itemToEdit != null) { int idx = items.indexWhere((it) => it.id == itemToEdit.id); items[idx] = newItem; } else { items.add(newItem); } }); Navigator.pop(context); }, onCancel: () => itemToEdit != null ? Navigator.pop(context) : setSheetState(() => selectedMed = null))))
            ]
          ])),
        );
      }),
    );
  }

  // 🆕 UPGRADED FOOTER: Mapped with extra discount and live round-off
  Widget _buildFooter(double itemTotal, double extraDisc, double roundOffVal, double finalGrandTotal) => Container(
    padding: const EdgeInsets.all(15), 
    decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
    child: Column(children: [
      _row("Items Total", "₹${itemTotal.toStringAsFixed(2)}"),
      const SizedBox(height: 5),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text("Extra Discount (-)", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        SizedBox(
          width: 100, 
          child: TextField(
            controller: discountC, 
            readOnly: widget.isReadOnly,
            keyboardType: TextInputType.number, 
            textAlign: TextAlign.right, 
            onChanged: (v) => setState(() {}), 
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8), border: OutlineInputBorder()),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)
          )
        ),
      ]),
      const SizedBox(height: 5),
      _row("Round Off", roundOffVal.toStringAsFixed(2)),
      const Divider(),
      _row("GRAND TOTAL", "₹${finalGrandTotal.toStringAsFixed(0)}.00", bold: true, size: 22, color: const Color(0xFFB45309)),
    ]),
  );

  Widget _row(String l, String v, {bool bold = false, double size = 15, Color? color}) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)), Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: size, color: color))]);

  void _handleSave(PharoahManager ph, double itemTotal, double extraDisc, double roundOffVal, double finalGrandTotal) {
    List<String> links = widget.linkedChallanIds ?? [];
    if (widget.modifyPurchaseId != null) {
      ph.updatePurchase(
        id: widget.modifyPurchaseId!, 
        internalNo: internalNoC.text, 
        billNo: distBillNoC.text.trim(), 
        date: selectedBillDate, 
        entryDate: widget.entryDate, 
        party: widget.distributor, 
        items: items, 
        total: finalGrandTotal, // Passed net total
        mode: widget.mode, 
        linkedChallanIds: links,
        extraDiscount: extraDisc, // 🆕 Mapped
        roundOff: roundOffVal,     // 🆕 Mapped
      );
    } else {
      ph.finalizePurchase(
        internalNo: internalNoC.text, 
        billNo: distBillNoC.text.trim(), 
        date: selectedBillDate, 
        entryDate: widget.entryDate, 
        party: widget.distributor, 
        items: items, 
        total: finalGrandTotal, // Passed net total
        mode: widget.mode, 
        linkedChallanIds: links,
        extraDiscount: extraDisc, // 🆕 Mapped
        roundOff: roundOffVal,     // 🆕 Mapped
      );
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class PurchaseItemEntryCard extends StatefulWidget {
  final Medicine med; 
  final int srNo; 
  final PurchaseItem? existingItem; 
  final Function(PurchaseItem) onAdd; 
  final VoidCallback onCancel;
  final bool allowExpired; 

  const PurchaseItemEntryCard({
    super.key, 
    required this.med, 
    required this.srNo, 
    this.existingItem, 
    required this.onAdd, 
    required this.onCancel,
    this.allowExpired = false,
  });

  @override State<PurchaseItemEntryCard> createState() => _PurchaseItemEntryCardState();
}

class _PurchaseItemEntryCardState extends State<PurchaseItemEntryCard> {
  final batchC = TextEditingController(); 
  final expC = TextEditingController(); 
  final gstC = TextEditingController();
  final mrpC = TextEditingController(); 
  final purRateC = TextEditingController(); 
  final qtyC = TextEditingController(text: "1");
  final freeC = TextEditingController(text: "0"); 
  final rateAC = TextEditingController(); 
  final rateBC = TextEditingController();
  final rateCC = TextEditingController(); 
  final rateCDiscC = TextEditingController(text: "0.0");
  final discPerC = TextEditingController(text: "0.0"); 
  final discAmtC = TextEditingController(text: "0.0");

  String selectedRateType = "A";

  @override 
  void initState() {
    super.initState();
    _setupInitialData();
  }

  void _setupInitialData() {
    if (widget.existingItem != null) {
      final i = widget.existingItem!;
      batchC.text = i.batch; 
      expC.text = i.exp; 
      gstC.text = i.gstRate.toString();
      mrpC.text = i.mrp.toString(); 
      purRateC.text = i.purchaseRate.toString();
      qtyC.text = i.qty.toString(); 
      freeC.text = i.freeQty.toString();
      rateAC.text = i.rateA.toString(); 
      rateBC.text = i.rateB.toString(); 
      rateCC.text = i.rateC.toString();
      selectedRateType = i.appliedRateType;
      rateCDiscC.text = i.rateCFormula.toString();
      discPerC.text = i.discountPer.toString();
      _syncDiscount(true); 
    } else {
      gstC.text = widget.med.gst.toString(); 
      mrpC.text = widget.med.mrp.toString();
      purRateC.text = widget.med.purRate.toString(); 
      rateAC.text = widget.med.rateA.toString(); 
      rateBC.text = widget.med.rateB.toString(); 
      _calcRateC();
    }
  }

  void _calcRateC() {
    double mrp = double.tryParse(mrpC.text) ?? 0.0; 
    double gst = double.tryParse(gstC.text) ?? 0.0;
    double formulaDisc = double.tryParse(rateCDiscC.text) ?? 0.0;
    double baseTaxable = (mrp / (1 + (gst / 100)));
    rateCC.text = (baseTaxable - (baseTaxable * (formulaDisc / 100))).toStringAsFixed(2);
    setState(() {});
  }

  void _syncDiscount(bool isPercentSource) {
    double q = double.tryParse(qtyC.text) ?? 0;
    double r = double.tryParse(purRateC.text) ?? 0;
    double gross = q * r;
    if (gross <= 0) return;
    if (isPercentSource) {
      double p = double.tryParse(discPerC.text) ?? 0;
      discAmtC.text = (gross * (p / 100)).toStringAsFixed(2);
    } else {
      double a = double.tryParse(discAmtC.text) ?? 0;
      discPerC.text = ((a / gross) * 100).toStringAsFixed(2);
    }
    setState(() {});
  }

  void _formatExpiry(String val) {
    String clean = val.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length >= 2 && !val.contains('/')) clean = '${clean.substring(0, 2)}/${clean.substring(2)}';
    if (clean.length > 5) clean = clean.substring(0, 5);
    if (expC.text != clean) {
      expC.value = TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
    }
    setState(() {});
  }

  void _triggerBatchLookup(PharoahManager ph) async {
    final rawBatches = ph.batchHistory[widget.med.identityKey] ?? [];

    // Global Batch Lookup modal kholna (Wholesale compliant)
    final selected = await showDialog<dynamic>(
      context: context,
      barrierDismissible: true,
      builder: (context) => MargBatchLookupDialog(
        medicine: widget.med,
        batches: rawBatches,
        prioritizeExpired: widget.allowExpired,
      ),
    );

    if (selected != null) {
      if (selected is BatchInfo) {
        // Dynamic autofill on choice
        setState(() {
          batchC.text = selected.batch;
          expC.text = selected.exp;
          mrpC.text = selected.mrp.toStringAsFixed(2);
          purRateC.text = selected.purRate.toStringAsFixed(2);
          rateAC.text = selected.rateA.toStringAsFixed(2);
          rateBC.text = selected.rateB.toStringAsFixed(2);
          rateCC.text = selected.rateC.toStringAsFixed(2);
          rateCDiscC.text = selected.rateCFormula.toStringAsFixed(2);
          selectedRateType = selected.appliedRateType;
          _syncDiscount(true);
        });
      } else if (selected == "MANUAL") {
        setState(() {
          batchC.clear();
          expC.clear();
          mrpC.text = widget.med.mrp.toString();
          purRateC.text = widget.med.purRate.toString();
          _calcRateC();
        });
      }
    }
  }

  @override 
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    
    double q = double.tryParse(qtyC.text) ?? 0; 
    double r = double.tryParse(purRateC.text) ?? 0;
    double dA = double.tryParse(discAmtC.text) ?? 0; 
    double g = double.tryParse(gstC.text) ?? 0;
    double netTotal = ((q * r) - dA) * (1 + g/100);

    // Jade Forest Theme Colors
    const Color brandTeal = Color(0xFF0F766E); 
    const Color sunsetCoral = Color(0xFFF97316); 
    const Color jadeForest = Color(0xFF065F46); 
    const Color mintLight = Color(0xFF34D399); 

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          width: 440,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: sunsetCoral.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 25,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Vibrant Jade Forest Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [brandTeal, Color(0xFF115E59)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "JADE FOREST INWARD CONFIG",
                            style: TextStyle(
                              color: Color(0xFF99F6E4),
                              fontWeight: FontWeight.w900,
                              fontSize: 9,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${widget.srNo}. ${widget.med.name}",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.1)),
                      icon: const Icon(Icons.close_rounded, size: 20, color: Colors.white70),
                      onPressed: widget.onCancel,
                    )
                  ],
                ),
              ),

              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row 1: Batch & Expiry
                      Row(
                        children: [
                          Expanded(
                            child: _vibrantInput(
                              "BATCH (Case-Sensitive)", 
                              batchC, 
                              brandTeal, 
                              false, 
                              onChanged: (v) => setState(() {}),
                              suffix: InkWell(
                                onTap: () => _triggerBatchLookup(ph),
                                child: const Icon(Icons.list_alt_rounded, color: Color(0xFF115E59), size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _vibrantInput("EXPIRY (MM/YY)", expC, brandTeal, false, isNum: true, onChanged: _formatExpiry)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Rate selection Row
                      Row(
                        children: [
                          _segmentTab("RATE A", selectedRateType == "A", sunsetCoral, () { setState(() { selectedRateType = "A"; _calcRateC(); }); }),
                          _segmentTab("RATE B", selectedRateType == "B", sunsetCoral, () { setState(() { selectedRateType = "B"; _calcRateC(); }); }),
                          _segmentTab("RATE C", selectedRateType == "C", sunsetCoral, () { setState(() { selectedRateType = "C"; _calcRateC(); }); }),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          if (selectedRateType == "C") ...[
                            Expanded(child: _vibrantInput("C FORMULA %", rateCDiscC, brandTeal, false, isNum: true, onChanged: (v) => _calcRateC())),
                            const SizedBox(width: 12),
                          ],
                          Expanded(child: _vibrantInput("MRP", mrpC, brandTeal, false, isNum: true, onChanged: (v) => _calcRateC())),
                          const SizedBox(width: 12),
                          Expanded(child: _vibrantInput("PUR. RATE", purRateC, brandTeal, false, isNum: true, onChanged: (v) => _syncDiscount(true))),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(child: _vibrantInput("QTY", qtyC, brandTeal, false, isNum: true, highlight: true, onChanged: (v) => _syncDiscount(true))),
                          const SizedBox(width: 12),
                          Expanded(child: _vibrantInput("FREE", freeC, brandTeal, false, isNum: true)),
                          const SizedBox(width: 12),
                          Expanded(child: _vibrantInput("GST %", gstC, brandTeal, false, isNum: true, onChanged: (v) => _calcRateC())),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(child: _vibrantInput("DISC %", discPerC, brandTeal, false, isNum: true, onChanged: (v) => _syncDiscount(true))),
                          const SizedBox(width: 12),
                          Expanded(child: _vibrantInput("DISC ₹", discAmtC, brandTeal, false, isNum: true, onChanged: (v) => _syncDiscount(false))),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Grid showing all derived rates
                      Row(
                        children: [
                          Expanded(child: _vibrantInput("RATE A", rateAC, brandTeal, false, isNum: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _vibrantInput("RATE B", rateBC, brandTeal, false, isNum: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _vibrantInput("RATE C", rateCC, brandTeal, true, isNum: true, labelColor: Colors.purple)),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Glowing Jade total box
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: jadeForest,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: mintLight.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
                          ]
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "NET ITEM TOTAL",
                              style: TextStyle(color: Color(0xFFA7F3D0), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                            ),
                            Text(
                              "₹ ${netTotal.toStringAsFixed(2)}",
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: mintLight),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Solid Action Button
                      // Solid Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: sunsetCoral,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ), 
                          onPressed: () {
                             widget.onAdd(PurchaseItem(
                                id: widget.existingItem?.id ?? DateTime.now().toString(),
                                srNo: widget.srNo, medicineID: widget.med.id, name: widget.med.name, packing: widget.med.packing,
                                batch: batchC.text.trim(), // 👈 Case Preserved (Removed .toUpperCase())
                                exp: expC.text, hsn: widget.med.hsnCode, mrp: double.tryParse(mrpC.text) ?? 0,
                                qty: double.tryParse(qtyC.text) ?? 0, freeQty: double.tryParse(freeC.text) ?? 0,
                                purchaseRate: double.tryParse(purRateC.text) ?? 0, gstRate: double.tryParse(gstC.text) ?? 0,
                                total: netTotal, discountPer: double.tryParse(discPerC.text) ?? 0, discountRupees: dA,
                                rateA: double.tryParse(rateAC.text) ?? 0, rateB: double.tryParse(rateBC.text) ?? 0, rateC: double.tryParse(rateCC.text) ?? 0,
                                appliedRateType: selectedRateType, rateCFormula: double.tryParse(rateCDiscC.text) ?? 0.0,
                                isBreakage: widget.allowExpired
                             ));
                          }, 
                          child: const Text("CONFIRM & ADD", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.0))
                        ),
                      )
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _vibrantInput(
    String label,
    TextEditingController ctrl,
    Color activeColor,
    bool isReadOnly, {
    Color? labelColor,
    bool highlight = false,
    bool isNum = false,
    Function(String)? onChanged,
    Widget? suffix, // Mapped safely
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: labelColor ?? const Color(0xFF64748B),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: highlight ? activeColor.withOpacity(0.05) : (isReadOnly ? const Color(0xFFF1F5F9) : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlight ? activeColor : (isReadOnly ? const Color(0xFFE2E8F0) : activeColor.withOpacity(0.3)),
              width: highlight ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  readOnly: isReadOnly,
                  onChanged: onChanged,
                  keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: isReadOnly ? const Color(0xFF64748B) : const Color(0xFF0F172A),
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (suffix != null) suffix,
            ],
          ),
        ),
      ],
    );
  }

  Widget _segmentTab(String label, bool isSelected, Color themeColor, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? themeColor : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? themeColor : const Color(0xFFE2E8F0)),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}
