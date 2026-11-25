// FILE: lib/web_live_sync/sub_views/web_returns/shared/web_return_batch_history_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../web_models.dart';
import '../../../pharoah_web_manager.dart';
import '../../../../logic/return_history_engine.dart';

class WebReturnBatchHistoryDialog extends StatefulWidget {
  final bool isSale;
  final Medicine medicine;
  final Party party;
  final PharoahWebManager webPh;
  final List<dynamic> currentCartItems;
  final String? excludeNoteId;
  final Function(Map<String, dynamic>? selectedHistory) onSelect;
  final Function(List<ReturnAllocationItem> allocations, bool hasOverReturn)? onAutoSplit;

  const WebReturnBatchHistoryDialog({
    super.key,
    required this.isSale,
    required this.medicine,
    required this.party,
    required this.webPh,
    this.currentCartItems = const [],
    this.excludeNoteId,
    required this.onSelect,
    this.onAutoSplit,
  });

  @override
  State<WebReturnBatchHistoryDialog> createState() =>
      _WebReturnBatchHistoryDialogState();
}

class _WebReturnBatchHistoryDialogState extends State<WebReturnBatchHistoryDialog> {
  final TextEditingController _filterC = TextEditingController();
  final Map<String, TextEditingController> _splitQtyControllers = {};
  final Set<String> _expandedBatches = {};
  final Set<String> _quickSplitOpen = {};
  bool _onlyAvailable = false;
  bool _newestFirst = true;
  late List<ReturnBatchGroup> _groups;

  Color get _accent =>
      widget.isSale ? const Color(0xFFF87171) : const Color(0xFFFBBF24);
  Color get _accentBg =>
      widget.isSale ? const Color(0x33EF4444) : const Color(0x33F59E0B);
  Color get _primaryBtn =>
      widget.isSale ? const Color(0xFFDC2626) : const Color(0xFFD97706);

  @override
  void initState() {
    super.initState();
    _groups = ReturnHistoryEngine.buildBatchGroups(
      isSale: widget.isSale,
      partyId: widget.party.id,
      partyName: widget.party.name,
      medicineId: widget.medicine.id,
      medicineName: widget.medicine.name,
      sales: widget.webPh.sales,
      purchases: widget.webPh.purchases,
      saleReturns: widget.webPh.saleReturns,
      purchaseReturns: widget.webPh.purchaseReturns,
      currentCartItems: widget.currentCartItems,
      excludeNoteId: widget.excludeNoteId,
    );
    if (_groups.length == 1) {
      _expandedBatches.add(_groups.first.batchKey);
      if (widget.onAutoSplit != null && _groups.first.billCount > 1) {
        _quickSplitOpen.add(_groups.first.batchKey);
      }
    }
  }

  @override
  void dispose() {
    _filterC.dispose();
    for (final c in _splitQtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _qtyControllerFor(ReturnBatchGroup g) {
    return _splitQtyControllers.putIfAbsent(g.batchKey, () {
      final def = g.netReturnableQty > 0
          ? formatQty(g.netReturnableQty)
          : formatQty(g.totalBilledQty);
      return TextEditingController(text: def);
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _filterC.text.trim().toLowerCase();
    final filtered = _groups.where((g) {
      if (_onlyAvailable && g.netReturnableQty <= 0.0001) return false;
      if (q.isEmpty) return true;
      if (g.batchDisplay.toLowerCase().contains(q)) return true;
      return g.invoices.any((inv) => inv.billNo.toLowerCase().contains(q));
    }).toList();

    final double totalAvailAll =
        _groups.fold(0.0, (sum, g) => sum + g.netReturnableQty);

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.white12),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 14, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: _accentBg, shape: BoxShape.circle),
            child: Icon(Icons.layers_rounded, color: _accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isSale
                      ? "BATCH-GROUPED SALE HISTORY"
                      : "BATCH-GROUPED INWARD PURCHASE HISTORY",
                  style: TextStyle(
                    color: _accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "${widget.medicine.name} (${widget.medicine.packing})",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_groups.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: totalAvailAll > 0
                    ? const Color(0x2210B981)
                    : const Color(0x22EF4444),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: totalAvailAll > 0
                      ? const Color(0x5510B981)
                      : const Color(0x55EF4444),
                ),
              ),
              child: Text(
                "${_groups.length} Batches • Avail: ${formatQty(totalAvailAll)}",
                style: TextStyle(
                  color: totalAvailAll > 0 ? Colors.greenAccent : _accent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isSale ? Icons.person_pin_rounded : Icons.business_rounded,
                    color: const Color(0xFF38BDF8),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "${widget.isSale ? 'Customer' : 'Supplier'}: ${widget.party.name} • Pick any batch to drill down into bills or Quick Auto-Split Qty",
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_groups.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _filterC,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: "Filter by Batch No or Invoice No...",
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                          prefixIcon: Icon(Icons.search_rounded, color: _accent, size: 16),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilterChip(
                    selected: _onlyAvailable,
                    label: const Text(
                      "Available > 0",
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                    selectedColor: const Color(0x3310B981),
                    backgroundColor: const Color(0xFF0F172A),
                    labelStyle: TextStyle(
                      color: _onlyAvailable ? Colors.greenAccent : Colors.white60,
                    ),
                    side: BorderSide(
                      color: _onlyAvailable ? Colors.greenAccent : Colors.white12,
                    ),
                    onSelected: (v) => setState(() => _onlyAvailable = v),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.history_toggle_off_rounded,
                            size: 42,
                            color: Colors.white.withAlpha(55),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _groups.isEmpty
                                ? "No past ${widget.isSale ? 'sale' : 'purchase'} records found for this party & medicine.\nUse Manual Entry below."
                                : "No batches match current filter.",
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, idx) => _buildBatchCard(filtered[idx], q),
                    ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onSelect(null);
                },
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text(
                  "NOT IN HISTORY? ENTER RETURN MANUALLY",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchCard(ReturnBatchGroup g, String searchQuery) {
    final bool isExpanded = _expandedBatches.contains(g.batchKey);
    final bool isSplitOpen = _quickSplitOpen.contains(g.batchKey);
    final bool hasAvail = g.netReturnableQty > 0.0001;

    final invList = searchQuery.isEmpty || g.batchDisplay.toLowerCase().contains(searchQuery)
        ? g.invoices
        : g.invoices.where((i) => i.billNo.toLowerCase().contains(searchQuery)).toList();

    final String rateText = g.hasRateVariance
        ? "₹${g.minRate.toStringAsFixed(2)} – ₹${g.maxRate.toStringAsFixed(2)}"
        : "₹${g.latestRate.toStringAsFixed(2)}";

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpanded
              ? _accent.withAlpha(140)
              : (hasAvail ? Colors.white12 : Colors.redAccent.withAlpha(60)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedBatches.remove(g.batchKey);
                } else {
                  _expandedBatches.add(g.batchKey);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: _accentBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "BATCH: ${g.batchDisplay}",
                          style: TextStyle(
                            color: _accent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: g.isExpired
                              ? const Color(0x33EF4444)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          g.isExpired
                              ? "EXP: ${g.exp} (EXPIRED)"
                              : "EXP: ${g.exp.isNotEmpty ? g.exp : 'N/A'}",
                          style: TextStyle(
                            color: g.isExpired ? Colors.redAccent : Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x2238BDF8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "${g.billCount} ${g.billCount == 1 ? 'Bill' : 'Bills'}",
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            rateText,
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            "MRP ₹${g.latestMrp.toStringAsFixed(2)} • Disc ${g.latestDiscPer.toStringAsFixed(1)}% • GST ${g.latestGstRate.toInt()}%",
                            style: const TextStyle(color: Colors.white54, fontSize: 9.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _statPill(
                        widget.isSale ? "Sold" : "Inward",
                        "${formatQty(g.totalBilledQty)}${g.totalBilledFreeQty > 0 ? ' + ${formatQty(g.totalBilledFreeQty)}F' : ''}",
                        Colors.white70,
                        Colors.white10,
                      ),
                      const SizedBox(width: 8),
                      _statPill(
                        "Returned",
                        formatQty(g.totalReturnedQty),
                        g.totalReturnedQty > 0 ? Colors.orangeAccent : Colors.white38,
                        g.totalReturnedQty > 0 ? const Color(0x22F59E0B) : Colors.white10,
                      ),
                      const SizedBox(width: 8),
                      _statPill(
                        "Returnable",
                        formatQty(g.netReturnableQty),
                        hasAvail ? Colors.greenAccent : Colors.redAccent,
                        hasAvail ? const Color(0x2210B981) : const Color(0x22EF4444),
                      ),
                      const Spacer(),
                      if (widget.onAutoSplit != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: _accent,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            backgroundColor: _accentBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              if (isSplitOpen) {
                                _quickSplitOpen.remove(g.batchKey);
                              } else {
                                _quickSplitOpen.add(g.batchKey);
                              }
                            });
                          },
                          icon: const Icon(Icons.bolt_rounded, size: 15),
                          label: const Text(
                            "QUICK SPLIT",
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
                          ),
                        ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedBatches.remove(g.batchKey);
                            } else {
                              _expandedBatches.add(g.batchKey);
                            }
                          });
                        },
                        icon: Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 16,
                        ),
                        label: Text(
                          isExpanded ? "HIDE BILLS" : "BILLS (${g.billCount})",
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isSplitOpen && widget.onAutoSplit != null)
            _buildQuickSplitBar(g),
          if (isExpanded)
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0B1222),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        "INVOICES IN THIS BATCH (TAP ANY BILL TO EDIT & ADD)",
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "Showing ${invList.length} of ${g.billCount}",
                        style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: invList.length,
                      itemBuilder: (c, i) => _buildInvoiceRow(invList[i]),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickSplitBar(ReturnBatchGroup g) {
    final qtyC = _qtyControllerFor(g);
    final double req = double.tryParse(qtyC.text) ?? 0.0;
    final alloc = ReturnHistoryEngine.allocateReturnQty(
      group: g,
      requestedQty: req,
      newestFirst: _newestFirst,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: _accentBg.withAlpha(40),
        border: const Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: _accent, size: 15),
              const SizedBox(width: 6),
              const Text(
                "AUTO-SPLIT RETURN ACROSS BILLS:",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              ChoiceChip(
                label: const Text("LIFO (Latest)", style: TextStyle(fontSize: 10)),
                selected: _newestFirst,
                onSelected: (_) => setState(() => _newestFirst = true),
                visualDensity: VisualDensity.compact,
                selectedColor: _primaryBtn,
                backgroundColor: const Color(0xFF0F172A),
                labelStyle: const TextStyle(color: Colors.white),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text("FIFO (Oldest)", style: TextStyle(fontSize: 10)),
                selected: !_newestFirst,
                onSelected: (_) => setState(() => _newestFirst = false),
                visualDensity: VisualDensity.compact,
                selectedColor: _primaryBtn,
                backgroundColor: const Color(0xFF0F172A),
                labelStyle: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 36,
                child: TextField(
                  controller: qtyC,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: "Return Qty",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (alloc.allocations.isEmpty)
                      const Text(
                        "Enter quantity > 0 to preview invoice allocation",
                        style: TextStyle(color: Colors.white38, fontSize: 10.5),
                      )
                    else
                      Text(
                        "Splits across ${alloc.allocations.length} bill(s): " +
                            alloc.allocations
                                .take(4)
                                .map((a) => "${a.line.billNo} (${formatQty(a.allocatedQty)})")
                                .join(", ") +
                            (alloc.allocations.length > 4 ? " +more" : ""),
                        style: const TextStyle(
                          color: Color(0xFF93C5FD),
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (alloc.hasOverReturn)
                      Text(
                        "Warning: Requested (${formatQty(req)}) exceeds Returnable (${formatQty(alloc.netReturnable)})!",
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryBtn,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: alloc.allocations.isEmpty
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onAutoSplit!(alloc.allocations, alloc.hasOverReturn);
                      },
                icon: const Icon(Icons.add_task_rounded, size: 16),
                label: Text(
                  "ADD (${alloc.allocations.length})",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceRow(ReturnHistoryInvoiceLine line) {
    final bool avail = line.availableQty > 0.0001;
    final dateStr = DateFormat('dd/MM/yyyy').format(line.date);
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        widget.onSelect(line.toHistoryMap());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: avail ? Colors.white10 : Colors.redAccent.withAlpha(50),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x332563EB),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                line.billNo,
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(dateStr, style: const TextStyle(color: Colors.white60, fontSize: 10.5)),
            const SizedBox(width: 12),
            Text(
              "Billed: ${formatQty(line.billedQty)}${line.billedFreeQty > 0 ? '+${formatQty(line.billedFreeQty)}F' : ''}",
              style: const TextStyle(color: Colors.white70, fontSize: 10.5),
            ),
            const SizedBox(width: 10),
            Text(
              "Ret: ${formatQty(line.alreadyReturnedQty)}",
              style: TextStyle(
                color: line.alreadyReturnedQty > 0 ? Colors.orangeAccent : Colors.white38,
                fontSize: 10.5,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: avail ? const Color(0x2210B981) : const Color(0x22EF4444),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "Avail: ${formatQty(line.availableQty)}",
                style: TextStyle(
                  color: avail ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Spacer(),
            Text(
              "₹${line.rate.toStringAsFixed(2)}",
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
              ),
            ),
            if (line.effectiveDiscPer > 0) ...[
              const SizedBox(width: 6),
              Text(
                "-${line.effectiveDiscPer.toStringAsFixed(1)}%",
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
            const SizedBox(width: 8),
            Icon(Icons.touch_app_rounded, color: _accent, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _statPill(String label, String value, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$label: ", style: const TextStyle(color: Colors.white54, fontSize: 10)),
          Text(
            value,
            style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
