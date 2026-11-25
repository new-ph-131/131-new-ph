// FILE: lib/web_live_sync/sub_views/web_returns/credit_note/ui/credit_note_cart_widget.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/credit_note_controller.dart';
import 'credit_note_magic_history_modal.dart';
import '../../shared/web_pull_from_bill_modal.dart';
import '../../../web_billing/web_item_entry_card.dart';
import '../../../web_billing/quick_add_product_modal.dart';
import '../../../../../logic/return_history_engine.dart';

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
        const SnackBar(
          content: Text("Please select a Customer first!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (c) => CreditNoteMagicHistoryModal(
        medicine: med,
        customer: controller.selectedCustomer!,
        webPh: webPh,
        currentCartItems: controller.items,
        excludeNoteId: controller.existingRecordId,
        onSelect: (selectedHistory) {
          _openItemEntryDialog(context, med, historyData: selectedHistory);
        },
        onAutoSplit: (allocations, hasOverReturn) {
          final List<BillItem> batchLines = [];
          int nextSr = controller.items.length + 1;
          for (final a in allocations) {
            batchLines.add(ReturnHistoryEngine.buildBillItemFromLine(
              med: med,
              line: a.line,
              qty: a.allocatedQty,
              srNo: nextSr++,
              isLocal: controller.isLocal,
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
                    : "Added ${batchLines.length} auto-split line(s) from batch history.",
              ),
              backgroundColor:
                  hasOverReturn ? Colors.orange.shade800 : const Color(0xFF0F766E),
            ),
          );
        },
      ),
    );
  }

  void _openPullFromBillModal(BuildContext context, {String? initialBillNo}) {
    if (controller.isReadOnly) return;
    if (controller.selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a Customer first!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (c) => WebPullFromBillModal(
        isSale: true,
        party: controller.selectedCustomer!,
        webPh: webPh,
        currentCartItems: controller.items,
        excludeNoteId: controller.existingRecordId,
        initialBillNo: initialBillNo,
        onAddSelected: (picked) {
          final List<BillItem> newLines = [];
          int nextSr = controller.items.length + 1;
          for (final p in picked) {
            newLines.add(ReturnHistoryEngine.buildBillItemFromLine(
              med: p.medicine,
              line: p.line,
              qty: p.qty,
              srNo: nextSr++,
              isLocal: controller.isLocal,
              isBreakage: controller.isBreakageMode,
              isCommercial: controller.isCommercial,
            ));
          }
          controller.addItemsBatch(newLines, webPh: webPh);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Pulled ${newLines.length} item(s) from invoice."),
              backgroundColor: const Color(0xFF0F766E),
            ),
          );
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
    List<BatchInfo> batches = webPh.getBatchesForMedicine(med);

    final String histBillNo = (historyData?['billNo'] ?? '').toString().trim();
    final DateTime? histDate =
        historyData?['date'] is DateTime ? historyData!['date'] as DateTime : null;
    final bool isManualNew = itemToEdit == null && historyData == null;

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
        origBillNo: histBillNo,
        origBillDate: histDate,
        isManualOrigin: histBillNo.isEmpty,
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
          final finalizedItem = itemToEdit != null
              ? newItem.copyWith(
                  isBreakage: itemToEdit.isBreakage,
                  origBillNo: itemToEdit.origBillNo,
                  origBillDate: itemToEdit.origBillDate,
                  isManualOrigin: itemToEdit.isManualOrigin,
                )
              : newItem.copyWith(
                  isBreakage: controller.isBreakageMode,
                  origBillNo: isManualNew ? "" : histBillNo,
                  origBillDate: isManualNew ? null : histDate,
                  clearOrigBillDate: isManualNew,
                  isManualOrigin: isManualNew || histBillNo.isEmpty,
                );
          if (editIndex != null) {
            controller.updateItem(editIndex, finalizedItem, webPh: webPh);
          } else {
            controller.addItem(finalizedItem, webPh: webPh);
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
    final recentBills = controller.getRecentBills(webPh, limit: 12);

    // Build direct Product matches (name, salt/uniqueCode, or active batch in stock/history)
    final matchingMeds = query.isEmpty
        ? <Medicine>[]
        : webPh.medicines.where((m) {
            if (m.name.toLowerCase().contains(query) ||
                m.uniqueCode.toLowerCase().contains(query)) return true;
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

    // Detect duplicates on origBillNo+batch+med inside current cart
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
                      labelText: "SMART RETURN LOOKUP (PRODUCT / BATCH / BILL NO)",
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                      hintText:
                          "Type medicine name, batch no, or bill no (opens Batch-Grouped History)...",
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Color(0xFFF87171), size: 18),
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
                constraints: const EdgeInsets.symmetric(horizontal: 0, vertical: 0)
                    .copyWith(maxHeight: 220),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x44EF4444)),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (matchingBills.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Text(
                          "MATCHING PARTY BILLS (PULL MULTI-ITEMS)",
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
                          "MEDICINES (BATCH-GROUPED HISTORY)",
                          style: TextStyle(
                              color: Color(0xFFF87171),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                      ...matchingMeds.map((med) => ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: const Icon(Icons.medication_rounded,
                                color: Color(0xFFF87171), size: 18),
                            title: Text(med.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                            subtitle: Text(
                              "Pack: ${med.packing} • MRP: ₹${med.mrp.toStringAsFixed(2)} • Stock: ${formatQty(med.stock)}",
                              style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                            ),
                            trailing: const Icon(Icons.layers_rounded,
                                color: Color(0xFFF87171), size: 16),
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
                    "RECENT BILLS:",
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
                              side: const BorderSide(color: Color(0x4438BDF8)),
                              avatar: const Icon(Icons.receipt_outlined,
                                  color: Color(0xFF38BDF8), size: 13),
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
              const Icon(Icons.assignment_return_rounded,
                  color: Color(0xFFF87171), size: 17),
              const SizedBox(width: 8),
              Text(
                "RETURN CART (${controller.items.length} ITEMS)",
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
                      "Return cart is empty. Search Medicine / Batch / Bill above or click PULL BILL to import items from a past sale invoice.",
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
                              _colHead("RATE / D%", width: 78, isRight: true),
                              _colHead("GST%", width: 44, isRight: true),
                              _colHead("NET AMT", width: 80, isRight: true),
                              _colHead("ACT", width: 58),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...controller.items.asMap().entries.map((entry) {
                          int idx = entry.key;
                          BillItem it = entry.value;
                          bool isExp = it.isBreakage;
                          final dupKey =
                              "${it.origBillNo.trim().toUpperCase()}||${it.batch.trim().toUpperCase()}||${it.name.trim().toUpperCase()}";
                          final bool isDup =
                              it.origBillNo.trim().isNotEmpty && (dupCounts[dupKey] ?? 0) > 1;

                          return Dismissible(
                            key: ValueKey("CN_ITEM_${it.id}_$idx"),
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
                                              : const Color(0x3310B981),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isExp ? "EXP" : "RET",
                                          style: TextStyle(
                                            color: isExp
                                                ? const Color(0xFFF97316)
                                                : Colors.greenAccent,
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
                                                  color: Color(0xFF93C5FD),
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
                                              color: Colors.cyanAccent,
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
                                          "₹${it.rate.toStringAsFixed(2)}",
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
                                      color: const Color(0xFFF87171)),
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
