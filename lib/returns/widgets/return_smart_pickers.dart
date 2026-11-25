// FILE: lib/returns/widgets/return_smart_pickers.dart
// Shared App Smart Pickers:
// 1) Batch-First Magic History BottomSheet with Invoice Drill-Down & Auto-Split Return (LIFO/FIFO)
// 2) Pull-From-Bill BottomSheet for Multi-Item Invoice Returns

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models.dart';
import '../../pharoah_manager.dart';
import '../../logic/return_history_engine.dart';

class AppPullBillPickedLine {
  final Medicine medicine;
  final ReturnHistoryInvoiceLine line;
  final double qty;

  const AppPullBillPickedLine({
    required this.medicine,
    required this.line,
    required this.qty,
  });
}

Future<void> showReturnBatchHistorySheet({
  required BuildContext context,
  required bool isSale,
  required Medicine medicine,
  required Party party,
  required PharoahManager ph,
  List<dynamic> currentCartItems = const [],
  String? excludeNoteId,
  required Function(Map<String, dynamic>? selectedHistory) onSelect,
  Function(List<ReturnAllocationItem> allocations, bool hasOverReturn)? onAutoSplit,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AppReturnBatchHistorySheet(
      isSale: isSale,
      medicine: medicine,
      party: party,
      ph: ph,
      currentCartItems: currentCartItems,
      excludeNoteId: excludeNoteId,
      onSelect: onSelect,
      onAutoSplit: onAutoSplit,
    ),
  );
}

Future<void> showPullFromBillSheet({
  required BuildContext context,
  required bool isSale,
  required Party party,
  required PharoahManager ph,
  List<dynamic> currentCartItems = const [],
  String? excludeNoteId,
  String? initialBillNo,
  required Function(List<AppPullBillPickedLine> picked) onAddSelected,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AppPullFromBillSheet(
      isSale: isSale,
      party: party,
      ph: ph,
      currentCartItems: currentCartItems,
      excludeNoteId: excludeNoteId,
      initialBillNo: initialBillNo,
      onAddSelected: onAddSelected,
    ),
  );
}

class _AppReturnBatchHistorySheet extends StatefulWidget {
  final bool isSale;
  final Medicine medicine;
  final Party party;
  final PharoahManager ph;
  final List<dynamic> currentCartItems;
  final String? excludeNoteId;
  final Function(Map<String, dynamic>? selectedHistory) onSelect;
  final Function(List<ReturnAllocationItem> allocations, bool hasOverReturn)? onAutoSplit;

  const _AppReturnBatchHistorySheet({
    required this.isSale,
    required this.medicine,
    required this.party,
    required this.ph,
    required this.currentCartItems,
    required this.excludeNoteId,
    required this.onSelect,
    required this.onAutoSplit,
  });

  @override
  State<_AppReturnBatchHistorySheet> createState() =>
      _AppReturnBatchHistorySheetState();
}

class _AppReturnBatchHistorySheetState extends State<_AppReturnBatchHistorySheet> {
  final TextEditingController _filterC = TextEditingController();
  final Map<String, TextEditingController> _splitQtyControllers = {};
  final Set<String> _expandedBatches = {};
  final Set<String> _quickSplitOpen = {};
  bool _onlyAvailable = false;
  bool _newestFirst = true;
  late List<ReturnBatchGroup> _groups;

  Color get _primary =>
      widget.isSale ? const Color(0xFFB71C1C) : const Color(0xFFB45309);
  Color get _tint =>
      widget.isSale ? Colors.red.shade50 : Colors.amber.shade50;

  @override
  void initState() {
    super.initState();
    _groups = ReturnHistoryEngine.buildBatchGroups(
      isSale: widget.isSale,
      partyId: widget.party.id,
      partyName: widget.party.name,
      medicineId: widget.medicine.id,
      medicineName: widget.medicine.name,
      sales: widget.ph.sales,
      purchases: widget.ph.purchases,
      saleReturns: widget.ph.saleReturns,
      purchaseReturns: widget.ph.purchaseReturns,
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
      return g.invoices.any((i) => i.billNo.toLowerCase().contains(q));
    }).toList();

    final double totalAvailAll =
        _groups.fold(0.0, (s, g) => s + g.netReturnableQty);

    return Container(
      height: MediaQuery.of(context).size.height * 0.84,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            height: 4,
            width: 48,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _tint,
                  child: Icon(Icons.layers_rounded, color: _primary, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isSale
                            ? "BATCH-GROUPED SALE HISTORY"
                            : "BATCH-GROUPED PURCHASE HISTORY",
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: _primary,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        "${widget.medicine.name} (${widget.medicine.packing})",
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_groups.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: totalAvailAll > 0
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: totalAvailAll > 0
                            ? Colors.green.shade300
                            : Colors.red.shade300,
                      ),
                    ),
                    child: Text(
                      "${_groups.length} Batches • Avail ${formatQty(totalAvailAll)}",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: totalAvailAll > 0
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                "${widget.isSale ? 'Customer' : 'Supplier'}: ${widget.party.name} • Tap a Batch to drill-down bills or Quick Auto-Split",
                style: const TextStyle(fontSize: 11, color: Colors.black54),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (_groups.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _filterC,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: "Filter batch or invoice no...",
                        prefixIcon: Icon(Icons.search_rounded, color: _primary, size: 17),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text("Avail > 0", style: TextStyle(fontSize: 10.5)),
                    selected: _onlyAvailable,
                    selectedColor: Colors.green.shade100,
                    onSelected: (v) => setState(() => _onlyAvailable = v),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_toggle_off_rounded,
                              size: 44, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(
                            _groups.isEmpty
                                ? "No past ${widget.isSale ? 'sale' : 'purchase'} records for this party.\nUse Manual Entry below."
                                : "No batches match your filter.",
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    itemCount: filtered.length,
                    itemBuilder: (c, idx) => _buildBatchCard(filtered[idx], q),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onSelect(null);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primary,
                    side: BorderSide(color: _primary, width: 1.3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.edit_document, size: 18),
                  label: const Text(
                    "NOT IN HISTORY? ENTER MANUALLY",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchCard(ReturnBatchGroup g, String searchQuery) {
    final bool isExpanded = _expandedBatches.contains(g.batchKey);
    final bool isSplitOpen = _quickSplitOpen.contains(g.batchKey);
    final bool hasAvail = g.netReturnableQty > 0.0001;

    final invList =
        searchQuery.isEmpty || g.batchDisplay.toLowerCase().contains(searchQuery)
            ? g.invoices
            : g.invoices.where((i) => i.billNo.toLowerCase().contains(searchQuery)).toList();

    final String rateStr = g.hasRateVariance
        ? "₹${g.minRate.toStringAsFixed(2)}–₹${g.maxRate.toStringAsFixed(2)}"
        : "₹${g.latestRate.toStringAsFixed(2)}";

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isExpanded
              ? _primary.withAlpha(140)
              : (hasAvail ? Colors.grey.shade200 : Colors.red.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
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
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _tint,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "BATCH: ${g.batchDisplay}",
                          style: TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: g.isExpired
                              ? Colors.red.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          g.isExpired
                              ? "EXP ${g.exp} (EXP)"
                              : "Exp: ${g.exp.isNotEmpty ? g.exp : 'N/A'}",
                          style: TextStyle(
                            color: g.isExpired ? Colors.red.shade800 : Colors.black54,
                            fontWeight: FontWeight.bold,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "${g.billCount} Bills",
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.w900,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        rateStr,
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _statChip("Billed", formatQty(g.totalBilledQty), Colors.black87,
                          Colors.grey.shade100),
                      const SizedBox(width: 6),
                      _statChip("Ret", formatQty(g.totalReturnedQty),
                          Colors.orange.shade900, Colors.orange.shade50),
                      const SizedBox(width: 6),
                      _statChip(
                        "Avail",
                        formatQty(g.netReturnableQty),
                        hasAvail ? Colors.green.shade900 : Colors.red.shade800,
                        hasAvail ? Colors.green.shade50 : Colors.red.shade50,
                      ),
                      const Spacer(),
                      if (widget.onAutoSplit != null)
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (isSplitOpen) {
                                _quickSplitOpen.remove(g.batchKey);
                              } else {
                                _quickSplitOpen.add(g.batchKey);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: _tint,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _primary.withAlpha(80)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bolt_rounded, size: 13, color: _primary),
                                const SizedBox(width: 3),
                                Text("SPLIT",
                                    style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        color: _primary)),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isSplitOpen && widget.onAutoSplit != null)
            _buildQuickSplitBox(g),
          if (isExpanded)
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "BILLS IN THIS BATCH (${invList.length}) — TAP TO PICK",
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: invList.length,
                      itemBuilder: (c, i) {
                        final ln = invList[i];
                        final bool avail = ln.availableQty > 0.0001;
                        return InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSelect(ln.toHistoryMap());
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: avail
                                    ? Colors.grey.shade200
                                    : Colors.red.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    ln.billNo,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo.shade900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "${DateFormat('dd/MM/yy').format(ln.date)} • Billed ${formatQty(ln.billedQty)}${ln.billedFreeQty > 0 ? '+${formatQty(ln.billedFreeQty)}F' : ''}",
                                        style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        "Ret: ${formatQty(ln.alreadyReturnedQty)} • Avail: ${formatQty(ln.availableQty)}${ln.effectiveDiscPer > 0 ? ' • Disc ${ln.effectiveDiscPer.toStringAsFixed(1)}%' : ''}",
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: avail
                                              ? Colors.green.shade700
                                              : Colors.red.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  "₹${ln.rate.toStringAsFixed(2)}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickSplitBox(ReturnBatchGroup g) {
    final qtyC = _qtyControllerFor(g);
    final req = double.tryParse(qtyC.text) ?? 0.0;
    final alloc = ReturnHistoryEngine.allocateReturnQty(
      group: g,
      requestedQty: req,
      newestFirst: _newestFirst,
    );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _tint.withAlpha(110),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "AUTO-SPLIT RETURN QTY",
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900, color: _primary),
              ),
              const Spacer(),
              ChoiceChip(
                label: const Text("LIFO", style: TextStyle(fontSize: 9.5)),
                selected: _newestFirst,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _newestFirst = true),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text("FIFO", style: TextStyle(fontSize: 9.5)),
                selected: !_newestFirst,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _newestFirst = false),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 90,
                height: 36,
                child: TextField(
                  controller: qtyC,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: "Qty",
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alloc.allocations.isEmpty
                          ? "Enter qty > 0"
                          : "${alloc.allocations.length} bill(s): " +
                              alloc.allocations
                                  .take(3)
                                  .map((a) =>
                                      "${a.line.billNo}(${formatQty(a.allocatedQty)})")
                                  .join(", "),
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (alloc.hasOverReturn)
                      Text(
                        "Exceeds Avail (${formatQty(alloc.netReturnable)})!",
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: alloc.allocations.isEmpty
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onAutoSplit!(
                            alloc.allocations, alloc.hasOverReturn);
                      },
                child: Text("ADD (${alloc.allocations.length})",
                    style: const TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String val, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        "$label: $val",
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _AppPullFromBillSheet extends StatefulWidget {
  final bool isSale;
  final Party party;
  final PharoahManager ph;
  final List<dynamic> currentCartItems;
  final String? excludeNoteId;
  final String? initialBillNo;
  final Function(List<AppPullBillPickedLine> picked) onAddSelected;

  const _AppPullFromBillSheet({
    required this.isSale,
    required this.party,
    required this.ph,
    required this.currentCartItems,
    required this.excludeNoteId,
    required this.initialBillNo,
    required this.onAddSelected,
  });

  @override
  State<_AppPullFromBillSheet> createState() => _AppPullFromBillSheetState();
}

class _AppPullFromBillSheetState extends State<_AppPullFromBillSheet> {
  final TextEditingController _searchC = TextEditingController();
  late List<ReturnRecentBill> _bills;
  ReturnRecentBill? _selectedBill;
  final Set<int> _checked = {};
  final Map<int, TextEditingController> _qtyC = {};

  Color get _primary =>
      widget.isSale ? const Color(0xFFB71C1C) : const Color(0xFFB45309);
  Color get _tint =>
      widget.isSale ? Colors.red.shade50 : Colors.amber.shade50;

  @override
  void initState() {
    super.initState();
    _bills = ReturnHistoryEngine.getRecentPartyBills(
      isSale: widget.isSale,
      partyId: widget.party.id,
      partyName: widget.party.name,
      sales: widget.ph.sales,
      purchases: widget.ph.purchases,
      saleReturns: widget.ph.saleReturns,
      purchaseReturns: widget.ph.purchaseReturns,
      currentCartItems: widget.currentCartItems,
      excludeNoteId: widget.excludeNoteId,
      limit: 25,
    );
    if (_bills.isNotEmpty) {
      if (widget.initialBillNo != null &&
          widget.initialBillNo!.trim().isNotEmpty) {
        final match = _bills.where((b) =>
            b.billNo.trim().toUpperCase() ==
            widget.initialBillNo!.trim().toUpperCase());
        _selectBill(match.isNotEmpty ? match.first : _bills.first);
      } else {
        _selectBill(_bills.first);
      }
    }
  }

  @override
  void dispose() {
    _searchC.dispose();
    for (final c in _qtyC.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectBill(ReturnRecentBill b) {
    for (final c in _qtyC.values) {
      c.dispose();
    }
    _qtyC.clear();
    _checked.clear();
    _selectedBill = b;
    for (int i = 0; i < b.lines.length; i++) {
      final ln = b.lines[i];
      final def = ln.availableQty > 0 ? ln.availableQty : ln.billedQty;
      _qtyC[i] = TextEditingController(text: formatQty(def));
      if (ln.availableQty > 0) _checked.add(i);
    }
    setState(() {});
  }

  Medicine _resolveMed(ReturnRecentBillLine line) {
    return widget.ph.medicines.firstWhere(
      (m) =>
          (line.medicineID.isNotEmpty && m.id == line.medicineID) ||
          m.name.trim().toUpperCase() == line.name.trim().toUpperCase(),
      orElse: () => Medicine(
        id: line.medicineID,
        name: line.name,
        packing: line.packing,
        mrp: line.mrp,
        gst: line.gstRate,
        hsnCode: line.hsn,
        rateA: line.rate,
        purRate: line.rate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchC.text.trim().toLowerCase();
    final filteredBills = q.isEmpty
        ? _bills
        : _bills
            .where((b) =>
                b.billNo.toLowerCase().contains(q) ||
                b.lines.any((l) =>
                    l.name.toLowerCase().contains(q) ||
                    l.batch.toLowerCase().contains(q)))
            .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            height: 4,
            width: 48,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _tint,
                  child: Icon(Icons.receipt_long_rounded,
                      color: _primary, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "PULL ITEMS FROM ${widget.isSale ? 'SALE' : 'PURCHASE'} BILL",
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: _primary,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        widget.party.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w900),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (_bills.isEmpty)
            const Expanded(
              child: Center(
                child: Text("No recent bills found for this party.",
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: _searchC,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: "Search bill no, medicine, or batch...",
                  prefixIcon:
                      Icon(Icons.search_rounded, color: _primary, size: 17),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SizedBox(
              height: 54,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: filteredBills.length,
                itemBuilder: (c, idx) {
                  final b = filteredBills[idx];
                  final isSel = _selectedBill?.billNo == b.billNo &&
                      _selectedBill?.date == b.date;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                    child: ChoiceChip(
                      selected: isSel,
                      selectedColor: _primary,
                      backgroundColor: Colors.white,
                      label: Text(
                        "${b.billNo} (${DateFormat('dd/MM').format(b.date)}) • ₹${b.totalAmount.toStringAsFixed(0)}",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSel ? Colors.white : Colors.black87,
                        ),
                      ),
                      onSelected: (_) => _selectBill(b),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 10),
            if (_selectedBill != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      "BILL ${_selectedBill!.billNo} • ${_selectedBill!.lines.length} ITEMS",
                      style: const TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _checked.clear();
                          for (int i = 0; i < _selectedBill!.lines.length; i++) {
                            if (_selectedBill!.lines[i].availableQty > 0) {
                              _checked.add(i);
                            }
                          }
                        });
                      },
                      child: const Text("Select All Avail",
                          style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _selectedBill!.lines.length,
                  itemBuilder: (c, idx) {
                    final ln = _selectedBill!.lines[idx];
                    final checked = _checked.contains(idx);
                    final ctrl = _qtyC[idx]!;
                    final typed = double.tryParse(ctrl.text) ?? 0.0;
                    final over = typed > ln.availableQty + 0.0001;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: checked
                              ? _primary.withAlpha(140)
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            Checkbox(
                              value: checked,
                              activeColor: _primary,
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _checked.add(idx);
                                } else {
                                  _checked.remove(idx);
                                }
                              }),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ln.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5)),
                                  Text(
                                    "Batch: ${ln.batch} • Exp: ${ln.exp} • Rate: ₹${ln.rate.toStringAsFixed(2)}${ln.discountPer > 0 ? ' (-${ln.discountPer.toStringAsFixed(1)}%)' : ''}",
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.black54),
                                  ),
                                  Text(
                                    "Billed: ${formatQty(ln.billedQty)} • Ret: ${formatQty(ln.alreadyReturnedQty)} • Avail: ${formatQty(ln.availableQty)}",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: ln.availableQty > 0
                                          ? Colors.green.shade700
                                          : Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 72,
                              height: 36,
                              child: TextField(
                                controller: ctrl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: over
                                      ? Colors.orange.shade900
                                      : Colors.black,
                                ),
                                decoration: InputDecoration(
                                  labelText: "Qty",
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 6),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onChanged: (_) => setState(() {
                                  _checked.add(idx);
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _checked.isEmpty
                          ? null
                          : () {
                              final out = <AppPullBillPickedLine>[];
                              for (final i in (_checked.toList()..sort())) {
                                final ln = _selectedBill!.lines[i];
                                final qty =
                                    double.tryParse(_qtyC[i]?.text ?? "0") ??
                                        0.0;
                                if (qty <= 0) continue;
                                out.add(AppPullBillPickedLine(
                                  medicine: _resolveMed(ln),
                                  line: ln.toInvoiceLine(),
                                  qty: qty,
                                ));
                              }
                              if (out.isEmpty) return;
                              Navigator.pop(context);
                              widget.onAddSelected(out);
                            },
                      icon: const Icon(Icons.playlist_add_check_rounded),
                      label: Text(
                        "ADD ${_checked.length} SELECTED ITEMS",
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
