import os
import subprocess

dn_file = "lib/web_live_sync/sub_views/web_returns/debit_note/ui/debit_note_cart_widget.dart"
cn_file = "lib/web_live_sync/sub_views/web_returns/credit_note/ui/credit_note_cart_widget.dart"
gw_file = "lib/web_live_sync/web_portal_gateway.dart"

# --- 1. CLEAN REWRITE OF DEBIT NOTE CART WIDGET ---
dn_code = r'''// FILE: lib/web_live_sync/sub_views/web_returns/debit_note/ui/debit_note_cart_widget.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/debit_note_controller.dart';
import 'debit_note_magic_history_modal.dart';
import '../../../web_billing/quick_add_product_modal.dart';
import '../../../web_billing/web_batch_lookup_dialog.dart';

class DebitNoteCartWidget extends StatelessWidget {
  final DebitNoteController controller;
  final PharoahWebManager webPh;

  const DebitNoteCartWidget({
    super.key,
    required this.controller,
    required this.webPh,
  });

  void _triggerProductSelection(BuildContext context, Medicine med) {
    if (controller.isReadOnly) return;
    if (controller.selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a Supplier / Distributor first!"), backgroundColor: Colors.orange),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (c) => DebitNoteMagicHistoryModal(
        medicine: med,
        supplier: controller.selectedSupplier!,
        webPh: webPh,
        onSelect: (selectedHistory) {
          _openItemEntryDialog(context, med, historyData: selectedHistory);
        },
      ),
    );
  }

  void _openItemEntryDialog(
    BuildContext context,
    Medicine med, {
    PurchaseItem? itemToEdit,
    int? editIndex,
    Map<String, dynamic>? historyData,
  }) {
    List<BatchInfo> batches = webPh.batchHistory[med.identityKey] ?? [];

    final batchC = TextEditingController(text: itemToEdit?.batch ?? (historyData?['batch'] ?? ""));
    final expC = TextEditingController(text: itemToEdit?.exp ?? (historyData?['exp'] ?? "12/28"));
    final mrpC = TextEditingController(
      text: itemToEdit != null
          ? itemToEdit.mrp.toStringAsFixed(2)
          : ((historyData?['mrp'] as num?)?.toDouble() ?? med.mrp).toStringAsFixed(2),
    );
    final purRateC = TextEditingController(
      text: itemToEdit != null
          ? itemToEdit.purchaseRate.toStringAsFixed(2)
          : ((historyData?['purchaseRate'] as num?)?.toDouble() ?? med.purRate).toStringAsFixed(2),
    );
    final rateAC = TextEditingController(
      text: itemToEdit != null ? itemToEdit.rateA.toStringAsFixed(2) : med.rateA.toStringAsFixed(2),
    );
    final rateBC = TextEditingController(
      text: itemToEdit != null ? itemToEdit.rateB.toStringAsFixed(2) : med.rateB.toStringAsFixed(2),
    );
    final rateCC = TextEditingController(
      text: itemToEdit != null ? itemToEdit.rateC.toStringAsFixed(2) : med.rateC.toStringAsFixed(2),
    );
    final rateCDiscC = TextEditingController(
      text: itemToEdit != null ? itemToEdit.rateCFormula.toString() : "0.0",
    );

    final qtyC = TextEditingController(
      text: itemToEdit != null
          ? itemToEdit.qty.toInt().toString()
          : ((historyData?['qty'] as num?)?.toDouble() ?? 1.0).toInt().toString(),
    );
    final freeC = TextEditingController(
      text: itemToEdit != null
          ? itemToEdit.freeQty.toInt().toString()
          : ((historyData?['free'] as num?)?.toDouble() ?? 0.0).toInt().toString(),
    );
    final gstC = TextEditingController(
      text: itemToEdit != null
          ? itemToEdit.gstRate.toString()
          : ((historyData?['gst'] as num?)?.toDouble() ?? med.gst).toString(),
    );
    final discPerC = TextEditingController(
      text: itemToEdit != null
          ? itemToEdit.discountPer.toString()
          : ((historyData?['discountPer'] as num?)?.toDouble() ?? 0.0).toString(),
    );
    final discAmtC = TextEditingController(
      text: itemToEdit != null ? itemToEdit.discountRupees.toStringAsFixed(2) : "0.0",
    );

    String selectedRateType = itemToEdit?.appliedRateType ?? "A";

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

            void executeSave() {
              if (batchC.text.trim().isEmpty || expC.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Batch and Expiry are required!"), backgroundColor: Colors.orange),
                );
                return;
              }

              double q = double.tryParse(qtyC.text) ?? 0.0;
              double pRate = double.tryParse(purRateC.text) ?? 0.0;
              double dAmt = double.tryParse(discAmtC.text) ?? 0.0;
              double gPer = double.tryParse(gstC.text) ?? 0.0;

              double gross = q * pRate;
              double taxable = gross - dAmt;
              if (taxable < 0) taxable = 0.0;
              double taxAmt = taxable * (gPer / 100);
              double netItemTotal = taxable + taxAmt;

              if (q <= 0 || pRate <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Quantity and Purchase Rate must be greater than zero!"), backgroundColor: Colors.orange),
                );
                return;
              }

              double mrp = double.tryParse(mrpC.text) ?? 0.0;
              double a = double.tryParse(rateAC.text) ?? mrp;
              double b = double.tryParse(rateBC.text) ?? (a * 0.95);
              double rateCVal = double.tryParse(rateCC.text) ?? (a * 0.92);

              final newItem = PurchaseItem(
                id: itemToEdit?.id ?? "PITM-${DateTime.now().millisecondsSinceEpoch}",
                srNo: itemToEdit != null ? itemToEdit.srNo : controller.items.length + 1,
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
                rateA: a,
                rateB: b,
                rateC: rateCVal,
                discountPer: double.tryParse(discPerC.text) ?? 0.0,
                discountRupees: dAmt,
                appliedRateType: selectedRateType,
                rateCFormula: double.tryParse(rateCDiscC.text) ?? 0.0,
                isBreakage: controller.isBreakageMode,
              );

              if (editIndex != null) {
                controller.updateItem(editIndex, newItem);
              } else {
                controller.addItem(newItem);
              }
              Navigator.pop(c);
            }

            double q = double.tryParse(qtyC.text) ?? 0.0;
            double pRate = double.tryParse(purRateC.text) ?? 0.0;
            double dAmt = double.tryParse(discAmtC.text) ?? 0.0;
            double gPer = double.tryParse(gstC.text) ?? 0.0;

            double gross = q * pRate;
            double taxable = gross - dAmt;
            if (taxable < 0) taxable = 0.0;
            double taxAmt = taxable * (gPer / 100);
            double netItemTotal = taxable + taxAmt;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Container(
                width: 600,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD97706), width: 1.5),
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
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: Color(0x33F59E0B), shape: BoxShape.circle),
                            child: const Icon(Icons.remove_shopping_cart_rounded, color: Color(0xFFFBBF24), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "DEBIT NOTE ITEM CONFIG",
                                  style: TextStyle(color: Color(0xFFFBBF24), fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 1.2),
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
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: _dialogInput(
                                    "BATCH NUMBER *",
                                    batchC,
                                    isHighlight: true,
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
                                          builder: (ctx) => WebBatchLookupDialog(medicine: med, batches: batches, prioritizeExpired: true),
                                        );
                                        if (selected != null && selected is BatchInfo) {
                                          setDialogState(() {
                                            batchC.text = selected.batch;
                                            expC.text = selected.exp;
                                            mrpC.text = selected.mrp.toStringAsFixed(2);
                                            purRateC.text = (selected.purRate > 0 ? selected.purRate : selected.rate).toStringAsFixed(2);
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
                                Expanded(flex: 2, child: _dialogInput("EXPIRY (MM/YY) *", expC, isNum: true)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Text("RATE SCHEME:", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 10),
                                _rateSegment("RATE A", selectedRateType == "A", () => setDialogState(() => selectedRateType = "A")),
                                const SizedBox(width: 6),
                                _rateSegment("RATE B", selectedRateType == "B", () => setDialogState(() => selectedRateType = "B")),
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
                                  Expanded(child: _dialogInput("C FORMULA %", rateCDiscC, isNum: true, onChanged: (_) => setDialogState(() => calculateRateC()))),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(child: _dialogInput("MRP ₹", mrpC, isNum: true, onChanged: (_) => setDialogState(() { if (selectedRateType == "C") calculateRateC(); }))),
                                const SizedBox(width: 8),
                                Expanded(child: _dialogInput("PUR. RATE ₹ *", purRateC, isNum: true, isHighlight: true, onChanged: (_) => setDialogState(() => syncDiscount(true)))),
                                const SizedBox(width: 8),
                                Expanded(child: _dialogInput("GST %", gstC, isNum: true, onChanged: (_) => setDialogState(() { if (selectedRateType == "C") calculateRateC(); }))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _dialogInput("QTY *", qtyC, isNum: true, isHighlight: true, onChanged: (_) => setDialogState(() => syncDiscount(true)), onSubmitted: (_) => executeSave())),
                                const SizedBox(width: 8),
                                Expanded(child: _dialogInput("FREE QTY", freeC, isNum: true)),
                                const SizedBox(width: 8),
                                Expanded(child: _dialogInput("DISC %", discPerC, isNum: true, onChanged: (_) => setDialogState(() => syncDiscount(true)))),
                                const SizedBox(width: 8),
                                Expanded(child: _dialogInput("DISC ₹", discAmtC, isNum: true, onChanged: (_) => setDialogState(() => syncDiscount(false)))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _dialogInput("RATE A ₹", rateAC, isNum: true)),
                                const SizedBox(width: 8),
                                Expanded(child: _dialogInput("RATE B ₹", rateBC, isNum: true)),
                                const SizedBox(width: 8),
                                Expanded(child: _dialogInput("RATE C ₹", rateCC, isNum: true, isReadOnly: selectedRateType == "C")),
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
                                  Text("Taxable: ₹${taxable.toStringAsFixed(2)} | GST: ₹${taxAmt.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  Text("₹${netItemTotal.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 18, fontWeight: FontWeight.w900)),
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
                                onPressed: executeSave,
                                child: Text(itemToEdit != null ? "UPDATE ITEM" : "CONFIRM & ADD TO DEBIT NOTE (ENTER)", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5)),
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

  Widget _dialogInput(
    String label,
    TextEditingController ctrl, {
    bool isNum = false,
    bool isHighlight = false,
    bool isReadOnly = false,
    Widget? suffix,
    Function(String)? onChanged,
    Function(String)? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: isReadOnly ? Colors.black38 : (isHighlight ? const Color(0x33F59E0B) : Colors.black26),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isHighlight ? const Color(0xFFF59E0B) : Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  readOnly: isReadOnly,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
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

  void _openQuickAddProduct(BuildContext context) {
    if (controller.isReadOnly) return;
    showDialog(
      context: context,
      builder: (c) => QuickAddProductModal(
        webPh: webPh,
        onProductCreated: (newMedMap) {
          final medObj = Medicine.fromMap(newMedMap);
          _openItemEntryDialog(context, medObj);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = controller.productSearchC.text.trim().toLowerCase();
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!controller.isReadOnly) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller.productSearchC,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                    decoration: InputDecoration(
                      labelText: "SEARCH MEDICINE TO RETURN",
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
                      hintText: "Type medicine name (opens Magic Purchase History)...",
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFFBBF24), size: 18),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) => controller.notifySearch(),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _openQuickAddProduct(context),
                  icon: const Icon(Icons.add_box_rounded, size: 16),
                  label: const Text("+ PRODUCT", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
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
                  itemCount: matchingMeds.length,
                  itemBuilder: (ctx, idx) {
                    final med = matchingMeds[idx];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.medication_rounded, color: Color(0xFFFBBF24), size: 18),
                      title: Text(med.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      subtitle: Text("Pack: ${med.packing} • Pur.Rate: ₹${med.purRate.toStringAsFixed(2)} • Live Stock: ${med.stock.toInt()}", style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
                      trailing: const Icon(Icons.auto_fix_high_rounded, color: Color(0xFFFBBF24), size: 16),
                      onTap: () {
                        controller.productSearchC.clear();
                        _triggerProductSelection(context, med);
                      },
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],

          Row(
            children: [
              const Icon(Icons.remove_shopping_cart_rounded, color: Color(0xFFFBBF24), size: 18),
              const SizedBox(width: 8),
              Text(
                "DEBIT NOTE CART ITEMS (${controller.items.length})",
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "Swipe Right to Delete 👉",
                  style: TextStyle(color: Colors.white54, fontSize: 9.5),
                ),
              ),
              const Spacer(),
              if (controller.items.isNotEmpty && !controller.isReadOnly)
                TextButton(
                  onPressed: () => controller.clearCart(),
                  child: const Text("Clear Cart", style: TextStyle(color: Colors.redAccent, fontSize: 10.5)),
                ),
            ],
          ),
          const Divider(color: Colors.white10, height: 16),

          if (controller.items.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(35),
                child: Text("Debit note cart is empty. Search products above to fetch supplier purchase history.", style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth > 850 ? constraints.maxWidth : 850,
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              _th("SN", width: 40),
                              _th("TYPE", width: 60),
                              Expanded(flex: 3, child: _th("PRODUCT NAME", isLeft: true)),
                              _th("PACK", width: 75),
                              _th("BATCH", width: 85),
                              _th("EXP", width: 65),
                              _th("QTY", width: 75),
                              _th("RATE", width: 80),
                              _th("TOTAL", width: 95),
                              _th("ACT", width: 70),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),

                        ...controller.items.asMap().entries.map((entry) {
                          int idx = entry.key;
                          PurchaseItem it = entry.value;
                          String qtyDisp = "${it.qty.toInt()}${it.freeQty > 0 ? ' + ${it.freeQty.toInt()}' : ''}";
                          bool isExp = it.isBreakage;

                          return Dismissible(
                            key: ValueKey("DN_ITEM_${it.id}_$idx"),
                            direction: controller.isReadOnly ? DismissDirection.none : DismissDirection.startToEnd,
                            background: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.red.shade900,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.centerLeft,
                              child: const Row(
                                children: [
                                  Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text("DELETING ITEM...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                ],
                              ),
                            ),
                            onDismissed: (_) {
                              controller.removeItem(idx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("🗑️ ${it.name} removed from Debit Note"), duration: const Duration(seconds: 2)),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  _td("${idx + 1}", width: 40),
                                  Container(
                                    width: 60,
                                    alignment: Alignment.center,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isExp ? const Color(0x33EA580C) : const Color(0x330F766E),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isExp ? "EXP" : "RET",
                                        style: TextStyle(
                                          color: isExp ? const Color(0xFFF97316) : Colors.tealAccent,
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: InkWell(
                                      onTap: () {
                                        final med = webPh.medicines.firstWhere(
                                          (m) => m.id == it.medicineID || m.name == it.name,
                                          orElse: () => Medicine(id: it.medicineID, name: it.name, packing: it.packing),
                                        );
                                        _openItemEntryDialog(context, med, itemToEdit: it, editIndex: idx);
                                      },
                                      child: Text(it.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                  _td(it.packing, width: 75),
                                  _td(it.batch, width: 85),
                                  _td(it.exp, width: 65),
                                  _td(qtyDisp, width: 75, isBold: true, color: const Color(0xFFFBBF24)),
                                  _td("₹${it.purchaseRate.toStringAsFixed(2)}", width: 80),
                                  _td("₹${it.total.toStringAsFixed(2)}", width: 95, isBold: true, color: const Color(0xFFF59E0B)),
                                  SizedBox(
                                    width: 70,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (!controller.isReadOnly) ...[
                                          IconButton(
                                            icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF38BDF8)),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              final med = webPh.medicines.firstWhere(
                                                (m) => m.id == it.medicineID || m.name == it.name,
                                                orElse: () => Medicine(id: it.medicineID, name: it.name, packing: it.packing),
                                              );
                                              _openItemEntryDialog(context, med, itemToEdit: it, editIndex: idx);
                                            },
                                          ),
                                          const SizedBox(width: 6),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () => controller.removeItem(idx),
                                          ),
                                        ] else
                                          const Icon(Icons.lock_rounded, size: 14, color: Colors.white38),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _th(String t, {double? width, bool isLeft = false}) {
    Widget textWidget = Text(
      t,
      textAlign: isLeft ? TextAlign.left : TextAlign.center,
      style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold),
    );
    return width != null ? SizedBox(width: width, child: textWidget) : textWidget;
  }

  Widget _td(String t, {double? width, bool isLeft = false, bool isBold = false, Color color = Colors.white}) {
    Widget textWidget = Text(
      t,
      textAlign: isLeft ? TextAlign.left : TextAlign.center,
      style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
      overflow: TextOverflow.ellipsis,
    );
    return width != null ? SizedBox(width: width, child: textWidget) : textWidget;
  }
}
'''

with open(dn_file, 'w', encoding='utf-8') as f:
    f.write(dn_code)
print(f"✔ Fixed and updated: {dn_file}")

# --- 2. CLEAN REWRITE OF CREDIT NOTE CART WIDGET ---
with open(cn_file, 'w', encoding='utf-8') as f:
    f.write(cn_code)
print(f"✔ Fixed and updated: {cn_file}")

# --- 3. CLEAN UP WEB PORTAL GATEWAY HEADER IF NEEDED ---
if os.path.exists(gw_file):
    with open(gw_file, 'r', encoding='utf-8') as f:
        content = f.read()
    if not content.startswith('//') and not content.startswith('import'):
        # Fix top line
        lines = content.splitlines()
        clean_lines = [l for l in lines if 'web_challan_view' not in l and not l.strip() == '']
        with open(gw_file, 'w', encoding='utf-8') as f:
            f.write('// FILE: lib/web_live_sync/web_portal_gateway.dart\n\n' + '\n'.join(clean_lines) + '\n')
        print(f"✔ Cleaned: {gw_file}")

# --- 4. VERIFY WITH FLUTTER ANALYZE ---
print("\n🔍 Running flutter analyze lib/web_live_sync/ ...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], capture_output=True, text=True)
print(res.stdout)
if res.stderr:
    print(res.stderr)
