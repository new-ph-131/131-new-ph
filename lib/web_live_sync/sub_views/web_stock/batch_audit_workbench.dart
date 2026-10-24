// FILE: lib/web_live_sync/sub_views/web_stock/batch_audit_workbench.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui' show PointerDeviceKind;
import 'package:pharoah_erp/models.dart';

class DisplayAuditItem {
  final String batchNo;
  final String exp;
  final BatchAdjustmentRecord record;

  DisplayAuditItem({
    required this.batchNo,
    required this.exp,
    required this.record,
  });
}

class BatchAuditWorkbench extends StatefulWidget {
  final Medicine medicine;
  final List<BatchInfo> batches;
  final String? initialBatchNo;
  final VoidCallback onBack;
  final bool isWebTheme;

  const BatchAuditWorkbench({
    super.key,
    required this.medicine,
    required this.batches,
    this.initialBatchNo,
    required this.onBack,
    this.isWebTheme = true,
  });

  @override
  State<BatchAuditWorkbench> createState() => _BatchAuditWorkbenchState();
}

class _BatchAuditWorkbenchState extends State<BatchAuditWorkbench> {
  late String selectedBatchFilter;
  String selectedReasonFilter = "ALL";
  final TextEditingController searchController = TextEditingController();
  final ScrollController horizontalHeaderController = ScrollController();
  final ScrollController horizontalBodyController = ScrollController();

  bool freezeColumns = true; // Excel-style Freeze Columns (Batch & Product sticky on left)

  // Column visibility map (Excel hide/show columns)
  Map<String, bool> columnVisibility = {
    'batch': true,
    'date': true,
    'prevQty': true,
    'adjQty': true,
    'newQty': true,
    'reason': true,
    'user': true,
    'actionId': false,
  };

  @override
  void initState() {
    super.initState();
    selectedBatchFilter = widget.initialBatchNo ?? "ALL";
  }

  @override
  void dispose() {
    searchController.dispose();
    horizontalHeaderController.dispose();
    horizontalBodyController.dispose();
    super.dispose();
  }

  List<DisplayAuditItem> _getAllItems() {
    List<DisplayAuditItem> items = [];

    for (var b in widget.batches) {
      if (b.adjustmentHistory.isNotEmpty) {
        for (var rec in b.adjustmentHistory) {
          items.add(DisplayAuditItem(
            batchNo: b.batch,
            exp: b.exp,
            record: rec,
          ));
        }
      } else if (b.adjustmentQty != 0) {
        // Synthesize fallback record for legacy adjustments
        items.add(DisplayAuditItem(
          batchNo: b.batch,
          exp: b.exp,
          record: BatchAdjustmentRecord(
            id: "LEGACY_ADJ_${b.batch}",
            timestamp: b.updatedAt > 0 ? b.updatedAt : DateTime.now().millisecondsSinceEpoch,
            previousQty: b.qty - b.adjustmentQty,
            adjustmentQty: b.adjustmentQty,
            newQty: b.qty,
            reason: b.adjReason.isNotEmpty ? b.adjReason : "Stock Correction",
            adjustedBy: "User",
          ),
        ));
      }
    }

    // Filter by Batch
    if (selectedBatchFilter != "ALL") {
      items = items.where((it) => it.batchNo.trim().toUpperCase() == selectedBatchFilter.trim().toUpperCase()).toList();
    }

    // Filter by Reason
    if (selectedReasonFilter != "ALL") {
      items = items.where((it) => it.record.reason == selectedReasonFilter).toList();
    }

    // Filter by Search Query
    final q = searchController.text.trim().toUpperCase();
    if (q.isNotEmpty) {
      items = items.where((it) {
        final dStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(it.record.timestamp)).toUpperCase();
        return it.batchNo.toUpperCase().contains(q) ||
            it.record.reason.toUpperCase().contains(q) ||
            it.record.adjustedBy.toUpperCase().contains(q) ||
            dStr.contains(q);
      }).toList();
    }

    // Sort newest first
    items.sort((a, b) => b.record.timestamp.compareTo(a.record.timestamp));
    return items;
  }

  void _showColumnCustomizerDialog() {
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: widget.isWebTheme ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.view_column_rounded, color: widget.isWebTheme ? const Color(0xFF38BDF8) : Colors.indigo, size: 22),
              const SizedBox(width: 10),
              Text(
                "Excel Column Controls",
                style: TextStyle(
                  color: widget.isWebTheme ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _colSwitch("Batch & Expiry", 'batch', setDlgState),
                _colSwitch("Date & Time (Timestamp)", 'date', setDlgState),
                _colSwitch("Previous Stock Qty", 'prevQty', setDlgState),
                _colSwitch("Adjustment Change (+/-)", 'adjQty', setDlgState),
                _colSwitch("Projected New Stock", 'newQty', setDlgState),
                _colSwitch("Reason for Adjustment", 'reason', setDlgState),
                _colSwitch("Adjusted By (Staff / Dev)", 'user', setDlgState),
                _colSwitch("Transaction ID / Audit Key", 'actionId', setDlgState),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(c);
                setState(() {});
              },
              child: const Text("APPLY VIEW", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colSwitch(String label, String key, StateSetter setDlgState) {
    final isDark = widget.isWebTheme;
    return CheckboxListTile(
      value: columnVisibility[key] ?? true,
      activeColor: const Color(0xFF059669),
      checkColor: Colors.white,
      title: Text(
        label,
        style: TextStyle(
          color: isDark ? Colors.white70 : Colors.black87,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      onChanged: (v) {
        setDlgState(() => columnVisibility[key] = v ?? true);
        setState(() => columnVisibility[key] = v ?? true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isWebTheme;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.black12;

    final items = _getAllItems();

    // Summary Metrics
    final int totalAdjustments = items.length;
    final double netQty = items.fold(0.0, (s, it) => s + it.record.adjustmentQty);
    final double totalAdded = items.where((it) => it.record.adjustmentQty > 0).fold(0.0, (s, it) => s + it.record.adjustmentQty);
    final double totalReduced = items.where((it) => it.record.adjustmentQty < 0).fold(0.0, (s, it) => s + it.record.adjustmentQty.abs());

    return Container(
      color: bgColor,
      child: Column(
        children: [
          // 🏆 TOP HEADER BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: cardColor,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : Colors.black87),
                  tooltip: "Back to Batch Traceability",
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.table_chart_rounded, color: Color(0xFF2DD4BF), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              "BATCH ADJUSTMENT AUDIT HISTORY • ${widget.medicine.name}",
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F766E).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.medicine.packing,
                              style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Excel-Style Audit Ledger | Consolidated & Individual Batch History Tracking",
                        style: TextStyle(color: isDark ? Colors.white54 : Colors.blueGrey, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Freeze Columns Toggle Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: freezeColumns ? const Color(0xFF2563EB) : (isDark ? Colors.white12 : Colors.grey.shade200),
                    foregroundColor: freezeColumns ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => setState(() => freezeColumns = !freezeColumns),
                  icon: Icon(freezeColumns ? Icons.push_pin_rounded : Icons.push_pin_outlined, size: 15),
                  label: Text(freezeColumns ? "FREEZE: ON" : "FREEZE: OFF", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                const SizedBox(width: 8),

                // Excel Column Controls
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF334155) : Colors.indigo.shade50,
                    foregroundColor: isDark ? Colors.white : Colors.indigo.shade900,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _showColumnCustomizerDialog,
                  icon: const Icon(Icons.tune_rounded, size: 15),
                  label: const Text("COLUMNS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
          ),

          // 📊 KPI METRIC STRIP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            color: isDark ? const Color(0xFF1E293B).withOpacity(0.5) : Colors.grey.shade100,
            child: Row(
              children: [
                _kpiCard("Total Adjustments", "$totalAdjustments Times", Icons.history_rounded, const Color(0xFF38BDF8), isDark),
                const SizedBox(width: 14),
                _kpiCard(
                  "Net Stock Impact",
                  "${netQty >= 0 ? '+' : ''}${netQty.toInt()} Qty",
                  Icons.exposure_rounded,
                  netQty >= 0 ? const Color(0xFF34D399) : const Color(0xFFF87171),
                  isDark,
                ),
                const SizedBox(width: 14),
                _kpiCard("Total Added", "+${totalAdded.toInt()} Qty", Icons.add_circle_outline_rounded, const Color(0xFF34D399), isDark),
                const SizedBox(width: 14),
                _kpiCard("Total Reduced", "-${totalReduced.toInt()} Qty", Icons.remove_circle_outline_rounded, const Color(0xFFF87171), isDark),
              ],
            ),
          ),

          // 🔍 FILTERS BAR (Consolidated vs Individual Batch selector)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: cardColor,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                // Batch Dropdown Filter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedBatchFilter,
                      dropdownColor: cardColor,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 12, fontWeight: FontWeight.bold),
                      items: [
                        const DropdownMenuItem(value: "ALL", child: Text("📦 ALL BATCHES (Consolidated)")),
                        ...widget.batches.map((b) => DropdownMenuItem(
                              value: b.batch,
                              child: Text("Batch: ${b.batch} (${b.qty.toInt()} Qty)"),
                            )),
                      ],
                      onChanged: (v) => setState(() => selectedBatchFilter = v ?? "ALL"),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Reason Filter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedReasonFilter,
                      dropdownColor: cardColor,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 12, fontWeight: FontWeight.bold),
                      items: const [
                        DropdownMenuItem(value: "ALL", child: Text("All Adjustment Reasons")),
                        DropdownMenuItem(value: "Stock Correction", child: Text("Stock Correction")),
                        DropdownMenuItem(value: "Breakage", child: Text("Breakage")),
                        DropdownMenuItem(value: "Shortage", child: Text("Shortage")),
                        DropdownMenuItem(value: "Sample", child: Text("Sample")),
                        DropdownMenuItem(value: "Expiry Damage", child: Text("Expiry Damage")),
                      ],
                      onChanged: (v) => setState(() => selectedReasonFilter = v ?? "ALL"),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Search Input
                Expanded(
                  child: TextField(
                    controller: searchController,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: "Search batch, date, reason or user...",
                      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11),
                      prefixIcon: Icon(Icons.search, size: 16, color: isDark ? Colors.white54 : Colors.black54),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                if (selectedBatchFilter != "ALL" || selectedReasonFilter != "ALL" || searchController.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      selectedBatchFilter = "ALL";
                      selectedReasonFilter = "ALL";
                      searchController.clear();
                    }),
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: const Text("RESET", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
              ],
            ),
          ),

          // 📋 EXCEL-STYLE DATA TABLE
          Expanded(
            child: items.isEmpty
                ? _buildEmptyState(isDark)
                : freezeColumns
                    ? _buildFrozenExcelTable(items, isDark, cardColor, borderColor)
                    : _buildUnfrozenExcelTable(items, isDark, cardColor, borderColor),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String label, String val, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade600, fontSize: 9.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 1),
              Text(val, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 56, color: isDark ? Colors.white24 : Colors.black26),
          const SizedBox(height: 14),
          Text(
            "No Adjustment Records Found",
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            "Whenever a batch stock adjustment is applied, full audit history is preserved here.",
            style: TextStyle(color: isDark ? Colors.white38 : Colors.blueGrey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // --- 1. FROZEN EXCEL TABLE (Sticky Product & Batch on Left, Rest Scrollable) ---
  Widget _buildFrozenExcelTable(List<DisplayAuditItem> items, bool isDark, Color cardColor, Color borderColor) {
    return Row(
      children: [
        // FIXED LEFT COLUMN (Product & Batch No)
        Container(
          width: 210,
          decoration: BoxDecoration(
            color: cardColor,
            border: Border(right: BorderSide(color: isDark ? Colors.white24 : Colors.black26, width: 2)),
          ),
          child: Column(
            children: [
              // Sticky Header
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                color: isDark ? const Color(0xFF0F172A) : Colors.indigo.shade50,
                child: Row(
                  children: [
                    const Icon(Icons.push_pin_rounded, color: Color(0xFF38BDF8), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      "FROZEN: BATCH NO",
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                  itemBuilder: (c, idx) {
                    final it = items[idx];
                    return Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      color: idx % 2 == 1 ? (isDark ? Colors.white.withOpacity(0.02) : Colors.grey.shade50) : Colors.transparent,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(it.batchNo, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12.5)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(it.exp, style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 9.5, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(widget.medicine.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 10)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // SCROLLABLE REMAINING COLUMNS
        Expanded(
          child: ScrollConfiguration(
            behavior: const MaterialScrollBehavior().copyWith(
              dragDevices: {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                width: 780,
                child: Column(
                  children: [
                    // Sticky Header Row
                    Container(
                      height: 44,
                      color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade200,
                      child: Row(
                        children: [
                          if (columnVisibility['date'] ?? true) _headerCell("DATE & TIME", 160, isDark),
                          if (columnVisibility['prevQty'] ?? true) _headerCell("PREV STOCK", 100, isDark),
                          if (columnVisibility['adjQty'] ?? true) _headerCell("ADJ DELTA (+/-)", 120, isDark),
                          if (columnVisibility['newQty'] ?? true) _headerCell("NEW STOCK", 100, isDark),
                          if (columnVisibility['reason'] ?? true) _headerCell("REASON", 150, isDark),
                          if (columnVisibility['user'] ?? true) _headerCell("ADJUSTED BY", 110, isDark),
                          if (columnVisibility['actionId'] ?? false) _headerCell("TRANSACTION ID", 140, isDark),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                        itemBuilder: (c, idx) {
                          final it = items[idx];
                          final dStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(it.record.timestamp));
                          final isPos = it.record.adjustmentQty > 0;

                          return Container(
                            height: 52,
                            color: idx % 2 == 1 ? (isDark ? Colors.white.withOpacity(0.02) : Colors.grey.shade50) : Colors.transparent,
                            child: Row(
                              children: [
                                if (columnVisibility['date'] ?? true)
                                  _dataCell(
                                    Text(dStr, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)),
                                    160,
                                  ),
                                if (columnVisibility['prevQty'] ?? true)
                                  _dataCell(
                                    Text("${it.record.previousQty.toInt()} Qty", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade700, fontSize: 11.5)),
                                    100,
                                  ),
                                if (columnVisibility['adjQty'] ?? true)
                                  _dataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isPos ? const Color(0xFF10B981).withOpacity(0.2) : const Color(0xFFEF4444).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        "${isPos ? '+' : ''}${it.record.adjustmentQty.toInt()} Qty",
                                        style: TextStyle(
                                          color: isPos ? const Color(0xFF34D399) : const Color(0xFFF87171),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    120,
                                  ),
                                if (columnVisibility['newQty'] ?? true)
                                  _dataCell(
                                    Text(
                                      "${it.record.newQty.toInt()} Qty",
                                      style: TextStyle(
                                        color: it.record.newQty >= 0 ? (isDark ? Colors.white : Colors.black87) : Colors.redAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    100,
                                  ),
                                if (columnVisibility['reason'] ?? true)
                                  _dataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B).withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        it.record.reason,
                                        style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 10.5, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    150,
                                  ),
                                if (columnVisibility['user'] ?? true)
                                  _dataCell(
                                    Row(
                                      children: [
                                        Icon(
                                          it.record.adjustedBy == "Developer" ? Icons.military_tech_rounded : Icons.person_rounded,
                                          size: 13,
                                          color: isDark ? Colors.white54 : Colors.black54,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(it.record.adjustedBy, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 11)),
                                      ],
                                    ),
                                    110,
                                  ),
                                if (columnVisibility['actionId'] ?? false)
                                  _dataCell(
                                    Text(it.record.id, style: TextStyle(color: isDark ? Colors.white38 : Colors.grey, fontSize: 9.5)),
                                    140,
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- 2. UNFROZEN TABLE (Single Scrollable DataTable) ---
  Widget _buildUnfrozenExcelTable(List<DisplayAuditItem> items, bool isDark, Color cardColor, Color borderColor) {
    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF0F172A) : Colors.grey.shade200),
            columns: [
              if (columnVisibility['batch'] ?? true) const DataColumn(label: Text("BATCH NO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              if (columnVisibility['date'] ?? true) const DataColumn(label: Text("DATE & TIME", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              if (columnVisibility['prevQty'] ?? true) const DataColumn(label: Text("PREV STOCK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              if (columnVisibility['adjQty'] ?? true) const DataColumn(label: Text("ADJ DELTA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              if (columnVisibility['newQty'] ?? true) const DataColumn(label: Text("NEW STOCK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              if (columnVisibility['reason'] ?? true) const DataColumn(label: Text("REASON", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              if (columnVisibility['user'] ?? true) const DataColumn(label: Text("ADJUSTED BY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              if (columnVisibility['actionId'] ?? false) const DataColumn(label: Text("ID", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
            ],
            rows: items.map((it) {
              final dStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(it.record.timestamp));
              final isPos = it.record.adjustmentQty > 0;

              return DataRow(
                cells: [
                  if (columnVisibility['batch'] ?? true)
                    DataCell(Text(it.batchNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  if (columnVisibility['date'] ?? true) DataCell(Text(dStr, style: const TextStyle(fontSize: 11))),
                  if (columnVisibility['prevQty'] ?? true) DataCell(Text("${it.record.previousQty.toInt()} Qty")),
                  if (columnVisibility['adjQty'] ?? true)
                    DataCell(Text(
                      "${isPos ? '+' : ''}${it.record.adjustmentQty.toInt()} Qty",
                      style: TextStyle(color: isPos ? const Color(0xFF10B981) : Colors.redAccent, fontWeight: FontWeight.bold),
                    )),
                  if (columnVisibility['newQty'] ?? true)
                    DataCell(Text("${it.record.newQty.toInt()} Qty", style: const TextStyle(fontWeight: FontWeight.bold))),
                  if (columnVisibility['reason'] ?? true)
                    DataCell(Text(it.record.reason, style: const TextStyle(fontSize: 11))),
                  if (columnVisibility['user'] ?? true)
                    DataCell(Text(it.record.adjustedBy, style: const TextStyle(fontSize: 11))),
                  if (columnVisibility['actionId'] ?? false)
                    DataCell(Text(it.record.id, style: const TextStyle(fontSize: 9.5))),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String title, double width, bool isDark) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          color: isDark ? Colors.white70 : Colors.black87,
          fontWeight: FontWeight.bold,
          fontSize: 10.5,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _dataCell(Widget child, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}
