// FILE: lib/web_live_sync/sub_views/web_returns/credit_note/ui/credit_note_cart_widget.dart

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
                          String qtyDisp = "${(it.qty % 1 == 0 ? it.qty.toInt().toString() : it.qty.toStringAsFixed(1))}${it.freeQty > 0 ? ' + ${(it.freeQty % 1 == 0 ? it.freeQty.toInt().toString() : it.freeQty.toStringAsFixed(1))}' : ''}";
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
