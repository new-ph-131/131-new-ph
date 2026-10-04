// FILE: lib/web_live_sync/sub_views/web_challans/sale_challan/ui/sale_challan_cart_widget.dart

import 'package:flutter/material.dart';
import 'package:pharoah_erp/models.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/sale_challan_controller.dart';
import '../../../web_billing/web_item_entry_card.dart';
import '../../../web_billing/quick_add_product_modal.dart';

class SaleChallanCartWidget extends StatelessWidget {
  final SaleChallanController controller;
  final PharoahWebManager webPh;

  const SaleChallanCartWidget({
    super.key,
    required this.controller,
    required this.webPh,
  });

  void _openItemEntryDialog(BuildContext context, Medicine med, {BillItem? itemToEdit, int? editIndex}) {
    if (controller.isReadOnly) return;
    if (controller.selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select Customer first!"), backgroundColor: Colors.orange),
      );
      return;
    }

    String shopState = (webPh.companyProfile['state'] ?? 'Rajasthan').toString();
    String partyState = controller.selectedCustomer!.state;
    List<BatchInfo> batches = webPh.batchHistory[med.identityKey] ?? [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => WebItemEntryCard(
        med: med,
        srNo: itemToEdit != null ? itemToEdit.srNo : controller.items.length + 1,
        partyState: partyState,
        shopState: shopState,
        availableBatches: batches,
        existingItem: itemToEdit,
        onAdd: (newItem) {
          if (editIndex != null) {
            controller.updateItem(editIndex, newItem);
          } else {
            controller.addItem(newItem);
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
                      labelText: "SEARCH MEDICINE TO DISPATCH",
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
                      hintText: "Type medicine name (e.g. DOLO, PAN 40)...",
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF2DD4BF), size: 18),
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
                  border: Border.all(color: const Color(0x332DD4BF)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: matchingMeds.length,
                  itemBuilder: (ctx, idx) {
                    final med = matchingMeds[idx];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.medication_rounded, color: Color(0xFF2DD4BF), size: 18),
                      title: Text(med.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      subtitle: Text("Pack: ${med.packing} | MRP: ₹${med.mrp.toStringAsFixed(2)} | Stock: ${med.stock.toInt()}", style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
                      onTap: () {
                        controller.productSearchC.clear();
                        _openItemEntryDialog(context, med);
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
              const Icon(Icons.local_shipping_outlined, color: Color(0xFF2DD4BF), size: 18),
              const SizedBox(width: 8),
              Text(
                "DISPATCH ITEMS (${controller.items.length})",
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
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
                child: Text("Cart is empty. Search products above to add to delivery challan.", style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 700),
                child: Table(
                  columnWidths: const {
                    0: FixedColumnWidth(35),
                    1: FlexColumnWidth(3),
                    2: FixedColumnWidth(70),
                    3: FixedColumnWidth(80),
                    4: FixedColumnWidth(60),
                    5: FixedColumnWidth(70),
                    6: FixedColumnWidth(70),
                    7: FixedColumnWidth(85),
                    8: FixedColumnWidth(65),
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
                        _th("TOTAL"),
                        _th("ACT"),
                      ],
                    ),
                    ...controller.items.asMap().entries.map((entry) {
                      int idx = entry.key;
                      BillItem it = entry.value;
                      String qtyDisp = "${(it.qty % 1 == 0 ? it.qty.toInt().toString() : it.qty.toStringAsFixed(1))}${it.freeQty > 0 ? ' + ${(it.freeQty % 1 == 0 ? it.freeQty.toInt().toString() : it.freeQty.toStringAsFixed(1))}' : ''}";

                      return TableRow(
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                        children: [
                          _td("${idx + 1}"),
                          _td(it.name, isLeft: true, isBold: true),
                          _td(it.packing),
                          _td(it.batch),
                          _td(it.exp),
                          _td(qtyDisp, isBold: true, color: Colors.cyanAccent),
                          _td("₹${it.rate.toStringAsFixed(2)}"),
                          _td("₹${it.total.toStringAsFixed(2)}", isBold: true, color: Colors.greenAccent),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!controller.isReadOnly)
                                IconButton(
                                  icon: const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF38BDF8)),
                                  onPressed: () {
                                    final med = webPh.medicines.firstWhere(
                                      (m) => m.id == it.medicineID || m.name == it.name,
                                      orElse: () => Medicine(id: it.medicineID, name: it.name, packing: it.packing),
                                    );
                                    _openItemEntryDialog(context, med, itemToEdit: it, editIndex: idx);
                                  },
                                ),
                              if (!controller.isReadOnly)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                                  onPressed: () => controller.removeItem(idx),
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

  Widget _th(String t, {bool isLeft = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: TextStyle(color: color, fontSize: 10.5, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
  );
}
