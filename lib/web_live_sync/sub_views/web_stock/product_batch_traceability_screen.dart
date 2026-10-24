import 'dart:ui' show PointerDeviceKind;
// FILE: lib/web_live_sync/sub_views/web_stock/product_batch_traceability_screen.dart
// Live Revision: #PH-REV-745 (ADVANCED-STOCK-TRACEABILITY-AND-BATCH-LEDGER)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/web_models.dart';

import 'package:pharoah_erp/logic/batch_cascade_engine.dart';
import 'package:pharoah_erp/sync_core/modules/batch_sync_module.dart';
import 'package:pharoah_erp/app_date_logic.dart';
class ProductBatchTraceabilityScreen extends StatefulWidget {
  final Medicine medicine;
  final VoidCallback onBack;

  const ProductBatchTraceabilityScreen({
    super.key,
    required this.medicine,
    required this.onBack,
  });

  @override
  State<ProductBatchTraceabilityScreen> createState() => _ProductBatchTraceabilityScreenState();
}

class _ProductBatchTraceabilityScreenState extends State<ProductBatchTraceabilityScreen> {
  String selectedFilter = 'ALL'; // ALL, ACTIVE, EXPIRED, ZERO

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final medKey = widget.medicine.identityKey;
    final batches = webPh.batchHistory[medKey] ?? [];

    // Calculate valuation metrics
    double totalQty = batches.fold(0.0, (sum, b) => sum + b.qty);
    double totalPurVal = batches.fold(0.0, (sum, b) => sum + (b.qty * b.purRate));
    double totalMrpVal = batches.fold(0.0, (sum, b) => sum + (b.qty * b.mrp));

    // Filtered batches
    final filteredBatches = batches.where((b) {
      if (selectedFilter == 'ACTIVE') return b.qty > 0;
      if (selectedFilter == 'ZERO') return b.qty == 0;
      return true;
    }).toList();

    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          // 🏆 TOP HEADER BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  tooltip: "Back to Stock View",
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.inventory_2_rounded, color: Color(0xFF60A5FA), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.medicine.name,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.medicine.packing,
                              style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D9488).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.medicine.systemId,
                              style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Form: ${widget.medicine.drugForm} | HSN: ${widget.medicine.hsnCode} | GST: ${widget.medicine.gst}% | Rack: ${widget.medicine.rackNo.isNotEmpty ? widget.medicine.rackNo : 'N/A'}",
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _showAddBatchDialog(context, webPh, widget.medicine),
                  icon: const Icon(Icons.add_box_rounded, size: 16),
                  label: const Text("NEW BATCH", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
          ),

          // 📊 FINANCIAL VALUATION METRICS BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            color: const Color(0xFF1E293B).withOpacity(0.6),
            child: Row(
              children: [
                _metricCard("Total Stock Qty", "${totalQty.toInt()} Units", Icons.layers_rounded, const Color(0xFF3B82F6)),
                const SizedBox(width: 16),
                _metricCard("Purchase Valuation", "₹${totalPurVal.toStringAsFixed(2)}", Icons.account_balance_wallet_rounded, const Color(0xFF10B981)),
                const SizedBox(width: 16),
                _metricCard("MRP Valuation", "₹${totalMrpVal.toStringAsFixed(2)}", Icons.price_check_rounded, const Color(0xFFF59E0B)),
                const SizedBox(width: 16),
                _metricCard("Active Batches", "${batches.where((b) => b.qty > 0).length} / ${batches.length}", Icons.qr_code_rounded, const Color(0xFF8B5CF6)),
                const Spacer(),
                ToggleButtons(
                  isSelected: [selectedFilter == 'ALL', selectedFilter == 'ACTIVE', selectedFilter == 'ZERO'],
                  onPressed: (idx) {
                    setState(() {
                      if (idx == 0) selectedFilter = 'ALL';
                      else if (idx == 1) selectedFilter = 'ACTIVE';
                      else selectedFilter = 'ZERO';
                    });
                  },
                  color: Colors.white60,
                  selectedColor: Colors.white,
                  fillColor: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(minHeight: 32, minWidth: 70),
                  children: const [
                    Text("All", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    Text("Active > 0", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    Text("Zero Stock", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),

          // 📋 BATCH TABLE & MOVEMENT LEDGER
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: filteredBatches.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.white24),
                          const SizedBox(height: 12),
                          const Text(
                            "No batches found for this product.",
                            style: TextStyle(color: Colors.white54, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ScrollConfiguration(
                          behavior: const MaterialScrollBehavior().copyWith(
                            dragDevices: {
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.touch,
                              PointerDeviceKind.stylus,
                              PointerDeviceKind.trackpad,
                            },
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: DataTable(
                            headingRowColor: WidgetStateProperty.all(const Color(0xFF0F172A)),
                            dataRowMaxHeight: 55,
                            columns: const [
                              DataColumn(label: Text("BATCH NO", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                              DataColumn(label: Text("EXPIRY", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                              DataColumn(label: Text("CURRENT QTY", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                              DataColumn(label: Text("PUR. RATE ₹", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                              DataColumn(label: Text("MRP ₹", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                              DataColumn(label: Text("RATE A ₹", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                              DataColumn(label: Text("VALUATION ₹", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                              DataColumn(label: Text("STATUS", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                              DataColumn(label: Text("ACTIONS & TRAIL", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                            ],
                            rows: filteredBatches.map((b) {
                              bool isExpired = _checkExpired(b.exp);
                              return DataRow(
                                cells: [
                                  DataCell(Text(b.batch, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                  DataCell(Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isExpired ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      b.exp,
                                      style: TextStyle(color: isExpired ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  )),
                                  DataCell(Text("${b.qty.toInt()}", style: TextStyle(color: b.qty > 0 ? const Color(0xFF60A5FA) : Colors.white38, fontWeight: FontWeight.bold, fontSize: 13))),
                                  DataCell(Text("₹${b.purRate.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                  DataCell(Text("₹${b.mrp.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                                  DataCell(Text("₹${b.rateA.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                  DataCell(Text("₹${(b.qty * b.purRate).toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 12))),
                                  DataCell(Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: b.qty > 0 ? Colors.teal.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      b.qty > 0 ? "AVAILABLE" : "OUT OF STOCK",
                                      style: TextStyle(color: b.qty > 0 ? const Color(0xFF2DD4BF) : Colors.white54, fontWeight: FontWeight.bold, fontSize: 10),
                                    ),
                                  )),
                                  DataCell(
                                    Builder(builder: (c) {
                                      final activeFY = webPh.financialYear.isNotEmpty
                                          ? webPh.financialYear
                                          : AppDateLogic.getCurrentFYString();
                                      final lockingRecords = BatchCascadeEngine.checkActiveFYUsage(
                                        medicine: widget.medicine,
                                        batchNo: b.batch,
                                        activeFY: activeFY,
                                        sales: webPh.sales,
                                        purchases: webPh.purchases,
                                        saleChallans: webPh.saleChallans,
                                        purchaseChallans: webPh.purchaseChallans,
                                        saleReturns: webPh.saleReturns,
                                        purchaseReturns: webPh.purchaseReturns,
                                      );
                                      final bool isLockedByFY = lockingRecords.isNotEmpty;

                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // MODIFY BUTTON
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF2563EB),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            ),
                                            onPressed: () => _showCascadeEditDialog(context, webPh, widget.medicine, b),
                                            icon: const Icon(Icons.edit_note_rounded, size: 14),
                                            label: const Text("MODIFY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 6),

                                          // DELETE BUTTON
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: isLockedByFY ? const Color(0xFF7F1D1D) : const Color(0xFFDC2626),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            ),
                                            onPressed: () => _showDeleteBatchDialog(context, webPh, widget.medicine, b),
                                            icon: Icon(isLockedByFY ? Icons.lock_outline_rounded : Icons.delete_outline_rounded, size: 12),
                                            label: Text(isLockedByFY ? "LOCKED" : "DELETE", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 6),

                                          // TRAIL & LEDGER BUTTON
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(0xFF60A5FA),
                                              side: const BorderSide(color: Color(0xFF3B82F6)),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            onPressed: () {
                                              _showBatchMovementModal(context, webPh, widget.medicine, b);
                                            },
                                            icon: const Icon(Icons.timeline_rounded, size: 13),
                                            label: const Text("Trail & Ledger", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      );
                                    }),
                                  ),
                                ],
                              );
                            }).toList(),
                              ),
                            ),
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

  bool _checkExpired(String exp) {
    try {
      final parts = exp.split('/');
      if (parts.length != 2) return false;
      int m = int.parse(parts[0]);
      int y = int.parse(parts[1]);
      if (y < 100) y += 2000;
      final now = DateTime.now();
      final expDate = DateTime(y, m + 1, 0);
      return expDate.isBefore(now);
    } catch (_) {
      return false;
    }
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  void _showBatchMovementModal(BuildContext context, PharoahWebManager webPh, Medicine med, BatchInfo batch) {
    final matchingPurchases = webPh.purchases.where((p) => p.items.any((it) => it.name.trim().toUpperCase() == med.name.trim().toUpperCase() && it.batch.trim().toUpperCase() == batch.batch.trim().toUpperCase())).toList();
    final matchingSales = webPh.sales.where((s) => s.items.any((it) => it.name.trim().toUpperCase() == med.name.trim().toUpperCase() && it.batch.trim().toUpperCase() == batch.batch.trim().toUpperCase())).toList();

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white12)),
        title: Row(
          children: [
            const Icon(Icons.timeline_rounded, color: Color(0xFF38BDF8), size: 20),
            const SizedBox(width: 10),
            Text(
              "BATCH TRACEABILITY • ${batch.batch} (${med.name})",
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 650,
          height: 450,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _auditItem("Batch No", batch.batch),
                      _auditItem("Expiry", batch.exp),
                      _auditItem("Initial Qty", "${batch.qty.toInt()}"),
                      _auditItem("MRP", "₹${batch.mrp.toStringAsFixed(2)}"),
                      _auditItem("Pur. Rate", "₹${batch.purRate.toStringAsFixed(2)}"),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text("📥 INWARD PURCHASES (Source)", style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                matchingPurchases.isEmpty
                    ? const Padding(padding: EdgeInsets.all(8.0), child: Text("No direct purchase inward record found for this batch.", style: TextStyle(color: Colors.white54, fontSize: 11)))
                    : Column(
                        children: matchingPurchases.map((p) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              const Icon(Icons.shopping_bag_rounded, color: Color(0xFF34D399), size: 16),
                              const SizedBox(width: 10),
                              Text("Bill: ${p.billNo.isNotEmpty ? p.billNo : p.internalNo}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(width: 14),
                              Text("Party: ${p.distributorName}", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              const Spacer(),
                              Text("Date: ${p.date.toLocal().toString().split(' ')[0]}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        )).toList(),
                      ),
                const SizedBox(height: 16),
                const Text("📤 OUTWARD SALES (Consumption)", style: TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                matchingSales.isEmpty
                    ? const Padding(padding: EdgeInsets.all(8.0), child: Text("No sales recorded yet for this batch.", style: TextStyle(color: Colors.white54, fontSize: 11)))
                    : Column(
                        children: matchingSales.map((s) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              const Icon(Icons.receipt_long_rounded, color: Color(0xFFF87171), size: 16),
                              const SizedBox(width: 10),
                              Text("Invoice: ${s.billNo}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(width: 14),
                              Text("Party: ${s.partyName}", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              const Spacer(),
                              Text("Date: ${s.date.toLocal().toString().split(' ')[0]}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        )).toList(),
                      ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CLOSE", style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _auditItem(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }

  // ===========================================================================
  // 1. REGISTER NEW BATCH DIALOG (WITH D1 SYNC)
  // ===========================================================================
  void _showAddBatchDialog(BuildContext context, PharoahWebManager webPh, Medicine med) {
    final batchNoC = TextEditingController();
    final expC = TextEditingController();
    final mrpC = TextEditingController(text: med.mrp.toStringAsFixed(2));
    final purRateC = TextEditingController(text: med.purRate.toStringAsFixed(2));
    final rateAC = TextEditingController(text: med.rateA.toStringAsFixed(2));
    final rateBC = TextEditingController(text: med.rateB.toStringAsFixed(2));
    final rateCC = TextEditingController(text: med.rateC.toStringAsFixed(2));
    final openingQtyC = TextEditingController(text: "0");

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Row(
          children: [
            const Icon(Icons.add_box_rounded, color: Color(0xFF38BDF8), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "REGISTER NEW BATCH • ${med.name}",
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _inputField("BATCH NUMBER (CASE-SENSITIVE) *", batchNoC, isCaps: true),
                const SizedBox(height: 12),
                _inputField("EXPIRY (MM/YY) *", expC, isNum: true),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _inputField("MRP ₹", mrpC, isNum: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _inputField("PUR. RATE ₹", purRateC, isNum: true)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _inputField("RATE A ₹", rateAC, isNum: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField("RATE B ₹", rateBC, isNum: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField("RATE C ₹", rateCC, isNum: true)),
                  ],
                ),
                const SizedBox(height: 12),
                _inputField("INITIAL OPENING STOCK QTY", openingQtyC, isNum: true),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final bNo = batchNoC.text.trim();
              final exp = expC.text.trim();
              if (bNo.isEmpty || exp.isEmpty) return;

              final medKey = med.identityKey;
              if (!webPh.batchHistory.containsKey(medKey)) {
                webPh.batchHistory[medKey] = [];
              }

              bool exists = webPh.batchHistory[medKey]!.any((b) => b.batch.trim() == bNo);
              if (exists) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Batch '$bNo' already exists for ${med.name}"),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              double q = double.tryParse(openingQtyC.text) ?? 0.0;
              double pur = double.tryParse(purRateC.text) ?? 0.0;
              double m = double.tryParse(mrpC.text) ?? 0.0;
              double rA = double.tryParse(rateAC.text) ?? 0.0;
              double rB = double.tryParse(rateBC.text) ?? 0.0;
              double rC = double.tryParse(rateCC.text) ?? 0.0;

              final newBatch = BatchInfo(
                batch: bNo,
                exp: exp,
                qty: q,
                mrp: m,
                rate: pur,
                purRate: pur,
                rateA: rA,
                rateB: rB,
                rateC: rC,
                packing: med.packing,
                status: "Active",
                isShell: false,
              );

              webPh.addBatch(med, newBatch);
              Navigator.pop(c);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Batch '$bNo' registered & mirrored to cloud."),
                  backgroundColor: const Color(0xFF10B981),
                ),
              );
            },
            child: const Text("REGISTER & SYNC"),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. CASCADE RENAME & EDIT BATCH DIALOG
  // ===========================================================================
  void _showCascadeEditDialog(BuildContext context, PharoahWebManager webPh, Medicine med, BatchInfo b) {
    final oldBatchNo = b.batch;
    final batchNoC = TextEditingController(text: b.batch);
    final expC = TextEditingController(text: b.exp);
    final mrpC = TextEditingController(text: b.mrp.toStringAsFixed(2));
    final purRateC = TextEditingController(text: b.purRate.toStringAsFixed(2));
    final rateAC = TextEditingController(text: b.rateA.toStringAsFixed(2));
    final rateBC = TextEditingController(text: b.rateB.toStringAsFixed(2));
    final rateCC = TextEditingController(text: b.rateC.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: Color(0xFF60A5FA), size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "MODIFY BATCH • $oldBatchNo",
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "${med.name} • Cascade Rename & Rate Modification Engine",
                    style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF60A5FA).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF60A5FA).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.info_outline, color: Color(0xFF60A5FA), size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Renaming or modifying this batch will cascade across all historical Sales, Purchases, Challans, and Returns, recalculating live stock automatically.",
                          style: TextStyle(color: Color(0xFFBAE6FD), fontSize: 11, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _inputField("BATCH NUMBER (RENAME)", batchNoC, isCaps: true),
                const SizedBox(height: 12),
                _inputField("EXPIRY (MM/YY)", expC, isNum: true),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _inputField("MRP ₹", mrpC, isNum: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _inputField("PUR. RATE ₹", purRateC, isNum: true)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _inputField("RATE A ₹", rateAC, isNum: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField("RATE B ₹", rateBC, isNum: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField("RATE C ₹", rateCC, isNum: true)),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.done_all_rounded, size: 16),
            label: const Text("SAVE & CASCADE MODIFY", style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final newBatchNo = batchNoC.text.trim();
              final newExp = expC.text.trim();
              if (newBatchNo.isEmpty || newExp.isEmpty) return;

              final double newMrp = double.tryParse(mrpC.text) ?? b.mrp;
              final double newPur = double.tryParse(purRateC.text) ?? b.purRate;
              final double newRa = double.tryParse(rateAC.text) ?? b.rateA;
              final double newRb = double.tryParse(rateBC.text) ?? b.rateB;
              final double newRc = double.tryParse(rateCC.text) ?? b.rateC;

              final mutatedCount = webPh.updateBatchCascade(
                med: med,
                oldBatchNo: oldBatchNo,
                newBatchNo: newBatchNo,
                newExp: newExp,
                newMrp: newMrp,
                newPurRate: newPur,
                newRateA: newRa,
                newRateB: newRb,
                newRateC: newRc,
              );
              Navigator.pop(c);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Modified batch '$oldBatchNo' -> '$newBatchNo' across $mutatedCount voucher item(s)."),
                  backgroundColor: const Color(0xFF10B981),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. SAFE BATCH DELETION WITH FINANCIAL YEAR GUARD
  // ===========================================================================
  void _showDeleteBatchDialog(BuildContext context, PharoahWebManager webPh, Medicine med, BatchInfo b) {
    final activeFY = webPh.financialYear.isNotEmpty
        ? webPh.financialYear
        : AppDateLogic.getCurrentFYString();

    final lockingRecords = BatchCascadeEngine.checkActiveFYUsage(
      medicine: med,
      batchNo: b.batch,
      activeFY: activeFY,
      sales: webPh.sales,
      purchases: webPh.purchases,
      saleChallans: webPh.saleChallans,
      purchaseChallans: webPh.purchaseChallans,
      saleReturns: webPh.saleReturns,
      purchaseReturns: webPh.purchaseReturns,
    );

    if (lockingRecords.isNotEmpty) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.lock_rounded, color: Color(0xFFEF4444), size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "DELETION LOCKED • ACTIVE FY $activeFY",
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Batch '${b.batch}' cannot be deleted because it is recorded in ${lockingRecords.length} active transaction(s) in Financial Year $activeFY.",
                  style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  "AUDIT LOCK BREAKDOWN:",
                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 240),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: lockingRecords.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (_, i) {
                      final rec = lockingRecords[i];
                      return ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            rec.documentType,
                            style: const TextStyle(color: Color(0xFFF87171), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          "Bill #${rec.billNo} • ${rec.partyName}",
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "Date: ${AppDateLogic.format(rec.date)} | Qty: ${rec.qty.toInt()} | Rate: ₹${rec.rate.toStringAsFixed(2)}",
                          style: const TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(c),
              child: const Text("ACKNOWLEDGE & CLOSE"),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Text(
              "DELETE BATCH • ${b.batch}",
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Zero transactions found for batch '${b.batch}' in active Financial Year $activeFY.",
                style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Are you sure you want to permanently delete this batch? A persistent tombstone will be recorded to prevent cloud resurrection.",
                style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text("PERMANENTLY DELETE BATCH", style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              final result = webPh.deleteBatchSafe(
                med: med,
                batchNo: b.batch,
                activeFY: activeFY,
              );
              Navigator.pop(c);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.message),
                  backgroundColor: result.success ? const Color(0xFF10B981) : Colors.redAccent,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _inputField(String label, TextEditingController c, {bool isNum = false, bool isCaps = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black26,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

}
