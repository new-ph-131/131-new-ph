import re
import subprocess
import sys

# 1. Update Revision Tag
top_bar_path = "lib/web_live_sync/components/web_top_bar.dart"
with open(top_bar_path, "r", encoding="utf-8") as f:
    tb_content = f.read()

new_rev = "#PH-REV-571 (AUTO-RESPONSIVE-SWIPE)"
tb_content = re.sub(r"#PH-REV-\d+[^\"]*", new_rev, tb_content)
with open(top_bar_path, "w", encoding="utf-8") as f:
    f.write(tb_content)
print(f"✔ Top Bar Tag: {new_rev}")

# 2. Write Responsive Credit Note Cart Widget
cn_path = "lib/web_live_sync/sub_views/web_returns/credit_note/ui/credit_note_cart_widget.dart"
cn_code = r'''// FILE: lib/web_live_sync/sub_views/web_returns/credit_note/ui/credit_note_cart_widget.dart

import 'package:flutter/material.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/credit_note_controller.dart';
import 'credit_note_magic_history_modal.dart';
import '../../../web_billing/web_item_entry_card.dart';
import '../../../web_billing/quick_add_product_modal.dart';

class CreditNoteCartWidget extends StatelessWidget {
  final CreditNoteController controller;
  final PharoahWebManager webPh;

  const CreditNoteCartWidget({
    super.key,
    required this.controller,
    required this.webPh,
  });

  void _triggerProductSelection(BuildContext context, Medicine med) {
    if (controller.isReadOnly) return;
    if (controller.selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a Customer first!"), backgroundColor: Colors.orange),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (c) => CreditNoteMagicHistoryModal(
        medicine: med,
        customer: controller.selectedCustomer!,
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
    BillItem? itemToEdit,
    int? editIndex,
    Map<String, dynamic>? historyData,
  }) {
    String shopState = (webPh.companyProfile['state'] ?? 'Rajasthan').toString();
    String partyState = controller.selectedCustomer?.state ?? 'Rajasthan';
    List<BatchInfo> batches = webPh.batchHistory[med.identityKey] ?? [];

    BillItem? preFilled = itemToEdit;
    if (historyData != null && itemToEdit == null) {
      preFilled = BillItem(
        id: "temp",
        srNo: controller.items.length + 1,
        medicineID: med.id,
        name: med.name,
        packing: historyData['packing'] ?? med.packing,
        batch: historyData['batch'] ?? "",
        exp: historyData['exp'] ?? "12/28",
        hsn: med.hsnCode,
        mrp: (historyData['mrp'] as num?)?.toDouble() ?? med.mrp,
        rate: (historyData['rate'] as num?)?.toDouble() ?? med.rateA,
        gstRate: (historyData['gst'] as num?)?.toDouble() ?? med.gst,
        qty: (historyData['qty'] as num?)?.toDouble() ?? 1.0,
        freeQty: (historyData['free'] as num?)?.toDouble() ?? 0.0,
        total: 0.0,
        appliedRateType: historyData['appliedRateType'] ?? "A",
        discountPer: (historyData['discountPer'] as num?)?.toDouble() ?? 0.0,
        isBreakage: controller.isBreakageMode,
      );
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => WebItemEntryCard(
        med: med,
        srNo: itemToEdit != null ? itemToEdit.srNo : controller.items.length + 1,
        partyState: partyState,
        shopState: shopState,
        availableBatches: batches,
        existingItem: preFilled,
        allowExpired: true,
        onAdd: (newItem) {
          final finalizedItem = newItem.copyWith(isBreakage: controller.isBreakageMode);
          if (editIndex != null) {
            controller.updateItem(editIndex, finalizedItem);
          } else {
            controller.addItem(finalizedItem);
          }
          Navigator.pop(context);
        },
        onCancel: () => Navigator.pop(context),
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
          _triggerProductSelection(context, medObj);
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      hintText: "Type medicine name (opens Magic Sales History)...",
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFF87171), size: 18),
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
                    backgroundColor: const Color(0xFF7C3AED),
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
                  border: Border.all(color: const Color(0x33EF4444)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: matchingMeds.length,
                  itemBuilder: (ctx, idx) {
                    final med = matchingMeds[idx];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.medication_rounded, color: Color(0xFFF87171), size: 18),
                      title: Text(med.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      subtitle: Text("Pack: ${med.packing} • MRP: ₹${med.mrp.toStringAsFixed(2)} • Stock: ${med.stock.toInt()}", style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
                      trailing: const Icon(Icons.auto_fix_high_rounded, color: Color(0xFFF87171), size: 16),
                      onTap: () {
                        controller.productSearchC.clear();
                        _triggerProductSelection(context, med);
                      },
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 14),
          ],

          Row(
            children: [
              const Icon(Icons.assignment_return_rounded, color: Color(0xFFF87171), size: 18),
              const SizedBox(width: 8),
              Text(
                "RETURN ITEMS CART (${controller.items.length})",
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "👉 Right Swipe on item to delete",
                  style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              if (controller.items.isNotEmpty && !controller.isReadOnly)
                TextButton(
                  onPressed: () => controller.clearCart(),
                  child: const Text("Clear Cart", style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                ),
            ],
          ),
          const Divider(color: Colors.white10, height: 16),

          if (controller.items.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(35),
                child: Text("Return cart is empty. Search products above to fetch customer sale history.", style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final bool isNarrow = constraints.maxWidth < 800;
                final double contentWidth = isNarrow ? 800.0 : constraints.maxWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: isNarrow ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Responsive Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              _colHead("SN", width: 36),
                              _colHead("TYPE", width: 56),
                              Expanded(flex: 4, child: _colHead("PRODUCT NAME", isLeft: true)),
                              _colHead("PACK", width: 75),
                              _colHead("BATCH", width: 85),
                              _colHead("EXP", width: 65),
                              _colHead("QTY", width: 70, isRight: true),
                              _colHead("RATE", width: 75, isRight: true),
                              _colHead("TOTAL", width: 90, isRight: true),
                              _colHead("ACT", width: 65),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Swipeable Items List
                        ...controller.items.asMap().entries.map((entry) {
                          int idx = entry.key;
                          BillItem it = entry.value;
                          String qtyDisp = "${it.qty.toInt()}${it.freeQty > 0 ? ' + ${it.freeQty.toInt()}' : ''}";
                          bool isExp = it.isBreakage;

                          return Dismissible(
                            key: ValueKey("CN_ITEM_${it.id}_$idx"),
                            direction: controller.isReadOnly ? DismissDirection.none : DismissDirection.startToEnd,
                            background: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.centerLeft,
                              child: const Row(
                                children: [
                                  Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 22),
                                  SizedBox(width: 10),
                                  Text(
                                    "SWIPE TO DELETE ITEM",
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5, letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                            ),
                            onDismissed: (_) {
                              controller.removeItem(idx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("🗑️ ${it.name} removed from Credit Note"),
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: Colors.red.shade900,
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  _colCell("${idx + 1}", width: 36),
                                  SizedBox(
                                    width: 56,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isExp ? const Color(0x33EA580C) : const Color(0x3310B981),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isExp ? "EXP" : "RET",
                                          style: TextStyle(
                                            color: isExp ? const Color(0xFFF97316) : Colors.greenAccent,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: InkWell(
                                      onTap: () {
                                        final med = webPh.medicines.firstWhere(
                                          (m) => m.id == it.medicineID || m.name == it.name,
                                          orElse: () => Medicine(id: it.medicineID, name: it.name, packing: it.packing),
                                        );
                                        _openItemEntryDialog(context, med, itemToEdit: it, editIndex: idx);
                                      },
                                      child: Text(
                                        it.name,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  _colCell(it.packing, width: 75),
                                  _colCell(it.batch, width: 85),
                                  _colCell(it.exp, width: 65),
                                  _colCell(qtyDisp, width: 70, isRight: true, isBold: true, color: Colors.cyanAccent),
                                  _colCell("₹${it.rate.toStringAsFixed(2)}", width: 75, isRight: true),
                                  _colCell("₹${it.total.toStringAsFixed(2)}", width: 90, isRight: true, isBold: true, color: const Color(0xFFF87171)),
                                  SizedBox(
                                    width: 65,
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
                                          const SizedBox(width: 8),
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

  Widget _colHead(String t, {double? width, bool isLeft = false, bool isRight = false}) {
    TextAlign align = isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center);
    Widget textWidget = Text(
      t,
      textAlign: align,
      style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold),
    );
    return width != null ? SizedBox(width: width, child: textWidget) : textWidget;
  }

  Widget _colCell(String t, {double? width, bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) {
    TextAlign align = isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center);
    Widget textWidget = Text(
      t,
      textAlign: align,
      style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
      overflow: TextOverflow.ellipsis,
    );
    return width != null ? SizedBox(width: width, child: textWidget) : textWidget;
  }
}
'''
with open(cn_path, "w", encoding="utf-8") as f:
    f.write(cn_code)
print(f"✔ Responsive Full-Width Credit Note Cart written: {cn_path}")

# 3. Write Responsive Debit Note Cart Widget
dn_path = "lib/web_live_sync/sub_views/web_returns/debit_note/ui/debit_note_cart_widget.dart"
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
                                child: const Text("CONFIRM & ADD TO DEBIT NOTE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5)),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      subtitle: Text("Pack: ${med.packing} • Pur.Rate: ₹${med.purRate.toStringAsFixed(2)} • Stock: ${med.stock.toInt()}", style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
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
            const SizedBox(height: 14),
          ],

          Row(
            children: [
              const Icon(Icons.remove_shopping_cart_rounded, color: Color(0xFFFBBF24), size: 18),
              const SizedBox(width: 8),
              Text(
                "DEBIT NOTE CART ITEMS (${controller.items.length})",
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "👉 Right Swipe on item to delete",
                  style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              if (controller.items.isNotEmpty && !controller.isReadOnly)
                TextButton(
                  onPressed: () => controller.clearCart(),
                  child: const Text("Clear Cart", style: TextStyle(color: Colors.redAccent, fontSize: 11)),
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
                final bool isNarrow = constraints.maxWidth < 800;
                final double contentWidth = isNarrow ? 800.0 : constraints.maxWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: isNarrow ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Responsive Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              _colHead("SN", width: 36),
                              _colHead("TYPE", width: 56),
                              Expanded(flex: 4, child: _colHead("PRODUCT NAME", isLeft: true)),
                              _colHead("PACK", width: 75),
                              _colHead("BATCH", width: 85),
                              _colHead("EXP", width: 65),
                              _colHead("QTY", width: 70, isRight: true),
                              _colHead("RATE", width: 75, isRight: true),
                              _colHead("TOTAL", width: 90, isRight: true),
                              _colHead("ACT", width: 65),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Swipeable Items List
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
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFD97706), Color(0xFF92400E)],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.centerLeft,
                              child: const Row(
                                children: [
                                  Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 22),
                                  SizedBox(width: 10),
                                  Text(
                                    "SWIPE TO DELETE ITEM",
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5, letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                            ),
                            onDismissed: (_) {
                              controller.removeItem(idx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("🗑️ ${it.name} removed from Debit Note"),
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: Colors.orange.shade900,
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  _colCell("${idx + 1}", width: 36),
                                  SizedBox(
                                    width: 56,
                                    child: Center(
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
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: InkWell(
                                      onTap: () {
                                        final med = webPh.medicines.firstWhere(
                                          (m) => m.id == it.medicineID || m.name == it.name,
                                          orElse: () => Medicine(id: it.medicineID, name: it.name, packing: it.packing),
                                        );
                                        _openItemEntryDialog(context, med, itemToEdit: it, editIndex: idx);
                                      },
                                      child: Text(
                                        it.name,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  _colCell(it.packing, width: 75),
                                  _colCell(it.batch, width: 85),
                                  _colCell(it.exp, width: 65),
                                  _colCell(qtyDisp, width: 70, isRight: true, isBold: true, color: const Color(0xFFFBBF24)),
                                  _colCell("₹${it.purchaseRate.toStringAsFixed(2)}", width: 75, isRight: true),
                                  _colCell("₹${it.total.toStringAsFixed(2)}", width: 90, isRight: true, isBold: true, color: const Color(0xFFF59E0B)),
                                  SizedBox(
                                    width: 65,
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
                                          const SizedBox(width: 8),
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

  Widget _colHead(String t, {double? width, bool isLeft = false, bool isRight = false}) {
    TextAlign align = isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center);
    Widget textWidget = Text(
      t,
      textAlign: align,
      style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold),
    );
    return width != null ? SizedBox(width: width, child: textWidget) : textWidget;
  }

  Widget _colCell(String t, {double? width, bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) {
    TextAlign align = isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center);
    Widget textWidget = Text(
      t,
      textAlign: align,
      style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
      overflow: TextOverflow.ellipsis,
    );
    return width != null ? SizedBox(width: width, child: textWidget) : textWidget;
  }
}
'''
with open(dn_path, "w", encoding="utf-8") as f:
    f.write(dn_code)
print(f"✔ Responsive Full-Width Debit Note Cart written: {dn_path}")

# 4. Analyze Code
print("\n🔍 Step 1/3: Analyzing Web Code...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], text=True)
if res.returncode != 0:
    print("❌ Analyze failed! Please inspect issues.")
    sys.exit(1)

# 5. Build Web Bundle
print("\n🔨 Step 2/3: Building Production Web Bundle...")
build_cmd = [
    "flutter", "build", "web",
    "-t", "lib/web_live_sync/web_main.dart",
    "--release",
    "--base-href", "/",
    "--pwa-strategy=none"
]
res_build = subprocess.run(build_cmd, text=True)
if res_build.returncode != 0:
    print("❌ Web Build failed!")
    sys.exit(1)

# 6. Deploy to Cloudflare Pages
print("\n🌐 Step 3/3: Deploying to Cloudflare Pages (pharoah-erp)...")
deploy_cmd = [
    "npx", "wrangler", "pages", "deploy", "build/web",
    "--project-name=pharoah-erp"
]
subprocess.run(deploy_cmd)

print("\n" + "="*52)
print(f"🎉 LIVE DEPLOY COMPLETE! Version: {new_rev}")
print("🔗 Live URL: https://pharoah-erp.pages.dev")
print("="*52)
