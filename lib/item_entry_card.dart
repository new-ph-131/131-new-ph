// FILE: lib/item_entry_card.dart (ROYAL COBALT + BACKDROP BLUR + MARG BATCH OVERLAY)

import 'dart:ui'; // Backdrop Filter के ब्लर इफ़ेक्ट के लिए अनिवार्य
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'pharoah_manager.dart';
import 'expiry_master.dart';
import 'batch_sync_engine.dart';
import 'widgets.dart'; // Naya global lookup widget load karne ke liye

class ItemEntryCard extends StatefulWidget {
  final Medicine med;
  final int srNo;
  final String partyState; 
  final BillItem? existingItem;
  final Function(BillItem) onAdd;
  final VoidCallback onCancel;
  final bool allowExpired; 

  const ItemEntryCard({
    super.key,
    required this.med,
    required this.srNo,
    required this.partyState, 
    this.existingItem,
    required this.onAdd,
    required this.onCancel,
    this.allowExpired = false, 
  });

  @override
  State<ItemEntryCard> createState() => _ItemEntryCardState();
}

class _ItemEntryCardState extends State<ItemEntryCard> {
  // लॉजिक कंट्रोलर्स (यथावत - 100% Preserved)
  final batchC = TextEditingController();
  final expC = TextEditingController();
  final mrpC = TextEditingController();
  final rateC = TextEditingController(); 
  final rateCDiscC = TextEditingController(text: "0.0");
  final qtyC = TextEditingController();
  final freeC = TextEditingController(text: "0"); 
  final gstC = TextEditingController();
  final normDiscC = TextEditingController(text: "0.0");
  final discAmtC = TextEditingController(text: "0.0"); 

  String selectedRateType = "A";
  bool hideZeroStock = true; 

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
      mrpC.text = i.mrp.toString();
      rateC.text = i.rate.toString();
      qtyC.text = i.qty.toString();
      freeC.text = i.freeQty.toString();
      gstC.text = i.gstRate.toString();
      
      selectedRateType = i.appliedRateType; 
      rateCDiscC.text = i.rateCFormula.toString();
      normDiscC.text = i.discountPer.toString();
      
      _syncBillDiscount(true); 
    } else {
      mrpC.text = widget.med.mrp.toString();
      gstC.text = widget.med.gst.toString();
      _updateRateLogic();
    }
  }

  void _calculateRateC() {
    double mrp = double.tryParse(mrpC.text) ?? 0.0;
    double gst = double.tryParse(gstC.text) ?? 0.0;
    double formulaDisc = double.tryParse(rateCDiscC.text) ?? 0.0;
    double baseTaxable = (mrp / (1 + (gst / 100)));
    double finalDerivedRate = baseTaxable - (baseTaxable * (formulaDisc / 100));
    rateC.text = finalDerivedRate.toStringAsFixed(2);
    _syncBillDiscount(true);
  }

  void _syncBillDiscount(bool isPercentSource) {
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

  void _updateRateLogic() {
    if (selectedRateType == "C") { _calculateRateC(); } 
    else { 
      rateC.text = selectedRateType == "A" ? widget.med.rateA.toString() : widget.med.rateB.toString(); 
      _syncBillDiscount(true);
    }
    setState(() {});
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
    final ph = Provider.of<PharoahManager>(context, listen: false);
    double q = double.tryParse(qtyC.text) ?? 0;
    double r = double.tryParse(rateC.text) ?? 0;
    double dAmt = double.tryParse(discAmtC.text) ?? 0;
    double g = double.tryParse(gstC.text) ?? 0;
    double gross = r * q;
    double taxable = gross - dAmt;
    double totalTax = taxable * (g / 100);
    bool isLocal = (ph.activeCompany?.state.toLowerCase() == widget.partyState.toLowerCase());
    return {
      'taxable': taxable, 
      'cgst': isLocal ? totalTax / 2 : 0, 'sgst': isLocal ? totalTax / 2 : 0, 'igst': !isLocal ? totalTax : 0, 
      'total': taxable + totalTax, 'discountAmt': dAmt
    };
  }

  // ===========================================================================
  // 📠 MARG-STYLE BATCH RECALL & TWO-WAY SYNC CONTROLLER
  // ===========================================================================
  void _triggerBatchLookup(PharoahManager ph) async {
    final rawBatches = ph.batchHistory[widget.med.identityKey] ?? [];

    // Global Batch Lookup modal kholna (Step 2 se loaded)
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
        // Two-way sync: Selected batch ka saara data controllers me load karein
        setState(() {
          batchC.text = selected.batch;
          expC.text = selected.exp;
          mrpC.text = selected.mrp.toStringAsFixed(2);
          
          // Current selected segment rate ko naye batch ke anusaar sync karein
          if (selectedRateType == "A") {
            rateC.text = selected.rateA.toStringAsFixed(2);
          } else if (selectedRateType == "B") {
            rateC.text = selected.rateB.toStringAsFixed(2);
          } else {
            rateC.text = selected.rateC.toStringAsFixed(2);
            rateCDiscC.text = selected.rateCFormula.toStringAsFixed(2);
          }
          _syncBillDiscount(true);
        });
      } else if (selected == "MANUAL") {
        // New manual entry fallback click
        setState(() {
          batchC.clear();
          expC.clear();
          mrpC.text = widget.med.mrp.toString();
          _updateRateLogic();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final totals = _calcTotals();

    // Theme Colors
    const Color brandDark = Color(0xFF1E1B4B); 
    const Color accentElectric = Color(0xFF3B82F6); 
    const Color neonGreen = Color(0xFF10B981); 

    final rawBatches = BatchSyncEngine.getFilteredBatches(
      ph: ph, 
      productKey: widget.med.identityKey, 
      hideExpired: !widget.allowExpired
    );

    final matchingBatches = rawBatches.where((b) {
      bool matchesSearch = b.batch.toLowerCase().contains(batchC.text.toLowerCase());
      if (!matchesSearch) return false;
      if (ph.showBatchFilter && hideZeroStock && b.qty <= 0) {
        return false; 
      }
      return true;
    }).toList();

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
            border: Border.all(color: accentElectric.withOpacity(0.4), width: 1.5),
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
              // Vibrant Royal Cobalt Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [brandDark, Color(0xFF312E81)],
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
                            "ROYAL COBALT CONFIG",
                            style: TextStyle(
                              color: Color(0xFF818CF8),
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
                              accentElectric, 
                              false, 
                              onChanged: (v) => setState(() {}),
                              suffix: InkWell(
                                onTap: () => _triggerBatchLookup(ph),
                                child: const Icon(Icons.list_alt_rounded, color: Color(0xFF312E81), size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _vibrantInput("EXPIRY (MM/YY)", expC, accentElectric, false, isNum: true, onChanged: _formatExpiry)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // High Contrast Segmented Buttons
                      Row(
                        children: [
                          _segmentTab("RATE A", selectedRateType == "A", accentElectric, () { setState(() { selectedRateType = "A"; _updateRateLogic(); }); }),
                          _segmentTab("RATE B", selectedRateType == "B", accentElectric, () { setState(() { selectedRateType = "B"; _updateRateLogic(); }); }),
                          _segmentTab("RATE C", selectedRateType == "C", accentElectric, () { setState(() { selectedRateType = "C"; _updateRateLogic(); }); }),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Price inputs row
                      Row(
                        children: [
                          if (selectedRateType == "C") ...[
                            Expanded(child: _vibrantInput("C DISC%", rateCDiscC, accentElectric, false, isNum: true, onChanged: (v) => _calculateRateC())),
                            const SizedBox(width: 12),
                          ],
                          Expanded(child: _vibrantInput("MRP", mrpC, accentElectric, false, isNum: true, onChanged: (v) { if(selectedRateType=="C") _calculateRateC(); })),
                          const SizedBox(width: 12),
                          Expanded(child: _vibrantInput("UNIT RATE", rateC, accentElectric, selectedRateType == "C", isNum: true, labelColor: selectedRateType == "C" ? Colors.purple : null, onChanged: (v) => _syncBillDiscount(true))),
                          const SizedBox(width: 12),
                          Expanded(child: _vibrantInput("GST %", gstC, accentElectric, true)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(child: _vibrantInput("QUANTITY", qtyC, accentElectric, false, isNum: true, highlight: true, onChanged: (v) => _syncBillDiscount(true))),
                          const SizedBox(width: 12),
                          Expanded(child: _vibrantInput("FREE QTY", freeC, accentElectric, false, isNum: true)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(child: _vibrantInput("DISCOUNT %", normDiscC, accentElectric, false, isNum: true, onChanged: (v) => _syncBillDiscount(true))),
                          const SizedBox(width: 12),
                          Expanded(child: _vibrantInput("DISCOUNT ₹", discAmtC, accentElectric, false, isNum: true, onChanged: (v) => _syncBillDiscount(false))),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Glowing Neon Emerald Total Box
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: brandDark,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: neonGreen.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
                          ]
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "NET ITEM TOTAL",
                              style: TextStyle(color: Color(0xFFC7D2FE), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                            Text(
                              "₹ ${totals['total']!.toStringAsFixed(2)}",
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: neonGreen),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Elegant Solid Confirm Button
                      // Elegant Solid Confirm Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentElectric,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ), 
                          onPressed: () {
                             if (qtyC.text.isEmpty || qtyC.text == "0") return;
                             widget.onAdd(BillItem(
                                id: widget.existingItem?.id ?? DateTime.now().toString(),
                                srNo: widget.srNo, medicineID: widget.med.id, name: widget.med.name, packing: widget.med.packing,
                                batch: batchC.text.trim(), // 👈 Case Preserved (Removed .toUpperCase())
                                exp: expC.text, hsn: widget.med.hsnCode, mrp: double.tryParse(mrpC.text) ?? 0,
                                qty: double.tryParse(qtyC.text) ?? 0, freeQty: double.tryParse(freeC.text) ?? 0,
                                rate: double.tryParse(rateC.text) ?? 0, gstRate: double.tryParse(gstC.text) ?? 0,
                                cgst: totals['cgst']!, sgst: totals['sgst']!, igst: totals['igst']!, total: totals['total']!,
                                discountRupees: totals['discountAmt']!, 
                                discountPer: double.tryParse(normDiscC.text) ?? 0.0,
                                appliedRateType: selectedRateType, 
                                rateCFormula: double.tryParse(rateCDiscC.text) ?? 0.0, 
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

  // Modified Vibrant Input: Support optional suffix widgets (e.g. search list icon) seamlessly
  Widget _vibrantInput(
    String label,
    TextEditingController ctrl,
    Color activeColor,
    bool isReadOnly, {
    Color? labelColor,
    bool highlight = false,
    bool isNum = false,
    Function(String)? onChanged,
    Widget? suffix, // Mapped for Batch Search trigger
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
              if (suffix != null) suffix, // Non-intrusively load search icon button
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
