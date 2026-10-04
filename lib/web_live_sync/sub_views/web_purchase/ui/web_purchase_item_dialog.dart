// FILE: lib/web_live_sync/sub_views/web_purchase/ui/web_purchase_item_dialog.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pharoah_erp/web_live_sync/web_models.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_billing/web_batch_lookup_dialog.dart';

class WebPurchaseItemDialog extends StatefulWidget {
  final Medicine med;
  final int srNo;
  final PurchaseItem? existingItem;
  final Function(PurchaseItem) onAdd;
  final VoidCallback onCancel;

  const WebPurchaseItemDialog({
    super.key,
    required this.med,
    required this.srNo,
    this.existingItem,
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<WebPurchaseItemDialog> createState() => _WebPurchaseItemDialogState();
}

class _WebPurchaseItemDialogState extends State<WebPurchaseItemDialog> {
  final batchC = TextEditingController();
  final expC = TextEditingController();
  final mrpC = TextEditingController();
  final purRateC = TextEditingController();
  final qtyC = TextEditingController(text: "1");
  final freeC = TextEditingController(text: "0");
  final gstC = TextEditingController();
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
      mrpC.text = i.mrp.toStringAsFixed(2);
      purRateC.text = i.purchaseRate.toStringAsFixed(2);
      qtyC.text = i.qty.toInt().toString();
      freeC.text = i.freeQty.toInt().toString();
      gstC.text = i.gstRate.toString();
      rateAC.text = i.rateA.toStringAsFixed(2);
      rateBC.text = i.rateB.toStringAsFixed(2);
      rateCC.text = i.rateC.toStringAsFixed(2);
      rateCDiscC.text = i.rateCFormula.toString();
      selectedRateType = i.appliedRateType;
      discPerC.text = i.discountPer.toString();
      _syncDiscount(true);
    } else {
      mrpC.text = widget.med.mrp.toStringAsFixed(2);
      purRateC.text = widget.med.purRate > 0 ? widget.med.purRate.toStringAsFixed(2) : "0.00";
      rateAC.text = widget.med.rateA.toStringAsFixed(2);
      rateBC.text = widget.med.rateB.toStringAsFixed(2);
      gstC.text = widget.med.gst.toString();
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

  void _triggerBatchLookup(PharoahWebManager webPh) async {
    final rawBatches = webPh.batchHistory[widget.med.identityKey] ?? [];

    final selected = await showDialog<dynamic>(
      context: context,
      barrierDismissible: true,
      builder: (context) => WebBatchLookupDialog(
        medicine: widget.med,
        batches: rawBatches,
        prioritizeExpired: false,
      ),
    );

    if (selected != null) {
      if (selected is BatchInfo) {
        setState(() {
          batchC.text = selected.batch;
          expC.text = selected.exp;
          mrpC.text = selected.mrp.toStringAsFixed(2);
          purRateC.text = selected.purRate > 0 ? selected.purRate.toStringAsFixed(2) : selected.rate.toStringAsFixed(2);
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
          mrpC.text = widget.med.mrp.toStringAsFixed(2);
          purRateC.text = widget.med.purRate.toStringAsFixed(2);
          _calcRateC();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    double q = double.tryParse(qtyC.text) ?? 0;
    double pRate = double.tryParse(purRateC.text) ?? 0;
    double dAmt = double.tryParse(discAmtC.text) ?? 0;
    double gPer = double.tryParse(gstC.text) ?? 0;

    double gross = q * pRate;
    double taxable = gross - dAmt;
    double taxAmt = taxable * (gPer / 100);
    double netTotal = taxable + taxAmt;

    const Color brandAmber = Color(0xFFD97706);
    const Color brandDark = Color(0xFF1E293B);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Container(
          width: 540,
          decoration: BoxDecoration(
            color: brandDark,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: brandAmber.withOpacity(0.5), width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 25, offset: Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF78350F), brandDark],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: Color(0x33F59E0B), shape: BoxShape.circle),
                      child: const Icon(Icons.downloading_rounded, color: Color(0xFFFBBF24), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("PURCHASE INWARD ITEM CONFIG", style: TextStyle(color: Color(0xFFFBBF24), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          const SizedBox(height: 2),
                          Text("${widget.srNo}. ${widget.med.name} (${widget.med.packing})", style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                      onPressed: widget.onCancel,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: _inputField(
                              label: "BATCH NO (CASE-SENSITIVE) *",
                              ctrl: batchC,
                              suffix: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: brandAmber,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  elevation: 0,
                                ),
                                onPressed: () => _triggerBatchLookup(webPh),
                                icon: const Icon(Icons.layers_rounded, size: 14),
                                label: const Text("BATCHES", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: _inputField(
                              label: "EXPIRY (MM/YY) *",
                              ctrl: expC,
                              isNum: true,
                              onChanged: _formatExpiry,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text("APPLY SCHEME:", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          _segmentRate("RATE A", selectedRateType == "A", () => setState(() => selectedRateType = "A")),
                          const SizedBox(width: 6),
                          _segmentRate("RATE B", selectedRateType == "B", () => setState(() => selectedRateType = "B")),
                          const SizedBox(width: 6),
                          _segmentRate("RATE C", selectedRateType == "C", () {
                            setState(() {
                              selectedRateType = "C";
                              _calcRateC();
                            });
                          }),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (selectedRateType == "C") ...[
                            Expanded(child: _inputField(label: "C FORMULA %", ctrl: rateCDiscC, isNum: true, onChanged: (_) => _calcRateC())),
                            const SizedBox(width: 8),
                          ],
                          Expanded(child: _inputField(label: "MRP ₹", ctrl: mrpC, isNum: true, onChanged: (_) { if (selectedRateType == "C") _calcRateC(); })),
                          const SizedBox(width: 8),
                          Expanded(child: _inputField(label: "PUR. RATE ₹ *", ctrl: purRateC, isNum: true, onChanged: (_) => _syncDiscount(true))),
                          const SizedBox(width: 8),
                          Expanded(child: _inputField(label: "GST %", ctrl: gstC, isNum: true, onChanged: (_) { if (selectedRateType == "C") _calcRateC(); })),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _inputField(label: "QTY *", ctrl: qtyC, isNum: true, onChanged: (_) => _syncDiscount(true))),
                          const SizedBox(width: 8),
                          Expanded(child: _inputField(label: "FREE QTY", ctrl: freeC, isNum: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _inputField(label: "DISC %", ctrl: discPerC, isNum: true, onChanged: (_) => _syncDiscount(true))),
                          const SizedBox(width: 8),
                          Expanded(child: _inputField(label: "DISC ₹", ctrl: discAmtC, isNum: true, onChanged: (_) => _syncDiscount(false))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _inputField(label: "RATE A ₹", ctrl: rateAC, isNum: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _inputField(label: "RATE B ₹", ctrl: rateBC, isNum: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _inputField(label: "RATE C ₹", ctrl: rateCC, isNum: true, isReadOnly: selectedRateType == "C")),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x33F59E0B)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Taxable: ₹${taxable.toStringAsFixed(2)} | GST: ₹${taxAmt.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                Text("Gross: ₹${gross.toStringAsFixed(2)} - Disc: ₹${dAmt.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text("NET INWARD VALUE", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                Text("₹${netTotal.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 18, fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandAmber,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            if (batchC.text.trim().isEmpty || expC.text.trim().isEmpty || q <= 0 || pRate <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Batch, Expiry, Qty and Purchase Rate are required!"), backgroundColor: Colors.orange),
                              );
                              return;
                            }

                            double mrp = double.tryParse(mrpC.text) ?? 0.0;
                            double a = double.tryParse(rateAC.text) ?? mrp;
                            double b = double.tryParse(rateBC.text) ?? (a * 0.95);
                            double rateCVal = double.tryParse(rateCC.text) ?? (a * 0.92);

                            widget.onAdd(PurchaseItem(
                              id: widget.existingItem?.id ?? "PITM-${DateTime.now().millisecondsSinceEpoch}",
                              srNo: widget.srNo,
                              medicineID: widget.med.id,
                              name: widget.med.name,
                              packing: widget.med.packing,
                              batch: batchC.text.trim(),
                              exp: expC.text.trim(),
                              hsn: widget.med.hsnCode,
                              mrp: mrp,
                              qty: q,
                              freeQty: double.tryParse(freeC.text) ?? 0.0,
                              purchaseRate: pRate,
                              gstRate: gPer,
                              total: netTotal,
                              rateA: a,
                              rateB: b,
                              rateC: rateCVal,
                              discountPer: double.tryParse(discPerC.text) ?? 0.0,
                              discountRupees: dAmt,
                              appliedRateType: selectedRateType,
                              rateCFormula: double.tryParse(rateCDiscC.text) ?? 0.0,
                            ));
                          },
                          child: Text(
                            widget.existingItem != null ? "UPDATE INWARD ITEM" : "CONFIRM & ADD TO INWARD",
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputField({
    required String label,
    required TextEditingController ctrl,
    bool isNum = false,
    bool isReadOnly = false,
    Widget? suffix,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: isReadOnly ? Colors.black38 : Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  readOnly: isReadOnly,
                  onChanged: onChanged,
                  keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8), border: InputBorder.none),
                ),
              ),
              if (suffix != null) suffix,
            ],
          ),
        ),
      ],
    );
  }

  Widget _segmentRate(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF59E0B) : Colors.black26,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: isSelected ? Colors.black : Colors.white54, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
