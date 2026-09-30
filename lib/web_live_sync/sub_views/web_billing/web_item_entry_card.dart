// FILE: lib/web_live_sync/sub_views/web_billing/web_item_entry_card.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../web_models.dart';
import '../../web_expiry_master.dart';
import 'web_batch_lookup_dialog.dart';

class WebItemEntryCard extends StatefulWidget {
  final Medicine med;
  final int srNo;
  final String partyState;
  final String shopState;
  final List<BatchInfo> availableBatches;
  final BillItem? existingItem;
  final Function(BillItem) onAdd;
  final VoidCallback onCancel;
  final bool allowExpired;

  const WebItemEntryCard({
    super.key,
    required this.med,
    required this.srNo,
    required this.partyState,
    required this.shopState,
    required this.availableBatches,
    this.existingItem,
    required this.onAdd,
    required this.onCancel,
    this.allowExpired = false,
  });

  @override
  State<WebItemEntryCard> createState() => _WebItemEntryCardState();
}

class _WebItemEntryCardState extends State<WebItemEntryCard> {
  final batchC = TextEditingController();
  final expC = TextEditingController();
  final mrpC = TextEditingController();
  final rateC = TextEditingController();
  final rateCDiscC = TextEditingController(text: "0.0");
  final qtyC = TextEditingController(text: "1");
  final freeC = TextEditingController(text: "0");
  final gstC = TextEditingController();
  final normDiscC = TextEditingController(text: "0.0");
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
      rateC.text = i.rate.toStringAsFixed(2);
      qtyC.text = i.qty.toInt().toString();
      freeC.text = i.freeQty.toInt().toString();
      gstC.text = i.gstRate.toString();
      selectedRateType = i.appliedRateType;
      rateCDiscC.text = i.rateCFormula.toString();
      normDiscC.text = i.discountPer.toString();
      _syncDiscount(true);
    } else {
      mrpC.text = widget.med.mrp.toStringAsFixed(2);
      gstC.text = widget.med.gst.toString();
      _updateRateLogic();
    }
  }

  void _calculateRateC() {
    double mrp = double.tryParse(mrpC.text) ?? 0.0;
    double gst = double.tryParse(gstC.text) ?? 0.0;
    double formulaDisc = double.tryParse(rateCDiscC.text) ?? 0.0;
    double baseTaxable = (mrp / (1 + (gst / 100)));
    double finalRate = baseTaxable - (baseTaxable * (formulaDisc / 100));
    rateC.text = finalRate.toStringAsFixed(2);
    _syncDiscount(true);
  }

  void _updateRateLogic() {
    if (selectedRateType == "C") {
      _calculateRateC();
    } else {
      rateC.text = (selectedRateType == "A" ? widget.med.rateA : widget.med.rateB).toStringAsFixed(2);
      _syncDiscount(true);
    }
  }

  void _syncDiscount(bool isPercentSource) {
    double q = double.tryParse(qtyC.text) ?? 0;
    double r = double.tryParse(rateC.text) ?? 0;
    double gross = q * r;
    if (gross <= 0) return;
    if (isPercentSource) {
      double p = double.tryParse(normDiscC.text) ?? 0;
      discAmtC.text = (gross * (p / 100)).toStringAsFixed(2);
    } else {
      double a = double.tryParse(discAmtC.text) ?? 0;
      normDiscC.text = ((a / gross) * 100).toStringAsFixed(2);
    }
    setState(() {});
  }

  void _formatExpiry(String val) {
    String text = val.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length >= 2 && !val.contains('/')) {
      text = '${text.substring(0, 2)}/${text.substring(2)}';
    }
    if (text.length > 5) text = text.substring(0, 5);
    if (expC.text != text) {
      expC.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    setState(() {});
  }

  Map<String, double> _calcTotals() {
    double q = double.tryParse(qtyC.text) ?? 0;
    double r = double.tryParse(rateC.text) ?? 0;
    double dAmt = double.tryParse(discAmtC.text) ?? 0;
    double g = double.tryParse(gstC.text) ?? 0;

    double gross = r * q;
    double taxable = gross - dAmt;
    double totalTax = taxable * (g / 100);
    bool isLocal = widget.shopState.trim().toLowerCase() == widget.partyState.trim().toLowerCase();

    return {
      'taxable': taxable,
      'cgst': isLocal ? totalTax / 2 : 0.0,
      'sgst': isLocal ? totalTax / 2 : 0.0,
      'igst': !isLocal ? totalTax : 0.0,
      'total': taxable + totalTax,
      'discountAmt': dAmt,
    };
  }

  void _openBatchLookup() async {
    final selected = await showDialog<dynamic>(
      context: context,
      barrierDismissible: true,
      builder: (context) => WebBatchLookupDialog(
        medicine: widget.med,
        batches: widget.availableBatches,
        prioritizeExpired: widget.allowExpired,
      ),
    );

    if (selected != null) {
      if (selected is BatchInfo) {
        setState(() {
          batchC.text = selected.batch;
          expC.text = selected.exp;
          mrpC.text = selected.mrp.toStringAsFixed(2);
          if (selectedRateType == "A") {
            rateC.text = selected.rateA.toStringAsFixed(2);
          } else if (selectedRateType == "B") {
            rateC.text = selected.rateB.toStringAsFixed(2);
          } else {
            rateC.text = selected.rateC.toStringAsFixed(2);
            rateCDiscC.text = selected.rateCFormula.toStringAsFixed(2);
          }
          _syncDiscount(true);
        });
      } else if (selected == "MANUAL") {
        setState(() {
          batchC.clear();
          expC.clear();
          mrpC.text = widget.med.mrp.toStringAsFixed(2);
          _updateRateLogic();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _calcTotals();
    String expStr = expC.text.trim();
    final expStatus = WebExpiryMaster.getStatus(expStr);
    final statusColor = WebExpiryMaster.getStatusColor(expStr);
    final bool isSaleAllowed = widget.allowExpired || WebExpiryMaster.isSaleAllowed(expStr);

    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 740 ? 680.0 : (screenWidth * 0.94);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: Container(
          width: dialogWidth,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x802563EB), width: 1.5),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 25, offset: Offset(0, 10))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E1B4B), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0x332563EB),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.medication_rounded, color: Color(0xFF38BDF8), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "ITEM BILLING & BATCH CONFIG",
                            style: TextStyle(
                              color: Color(0xFF38BDF8),
                              fontWeight: FontWeight.w900,
                              fontSize: 9,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            "${widget.srNo}. ${widget.med.name.toUpperCase()} (${widget.med.packing})",
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      style: IconButton.styleFrom(backgroundColor: Colors.white10),
                      icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                      onPressed: widget.onCancel,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: _spaciousInput(
                              "BATCH NUMBER (CASE-SENSITIVE)",
                              batchC,
                              isHighlight: true,
                              suffix: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                onPressed: _openBatchLookup,
                                icon: const Icon(Icons.layers_rounded, size: 14),
                                label: const Text("BATCHES", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: _spaciousInput(
                              "EXPIRY (MM/YY)",
                              expC,
                              isNum: true,
                              textColor: statusColor,
                              onChanged: _formatExpiry,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Text("RATE:", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          _rateSegment("RATE A", selectedRateType == "A", () {
                            setState(() { selectedRateType = "A"; _updateRateLogic(); });
                          }),
                          const SizedBox(width: 6),
                          _rateSegment("RATE B", selectedRateType == "B", () {
                            setState(() { selectedRateType = "B"; _updateRateLogic(); });
                          }),
                          const SizedBox(width: 6),
                          _rateSegment("RATE C", selectedRateType == "C", () {
                            setState(() { selectedRateType = "C"; _updateRateLogic(); });
                          }),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          if (selectedRateType == "C") ...[
                            Expanded(
                              child: _spaciousInput("FORMULA DISC %", rateCDiscC, isNum: true, onChanged: (_) => _calculateRateC()),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: _spaciousInput("MRP ₹", mrpC, isNum: true, onChanged: (_) { if (selectedRateType == "C") _calculateRateC(); }),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _spaciousInput("UNIT RATE ₹", rateC, isNum: true, isReadOnly: selectedRateType == "C", isHighlight: selectedRateType != "C", onChanged: (_) => _syncDiscount(true)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _spaciousInput("GST %", gstC, isNum: true, isReadOnly: true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _spaciousInput("QTY", qtyC, isNum: true, isHighlight: true, onChanged: (_) => _syncDiscount(true)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _spaciousInput("FREE", freeC, isNum: true),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _spaciousInput("DISC %", normDiscC, isNum: true, onChanged: (_) => _syncDiscount(true)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _spaciousInput("DISC ₹", discAmtC, isNum: true, onChanged: (_) => _syncDiscount(false)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Taxable: ₹${totals['taxable']!.toStringAsFixed(2)} | GST: ₹${(totals['cgst']! + totals['sgst']! + totals['igst']!).toStringAsFixed(2)}",
                                  style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "CGST: ₹${totals['cgst']!.toStringAsFixed(2)} | SGST: ₹${totals['sgst']!.toStringAsFixed(2)} | IGST: ₹${totals['igst']!.toStringAsFixed(2)}",
                                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text("ITEM TOTAL", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                Text(
                                  "₹${totals['total']!.toStringAsFixed(2)}",
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.w900),
                                ),
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
                            backgroundColor: isSaleAllowed ? const Color(0xFF2563EB) : Colors.red.shade900,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          onPressed: !isSaleAllowed || qtyC.text.isEmpty || qtyC.text == "0"
                              ? null
                              : () {
                                  double q = double.tryParse(qtyC.text) ?? 1;
                                  double freeQ = double.tryParse(freeC.text) ?? 0;
                                  double r = double.tryParse(rateC.text) ?? 0;

                                  widget.onAdd(BillItem(
                                    id: widget.existingItem?.id ?? DateTime.now().toString(),
                                    srNo: widget.srNo,
                                    medicineID: widget.med.id,
                                    name: widget.med.name,
                                    packing: widget.med.packing,
                                    batch: batchC.text.trim(),
                                    exp: expC.text.trim(),
                                    hsn: widget.med.hsnCode,
                                    mrp: double.tryParse(mrpC.text) ?? 0.0,
                                    qty: q,
                                    freeQty: freeQ,
                                    rate: r,
                                    gstRate: double.tryParse(gstC.text) ?? 0.0,
                                    cgst: totals['cgst']!,
                                    sgst: totals['sgst']!,
                                    igst: totals['igst']!,
                                    total: totals['total']!,
                                    discountRupees: totals['discountAmt']!,
                                    discountPer: double.tryParse(normDiscC.text) ?? 0.0,
                                    appliedRateType: selectedRateType,
                                    rateCFormula: double.tryParse(rateCDiscC.text) ?? 0.0,
                                    isBreakage: widget.allowExpired,
                                  ));
                                },
                          child: Text(
                            expStatus == ExpiryStatus.expired && !widget.allowExpired
                                ? "EXPIRED BATCH - SALE BLOCKED"
                                : (widget.existingItem != null ? "UPDATE INVOICE ITEM" : "CONFIRM & ADD TO INVOICE"),
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

  Widget _spaciousInput(
    String label,
    TextEditingController ctrl, {
    bool isNum = false,
    bool isReadOnly = false,
    bool isHighlight = false,
    Color? textColor,
    Widget? suffix,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: isReadOnly ? Colors.black38 : (isHighlight ? const Color(0x332563EB) : Colors.black26),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isHighlight ? const Color(0xFF38BDF8) : Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  readOnly: isReadOnly,
                  onChanged: onChanged,
                  keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                  style: TextStyle(color: textColor ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
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

  Widget _rateSegment(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2563EB) : Colors.black26,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isSelected ? const Color(0xFF60A5FA) : Colors.white10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
