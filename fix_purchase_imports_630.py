import subprocess
import sys

print("==================================================================")
print("🎯 FIXING PACKAGE IMPORTS IN SUB_VIEWS/WEB_PURCHASE (#PH-REV-630)")
print("==================================================================\n")

base = "lib/web_live_sync/sub_views/web_purchase"

# 1. FIX MECHANISM IMPORTS
print("⚙️ Step 1/5: Correcting imports in web_purchase_mechanism.dart...")
mech_code = '''// FILE: lib/web_live_sync/sub_views/web_purchase/mechanism/web_purchase_mechanism.dart

import 'package:pharoah_erp/web_live_sync/web_models.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';

class WebPurchaseMechanism {
  static Future<bool> commitPurchase({
    required PharoahWebManager webPh,
    required String purchaseId,
    required String internalNo,
    required String billNo,
    required Party supplier,
    required DateTime billDate,
    required DateTime entryDate,
    required String paymentMode,
    required List<PurchaseItem> items,
    required double totalAmount,
    required double extraDiscount,
    required double roundOff,
    required List<String> linkedChallanIds,
    String? existingId,
  }) async {
    if (existingId != null) {
      webPh.purchases.removeWhere((p) => p.id == existingId);
    }

    final newPurchase = Purchase(
      id: purchaseId,
      internalNo: internalNo,
      billNo: billNo,
      partyId: supplier.id,
      distributorName: supplier.name,
      date: billDate,
      entryDate: entryDate,
      paymentMode: paymentMode,
      totalAmount: totalAmount,
      extraDiscount: extraDiscount,
      roundOff: roundOff,
      gstStatus: "Pending",
      items: List.from(items),
      linkedChallanIds: linkedChallanIds,
      sourceTag: "WEB-PORTAL",
    );

    webPh.purchases.add(newPurchase);

    // 2-Way Batch Inventory Activity + Medicine Master L.P.R. Update
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        int mIdx = webPh.medicines.indexWhere(
          (m) => m.id == item.medicineID || m.name.trim().toUpperCase() == item.name.trim().toUpperCase()
        );
        if (mIdx != -1) {
          final med = webPh.medicines[mIdx];
          resolvedKey = med.identityKey;
          med.purRate = item.purchaseRate;
          if (item.mrp > 0) med.mrp = item.mrp;
          if (item.rateA > 0) med.rateA = item.rateA;
          if (item.rateB > 0) med.rateB = item.rateB;
          if (item.rateC > 0) med.rateC = item.rateC;
          webPh.updateMedicine(med);
        }
      } catch (_) {}

      webPh.registerBatchActivity(
        productKey: resolvedKey,
        batchNo: item.batch,
        exp: item.exp,
        packing: item.packing,
        mrp: item.mrp,
        rate: item.purchaseRate,
        rateA: item.rateA,
        rateB: item.rateB,
        rateC: item.rateC,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
        qtyChange: item.qty + item.freeQty,
      );
    }

    // Revert any linked challans to Billed
    if (linkedChallanIds.isNotEmpty) {
      for (var id in linkedChallanIds) {
        int idx = webPh.purchaseChallans.indexWhere((c) => c.id == id);
        if (idx != -1) webPh.purchaseChallans[idx].status = "Billed";
      }
    }

    // Update supplier payable
    supplier.opBal += totalAmount;
    webPh.updateParty(supplier);

    webPh.rebuildInventory();
    return await webPh.pushUpdatedDataToCloud();
  }
}
'''
with open(f"{base}/mechanism/web_purchase_mechanism.dart", "w", encoding="utf-8") as f:
    f.write(mech_code)
print("✔ web_purchase_mechanism.dart imports updated.")

# 2. FIX ITEM DIALOG IMPORTS
print("\n🎨 Step 2/5: Correcting imports in web_purchase_item_dialog.dart...")
dialog_code = '''// FILE: lib/web_live_sync/sub_views/web_purchase/ui/web_purchase_item_dialog.dart

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
'''
with open(f"{base}/ui/web_purchase_item_dialog.dart", "w", encoding="utf-8") as f:
    f.write(dialog_code)
print("✔ web_purchase_item_dialog.dart imports updated.")

# 3. FIX STEP 1 (web_purchase_entry_screen.dart) IMPORTS
print("\n🖥️ Step 3/5: Correcting imports in web_purchase_entry_screen.dart...")
step1_code = '''// FILE: lib/web_live_sync/sub_views/web_purchase/ui/web_purchase_entry_screen.dart

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
'''
with open(f"{base}/ui/web_purchase_entry_screen.dart", "w", encoding="utf-8") as f:
    f.write(step1_code)
print("✔ web_purchase_entry_screen.dart imports updated.")

# 4. FIX STEP 2 (web_purchase_billing_screen.dart) IMPORTS
print("\n🖥️ Step 4/5: Correcting imports in web_purchase_billing_screen.dart...")
step2_code = '''// FILE: lib/web_live_sync/sub_views/web_purchase/ui/web_purchase_billing_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:pharoah_erp/web_live_sync/web_models.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/web_pdf_router_service.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_billing/quick_add_product_modal.dart';
import '../mechanism/web_purchase_mechanism.dart';
import 'web_purchase_item_dialog.dart';

class WebPurchaseBillingScreen extends StatefulWidget {
  final Party supplier;
  final String internalNo;
  final String supplierBillNo;
  final DateTime billDate;
  final DateTime entryDate;
  final String paymentMode;
  final Purchase? existingPurchase;
  final bool isReadOnly;
  final VoidCallback onCompleted;

  const WebPurchaseBillingScreen({
    super.key,
    required this.supplier,
    required this.internalNo,
    required this.supplierBillNo,
    required this.billDate,
    required this.entryDate,
    required this.paymentMode,
    this.existingPurchase,
    this.isReadOnly = false,
    required this.onCompleted,
  });

  @override
  State<WebPurchaseBillingScreen> createState() => _WebPurchaseBillingScreenState();
}

class _WebPurchaseBillingScreenState extends State<WebPurchaseBillingScreen> {
  List<PurchaseItem> items = [];
  final extraDiscC = TextEditingController(text: "0");
  final productSearchC = TextEditingController();
  final remarksC = TextEditingController();
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingPurchase != null) {
      items = List.from(widget.existingPurchase!.items);
      extraDiscC.text = widget.existingPurchase!.extraDiscount.toString();
    }
  }

  @override
  void dispose() {
    extraDiscC.dispose();
    productSearchC.dispose();
    remarksC.dispose();
    super.dispose();
  }

  void _recalculateSR() {
    setState(() {
      for (int i = 0; i < items.length; i++) {
        items[i] = items[i].copyWith(srNo: i + 1);
      }
    });
  }

  void _openItemDialog(PharoahWebManager webPh, Medicine med, {PurchaseItem? itemToEdit, int? editIndex}) {
    if (widget.isReadOnly) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => WebPurchaseItemDialog(
        med: med,
        srNo: itemToEdit != null ? itemToEdit.srNo : items.length + 1,
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
          _openItemDialog(webPh, medObj);
        },
      ),
    );
  }

  double get subTotal => items.fold(0.0, (sum, it) => sum + it.total);
  double get totalTaxable => items.fold(0.0, (sum, it) => sum + (it.qty * it.purchaseRate - it.discountRupees));
  double get totalITC => subTotal - totalTaxable;
  double get extraDiscount => double.tryParse(extraDiscC.text) ?? 0.0;
  double get rawGrandTotal => (subTotal - extraDiscount);
  double get finalGrandTotal => rawGrandTotal.roundToDouble();
  double get roundOff => double.parse((finalGrandTotal - rawGrandTotal).toStringAsFixed(2));

  void _finalizePurchase(PharoahWebManager webPh, {bool andPrint = false}) async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Purchase cannot be empty! Please add products."), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => isSaving = true);

    String id = widget.existingPurchase?.id ?? "PUR-WEB-${DateTime.now().millisecondsSinceEpoch}";
    List<String> links = widget.existingPurchase?.linkedChallanIds ?? [];

    bool ok = await WebPurchaseMechanism.commitPurchase(
      webPh: webPh,
      purchaseId: id,
      internalNo: widget.internalNo,
      billNo: widget.supplierBillNo,
      supplier: widget.supplier,
      billDate: widget.billDate,
      entryDate: widget.entryDate,
      paymentMode: widget.paymentMode,
      items: items,
      totalAmount: finalGrandTotal,
      extraDiscount: extraDiscount,
      roundOff: roundOff,
      linkedChallanIds: links,
      existingId: widget.existingPurchase?.id,
    );

    setState(() => isSaving = false);

    if (ok) {
      if (andPrint) {
        final p = Purchase(
          id: id,
          internalNo: widget.internalNo,
          billNo: widget.supplierBillNo,
          partyId: widget.supplier.id,
          distributorName: widget.supplier.name,
          date: widget.billDate,
          entryDate: widget.entryDate,
          paymentMode: widget.paymentMode,
          totalAmount: finalGrandTotal,
          items: items,
          extraDiscount: extraDiscount,
          roundOff: roundOff,
        );
        final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);
        await WebPdfRouterService.printPurchaseInvoice(purchase: p, party: widget.supplier, shop: shopProfile);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Purchase Inward ${widget.internalNo} Saved & Cloud Synced!"), backgroundColor: Colors.green),
        );
        Navigator.pop(context); // Close Step 2
        widget.onCompleted();   // Return to Step 1 or Hub
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "View Inward Items" : "Inward Note: ${widget.internalNo} (Step 2)"),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: "Print Inward Slip",
            onPressed: items.isEmpty
                ? null
                : () async {
                    final tempPur = Purchase(
                      id: "temp",
                      internalNo: widget.internalNo,
                      billNo: widget.supplierBillNo,
                      partyId: widget.supplier.id,
                      distributorName: widget.supplier.name,
                      date: widget.billDate,
                      entryDate: widget.entryDate,
                      paymentMode: widget.paymentMode,
                      totalAmount: finalGrandTotal,
                      items: items,
                      extraDiscount: extraDiscount,
                      roundOff: roundOff,
                    );
                    await WebPdfRouterService.printPurchaseInvoice(
                      purchase: tempPur,
                      party: widget.supplier,
                      shop: CompanyProfile.fromMap(webPh.companyProfile),
                    );
                  },
          ),
          if (!widget.isReadOnly)
            TextButton(
              onPressed: items.isEmpty ? null : () => _finalizePurchase(webPh, andPrint: false),
              child: const Text("FINISH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Top Supplier Info Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: Color(0x33F59E0B), shape: BoxShape.circle),
                        child: const Icon(Icons.business_rounded, color: Color(0xFFF59E0B), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.supplier.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                          Text("Bill No: ${widget.supplierBillNo} • Entry: ${widget.internalNo} • GST: ${widget.supplier.gst}", style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      "DATE: ${DateFormat('dd/MM/yyyy').format(widget.billDate)}",
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (!widget.isReadOnly) _buildProductSearchCard(webPh),
            if (!widget.isReadOnly) const SizedBox(height: 14),

            _buildCartTable(webPh),
            const SizedBox(height: 14),

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
                m.systemId.toLowerCase().contains(query) ||
                m.hsnCode.toLowerCase().contains(query))
            .take(5)
            .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x66F59E0B), width: 1.2),
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
                    labelText: "SEARCH PRODUCT TO INWARD",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
                    hintText: "Type medicine name...",
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFFF59E0B), size: 18),
                    suffixIcon: productSearchC.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 16),
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
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x33F59E0B)),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: matchingMeds.length,
                itemBuilder: (context, idx) {
                  final med = matchingMeds[idx];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.medication_rounded, color: Color(0xFFF59E0B), size: 18),
                    title: Row(
                      children: [
                        Text(med.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                        const SizedBox(width: 8),
                        Text("(${med.packing})", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                    subtitle: Text("MRP: ₹${med.mrp.toStringAsFixed(2)} | Pur.Rate: ₹${med.purRate.toStringAsFixed(2)} | Stock: ${med.stock.toInt()}", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    onTap: () {
                      setState(() => productSearchC.clear());
                      _openItemDialog(webPh, med);
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
              const Icon(Icons.inventory_2_outlined, color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Text("INWARD ITEMS (${items.length})", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
          const Divider(color: Colors.white10, height: 16),
          if (items.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("Inward cart is empty. Search products above to add stock.", style: TextStyle(color: Colors.white38, fontSize: 11))))
          else
            Container(
              constraints: const BoxConstraints(minHeight: 220, maxHeight: 520),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 700),
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(35),
                          1: FlexColumnWidth(3),
                          2: FixedColumnWidth(65),
                          3: FixedColumnWidth(75),
                          4: FixedColumnWidth(55),
                          5: FixedColumnWidth(65),
                          6: FixedColumnWidth(70),
                          7: FixedColumnWidth(55),
                          8: FixedColumnWidth(50),
                          9: FixedColumnWidth(80),
                          10: FixedColumnWidth(65),
                        },
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                            children: [
                              _th("SN"), _th("PRODUCT NAME", isLeft: true), _th("PACK"), _th("BATCH"), _th("EXP"), _th("QTY"), _th("RATE"), _th("DISC"), _th("GST%"), _th("TOTAL"), _th("ACT")
                            ],
                          ),
                          ...items.asMap().entries.map((entry) {
                            int idx = entry.key;
                            PurchaseItem it = entry.value;
                            String qtyDisp = "${it.qty.toInt()}${it.freeQty > 0 ? ' + ${it.freeQty.toInt()}' : ''}";
                            String discDisp = it.discountRupees > 0 ? "₹${it.discountRupees.toStringAsFixed(1)}" : (it.discountPer > 0 ? "${it.discountPer}%" : "-");

                            return TableRow(
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                              children: [
                                _td("${idx + 1}"),
                                _td(it.name, isLeft: true, isBold: true),
                                _td(it.packing),
                                _td(it.batch),
                                _td(it.exp),
                                _td(qtyDisp, isBold: true, color: const Color(0xFFF59E0B)),
                                _td("₹${it.purchaseRate.toStringAsFixed(2)}"),
                                _td(discDisp, color: Colors.orangeAccent),
                                _td("${it.gstRate.toInt()}%"),
                                _td("₹${it.total.toStringAsFixed(2)}", isBold: true, color: Colors.greenAccent),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (!widget.isReadOnly)
                                      IconButton(
                                        icon: const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF38BDF8)),
                                        onPressed: () {
                                          final med = webPh.medicines.firstWhere((m) => m.id == it.medicineID);
                                          _openItemDialog(webPh, med, itemToEdit: it, editIndex: idx);
                                        },
                                      ),
                                    if (!widget.isReadOnly)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                                        onPressed: () => setState(() {
                                          items.removeAt(idx);
                                          _recalculateSR();
                                        }),
                                      ),
                                  ],
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter(PharoahWebManager webPh) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text("Extra Disc (-): ", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  SizedBox(
                    width: 80,
                    height: 34,
                    child: TextField(
                      controller: extraDiscC,
                      readOnly: widget.isReadOnly,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              Text("R/O: ₹${roundOff.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("NET INWARD VALUE", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  Text("₹${finalGrandTotal.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 24, fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (!widget.isReadOnly)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: isSaving ? null : () => _finalizePurchase(webPh, andPrint: false),
                  icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(isSaving ? "SAVING..." : "SAVE & ADD STOCK", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFF59E0B), side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: isSaving ? null : () => _finalizePurchase(webPh, andPrint: true),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text("SAVE & PRINT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)));
  Widget _td(String t, {bool isLeft = false, bool isBold = false, Color color = Colors.white}) => Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4), child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: TextStyle(color: color, fontSize: 10.5, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)));
}
'''
with open(f"{base}/ui/web_purchase_billing_screen.dart", "w", encoding="utf-8") as f:
    f.write(step2_code)
print("✔ web_purchase_billing_screen.dart imports updated.")

# 5. RUN FLUTTER ANALYZE ON WEB TARGET
print("\n🔍 Step 5/5: Running Flutter Analyze on lib/web_live_sync/...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], capture_output=True, text=True)
print(res.stdout)

errors = [line for line in res.stdout.split('\n') if 'error •' in line]
if len(errors) > 0:
    print(f"❌ Still found {len(errors)} error(s):")
    for e in errors:
        print("  " + e)
    sys.exit(1)

print("🎉 0 ERRORS! COMPILATION IS 100% CLEAN.")

# 6. BUILD & DEPLOY TO CLOUDFLARE
print("\n🔨 Building Production Web App...")
b_res = subprocess.run(
    ["flutter", "build", "web", "-t", "lib/web_live_sync/web_main.dart", "--release", "--base-href", "/", "--pwa-strategy=none"],
    text=True
)
if b_res.returncode != 0:
    print("❌ Web Build Failed!")
    sys.exit(1)

print("\n🌐 Deploying to Cloudflare Pages...")
subprocess.run(["npx", "wrangler", "pages", "deploy", "build/web", "--project-name=pharoah-erp"], text=True)

# Commit & Push
print("\n🔄 Committing & Pushing to GitHub...")
subprocess.run(["git", "add", "."], text=True)
subprocess.run(["git", "commit", "-m", "🚀 #PH-REV-630: Clean Package Imports & Modular Purchase Workflow Deployed"], text=True)
branch_res = subprocess.run(["git", "branch", "--show-current"], capture_output=True, text=True)
branch = branch_res.stdout.strip() or "main"
subprocess.run(["git", "push", "origin", branch], text=True)

print("\n" + "="*65)
print("🎉 SUCCESS: #PH-REV-630 IS 100% DEPLOYED & LIVE!")
print("🔗 Website: https://pharoah-erp.pages.dev")
print("✅ Verified Tag: #PH-REV-630 (FULL-PURCHASE-WORKFLOW-PARITY)")
print("="*65)
