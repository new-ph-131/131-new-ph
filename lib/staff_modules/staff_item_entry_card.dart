// FILE: lib/staff_modules/staff_item_entry_card.dart (UPGRADED DYNAMIC BATCH FILTER VERSION)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../pharoah_manager.dart';
import '../batch_sync_engine.dart'; // NAYA IMPORT
import '../widgets.dart'; 
import '../expiry_master.dart';    // NAYA IMPORT

class StaffItemEntryCard extends StatefulWidget {
  final Medicine med;
  final int srNo;
  final BillItem? existingItem;
  final Function(BillItem) onAdd;
  final VoidCallback onCancel;

  const StaffItemEntryCard({
    super.key,
    required this.med,
    required this.srNo,
    this.existingItem,
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<StaffItemEntryCard> createState() => _StaffItemEntryCardState();
}

class _StaffItemEntryCardState extends State<StaffItemEntryCard> {
  final batchC = TextEditingController();
  final expC = TextEditingController();
  final mrpC = TextEditingController();
  final rateC = TextEditingController();
  final qtyC = TextEditingController();
  final freeC = TextEditingController(text: "0");
  final gstC = TextEditingController();
  final normDiscC = TextEditingController(text: "0.0");

  // --- NAYA: Dynamic Batch Filter Local State ---
  bool hideZeroStock = true; // By default zero stock batches chhupayenge

  @override
  void initState() {
    super.initState();
    _setupInitialData();
  }

  // 🆕 TWO-WAY RECALL: Mapped for Staff Item Entry Card
  void _triggerBatchLookup(PharoahManager ph) async {
    final rawBatches = ph.batchHistory[widget.med.identityKey] ?? [];

    // Global Batch Lookup modal kholna (Staff Compliant)
    final selected = await showDialog<dynamic>(
      context: context,
      barrierDismissible: true,
      builder: (context) => MargBatchLookupDialog(
        medicine: widget.med,
        batches: rawBatches,
        prioritizeExpired: false, // Sales screen default
      ),
    );

    if (selected != null) {
      if (selected is BatchInfo) {
        setState(() {
          batchC.text = selected.batch;
          expC.text = selected.exp;
          mrpC.text = selected.mrp.toString();
          rateC.text = selected.rate.toString();
        });
      } else if (selected == "MANUAL") {
        setState(() {
          batchC.clear();
          expC.clear();
          mrpC.text = widget.med.mrp.toString();
          rateC.text = widget.med.rateA.toString();
        });
      }
    }
  }

  void _setupInitialData() {
    if (widget.existingItem != null) {
      final i = widget.existingItem!;
      batchC.text = i.batch;
      expC.text = i.exp;
      mrpC.text = i.mrp.toString();
      rateC.text = i.rate.toString();
      qtyC.text = i.qty.toString();
      freeC.text = i.freeQty.toString();
      gstC.text = i.gstRate.toString();
    } else {
      mrpC.text = widget.med.mrp.toString();
      rateC.text = widget.med.rateA.toString(); 
      gstC.text = widget.med.gst.toString();
    }
  }

  void _formatExpiry(String val) {
    String text = val.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length >= 2 && !val.contains('/')) { text = '${text.substring(0, 2)}/${text.substring(2)}'; }
    if (text.length > 5) text = text.substring(0, 5);
    if (expC.text != text) {
      expC.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    setState(() {});
  }

  Map<String, double> _calcTotals() {
    double q = double.tryParse(qtyC.text) ?? 0;
    double r = double.tryParse(rateC.text) ?? 0;
    double d = double.tryParse(normDiscC.text) ?? 0;
    double g = double.tryParse(gstC.text) ?? 0;
    double gross = r * q;
    double discAmt = gross * (d / 100);
    double taxable = gross - discAmt;
    double taxAmt = taxable * (g / 100);
    return {'total': taxable + taxAmt, 'discountAmt': discAmt};
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final totals = _calcTotals();

    // --- SMART BATCH SELECTION FILTER ENGINE (NEW) ---
    final rawBatches = BatchSyncEngine.getFilteredBatches(
      ph: ph, 
      productKey: widget.med.identityKey,
      hideExpired: true // Staff ko expired batch nahi dikhna chahiye
    );

    final matchingBatches = rawBatches.where((b) {
      bool matchesSearch = b.batch.toLowerCase().contains(batchC.text.toLowerCase());
      if (!matchesSearch) return false;
      
      // Dynamic Filter Check
      if (ph.showBatchFilter && hideZeroStock && b.qty <= 0) {
        return false;
      }
      return true;
    }).toList();

    // Expiry UI Status
    String expStr = expC.text;
    ExpiryStatus expStatus = ExpiryMaster.getStatus(expStr);
    Color statusColor = ExpiryMaster.getStatusColor(expStr);
    bool isAllowed = ExpiryMaster.isSaleAllowed(expStr);

    return Container(
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("${widget.srNo}. ${widget.med.name}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            IconButton(icon: const Icon(Icons.cancel, color: Colors.grey), onPressed: widget.onCancel)
          ]),
          const Divider(),
      Row(children: [
                    Expanded(
                      child: _input(
                        batchC, 
                        "BATCH", 
                        Icons.layers, 
                        onChanged: (v)=>setState((){}),
                        suffix: InkWell(
                          onTap: () => _triggerBatchLookup(ph),
                          child: const Icon(Icons.list_alt_rounded, color: Colors.teal, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _input(expC, "EXPIRY", Icons.event, color: statusColor, isNum: true, onChanged: _formatExpiry)),
                  ]),

          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _input(mrpC, "MRP", Icons.tag, isReadOnly: true)),
            const SizedBox(width: 8),
            Expanded(child: _input(rateC, "SALE RATE", Icons.payments, color: Colors.blue)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _input(qtyC, "QTY", Icons.add_box, isNum: true, onChanged: (v)=>setState((){}))),
            const SizedBox(width: 8),
            Expanded(child: _input(freeC, "FREE", Icons.card_giftcard, isNum: true)),
            const SizedBox(width: 8),
            Expanded(child: _input(normDiscC, "DISC %", Icons.percent, isNum: true, onChanged: (v)=>setState((){}))),
          ]),
          const SizedBox(height: 20),
          Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Net Amount:", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("₹${totals['total']!.toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
            ]),
          ),
          const SizedBox(height: 15),
          SizedBox(width: double.infinity, height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: isAllowed ? Colors.green : Colors.grey.shade400, foregroundColor: Colors.white),
              onPressed: (!isAllowed || qtyC.text.isEmpty || qtyC.text == "0") ? null : () {
                // NAYA: Staff screen se bhi batch register karo
                BatchSyncEngine.registerBatchActivity(ph: ph, productKey: widget.med.identityKey, batchNo: batchC.text, exp: expC.text, packing: widget.med.packing, mrp: double.tryParse(mrpC.text) ?? 0, rate: double.tryParse(rateC.text) ?? 0);

                widget.onAdd(BillItem(
                  id: widget.existingItem?.id ?? DateTime.now().toString(),
                  srNo: widget.srNo,
                  medicineID: widget.med.id,
                  name: widget.med.name,
                  packing: widget.med.packing,
                  batch: batchC.text.trim(), // 👈 Case Preserved (Removed .toUpperCase() and added .trim())
                  exp: expC.text,
                  hsn: widget.med.hsnCode,
                  mrp: double.tryParse(mrpC.text) ?? 0,
                  qty: double.tryParse(qtyC.text) ?? 0,
                  freeQty: double.tryParse(freeC.text) ?? 0,
                  rate: double.tryParse(rateC.text) ?? 0,
                  gstRate: double.tryParse(gstC.text) ?? 0,
                  total: totals['total']!,
                  discountRupees: totals['discountAmt']!,
                ));
              },
              child: Text(expStatus == ExpiryStatus.expired ? "EXPIRED BATCH" : "ADD TO BILL", style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

Widget _input(TextEditingController ctrl, String label, IconData icon, {bool isNum = false, bool isReadOnly = false, Color? color, Function(String)? onChanged, Widget? suffix}) {
    return TextField(
      controller: ctrl, readOnly: isReadOnly, onChanged: onChanged,
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
      decoration: InputDecoration(
        labelText: label, 
        prefixIcon: Icon(icon, size: 16), 
        border: const OutlineInputBorder(), 
        isDense: true, 
        filled: isReadOnly, 
        fillColor: isReadOnly ? Colors.grey.shade100 : Colors.white,
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      ),
    );
  }
}
