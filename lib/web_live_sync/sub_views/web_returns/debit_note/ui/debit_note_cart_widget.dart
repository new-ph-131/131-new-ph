// FILE: lib/web_live_sync/sub_views/web_returns/debit_note/ui/debit_note_cart_widget.dart
// ignore_for_file: prefer_const_constructors, unnecessary_const

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/debit_note_controller.dart';
import 'debit_note_magic_history_modal.dart';
import '../../shared/web_pull_from_bill_modal.dart';
import '../../../web_billing/web_batch_lookup_dialog.dart';
import '../../../web_billing/quick_add_product_modal.dart';
import '../../../../../logic/return_history_engine.dart';
import '../../../../../logic/item_net_rate_helper.dart';
import '../../../../../expiry_master.dart';

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
        const SnackBar(
            content: Text("Please select a Supplier / Distributor first!"),
            backgroundColor: Colors.orange),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (c) => DebitNoteMagicHistoryModal(
        medicine: med,
        supplier: controller.selectedSupplier!,
        webPh: webPh,
        currentCartItems: controller.items,
        excludeNoteId: controller.existingRecordId,
        onSelect: (selectedHistory) {
          _openItemEntryDialog(context, med, historyData: selectedHistory);
        },
        onAutoSplit: (allocations, hasOverReturn) {
          final List<PurchaseItem> batchLines = [];
          int nextSr = controller.items.length + 1;
          for (final a in allocations) {
            batchLines.add(ReturnHistoryEngine.buildPurchaseItemFromLine(
              med: med,
              line: a.line,
              qty: a.allocatedQty,
              freeQty: a.allocatedFreeQty,
              useSchemeNetRate: a.useSchemeNetRate,
              srNo: nextSr++,
              isBreakage: controller.isBreakageMode,
              isCommercial: controller.isCommercial,
            ));
          }
          controller.addItemsBatch(batchLines, webPh: webPh);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                hasOverReturn
                    ? "Added ${batchLines.length} auto-split line(s) (Notice: exceeded available return balance on batch)."
                    : "Added ${batchLines.length} auto-split line(s) from inward batch history.",
              ),
              backgroundColor:
                  hasOverReturn ? Colors.orange.shade800 : const Color(0xFFD97706),
            ),
          );
        },
      ),
    );
  }

  void _openPullFromBillModal(BuildContext context, {String? initialBillNo}) {
    if (controller.isReadOnly) return;
    if (controller.selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a Supplier / Distributor first!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (c) => WebPullFromBillModal(
        isSale: false,
        party: controller.selectedSupplier!,
        webPh: webPh,
        currentCartItems: controller.items,
        excludeNoteId: controller.existingRecordId,
        initialBillNo: initialBillNo,
        onAddSelected: (picked) {
          final List<PurchaseItem> newLines = [];
          int nextSr = controller.items.length + 1;
          for (final p in picked) {
            newLines.add(ReturnHistoryEngine.buildPurchaseItemFromLine(
              med: p.medicine,
              line: p.line,
              qty: p.qty,
              freeQty: p.freeQty,
              useSchemeNetRate: p.useSchemeNetRate,
              srNo: nextSr++,
              isBreakage: controller.isBreakageMode,
              isCommercial: controller.isCommercial,
            ));
          }
          controller.addItemsBatch(newLines, webPh: webPh);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Pulled ${newLines.length} item(s) from purchase invoice."),
              backgroundColor: const Color(0xFFD97706),
            ),
          );
        },
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

  void _openItemEntryDialog(
    BuildContext context,
    Medicine med, {
    PurchaseItem? itemToEdit,
    int? editIndex,
    Map<String, dynamic>? historyData,
  }) {
    List<BatchInfo> batches = webPh.getBatchesForMedicine(med);
    final String histBillNo = (historyData?['billNo'] ?? '').toString().trim();
    final DateTime? histDate =
        historyData?['date'] is DateTime ? historyData!['date'] as DateTime : null;
    final bool isManualNew = itemToEdit == null && historyData == null;

    final batchC = TextEditingController(
        text: itemToEdit?.batch ?? (historyData?['batch'] ?? ""));
    final expC = TextEditingController(
        text: itemToEdit?.exp ?? (historyData?['exp'] ?? "12/28"));
    final mrpC = TextEditingController(
      text: itemToEdit != null
          ? itemToEdit.mrp.toStringAsFixed(2)
          : ((historyData?['mrp'] as num?)?.toDouble() ?? med.mrp)
              .toStringAsFixed(2),
    );
    final purRateC = TextEditingController(
      text: itemToEdit != null
          ? itemToEdit.purchaseRate.toStringAsFixed(2)
          : ((historyData?['purchaseRate'] as num?)?.toDouble() ?? med.purRate)
              .toStringAsFixed(2),
    );
    final rateAC = TextEditingController(
      text: itemToEdit != null
          ? itemToEdit.rateA.toStringAsFixed(2)
          : med.rateA.toStringAsFixed(2),
    );
    final rateBC = TextEditingController(
      text: itemToEdit != null
          ? itemToEdit.rateB.toStringAsFixed(2)
          : med.rateB.toStringAsFixed(2),
    );
    final rateCC = TextEditingController(
      text: itemToEdit != null
          ? itemToEdit.rateC.toStringAsFixed(2)
          : med.rateC.toStringAsFixed(2),
    );
    final rateCDiscC = TextEditingController(
      text: itemToEdit != null ? itemToEdit.rateCFormula.toString() : "0.0",
    );

    final qtyC = TextEditingController(
      text: itemToEdit != null
          ? formatQty(itemToEdit.qty)
          : formatQty((historyData?['qty'] as num?)?.toDouble() ?? 1.0),
    );
    final freeC = TextEditingController(
      text: itemToEdit != null
          ? formatQty(itemToEdit.freeQty)
          : formatQty((historyData?['free'] as num?)?.toDouble() ?? 0.0),
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
      text: itemToEdit != null
          ? itemToEdit.discountRupees.toStringAsFixed(2)
          : (((double.tryParse(qtyC.text) ?? 0.0) *
                  (double.tryParse(purRateC.text) ?? 0.0) *
                  ((double.tryParse(discPerC.text) ?? 0.0) / 100.0)))
              .toStringAsFixed(2),
    );
    final netRateC = TextEditingController();

    String selectedRateType = itemToEdit?.appliedRateType ?? "A";
    bool netRateInclGst = false;
    bool netViaDisc = false;
    final double histBilledQ = (historyData?['billedQty'] as num?)?.toDouble() ?? 0.0;
    final double histBilledF = (historyData?['billedFreeQty'] as num?)?.toDouble() ?? 0.0;
    final double histOrigRate =
        ((historyData?['originalRate'] ?? historyData?['purchaseRate'] ?? historyData?['rate']) as num?)
                ?.toDouble() ??
            med.purRate;
    final ReturnSchemeContext? schemeCtx = (historyData != null && histBilledF > 0 && histBilledQ > 0)
        ? ReturnSchemeContext(
            billedQty: histBilledQ,
            billedFreeQty: histBilledF,
            originalRate: histOrigRate,
            initialUseSchemeNetRate: historyData['useSchemeNetRate'] == true,
          )
        : null;
    bool useSchemeNetRate = schemeCtx?.initialUseSchemeNetRate ?? false;

    void syncNetRateFromInputs() {
      final double q = double.tryParse(qtyC.text) ?? 0.0;
      final double f = double.tryParse(freeC.text) ?? 0.0;
      final double r = double.tryParse(purRateC.text) ?? 0.0;
      final double dAmt = double.tryParse(discAmtC.text) ?? 0.0;
      final double g = double.tryParse(gstC.text) ?? 0.0;
      final double val = netRateInclGst
          ? ItemNetRateHelper.computeLandedNetRate(
              qty: q, freeQty: f, rate: r, discRupees: dAmt, gstRate: g)
          : ItemNetRateHelper.computeTaxableNetRate(
              qty: q, freeQty: f, rate: r, discRupees: dAmt);
      netRateC.text = val.toStringAsFixed(2);
    }

    syncNetRateFromInputs();

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
              double finalDerivedRate =
                  baseTaxable - (baseTaxable * (formulaDisc / 100));
              rateCC.text = finalDerivedRate.toStringAsFixed(2);
            }

            void syncDiscount(bool isPercentSource) {
              double q = double.tryParse(qtyC.text) ?? 0.0;
              double r = double.tryParse(purRateC.text) ?? 0.0;
              double gross = q * r;
              if (gross <= 0) {
                discAmtC.text = "0.00";
                syncNetRateFromInputs();
                return;
              }

              if (isPercentSource) {
                double p = double.tryParse(discPerC.text) ?? 0.0;
                discAmtC.text = (gross * (p / 100)).toStringAsFixed(2);
              } else {
                double a = double.tryParse(discAmtC.text) ?? 0.0;
                discPerC.text = ((a / gross) * 100).toStringAsFixed(2);
              }
              syncNetRateFromInputs();
            }

            void onNetRateChanged(String raw) {
              final double target = double.tryParse(raw) ?? 0.0;
              final double rawQ = double.tryParse(qtyC.text) ?? 0.0;
              final double qVal = rawQ > 0 ? rawQ : 1.0;
              final double fVal = double.tryParse(freeC.text) ?? 0.0;
              final double gVal = double.tryParse(gstC.text) ?? 0.0;
              if (target <= 0) {
                setDialogState(() {});
                return;
              }
              if (netViaDisc) {
                final double rVal = double.tryParse(purRateC.text) ?? 0.0;
                final res = ItemNetRateHelper.reverseComputeDiscount(
                  targetNetRate: target,
                  qty: qVal,
                  freeQty: fVal,
                  rate: rVal,
                  gstRate: gVal,
                  isInclGst: netRateInclGst,
                );
                discPerC.text = res.discPer.toStringAsFixed(2);
                discAmtC.text = (rawQ > 0 ? res.discAmt : 0.0).toStringAsFixed(2);
              } else {
                final double dPer = double.tryParse(discPerC.text) ?? 0.0;
                final double newRate = ItemNetRateHelper.reverseComputeRate(
                  targetNetRate: target,
                  qty: qVal,
                  freeQty: fVal,
                  discPer: dPer,
                  gstRate: gVal,
                  isInclGst: netRateInclGst,
                );
                purRateC.text = newRate.toStringAsFixed(2);
                final double gross = rawQ * newRate;
                discAmtC.text = (gross * (dPer / 100.0)).toStringAsFixed(2);
              }
              setDialogState(() {});
            }

            void toggleSchemeMode(bool useNet) {
              if (schemeCtx == null || !schemeCtx.hasFreeScheme) return;
              setDialogState(() {
                useSchemeNetRate = useNet;
                if (useNet) {
                  final curQ = double.tryParse(qtyC.text) ?? 0.0;
                  final curF = double.tryParse(freeC.text) ?? 0.0;
                  if (curF > 0) {
                    qtyC.text = formatQty(curQ + curF);
                    freeC.text = "0";
                  }
                  purRateC.text = schemeCtx.schemeNetRate.toStringAsFixed(2);
                } else {
                  purRateC.text = schemeCtx.originalRate.toStringAsFixed(2);
                }
                syncDiscount(true);
              });
            }

            void executeSave() {
              if (expC.text.trim().isNotEmpty) {
                final expWarn = ExpiryMaster.getValidationWarning(expC.text.trim());
                if (expWarn != null && expWarn.startsWith("Error")) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(expWarn), backgroundColor: Colors.orange),
                  );
                  return;
                }
              }

              double q = double.tryParse(qtyC.text) ?? 0.0;
              double fQty = double.tryParse(freeC.text) ?? 0.0;
              double pRate = double.tryParse(purRateC.text) ?? 0.0;
              double dAmt = double.tryParse(discAmtC.text) ?? 0.0;
              double gPer = double.tryParse(gstC.text) ?? 0.0;

              double gross = q * pRate;
              double taxable = gross - dAmt;
              if (taxable < 0) taxable = 0.0;
              double taxAmt = taxable * (gPer / 100);
              double netItemTotal = taxable + taxAmt;

              if ((q <= 0 && (schemeCtx == null || fQty <= 0)) || pRate <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          "Quantity and Purchase Rate must be greater than zero!"),
                      backgroundColor: Colors.orange),
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
                isBreakage:
                    itemToEdit != null ? itemToEdit.isBreakage : controller.isBreakageMode,
                origBillNo: itemToEdit != null
                    ? itemToEdit.origBillNo
                    : (isManualNew ? "" : histBillNo),
                origBillDate: itemToEdit != null
                    ? itemToEdit.origBillDate
                    : (isManualNew ? null : histDate),
                isManualOrigin: itemToEdit != null
                    ? itemToEdit.isManualOrigin
                    : (isManualNew || histBillNo.isEmpty),
              );

              if (editIndex != null) {
                controller.updateItem(editIndex, newItem, webPh: webPh);
              } else {
                controller.addItem(newItem, webPh: webPh);
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
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black54, blurRadius: 25, offset: Offset(0, 10))
                  ],
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
                            decoration: const BoxDecoration(
                                color: Color(0x33F59E0B), shape: BoxShape.circle),
                            child: const Icon(Icons.remove_shopping_cart_rounded,
                                color: Color(0xFFFBBF24), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "DEBIT NOTE ITEM CONFIG",
                                  style: TextStyle(
                                      color: Color(0xFFFBBF24),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "${med.name} (${med.packing})",
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white54, size: 20),
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
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(6)),
                                        elevation: 0,
                                      ),
                                      onPressed: () async {
                                        final selected = await showDialog<dynamic>(
                                          context: context,
                                          builder: (ctx) => WebBatchLookupDialog(
                                              medicine: med,
                                              batches: batches,
                                              prioritizeExpired: true),
                                        );
                                        if (selected != null && selected is BatchInfo) {
                                          setDialogState(() {
                                            batchC.text = selected.batch;
                                            expC.text = selected.exp;
                                            mrpC.text = selected.mrp.toStringAsFixed(2);
                                            purRateC.text =
                                                (selected.purRate > 0
                                                        ? selected.purRate
                                                        : selected.rate)
                                                    .toStringAsFixed(2);
                                            rateAC.text =
                                                selected.rateA.toStringAsFixed(2);
                                            rateBC.text =
                                                selected.rateB.toStringAsFixed(2);
                                            rateCC.text =
                                                selected.rateC.toStringAsFixed(2);
                                            rateCDiscC.text =
                                                selected.rateCFormula.toStringAsFixed(2);
                                            selectedRateType = selected.appliedRateType;
                                            syncDiscount(true);
                                          });
                                        }
                                      },
                                      icon: const Icon(Icons.layers_rounded, size: 14),
                                      label: const Text("BATCHES",
                                          style: TextStyle(
                                              fontSize: 9, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                    flex: 2,
                                    child: _dialogInput("EXPIRY (MM/YY) *", expC,
                                        isNum: true)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Text("RATE SCHEME:",
                                    style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(width: 10),
                                _rateSegment("RATE A", selectedRateType == "A", () {
                                  if (selectedRateType == "A") return;
                                  FocusScope.of(context).unfocus();
                                  setDialogState(() => selectedRateType = "A");
                                }),
                                const SizedBox(width: 6),
                                _rateSegment("RATE B", selectedRateType == "B", () {
                                  if (selectedRateType == "B") return;
                                  FocusScope.of(context).unfocus();
                                  setDialogState(() => selectedRateType = "B");
                                }),
                                const SizedBox(width: 6),
                                _rateSegment("RATE C", selectedRateType == "C", () {
                                  if (selectedRateType == "C") return;
                                  FocusScope.of(context).unfocus();
                                  setDialogState(() {
                                    selectedRateType = "C";
                                    calculateRateC();
                                  });
                                }),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (schemeCtx != null && schemeCtx.hasFreeScheme) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0x44F59E0B)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.auto_fix_high_rounded,
                                        color: Color(0xFFFBBF24), size: 15),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "SCHEME (${formatQty(schemeCtx.billedQty)}+${formatQty(schemeCtx.billedFreeQty)}F):",
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    ChoiceChip(
                                      label: Text(
                                        "Bill ₹${schemeCtx.originalRate.toStringAsFixed(2)} + Free",
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                      selected: !useSchemeNetRate,
                                      onSelected: (_) {
                                        if (!useSchemeNetRate) return;
                                        FocusScope.of(context).unfocus();
                                        toggleSchemeMode(false);
                                      },
                                      visualDensity: VisualDensity.compact,
                                      selectedColor: const Color(0xFFD97706),
                                      backgroundColor: const Color(0xFF1E293B),
                                      labelStyle: const TextStyle(color: Colors.white),
                                    ),
                                    const SizedBox(width: 6),
                                    ChoiceChip(
                                      label: Text(
                                        "Net ₹${schemeCtx.schemeNetRate.toStringAsFixed(2)} (Random Qty)",
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                      selected: useSchemeNetRate,
                                      onSelected: (_) {
                                        if (useSchemeNetRate) return;
                                        FocusScope.of(context).unfocus();
                                        toggleSchemeMode(true);
                                      },
                                      visualDensity: VisualDensity.compact,
                                      selectedColor: const Color(0xFF0F766E),
                                      backgroundColor: const Color(0xFF1E293B),
                                      labelStyle: const TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            Row(
                              children: [
                                if (selectedRateType == "C") ...[
                                  Expanded(
                                      child: _dialogInput("C FORMULA %", rateCDiscC,
                                          isNum: true,
                                          onChanged: (_) =>
                                              setDialogState(() => calculateRateC()))),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                    child: _dialogInput("MRP ₹", mrpC,
                                        isNum: true,
                                        onChanged: (_) => setDialogState(() {
                                              if (selectedRateType == "C")
                                                calculateRateC();
                                            }))),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: _dialogInput("PUR. RATE ₹ *", purRateC,
                                        isNum: true,
                                        isHighlight: true,
                                        onChanged: (_) =>
                                            setDialogState(() => syncDiscount(true)))),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: _dialogInput("GST %", gstC,
                                        isNum: true,
                                        onChanged: (_) => setDialogState(() {
                                              if (selectedRateType == "C")
                                                calculateRateC();
                                              syncNetRateFromInputs();
                                            }))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                    child: _dialogInput("QTY *", qtyC,
                                        isNum: true,
                                        isHighlight: true,
                                        onChanged: (_) =>
                                            setDialogState(() => syncDiscount(true)),
                                        onSubmitted: (_) => executeSave())),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: _dialogInput("FREE QTY", freeC,
                                        isNum: true,
                                        onChanged: (_) => setDialogState(
                                            () => syncNetRateFromInputs()))),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: _dialogInput("DISC %", discPerC,
                                        isNum: true,
                                        onChanged: (_) =>
                                            setDialogState(() => syncDiscount(true)))),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: _dialogInput("DISC ₹", discAmtC,
                                        isNum: true,
                                        onChanged: (_) =>
                                            setDialogState(() => syncDiscount(false)))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Builder(
                              builder: (_) {
                                final double fQty = double.tryParse(freeC.text) ?? 0.0;
                                final double taxableNet = ItemNetRateHelper.computeTaxableNetRate(
                                    qty: q, freeQty: fQty, rate: pRate, discRupees: dAmt);
                                final double landedNet = ItemNetRateHelper.computeLandedNetRate(
                                    qty: q, freeQty: fQty, rate: pRate, discRupees: dAmt, gstRate: gPer);
                                return Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0x44F59E0B)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            "NET RATE / UNIT (${netRateInclGst ? 'INCL. GST' : 'EXCL. GST'})",
                                            style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFFFBBF24),
                                              letterSpacing: 0.6,
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () {
                                              FocusScope.of(context).unfocus();
                                              setDialogState(() {
                                                netRateInclGst = !netRateInclGst;
                                                syncNetRateFromInputs();
                                              });
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: netRateInclGst ? const Color(0xFF0F766E) : const Color(0xFF1E293B),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0x55F59E0B)),
                                              ),
                                              child: Text(
                                                netRateInclGst ? "Incl. GST" : "Excl. GST",
                                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () {
                                              FocusScope.of(context).unfocus();
                                              setDialogState(() => netViaDisc = !netViaDisc);
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: netViaDisc ? const Color(0xFF2563EB) : const Color(0xFFD97706),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                netViaDisc ? "Via: Disc%" : "Via: Pur.Rate",
                                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: _dialogInput(
                                              "NET RATE ₹ (${netRateInclGst ? 'INCL. GST' : 'EXCL. GST'})",
                                              netRateC,
                                              isNum: true,
                                              isHighlight: true,
                                              onChanged: onNetRateChanged,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            flex: 4,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.black26,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.white12),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "Taxable/u: ₹${taxableNet.toStringAsFixed(2)}",
                                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70),
                                                  ),
                                                  Text(
                                                    "Landed/u (incl GST): ₹${landedNet.toStringAsFixed(2)}",
                                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFFBBF24)),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                    child: _dialogInput("RATE A ₹", rateAC, isNum: true)),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: _dialogInput("RATE B ₹", rateBC, isNum: true)),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: _dialogInput("RATE C ₹", rateCC,
                                        isNum: true,
                                        isReadOnly: selectedRateType == "C")),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0x33F59E0B)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                      "Taxable: ₹${taxable.toStringAsFixed(2)} | GST: ₹${taxAmt.toStringAsFixed(2)}",
                                      style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold)),
                                  Text("₹${netItemTotal.toStringAsFixed(2)}",
                                      style: const TextStyle(
                                          color: Color(0xFFFBBF24),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900)),
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
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: executeSave,
                                child: const Text("CONFIRM & ADD TO DEBIT NOTE",
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                        letterSpacing: 0.5)),
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
    return _DebitNoteInputField(
      label: label,
      ctrl: ctrl,
      isNum: isNum,
      isHighlight: isHighlight,
      isReadOnly: isReadOnly,
      suffix: suffix,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

class _DebitNoteInputField extends StatefulWidget {
  final String label;
  final TextEditingController ctrl;
  final bool isNum;
  final bool isHighlight;
  final bool isReadOnly;
  final Widget? suffix;
  final Function(String)? onChanged;
  final Function(String)? onSubmitted;

  const _DebitNoteInputField({
    required this.label,
    required this.ctrl,
    this.isNum = false,
    this.isHighlight = false,
    this.isReadOnly = false,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<_DebitNoteInputField> createState() => _DebitNoteInputFieldState();
}

class _DebitNoteInputFieldState extends State<_DebitNoteInputField> {
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
    final bool activeBorder = _isFocused || widget.isHighlight;
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: widget.isReadOnly
                ? Colors.black38
                : (activeBorder ? const Color(0x33F59E0B) : Colors.black26),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: activeBorder ? const Color(0xFFFBBF24) : Colors.white12,
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
                  cursorColor: const Color(0xFFFBBF24),
                  cursorHeight: 14,
                  cursorWidth: 1.5,
                  cursorRadius: const Radius.circular(2),
                  readOnly: widget.isReadOnly,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
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
    final recentBills = controller.getRecentBills(webPh, limit: 12);

    final matchingMeds = query.isEmpty
        ? <Medicine>[]
        : webPh.medicines.where((m) {
            if (m.name.toLowerCase().contains(query) ||
                m.systemId.toLowerCase().contains(query) ||
                m.hsnCode.toLowerCase().contains(query)) return true;
            final batches = webPh.getBatchesForMedicine(m);
            return batches.any((b) => b.batch.toLowerCase().contains(query));
          }).take(18).toList();

    final matchingBills = query.isEmpty
        ? <ReturnRecentBill>[]
        : recentBills
            .where((b) =>
                b.billNo.toLowerCase().contains(query) ||
                b.lines.any((l) => l.batch.toLowerCase().contains(query)))
            .take(6)
            .toList();

    final Map<String, int> dupCounts = {};
    for (final it in controller.items) {
      final k =
          "${it.origBillNo.trim().toUpperCase()}||${it.batch.trim().toUpperCase()}||${it.name.trim().toUpperCase()}";
      dupCounts[k] = (dupCounts[k] ?? 0) + 1;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
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
                      labelText: "SMART RETURN LOOKUP (PRODUCT / BATCH / SUPPLIER BILL)",
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                      hintText:
                          "Type medicine name, batch no, or purchase bill no (opens Batch-Grouped History)...",
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Color(0xFFFBBF24), size: 18),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => controller.notifySearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _openPullFromBillModal(context),
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: Text(
                    recentBills.isNotEmpty
                        ? "PULL BILL (${recentBills.length})"
                        : "PULL BILL",
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _openQuickAddProduct(context),
                  icon: const Icon(Icons.add_box_rounded, size: 16),
                  label: const Text("+ PRODUCT",
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (matchingMeds.isNotEmpty || matchingBills.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x44F59E0B)),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (matchingBills.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Text(
                          "MATCHING SUPPLIER BILLS (PULL MULTI-ITEMS)",
                          style: TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                      ...matchingBills.map((b) => ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: const Icon(Icons.receipt_long_rounded,
                                color: Color(0xFF38BDF8), size: 18),
                            title: Text("Bill ${b.billNo}",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                            subtitle: Text(
                              "${DateFormat('dd/MM/yyyy').format(b.date)} • ${b.lines.length} items • ₹${b.totalAmount.toStringAsFixed(0)}",
                              style: const TextStyle(color: Colors.white54, fontSize: 10),
                            ),
                            trailing: const Icon(Icons.playlist_add_rounded,
                                color: Color(0xFF38BDF8), size: 18),
                            onTap: () {
                              controller.productSearchC.clear();
                              _openPullFromBillModal(context, initialBillNo: b.billNo);
                            },
                          )),
                    ],
                    if (matchingMeds.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Text(
                          "MEDICINES (BATCH-GROUPED INWARD HISTORY)",
                          style: TextStyle(
                              color: Color(0xFFFBBF24),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                      ...matchingMeds.map((med) => ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: const Icon(Icons.medication_rounded,
                                color: Color(0xFFFBBF24), size: 18),
                            title: Text(med.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                            subtitle: Text(
                              "Pack: ${med.packing} • Pur.Rate: ₹${med.purRate.toStringAsFixed(2)} • Stock: ${formatQty(med.stock)}",
                              style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                            ),
                            trailing: const Icon(Icons.layers_rounded,
                                color: Color(0xFFFBBF24), size: 16),
                            onTap: () {
                              controller.productSearchC.clear();
                              _triggerProductSelection(context, med);
                            },
                          )),
                    ],
                  ],
                ),
              ),
            ],
            if (recentBills.isNotEmpty && query.isEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text(
                    "RECENT INWARD BILLS:",
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: recentBills.take(8).map((b) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              backgroundColor: const Color(0xFF0F172A),
                              side: const BorderSide(color: Color(0x44F59E0B)),
                              avatar: const Icon(Icons.receipt_outlined,
                                  color: Color(0xFFFBBF24), size: 13),
                              label: Text(
                                "${b.billNo} • ${DateFormat('dd/MM').format(b.date)} • ₹${b.totalAmount.toStringAsFixed(0)}",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                              onPressed: () =>
                                  _openPullFromBillModal(context, initialBillNo: b.billNo),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              const Icon(Icons.remove_shopping_cart_rounded,
                  color: Color(0xFFFBBF24), size: 17),
              const SizedBox(width: 8),
              Text(
                "DEBIT NOTE CART (${controller.items.length} ITEMS)",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "Inline -/+ Qty • Swipe right to delete",
                  style: TextStyle(
                      color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              if (controller.items.isNotEmpty && !controller.isReadOnly)
                TextButton.icon(
                  onPressed: () => controller.clearCart(webPh: webPh),
                  icon: const Icon(Icons.clear_all_rounded,
                      color: Colors.redAccent, size: 15),
                  label: const Text("Clear Cart",
                      style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                ),
            ],
          ),
          const Divider(color: Colors.white10, height: 14),

          if (controller.items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.layers_clear_rounded,
                        size: 42, color: Colors.white.withAlpha(40)),
                    const SizedBox(height: 10),
                    const Text(
                      "Debit Note cart is empty. Search Medicine / Batch / Supplier Bill above or click PULL BILL to import items from a past purchase invoice.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final bool isNarrow = constraints.maxWidth < 860;
                final double contentWidth = isNarrow ? 860.0 : constraints.maxWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: isNarrow
                      ? const BouncingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              _colHead("SN", width: 30),
                              _colHead("TYPE", width: 46),
                              Expanded(flex: 3, child: _colHead("PRODUCT", isLeft: true)),
                              _colHead("ORIG. INV", width: 95, isLeft: true),
                              _colHead("BATCH / EXP", width: 105, isLeft: true),
                              _colHead("QTY", width: 108),
                              _colHead("P.RATE / D%", width: 78, isRight: true),
                              _colHead("GST%", width: 44, isRight: true),
                              _colHead("NET AMT", width: 80, isRight: true),
                              _colHead("ACT", width: 58),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...controller.items.asMap().entries.map((entry) {
                          int idx = entry.key;
                          PurchaseItem it = entry.value;
                          bool isExp = it.isBreakage;
                          final dupKey =
                              "${it.origBillNo.trim().toUpperCase()}||${it.batch.trim().toUpperCase()}||${it.name.trim().toUpperCase()}";
                          final bool isDup =
                              it.origBillNo.trim().isNotEmpty && (dupCounts[dupKey] ?? 0) > 1;

                          return Dismissible(
                            key: ValueKey("DN_ITEM_${it.id}_$idx"),
                            direction: controller.isReadOnly
                                ? DismissDirection.none
                                : DismissDirection.startToEnd,
                            background: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [Color(0xFFDC2626), Color(0xFF991B1B)]),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.centerLeft,
                              child: const Row(
                                children: [
                                  Icon(Icons.delete_sweep_rounded,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text("SWIPE TO DELETE",
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11)),
                                ],
                              ),
                            ),
                            onDismissed: (_) => controller.removeItem(idx, webPh: webPh),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDup
                                      ? Colors.orangeAccent.withAlpha(140)
                                      : Colors.white10,
                                ),
                              ),
                              child: Row(
                                children: [
                                  _colCell("${idx + 1}", width: 30),
                                  SizedBox(
                                    width: 46,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isExp
                                              ? const Color(0x33EA580C)
                                              : const Color(0x330F766E),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isExp ? "EXP" : "RET",
                                          style: TextStyle(
                                            color: isExp
                                                ? const Color(0xFFF97316)
                                                : Colors.tealAccent,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: InkWell(
                                      onTap: controller.isReadOnly
                                          ? null
                                          : () {
                                              final med = webPh.medicines.firstWhere(
                                                (m) =>
                                                    m.id == it.medicineID ||
                                                    m.name == it.name,
                                                orElse: () => Medicine(
                                                  id: it.medicineID,
                                                  name: it.name,
                                                  packing: it.packing,
                                                ),
                                              );
                                              _openItemEntryDialog(context, med,
                                                  itemToEdit: it, editIndex: idx);
                                            },
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  it.name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11.5,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isDup)
                                                Container(
                                                  margin: const EdgeInsets.only(left: 4),
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 4, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0x33F59E0B),
                                                    borderRadius: BorderRadius.circular(3),
                                                  ),
                                                  child: const Text(
                                                    "DUP",
                                                    style: TextStyle(
                                                      color: Colors.orangeAccent,
                                                      fontSize: 7.5,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          Text(
                                            it.packing,
                                            style: const TextStyle(
                                                color: Colors.white38, fontSize: 9.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 95,
                                    child: it.origBillNo.trim().isEmpty
                                        ? const Text("Manual",
                                            style: TextStyle(
                                                color: Colors.white38, fontSize: 9.5))
                                        : Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                it.origBillNo,
                                                style: const TextStyle(
                                                  color: Color(0xFFFBBF24),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (it.origBillDate != null)
                                                Text(
                                                  DateFormat('dd/MM/yy')
                                                      .format(it.origBillDate!),
                                                  style: const TextStyle(
                                                      color: Colors.white54,
                                                      fontSize: 8.5),
                                                ),
                                            ],
                                          ),
                                  ),
                                  SizedBox(
                                    width: 105,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          it.batch,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          "Exp: ${it.exp}",
                                          style: const TextStyle(
                                              color: Colors.white54, fontSize: 9),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // INLINE QTY STEPPER
                                  SizedBox(
                                    width: 108,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (!controller.isReadOnly)
                                          InkWell(
                                            onTap: it.qty > 1
                                                ? () => controller.updateItemQty(
                                                    idx, it.qty - 1,
                                                    webPh: webPh)
                                                : null,
                                            child: Container(
                                              padding: const EdgeInsets.all(3),
                                              decoration: BoxDecoration(
                                                color: Colors.white10,
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: Icon(
                                                Icons.remove_rounded,
                                                size: 13,
                                                color: it.qty > 1
                                                    ? Colors.white
                                                    : Colors.white24,
                                              ),
                                            ),
                                          ),
                                        Padding(
                                          padding:
                                              const EdgeInsets.symmetric(horizontal: 6),
                                          child: Text(
                                            formatQtyPair(it.qty, it.freeQty),
                                            style: const TextStyle(
                                              color: Color(0xFFFBBF24),
                                              fontWeight: FontWeight.w900,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ),
                                        if (!controller.isReadOnly)
                                          InkWell(
                                            onTap: () => controller.updateItemQty(
                                                idx, it.qty + 1,
                                                webPh: webPh),
                                            child: Container(
                                              padding: const EdgeInsets.all(3),
                                              decoration: BoxDecoration(
                                                color: Colors.white10,
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: const Icon(Icons.add_rounded,
                                                  size: 13, color: Colors.white),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: 78,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          "₹${it.purchaseRate.toStringAsFixed(2)}",
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        if (it.discountPer > 0)
                                          Text(
                                            "-${it.discountPer.toStringAsFixed(1)}%",
                                            style: const TextStyle(
                                                color: Colors.orangeAccent,
                                                fontSize: 9),
                                          ),
                                      ],
                                    ),
                                  ),
                                  _colCell("${it.gstRate.toInt()}%",
                                      width: 44, isRight: true, color: Colors.white60),
                                  _colCell("₹${it.total.toStringAsFixed(2)}",
                                      width: 80,
                                      isRight: true,
                                      isBold: true,
                                      color: const Color(0xFFF59E0B)),
                                  SizedBox(
                                    width: 58,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (!controller.isReadOnly) ...[
                                          IconButton(
                                            icon: const Icon(Icons.edit_note_rounded,
                                                size: 17, color: Color(0xFF38BDF8)),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              final med = webPh.medicines.firstWhere(
                                                (m) =>
                                                    m.id == it.medicineID ||
                                                    m.name == it.name,
                                                orElse: () => Medicine(
                                                  id: it.medicineID,
                                                  name: it.name,
                                                  packing: it.packing,
                                                ),
                                              );
                                              _openItemEntryDialog(context, med,
                                                  itemToEdit: it, editIndex: idx);
                                            },
                                          ),
                                          const SizedBox(width: 6),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded,
                                                size: 17, color: Colors.redAccent),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () =>
                                                controller.removeItem(idx, webPh: webPh),
                                          ),
                                        ] else
                                          const Icon(Icons.lock_rounded,
                                              size: 14, color: Colors.white38),
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
    TextAlign align =
        isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center);
    Widget textWidget = Text(
      t,
      textAlign: align,
      style: const TextStyle(
          color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold),
    );
    return width != null ? SizedBox(width: width, child: textWidget) : textWidget;
  }

  Widget _colCell(String t,
      {double? width,
      bool isLeft = false,
      bool isRight = false,
      bool isBold = false,
      Color color = Colors.white}) {
    TextAlign align =
        isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center);
    Widget textWidget = Text(
      t,
      textAlign: align,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      ),
      overflow: TextOverflow.ellipsis,
    );
    return width != null ? SizedBox(width: width, child: textWidget) : textWidget;
  }
}
