// FILE: lib/web_live_sync/sub_views/web_challans/web_purchase_challan_billing_view.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../web_pdf_router_service.dart';
import '../web_billing/quick_add_product_modal.dart';
import '../web_billing/web_batch_lookup_dialog.dart';

class WebPurchaseChallanBillingView extends StatefulWidget {
  final Party supplier;
  final String internalNo;
  final String supplierRefNo;
  final DateTime challanDate;
  final PurchaseChallan? existingRecord;
  final bool isReadOnly;

  const WebPurchaseChallanBillingView({
    super.key,
    required this.supplier,
    required this.internalNo,
    required this.supplierRefNo,
    required this.challanDate,
    this.existingRecord,
    this.isReadOnly = false,
  });

  @override
  State<WebPurchaseChallanBillingView> createState() => _WebPurchaseChallanBillingViewState();
}

class _WebPurchaseChallanBillingViewState extends State<WebPurchaseChallanBillingView> {
  List<PurchaseItem> items = [];
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

  // 🧠 SMART LPR ENGINE: Find Latest Purchase Rate across Batches and Inward History
  double _findLatestPurchaseRate(PharoahWebManager webPh, Medicine med) {
    if (med.purRate > 0) return med.purRate;

    // Check available batches for this medicine
    final batches = webPh.batchHistory[med.identityKey] ?? [];
    for (var b in batches.reversed) {
      if (b.purRate > 0) return b.purRate;
      if (b.rate > 0) return b.rate;
    }

    // Check previous purchase bills for this supplier and medicine
    for (var p in webPh.purchases.reversed) {
      for (var it in p.items) {
        if ((it.medicineID == med.id || it.name.trim().toUpperCase() == med.name.trim().toUpperCase()) && it.purchaseRate > 0) {
          return it.purchaseRate;
        }
      }
    }

    // Check previous purchase challans
    for (var c in webPh.purchaseChallans.reversed) {
      for (var it in c.items) {
        if ((it.medicineID == med.id || it.name.trim().toUpperCase() == med.name.trim().toUpperCase()) && it.purchaseRate > 0) {
          return it.purchaseRate;
        }
      }
    }

    return 0.0;
  }

  // ===========================================================================
  // 🪄 INWARD ITEM ENTRY MODAL WITH AUTO-FETCH PURCHASE RATE
  // ===========================================================================
  void _openPcItemDialog(PharoahWebManager webPh, Medicine med, {PurchaseItem? itemToEdit, int? editIndex}) {
    if (widget.isReadOnly) return;

    double autoPurRate = itemToEdit != null 
        ? itemToEdit.purchaseRate 
        : _findLatestPurchaseRate(webPh, med);

    final batchC = TextEditingController(text: itemToEdit?.batch ?? "");
    final expC = TextEditingController(text: itemToEdit?.exp ?? "12/28");
    final mrpC = TextEditingController(text: itemToEdit?.mrp.toStringAsFixed(2) ?? med.mrp.toStringAsFixed(2));
    final purRateC = TextEditingController(text: autoPurRate > 0 ? autoPurRate.toStringAsFixed(2) : (med.purRate > 0 ? med.purRate.toStringAsFixed(2) : "0.00"));
    final qtyC = TextEditingController(text: itemToEdit?.qty.toInt().toString() ?? "1");
    final freeC = TextEditingController(text: itemToEdit?.freeQty.toInt().toString() ?? "0");
    final gstC = TextEditingController(text: itemToEdit?.gstRate.toString() ?? med.gst.toString());

    final rateAC = TextEditingController(text: itemToEdit?.rateA.toStringAsFixed(2) ?? med.rateA.toStringAsFixed(2));
    final rateBC = TextEditingController(text: itemToEdit?.rateB.toStringAsFixed(2) ?? med.rateB.toStringAsFixed(2));
    final rateCC = TextEditingController(text: itemToEdit?.rateC.toStringAsFixed(2) ?? med.rateC.toStringAsFixed(2));
    final rateCDiscC = TextEditingController(text: itemToEdit?.rateCFormula.toString() ?? "0.0");

    final discPerC = TextEditingController(text: itemToEdit?.discountPer.toString() ?? "0.0");
    final discAmtC = TextEditingController(text: itemToEdit?.discountRupees.toString() ?? "0.0");

    String selectedRateType = itemToEdit?.appliedRateType ?? "A";
    List<BatchInfo> availableBatches = webPh.batchHistory[med.identityKey] ?? [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            void calculateRateC() {
              double mrp = double.tryParse(mrpC.text) ?? 0.0;
              double gst = double.tryParse(gstC.text) ?? 0.0;
              double formulaDisc = double.tryParse(rateCDiscC.text) ?? 0.0;
              double baseTaxable = (mrp / (1 + (gst / 100)));
              double finalDerivedRate = baseTaxable - (baseTaxable * (formulaDisc / 100));
              rateCC.text = finalDerivedRate.toStringAsFixed(2);
            }

            void syncDiscount(bool isPercentSource) {
              double q = double.tryParse(qtyC.text) ?? 0.0;
              double pRate = double.tryParse(purRateC.text) ?? 0.0;
              double gross = q * pRate;
              if (gross <= 0) return;
              if (isPercentSource) {
                double p = double.tryParse(discPerC.text) ?? 0.0;
                discAmtC.text = (gross * (p / 100)).toStringAsFixed(2);
              } else {
                double a = double.tryParse(discAmtC.text) ?? 0.0;
                discPerC.text = ((a / gross) * 100).toStringAsFixed(2);
              }
            }

            void formatExpiry(String val) {
              String text = val.replaceAll(RegExp(r'[^0-9]'), '');
              if (text.length >= 2 && !val.contains('/')) {
                text = '${text.substring(0, 2)}/${text.substring(2)}';
              }
              if (text.length > 5) text = text.substring(0, 5);
              if (expC.text != text) {
                expC.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
              }
            }

            double q = double.tryParse(qtyC.text) ?? 0.0;
            double pRate = double.tryParse(purRateC.text) ?? 0.0;
            double dAmt = double.tryParse(discAmtC.text) ?? 0.0;
            double gPer = double.tryParse(gstC.text) ?? 0.0;

            double gross = q * pRate;
            double taxable = gross - dAmt;
            double taxAmt = taxable * (gPer / 100);
            double netItemTotal = taxable + taxAmt;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Container(
                width: 580,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0x80F59E0B), width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 25, offset: Offset(0, 10))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF78350F), Color(0xFF1E293B)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: Color(0x33F59E0B), shape: BoxShape.circle),
                            child: const Icon(Icons.downloading_rounded, color: Color(0xFFF59E0B), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "INWARD STOCK CONFIGURATION",
                                  style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "${med.name} (${med.packing})",
                                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                            onPressed: () => Navigator.pop(c),
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
                                  child: _DialogInputField(
                                    label: "BATCH NO (CASE-SENSITIVE) *",
                                    ctrl: batchC,
                                    suffix: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFF59E0B),
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        elevation: 0,
                                      ),
                                      onPressed: () async {
                                        final selected = await showDialog<dynamic>(
                                          context: context,
                                          builder: (ctx) => WebBatchLookupDialog(medicine: med, batches: availableBatches, prioritizeExpired: false),
                                        );
                                        if (selected != null && selected is BatchInfo) {
                                          setDialogState(() {
                                            batchC.text = selected.batch;
                                            expC.text = selected.exp;
                                            mrpC.text = selected.mrp.toStringAsFixed(2);
                                            double bPur = selected.purRate > 0 ? selected.purRate : (selected.rate > 0 ? selected.rate : autoPurRate);
                                            purRateC.text = bPur.toStringAsFixed(2);
                                            rateAC.text = selected.rateA.toStringAsFixed(2);
                                            rateBC.text = selected.rateB.toStringAsFixed(2);
                                            rateCC.text = selected.rateC.toStringAsFixed(2);
                                            rateCDiscC.text = selected.rateCFormula.toStringAsFixed(2);
                                            selectedRateType = selected.appliedRateType;
                                            syncDiscount(true);
                                          });
                                        }
                                      },
                                      icon: const Icon(Icons.layers_rounded, size: 14),
                                      label: const Text("BATCHES", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: _DialogInputField(
                                    label: "EXPIRY (MM/YY) *",
                                    ctrl: expC,
                                    isNum: true,
                                    onChanged: (v) => setDialogState(() => formatExpiry(v)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            Row(
                              children: [
                                const Text("RATE SCHEME:", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 10),
                                _rateSegment("RATE A", selectedRateType == "A", () {
                                  setDialogState(() {
                                    selectedRateType = "A";
                                  });
                                }),
                                const SizedBox(width: 6),
                                _rateSegment("RATE B", selectedRateType == "B", () {
                                  setDialogState(() {
                                    selectedRateType = "B";
                                  });
                                }),
                                const SizedBox(width: 6),
                                _rateSegment("RATE C", selectedRateType == "C", () {
                                  setDialogState(() {
                                    selectedRateType = "C";
                                    calculateRateC();
                                  });
                                }),
                              ],
                            ),
                            const SizedBox(height: 12),

                            Row(
                              children: [
                                if (selectedRateType == "C") ...[
                                  Expanded(
                                    child: _DialogInputField(
                                      label: "C FORMULA %",
                                      ctrl: rateCDiscC,
                                      isNum: true,
                                      onChanged: (_) => setDialogState(() => calculateRateC()),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: _DialogInputField(
                                    label: "MRP ₹",
                                    ctrl: mrpC,
                                    isNum: true,
                                    onChanged: (_) => setDialogState(() { if (selectedRateType == "C") calculateRateC(); }),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _DialogInputField(
                                    label: "PUR. RATE ₹ *",
                                    ctrl: purRateC,
                                    isNum: true,
                                    onChanged: (_) => setDialogState(() => syncDiscount(true)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _DialogInputField(
                                    label: "GST %",
                                    ctrl: gstC,
                                    isNum: true,
                                    onChanged: (_) => setDialogState(() { if (selectedRateType == "C") calculateRateC(); }),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            Row(
                              children: [
                                Expanded(
                                  child: _DialogInputField(
                                    label: "QTY *",
                                    ctrl: qtyC,
                                    isNum: true,
                                    onChanged: (_) => setDialogState(() => syncDiscount(true)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _DialogInputField(
                                    label: "FREE QTY",
                                    ctrl: freeC,
                                    isNum: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _DialogInputField(
                                    label: "DISC %",
                                    ctrl: discPerC,
                                    isNum: true,
                                    onChanged: (_) => setDialogState(() => syncDiscount(true)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _DialogInputField(
                                    label: "DISC ₹",
                                    ctrl: discAmtC,
                                    isNum: true,
                                    onChanged: (_) => setDialogState(() => syncDiscount(false)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            Row(
                              children: [
                                Expanded(
                                  child: _DialogInputField(
                                    label: "RATE A ₹",
                                    ctrl: rateAC,
                                    isNum: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _DialogInputField(
                                    label: "RATE B ₹",
                                    ctrl: rateBC,
                                    isNum: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _DialogInputField(
                                    label: "RATE C ₹",
                                    ctrl: rateCC,
                                    isNum: true,
                                    isReadOnly: selectedRateType == "C",
                                  ),
                                ),
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
                                      Text(
                                        "Taxable: ₹${taxable.toStringAsFixed(2)} | GST: ₹${taxAmt.toStringAsFixed(2)}",
                                        style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        "Gross: ₹${gross.toStringAsFixed(2)} - Disc: ₹${dAmt.toStringAsFixed(2)}",
                                        style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text("NET INWARD VALUE", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                      Text(
                                        "₹${netItemTotal.toStringAsFixed(2)}",
                                        style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 18, fontWeight: FontWeight.w900),
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
                                  backgroundColor: const Color(0xFFD97706),
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

                                  final newItem = PurchaseItem(
                                    id: itemToEdit?.id ?? "PCITM-${DateTime.now().millisecondsSinceEpoch}",
                                    srNo: itemToEdit != null ? itemToEdit.srNo : items.length + 1,
                                    medicineID: med.id,
                                    name: med.name,
                                    packing: med.packing,
                                    batch: batchC.text.trim(),
                                    exp: expC.text.trim(),
                                    hsn: med.hsnCode,
                                    mrp: mrp,
                                    qty: q,
                                    freeQty: double.tryParse(freeC.text) ?? 0.0,
                                    purchaseRate: pRate,
                                    gstRate: gPer,
                                    total: netItemTotal,
                                    discountPer: double.tryParse(discPerC.text) ?? 0.0,
                                    discountRupees: dAmt,
                                    rateA: a,
                                    rateB: b,
                                    rateC: rateCVal,
                                    appliedRateType: selectedRateType,
                                    rateCFormula: double.tryParse(rateCDiscC.text) ?? 0.0,
                                    isBreakage: false,
                                  );

                                  setState(() {
                                    if (editIndex != null) {
                                      items[editIndex] = newItem;
                                    } else {
                                      items.add(newItem);
                                    }
                                  });
                                  Navigator.pop(c);
                                },
                                child: Text(
                                  itemToEdit != null ? "UPDATE INWARD ITEM" : "CONFIRM & ADD TO INWARD",
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
            );
          },
        ),
      ),
    );
  }

  Widget _rateSegment(String label, bool isSelected, VoidCallback onTap) {
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
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
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
          _openPcItemDialog(webPh, medObj);
        },
      ),
    );
  }

  // ===========================================================================
  // 💾 SAVE INWARD & PERMANENTLY UPDATE MEDICINE MASTER L.P.R. (LATEST RATE)
  // ===========================================================================
  void _savePurchaseChallan(PharoahWebManager webPh, {bool andPrint = false}) async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Challan cannot be empty! Please add products."), backgroundColor: Colors.orange));
      return;
    }

    setState(() => isSaving = true);

    final newChallan = PurchaseChallan(
      id: widget.existingRecord?.id ?? "PCH-WEB-${DateTime.now().millisecondsSinceEpoch}",
      internalNo: widget.internalNo,
      billNo: widget.supplierRefNo,
      partyId: widget.supplier.id,
      distributorName: widget.supplier.name,
      date: widget.challanDate,
      items: List.from(items),
      totalAmount: totalAmt,
      status: widget.existingRecord?.status ?? "Pending",
      remarks: remarksC.text.trim().isNotEmpty ? remarksC.text.trim() : "Stock inward verified.",
    );

    if (widget.existingRecord != null) { webPh.purchaseChallans.removeWhere((c) => c.id == widget.existingRecord!.id); }
    
    webPh.purchaseChallans.add(newChallan);

    // 2-Way Batch Inventory Activity + Medicine Master Auto-Update
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        int mIdx = webPh.medicines.indexWhere((m) => m.id == item.medicineID || m.name.trim().toUpperCase() == item.name.trim().toUpperCase());
        if (mIdx != -1) {
          final med = webPh.medicines[mIdx];
          resolvedKey = med.identityKey;

          // 🔥 AUTO-UPDATE MEDICINE MASTER WITH LATEST PURCHASE RATE (L.P.R.)
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
      );
    }

    webPh.rebuildInventory();
    await webPh.pushUpdatedDataToCloud();
    setState(() => isSaving = false);

    if (andPrint) {
      final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);
      await WebPdfRouterService.printPurchaseChallan(challan: newChallan, party: widget.supplier, shop: shopProfile);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Inward Challan ${widget.internalNo} Saved & Master L.P.R. Updated!"), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "View Inward Items" : "Inward Note: ${widget.internalNo}"),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: "Print Inward PDF",
            onPressed: items.isEmpty
                ? null
                : () async {
                    final tempChallan = PurchaseChallan(
                      id: "temp",
                      internalNo: widget.internalNo,
                      billNo: widget.supplierRefNo,
                      partyId: widget.supplier.id,
                      distributorName: widget.supplier.name,
                      date: widget.challanDate,
                      items: items,
                      totalAmount: totalAmt,
                      remarks: remarksC.text.trim().isNotEmpty ? remarksC.text.trim() : "Stock inward verified.",
                    );
                    await WebPdfRouterService.printPurchaseChallan(
                      challan: tempChallan,
                      party: widget.supplier,
                      shop: CompanyProfile.fromMap(webPh.companyProfile),
                    );
                  },
          ),
          if (!widget.isReadOnly)
            TextButton(
              onPressed: items.isEmpty ? null : () => _savePurchaseChallan(webPh, andPrint: false),
              child: const Text("FINISH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
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
                          Text("Ref: ${widget.supplierRefNo} | GST: ${widget.supplier.gst}", style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: Text("DATE: ${DateFormat('dd/MM/yyyy').format(widget.challanDate)}", style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (!widget.isReadOnly) _buildProductSearchCard(webPh),
            if (!widget.isReadOnly) const SizedBox(height: 14),

            Expanded(child: _buildCartTable(webPh)),
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
                m.systemId.toLowerCase().contains(query))
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
                  double lpr = _findLatestPurchaseRate(webPh, med);

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
                    subtitle: Text("MRP: ₹${med.mrp.toStringAsFixed(2)} | L.P.R: ₹${lpr.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    onTap: () {
                      setState(() => productSearchC.clear());
                      _openPcItemDialog(webPh, med);
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
            const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("Cart is empty. Search products above to add to inward challan.", style: TextStyle(color: Colors.white38, fontSize: 11))))
          else
            Expanded(
              child: SingleChildScrollView(
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
                        _th("SN"),
                        _th("PRODUCT NAME", isLeft: true),
                        _th("PACK"),
                        _th("BATCH"),
                        _th("EXP"),
                        _th("QTY"),
                        _th("RATE"),
                        _th("DISC"),
                        _th("GST%"),
                        _th("TOTAL"),
                        _th("ACT"),
                      ],
                    ),
                    ...items.asMap().entries.map((entry) {
                      int idx = entry.key;
                      PurchaseItem it = entry.value;
                      String qtyDisp = "${it.qty.toInt()}${it.freeQty > 0 ? ' + ${it.freeQty.toInt()}' : ''}";
                      String discDisp = it.discountRupees > 0 
                          ? "₹${it.discountRupees.toStringAsFixed(1)}" 
                          : (it.discountPer > 0 ? "${it.discountPer}%" : "-");

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
                                    _openPcItemDialog(webPh, med, itemToEdit: it, editIndex: idx);
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
        ],
      ),
    );
  }

  Widget _buildFooter(PharoahWebManager webPh) {
    return Container(
      padding: const EdgeInsets.all(18),
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
                labelText: "INWARD REMARKS / TRANSPORT DETAILS",
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                prefixIcon: const Icon(Icons.note_alt_outlined, color: Colors.white54, size: 18),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 30),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text("NET INWARD VALUE", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              Text("₹${totalAmt.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 24, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(width: 25),
          if (!widget.isReadOnly) ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: isSaving ? null : () => _savePurchaseChallan(webPh, andPrint: false),
              icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(isSaving ? "SAVING..." : "SAVE INWARD", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFF59E0B), side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: isSaving ? null : () => _savePurchaseChallan(webPh, andPrint: true),
              icon: const Icon(Icons.print_rounded, size: 18),
              label: const Text("SAVE & PRINT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6), child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)));
  Widget _td(String t, {bool isLeft = false, bool isBold = false, Color color = Colors.white}) => Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6), child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)));
}

// =============================================================================
// 🛡️ DYNAMIC FOCUS & NO-GHOST-CURSOR INPUT FIELD (100% CLEAN SYNTAX)
// =============================================================================
class _DialogInputField extends StatefulWidget {
  final String label;
  final TextEditingController ctrl;
  final bool isNum;
  final bool isReadOnly;
  final Widget? suffix;
  final Function(String)? onChanged;

  const _DialogInputField({
    required this.label,
    required this.ctrl,
    this.isNum = false,
    this.isReadOnly = false,
    this.suffix,
    this.onChanged,
  });

  @override
  State<_DialogInputField> createState() => _DialogInputFieldState();
}

class _DialogInputFieldState extends State<_DialogInputField> {
  late final FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isFocused = _focusNode.hasFocus;
        });
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: _isFocused ? const Color(0xFFFBBF24) : Colors.white54,
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.isReadOnly
                ? Colors.black38
                : (_isFocused ? const Color(0x33F59E0B) : Colors.black26),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? const Color(0xFFF59E0B) : Colors.white12,
              width: _isFocused ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.ctrl,
                  focusNode: _focusNode,
                  showCursor: _isFocused,
                  cursorColor: const Color(0xFFF59E0B),
                  cursorHeight: 14,
                  cursorWidth: 1.5,
                  cursorRadius: const Radius.circular(2),
                  readOnly: widget.isReadOnly,
                  onChanged: widget.onChanged,
                  keyboardType: widget.isNum
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (widget.suffix != null) widget.suffix!,
            ],
          ),
        ),
      ],
    );
  }
}
