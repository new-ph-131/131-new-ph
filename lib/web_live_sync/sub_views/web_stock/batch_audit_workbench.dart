// FILE: lib/web_live_sync/sub_views/web_stock/batch_audit_workbench.dart
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pharoah_erp/models.dart';

enum BatchAuditFreezeOption {
  none,
  srAndBatch,
  srBatchAndExp,
  srBatchAndDate,
  srBatchDateAndPrev,
}

enum BatchAuditColumnId {
  srNo,
  batchNo,
  expiry,
  liveStock,
  dateTime,
  prevQty,
  adjQty,
  newQty,
  reason,
  adjustedBy,
  auditId,
  actions,
}

class BatchAuditColumnDef {
  final BatchAuditColumnId id;
  final String title;
  final double width;
  final double portraitWidth;
  final bool isNumeric;
  bool isVisible;

  BatchAuditColumnDef({
    required this.id,
    required this.title,
    required this.width,
    required this.portraitWidth,
    this.isNumeric = false,
    this.isVisible = true,
  });
}

class DisplayAuditItem {
  final String batchNo;
  final String exp;
  final double currentBatchQty;
  final double mrp;
  final double purRate;
  final BatchAdjustmentRecord record;

  DisplayAuditItem({
    required this.batchNo,
    required this.exp,
    required this.currentBatchQty,
    required this.mrp,
    required this.purRate,
    required this.record,
  });
}

class BatchAuditSummaryStat {
  final String batchNo;
  final String exp;
  final double liveQty;
  final int adjustmentCount;
  final double netDelta;
  final int lastTimestamp;

  BatchAuditSummaryStat({
    required this.batchNo,
    required this.exp,
    required this.liveQty,
    required this.adjustmentCount,
    required this.netDelta,
    required this.lastTimestamp,
  });
}

class BatchAuditWorkbench extends StatefulWidget {
  final Medicine medicine;
  final List<BatchInfo> batches;
  final String? initialBatchNo;
  final VoidCallback onBack;
  final bool isWebTheme;
  final void Function({
    required String batchNo,
    required BatchAdjustmentRecord record,
    required double newAdjQty,
    required String newReason,
    required String newNotes,
  })? onModifyRecord;
  final void Function({
    required String batchNo,
    required BatchAdjustmentRecord record,
  })? onDeleteRecord;

  const BatchAuditWorkbench({
    super.key,
    required this.medicine,
    required this.batches,
    this.initialBatchNo,
    required this.onBack,
    this.isWebTheme = true,
    this.onModifyRecord,
    this.onDeleteRecord,
  });

  @override
  State<BatchAuditWorkbench> createState() => _BatchAuditWorkbenchState();
}

class _BatchAuditWorkbenchState extends State<BatchAuditWorkbench> {
  late String selectedBatchFilter;
  String selectedReasonFilter = "ALL";
  String activeQuickChip = "ALL"; // ALL, ADDED, REDUCED, TODAY, CORRECTION, BREAKAGE, SHORTAGE
  final TextEditingController searchController = TextEditingController();
  String _searchQuery = "";

  // Stock-Style Freeze Pane & Sort State
  BatchAuditFreezeOption _freezeOption = BatchAuditFreezeOption.srAndBatch;
  BatchAuditFreezeOption _lastNonZeroFreeze = BatchAuditFreezeOption.srAndBatch;
  BatchAuditColumnId _sortColumn = BatchAuditColumnId.dateTime;
  bool _isAscending = false; // Newest adjustments first by default

  // Synchronized Scroll Controllers (Stock Workbench Architecture)
  final ScrollController _frozenVerticalScroll = ScrollController();
  final ScrollController _scrollableVerticalScroll = ScrollController();
  final ScrollController _horizontalScroll = ScrollController();
  bool _isSyncingVertical = false;

  late Map<BatchAuditColumnId, BatchAuditColumnDef> _columnDefs;

  @override
  void initState() {
    super.initState();
    selectedBatchFilter = widget.initialBatchNo ?? "ALL";
    _initColumns();

    // Synchronize vertical scroll between Frozen Left Pane and Scrollable Right Pane
    _frozenVerticalScroll.addListener(() {
      if (_isSyncingVertical) return;
      if (_scrollableVerticalScroll.hasClients) {
        _isSyncingVertical = true;
        final target = _frozenVerticalScroll.offset.clamp(
          0.0,
          _scrollableVerticalScroll.position.maxScrollExtent,
        );
        _scrollableVerticalScroll.jumpTo(target);
        _isSyncingVertical = false;
      }
    });

    _scrollableVerticalScroll.addListener(() {
      if (_isSyncingVertical) return;
      if (_frozenVerticalScroll.hasClients) {
        _isSyncingVertical = true;
        final target = _scrollableVerticalScroll.offset.clamp(
          0.0,
          _frozenVerticalScroll.position.maxScrollExtent,
        );
        _frozenVerticalScroll.jumpTo(target);
        _isSyncingVertical = false;
      }
    });
  }

  void _initColumns() {
    _columnDefs = {
      BatchAuditColumnId.srNo: BatchAuditColumnDef(
        id: BatchAuditColumnId.srNo,
        title: "# SR",
        width: 58,
        portraitWidth: 46,
        isNumeric: true,
        isVisible: true,
      ),
      BatchAuditColumnId.batchNo: BatchAuditColumnDef(
        id: BatchAuditColumnId.batchNo,
        title: "BATCH NO",
        width: 145,
        portraitWidth: 118,
        isVisible: true,
      ),
      BatchAuditColumnId.dateTime: BatchAuditColumnDef(
        id: BatchAuditColumnId.dateTime,
        title: "DATE & TIME",
        width: 155,
        portraitWidth: 138,
        isVisible: true,
      ),
      BatchAuditColumnId.prevQty: BatchAuditColumnDef(
        id: BatchAuditColumnId.prevQty,
        title: "PREV STOCK",
        width: 100,
        portraitWidth: 88,
        isNumeric: true,
        isVisible: true,
      ),
      BatchAuditColumnId.adjQty: BatchAuditColumnDef(
        id: BatchAuditColumnId.adjQty,
        title: "ADJ DELTA (+/-)",
        width: 120,
        portraitWidth: 105,
        isNumeric: true,
        isVisible: true,
      ),
      BatchAuditColumnId.newQty: BatchAuditColumnDef(
        id: BatchAuditColumnId.newQty,
        title: "NEW STOCK",
        width: 100,
        portraitWidth: 88,
        isNumeric: true,
        isVisible: true,
      ),
      BatchAuditColumnId.actions: BatchAuditColumnDef(
        id: BatchAuditColumnId.actions,
        title: "ACTIONS (MODIFY / CANCEL)",
        width: 175,
        portraitWidth: 155,
        isVisible: true,
      ),
      BatchAuditColumnId.reason: BatchAuditColumnDef(
        id: BatchAuditColumnId.reason,
        title: "REASON",
        width: 145,
        portraitWidth: 125,
        isVisible: true,
      ),
      BatchAuditColumnId.expiry: BatchAuditColumnDef(
        id: BatchAuditColumnId.expiry,
        title: "EXPIRY",
        width: 85,
        portraitWidth: 74,
        isVisible: true,
      ),
      BatchAuditColumnId.liveStock: BatchAuditColumnDef(
        id: BatchAuditColumnId.liveStock,
        title: "LIVE STOCK",
        width: 100,
        portraitWidth: 86,
        isNumeric: true,
        isVisible: true,
      ),
      BatchAuditColumnId.adjustedBy: BatchAuditColumnDef(
        id: BatchAuditColumnId.adjustedBy,
        title: "ADJUSTED BY",
        width: 115,
        portraitWidth: 96,
        isVisible: true,
      ),
      BatchAuditColumnId.auditId: BatchAuditColumnDef(
        id: BatchAuditColumnId.auditId,
        title: "AUDIT ID",
        width: 150,
        portraitWidth: 130,
        isVisible: false,
      ),
    };
  }

  @override
  void dispose() {
    searchController.dispose();
    _frozenVerticalScroll.dispose();
    _scrollableVerticalScroll.dispose();
    _horizontalScroll.dispose();
    super.dispose();
  }

  double _effectiveColWidth(BatchAuditColumnId colId, bool isPortrait) {
    final def = _columnDefs[colId]!;
    return isPortrait ? def.portraitWidth : def.width;
  }

  List<BatchAuditColumnId> _getFrozenColumns() {
    switch (_freezeOption) {
      case BatchAuditFreezeOption.none:
        return [];
      case BatchAuditFreezeOption.srAndBatch:
        return [BatchAuditColumnId.srNo, BatchAuditColumnId.batchNo];
      case BatchAuditFreezeOption.srBatchAndExp:
        return [BatchAuditColumnId.srNo, BatchAuditColumnId.batchNo, BatchAuditColumnId.expiry];
      case BatchAuditFreezeOption.srBatchAndDate:
        return [BatchAuditColumnId.srNo, BatchAuditColumnId.batchNo, BatchAuditColumnId.dateTime];
      case BatchAuditFreezeOption.srBatchDateAndPrev:
        return [
          BatchAuditColumnId.srNo,
          BatchAuditColumnId.batchNo,
          BatchAuditColumnId.dateTime,
          BatchAuditColumnId.prevQty,
        ];
    }
  }

  void _toggleQuickFreeze() {
    setState(() {
      if (_freezeOption == BatchAuditFreezeOption.none) {
        _freezeOption = _lastNonZeroFreeze;
      } else {
        _lastNonZeroFreeze = _freezeOption;
        _freezeOption = BatchAuditFreezeOption.none;
      }
    });
  }

  void _onSort(BatchAuditColumnId colId) {
    setState(() {
      if (_sortColumn == colId) {
        _isAscending = !_isAscending;
      } else {
        _sortColumn = colId;
        _isAscending = colId == BatchAuditColumnId.batchNo || colId == BatchAuditColumnId.reason;
      }
    });
  }

  List<BatchAuditSummaryStat> _buildBatchSummaryStats() {
    final List<BatchAuditSummaryStat> stats = [];
    for (final b in widget.batches) {
      final List<BatchAdjustmentRecord> recs = List<BatchAdjustmentRecord>.from(b.adjustmentHistory);
      if (recs.isEmpty && b.adjustmentQty != 0) {
        recs.add(
          BatchAdjustmentRecord(
            id: "LEGACY_${b.batch}",
            timestamp: b.updatedAt > 0 ? b.updatedAt : DateTime.now().millisecondsSinceEpoch,
            previousQty: b.qty - b.adjustmentQty,
            adjustmentQty: b.adjustmentQty,
            newQty: b.qty,
            reason: b.adjReason.isNotEmpty ? b.adjReason : "Stock Correction",
            adjustedBy: "User",
          ),
        );
      }
      double net = 0;
      int lastTs = b.updatedAt;
      for (final r in recs) {
        net += r.adjustmentQty;
        if (r.timestamp > lastTs) lastTs = r.timestamp;
      }
      stats.add(
        BatchAuditSummaryStat(
          batchNo: b.batch,
          exp: b.exp,
          liveQty: b.qty,
          adjustmentCount: recs.length,
          netDelta: net,
          lastTimestamp: lastTs,
        ),
      );
    }
    stats.sort((a, b) {
      if (b.adjustmentCount != a.adjustmentCount) {
        return b.adjustmentCount.compareTo(a.adjustmentCount);
      }
      return b.lastTimestamp.compareTo(a.lastTimestamp);
    });
    return stats;
  }

  List<DisplayAuditItem> _getFilteredAndSortedItems() {
    final List<DisplayAuditItem> list = [];
    final now = DateTime.now();

    for (var b in widget.batches) {
      if (selectedBatchFilter != "ALL" && b.batch.trim().toUpperCase() != selectedBatchFilter.trim().toUpperCase()) {
        continue;
      }

      List<BatchAdjustmentRecord> records = List<BatchAdjustmentRecord>.from(b.adjustmentHistory);
      if (records.isEmpty && b.adjustmentQty != 0) {
        records.add(
          BatchAdjustmentRecord(
            id: "LEGACY_${b.batch}",
            timestamp: b.updatedAt > 0 ? b.updatedAt : DateTime.now().millisecondsSinceEpoch,
            previousQty: b.qty - b.adjustmentQty,
            adjustmentQty: b.adjustmentQty,
            newQty: b.qty,
            reason: b.adjReason.isNotEmpty ? b.adjReason : "Stock Correction",
            adjustedBy: "User",
          ),
        );
      }

      for (var r in records) {
        if (selectedReasonFilter != "ALL" && r.reason.toLowerCase() != selectedReasonFilter.toLowerCase()) {
          continue;
        }

        // Quick Filter Chip check
        if (activeQuickChip == "ADDED" && r.adjustmentQty <= 0) continue;
        if (activeQuickChip == "REDUCED" && r.adjustmentQty >= 0) continue;
        if (activeQuickChip == "TODAY") {
          final dt = DateTime.fromMillisecondsSinceEpoch(r.timestamp);
          if (dt.year != now.year || dt.month != now.month || dt.day != now.day) continue;
        }
        if (activeQuickChip == "CORRECTION" && !r.reason.toLowerCase().contains("correction")) continue;
        if (activeQuickChip == "BREAKAGE" &&
            !r.reason.toLowerCase().contains("breakage") &&
            !r.reason.toLowerCase().contains("damage") &&
            !r.reason.toLowerCase().contains("expiry")) {
          continue;
        }
        if (activeQuickChip == "SHORTAGE" &&
            !r.reason.toLowerCase().contains("shortage") &&
            !r.reason.toLowerCase().contains("sample")) {
          continue;
        }

        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          final dStr = DateFormat('dd/MM/yyyy hh:mm a')
              .format(DateTime.fromMillisecondsSinceEpoch(r.timestamp))
              .toLowerCase();
          final deltaStr = "${r.adjustmentQty > 0 ? '+' : ''}${r.adjustmentQty.toInt()}".toLowerCase();
          final prevStr = "${r.previousQty.toInt()}";
          final newStr = "${r.newQty.toInt()}";

          final matches = b.batch.toLowerCase().contains(q) ||
              b.exp.toLowerCase().contains(q) ||
              r.reason.toLowerCase().contains(q) ||
              r.adjustedBy.toLowerCase().contains(q) ||
              r.id.toLowerCase().contains(q) ||
              dStr.contains(q) ||
              deltaStr.contains(q) ||
              prevStr.contains(q) ||
              newStr.contains(q);

          if (!matches) continue;
        }

        list.add(
          DisplayAuditItem(
            batchNo: b.batch,
            exp: b.exp,
            currentBatchQty: b.qty,
            mrp: b.mrp,
            purRate: b.purRate,
            record: r,
          ),
        );
      }
    }

    list.sort((a, b) {
      int cmp = 0;
      switch (_sortColumn) {
        case BatchAuditColumnId.srNo:
        case BatchAuditColumnId.dateTime:
          cmp = a.record.timestamp.compareTo(b.record.timestamp);
          break;
        case BatchAuditColumnId.batchNo:
          cmp = a.batchNo.toLowerCase().compareTo(b.batchNo.toLowerCase());
          break;
        case BatchAuditColumnId.expiry:
          cmp = a.exp.toLowerCase().compareTo(b.exp.toLowerCase());
          break;
        case BatchAuditColumnId.liveStock:
          cmp = a.currentBatchQty.compareTo(b.currentBatchQty);
          break;
        case BatchAuditColumnId.prevQty:
          cmp = a.record.previousQty.compareTo(b.record.previousQty);
          break;
        case BatchAuditColumnId.adjQty:
          cmp = a.record.adjustmentQty.compareTo(b.record.adjustmentQty);
          break;
        case BatchAuditColumnId.newQty:
          cmp = a.record.newQty.compareTo(b.record.newQty);
          break;
        case BatchAuditColumnId.reason:
          cmp = a.record.reason.toLowerCase().compareTo(b.record.reason.toLowerCase());
          break;
        case BatchAuditColumnId.adjustedBy:
          cmp = a.record.adjustedBy.toLowerCase().compareTo(b.record.adjustedBy.toLowerCase());
          break;
        case BatchAuditColumnId.auditId:
        case BatchAuditColumnId.actions:
          cmp = a.record.id.compareTo(b.record.id);
          break;
      }
      return _isAscending ? cmp : -cmp;
    });

    return list;
  }

  void _showColumnCustomizerDialog() {
    final isDark = widget.isWebTheme;
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                const Icon(Icons.view_column_rounded, color: Color(0xFF38BDF8), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Excel Columns & Freeze Pane",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "FREEZE LEFT PANE MODE",
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.blueGrey,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<BatchAuditFreezeOption>(
                      value: _freezeOption,
                      dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: BatchAuditFreezeOption.none,
                          child: Text("No Freeze (Unfrozen Scroll)"),
                        ),
                        DropdownMenuItem(
                          value: BatchAuditFreezeOption.srAndBatch,
                          child: Text("Freeze: # SR + Batch No"),
                        ),
                        DropdownMenuItem(
                          value: BatchAuditFreezeOption.srBatchAndExp,
                          child: Text("Freeze: # SR + Batch + Expiry"),
                        ),
                        DropdownMenuItem(
                          value: BatchAuditFreezeOption.srBatchAndDate,
                          child: Text("Freeze: # SR + Batch + Date"),
                        ),
                        DropdownMenuItem(
                          value: BatchAuditFreezeOption.srBatchDateAndPrev,
                          child: Text("Freeze: # SR + Batch + Date + Prev Stock"),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => _freezeOption = val);
                          setState(() {
                            _freezeOption = val;
                            if (val != BatchAuditFreezeOption.none) {
                              _lastNonZeroFreeze = val;
                            }
                          });
                        }
                      },
                    ),
                    const Divider(height: 22),
                    Text(
                      "VISIBLE COLUMNS",
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.blueGrey,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._columnDefs.values.map((def) {
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          def.title,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        activeColor: const Color(0xFF0284C7),
                        value: def.isVisible,
                        onChanged: (val) {
                          if (def.id == BatchAuditColumnId.batchNo) return; // keep batchNo always visible
                          setDialogState(() => def.isVisible = val ?? true);
                          setState(() {});
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    for (final d in _columnDefs.values) {
                      d.isVisible = d.id != BatchAuditColumnId.auditId;
                    }
                    _freezeOption = BatchAuditFreezeOption.srAndBatch;
                  });
                  setState(() {});
                },
                child: const Text("RESET DEFAULT"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(c),
                child: const Text("DONE"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isWebTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isPortrait = screenWidth < 720;

    final bgColor = isDark ? const Color(0xFF0B0F19) : const Color(0xFFF1F5F9);
    final cardColor = isDark ? const Color(0xFF131C31) : Colors.white;
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    final items = _getFilteredAndSortedItems();
    final batchStats = _buildBatchSummaryStats();

    // Summary Metrics
    final int totalAdjustments = items.length;
    final double netQty = items.fold(0.0, (s, it) => s + it.record.adjustmentQty);
    final double totalAdded = items
        .where((it) => it.record.adjustmentQty > 0)
        .fold(0.0, (s, it) => s + it.record.adjustmentQty);
    final double totalReduced = items
        .where((it) => it.record.adjustmentQty < 0)
        .fold(0.0, (s, it) => s + it.record.adjustmentQty.abs());

    // Frozen & Scrollable Column Partitioning (Identical to Stock Analysis Master View)
    final frozenSet = _getFrozenColumns();
    final visibleFrozenCols = _columnDefs.keys
        .where((k) => _columnDefs[k]!.isVisible && frozenSet.contains(k))
        .toList();
    final visibleScrollableCols = _columnDefs.keys
        .where((k) => _columnDefs[k]!.isVisible && !frozenSet.contains(k))
        .toList();

    final double frozenPaneWidth = visibleFrozenCols.fold(
      0.0,
      (sum, col) => sum + _effectiveColWidth(col, isPortrait),
    );
    final double scrollablePaneWidth = visibleScrollableCols.fold(
      0.0,
      (sum, col) => sum + _effectiveColWidth(col, isPortrait),
    );

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        // Guarantee bounded height even when embedded inside WebPortalGateway's SingleChildScrollView!
        final double workbenchHeight = outerConstraints.hasBoundedHeight
            ? outerConstraints.maxHeight
            : (screenHeight - 135.0).clamp(540.0, 1100.0);

        return SizedBox(
          width: double.infinity,
          height: workbenchHeight,
          child: Container(
            color: bgColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. TOP BANNER & KPI METRICS
                _buildTopBanner(
                  isDark: isDark,
                  isPortrait: isPortrait,
                  cardColor: cardColor,
                  borderColor: borderColor,
                  totalAdjustments: totalAdjustments,
                  netQty: netQty,
                  totalAdded: totalAdded,
                  totalReduced: totalReduced,
                ),

                // 2. BATCH-WISE SUMMARY PILLS STRIP (1-Click Batch Jump)
                if (batchStats.isNotEmpty)
                  _buildBatchSummaryStrip(batchStats, isDark, borderColor),

                // 3. ADVANCED SEARCH, FREEZE DROPDOWN & QUICK FILTER CHIPS BAR
                _buildControlToolbar(isDark, isPortrait, cardColor, borderColor),

                // 4. SMOOTH STOCK-STYLE SYNCHRONIZED ROW TABLE
                Expanded(
                  child: items.isEmpty
                      ? _buildEmptyState(isDark)
                      : LayoutBuilder(
                          builder: (context, tableConstraints) {
                            final double tableHeight = tableConstraints.hasBoundedHeight
                                ? tableConstraints.maxHeight
                                : (workbenchHeight - 240.0).clamp(260.0, 800.0);

                            final double availableWidth = tableConstraints.hasBoundedWidth
                                ? tableConstraints.maxWidth
                                : screenWidth;
                            final double minRightWidth = (availableWidth - frozenPaneWidth).clamp(200.0, 4000.0);
                            final double effectiveScrollableWidth =
                                scrollablePaneWidth > minRightWidth ? scrollablePaneWidth : minRightWidth;

                            return SizedBox(
                              height: tableHeight,
                              width: availableWidth,
                              child: ScrollConfiguration(
                                behavior: const MaterialScrollBehavior().copyWith(
                                  dragDevices: {
                                    PointerDeviceKind.mouse,
                                    PointerDeviceKind.touch,
                                    PointerDeviceKind.trackpad,
                                    PointerDeviceKind.stylus,
                                  },
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // LEFT PANE: FROZEN COLUMNS (Locked during horizontal scroll)
                                    if (visibleFrozenCols.isNotEmpty)
                                      SizedBox(
                                        width: frozenPaneWidth,
                                        height: tableHeight,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF131C31) : Colors.indigo.shade50.withOpacity(0.45),
                                            border: Border(
                                              right: BorderSide(
                                                color: const Color(0xFF38BDF8).withOpacity(isDark ? 0.45 : 0.65),
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              _buildFrozenHeader(visibleFrozenCols, isDark, isPortrait),
                                              Expanded(
                                                child: ListView.builder(
                                                  controller: _frozenVerticalScroll,
                                                  physics: const ClampingScrollPhysics(),
                                                  itemCount: items.length,
                                                  itemExtent: 46,
                                                  itemBuilder: (context, index) {
                                                    return _buildFrozenRow(
                                                      items[index],
                                                      index + 1,
                                                      visibleFrozenCols,
                                                      isDark,
                                                      isPortrait,
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                    // RIGHT PANE: HORIZONTALLY SCROLLABLE COLUMNS
                                    Expanded(
                                      child: SingleChildScrollView(
                                        controller: _horizontalScroll,
                                        scrollDirection: Axis.horizontal,
                                        physics: const ClampingScrollPhysics(),
                                        child: SizedBox(
                                          width: effectiveScrollableWidth,
                                          height: tableHeight,
                                          child: Column(
                                            children: [
                                              _buildScrollableHeader(visibleScrollableCols, isDark, isPortrait),
                                              Expanded(
                                                child: ListView.builder(
                                                  controller: _scrollableVerticalScroll,
                                                  physics: const ClampingScrollPhysics(),
                                                  itemCount: items.length,
                                                  itemExtent: 46,
                                                  itemBuilder: (context, index) {
                                                    return _buildScrollableRow(
                                                      items[index],
                                                      index + 1,
                                                      visibleScrollableCols,
                                                      isDark,
                                                      isPortrait,
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
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

                // 5. BOTTOM SUMMARY FOOTER BAR
                _buildFooterBar(items.length, visibleFrozenCols.length, isDark, cardColor, borderColor),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 1. TOP BANNER & KPI STRIP
  // ===========================================================================
  Widget _buildTopBanner({
    required bool isDark,
    required bool isPortrait,
    required Color cardColor,
    required Color borderColor,
    required int totalAdjustments,
    required double netQty,
    required double totalAdded,
    required double totalReduced,
  }) {
    final bool isFrozen = _freezeOption != BatchAuditFreezeOption.none;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isPortrait ? 12 : 20, vertical: isPortrait ? 10 : 12),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : Colors.black87, size: 20),
                tooltip: "Back to Batch Traceability",
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF14B8A6).withOpacity(0.4)),
                ),
                child: const Icon(Icons.table_chart_rounded, color: Color(0xFF2DD4BF), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            "BATCH ADJUSTMENT AUDIT WORKBENCH • ${widget.medicine.name}",
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              fontSize: isPortrait ? 13 : 15,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            widget.medicine.packing,
                            style: const TextStyle(
                              color: Color(0xFF2DD4BF),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Smooth Synchronized Row Engine • Click Any Column Header to Sort • Instant Batch Search",
                      style: TextStyle(color: isDark ? Colors.white54 : Colors.blueGrey, fontSize: 10.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isPortrait) ...[
                _topMetricTile("ADJUSTMENTS", "$totalAdjustments Times", const Color(0xFF38BDF8), isDark),
                _verticalDivider(isDark),
                _topMetricTile(
                  "NET IMPACT",
                  "${netQty >= 0 ? '+' : ''}${netQty.toInt()} Qty",
                  netQty >= 0 ? const Color(0xFF34D399) : const Color(0xFFF87171),
                  isDark,
                ),
                _verticalDivider(isDark),
                _topMetricTile("TOTAL ADDED", "+${totalAdded.toInt()} Qty", const Color(0xFF34D399), isDark),
                _verticalDivider(isDark),
                _topMetricTile("TOTAL REDUCED", "-${totalReduced.toInt()} Qty", const Color(0xFFF87171), isDark),
                const SizedBox(width: 12),
              ],
              // Quick Freeze Toggle Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFrozen
                      ? const Color(0xFF2563EB)
                      : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade200),
                  foregroundColor: isFrozen ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                  padding: EdgeInsets.symmetric(horizontal: isPortrait ? 8 : 12, vertical: 8),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _toggleQuickFreeze,
                icon: Icon(isFrozen ? Icons.ac_unit_rounded : Icons.lock_open_rounded, size: 14),
                label: Text(
                  isFrozen ? "FREEZE: ON" : "FREEZE: OFF",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                ),
              ),
              const SizedBox(width: 6),
              // Column & Freeze Config Dialog
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.indigo.shade50,
                  foregroundColor: isDark ? Colors.white : Colors.indigo.shade900,
                  side: BorderSide(color: borderColor),
                  padding: EdgeInsets.symmetric(horizontal: isPortrait ? 8 : 12, vertical: 8),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _showColumnCustomizerDialog,
                icon: const Icon(Icons.view_column_rounded, size: 14, color: Color(0xFFA78BFA)),
                label: Text(
                  isPortrait ? "COLS" : "COLUMNS",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                ),
              ),
            ],
          ),
          if (isPortrait) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _topMetricTile("ADJUSTMENTS", "$totalAdjustments Times", const Color(0xFF38BDF8), isDark),
                  _verticalDivider(isDark),
                  _topMetricTile(
                    "NET IMPACT",
                    "${netQty >= 0 ? '+' : ''}${netQty.toInt()} Qty",
                    netQty >= 0 ? const Color(0xFF34D399) : const Color(0xFFF87171),
                    isDark,
                  ),
                  _verticalDivider(isDark),
                  _topMetricTile("ADDED", "+${totalAdded.toInt()} Qty", const Color(0xFF34D399), isDark),
                  _verticalDivider(isDark),
                  _topMetricTile("REDUCED", "-${totalReduced.toInt()} Qty", const Color(0xFFF87171), isDark),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _topMetricTile(String label, String value, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey.shade600,
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider(bool isDark) =>
      Container(height: 22, width: 1, color: isDark ? Colors.white10 : Colors.black12);

  // ===========================================================================
  // 2. INTERACTIVE PER-BATCH SUMMARY PILLS STRIP ("1000-IQ Batch Quick Jump")
  // ===========================================================================
  Widget _buildBatchSummaryStrip(List<BatchAuditSummaryStat> stats, bool isDark, Color borderColor) {
    final totalAdjCount = stats.fold<int>(0, (s, x) => s + x.adjustmentCount);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            Icon(Icons.layers_rounded, size: 14, color: isDark ? const Color(0xFF38BDF8) : Colors.indigo),
            const SizedBox(width: 6),
            Text(
              "BATCH QUICK SELECT:",
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.blueGrey.shade700,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 8),
            _batchPill(
              label: "ALL BATCHES (${widget.batches.length})",
              badge: "$totalAdjCount Adj",
              isSelected: selectedBatchFilter == "ALL",
              badgeColor: const Color(0xFF38BDF8),
              isDark: isDark,
              onTap: () => setState(() => selectedBatchFilter = "ALL"),
            ),
            ...stats.map((st) {
              final bool isSel = selectedBatchFilter.trim().toUpperCase() == st.batchNo.trim().toUpperCase();
              final String sign = st.netDelta > 0 ? "+" : "";
              final String badgeText = st.adjustmentCount > 0
                  ? "${st.adjustmentCount}x (${sign}${st.netDelta.toInt()})"
                  : "0 Adj • ${st.liveQty.toInt()} Qty";
              final Color bColor = st.adjustmentCount == 0
                  ? Colors.grey
                  : (st.netDelta >= 0 ? const Color(0xFF34D399) : const Color(0xFFF87171));

              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _batchPill(
                  label: st.batchNo,
                  badge: badgeText,
                  isSelected: isSel,
                  badgeColor: bColor,
                  isDark: isDark,
                  onTap: () => setState(() {
                    selectedBatchFilter = isSel ? "ALL" : st.batchNo;
                  }),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _batchPill({
    required String label,
    required String badge,
    required bool isSelected,
    required Color badgeColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2563EB)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF60A5FA)
                : (isDark ? Colors.white12 : Colors.black12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black87),
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? Colors.black26 : badgeColor.withOpacity(0.16),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: isSelected ? Colors.white : badgeColor,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 3. ADVANCED SEARCH, FREEZE DROPDOWN & QUICK FILTER CHIPS BAR
  // ===========================================================================
  Widget _buildControlToolbar(bool isDark, bool isPortrait, Color cardColor, Color borderColor) {
    final bool hasActiveFilters = selectedBatchFilter != "ALL" ||
        selectedReasonFilter != "ALL" ||
        activeQuickChip != "ALL" ||
        _searchQuery.isNotEmpty;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isPortrait ? 10 : 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPortrait) ...[
            // Portrait Row 1: Search Box
            _buildSearchBox(isDark, borderColor),
            const SizedBox(height: 6),
            // Portrait Row 2: Scrollable Dropdowns
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildBatchDropdown(isDark, cardColor, borderColor),
                  const SizedBox(width: 8),
                  _buildFreezeDropdown(isDark, cardColor, borderColor),
                  const SizedBox(width: 8),
                  _buildReasonDropdown(isDark, cardColor, borderColor),
                  if (hasActiveFilters) ...[
                    const SizedBox(width: 8),
                    _buildResetButton(),
                  ],
                ],
              ),
            ),
          ] else ...[
            // Landscape Row: Search + Batch Selector + Reason Selector + Freeze Mode Selector + Reset
            Row(
              children: [
                Expanded(flex: 3, child: _buildSearchBox(isDark, borderColor)),
                const SizedBox(width: 10),
                _buildBatchDropdown(isDark, cardColor, borderColor),
                const SizedBox(width: 10),
                _buildReasonDropdown(isDark, cardColor, borderColor),
                const SizedBox(width: 10),
                _buildFreezeDropdown(isDark, cardColor, borderColor),
                if (hasActiveFilters) ...[
                  const SizedBox(width: 8),
                  _buildResetButton(),
                ],
              ],
            ),
          ],
          const SizedBox(height: 7),
          // Quick Filter Chips Strip
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _quickFilterChip("ALL", "All Adjustments", isDark),
                const SizedBox(width: 6),
                _quickFilterChip("ADDED", "➕ Added (+ Stock)", isDark),
                const SizedBox(width: 6),
                _quickFilterChip("REDUCED", "➖ Reduced (- Stock)", isDark),
                const SizedBox(width: 6),
                _quickFilterChip("TODAY", "📅 Today's Audit", isDark),
                const SizedBox(width: 6),
                _quickFilterChip("CORRECTION", "🔧 Stock Correction", isDark),
                const SizedBox(width: 6),
                _quickFilterChip("BREAKAGE", "💔 Breakage / Expiry", isDark),
                const SizedBox(width: 6),
                _quickFilterChip("SHORTAGE", "⚠️ Shortage / Sample", isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox(bool isDark, Color borderColor) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: searchController,
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 12),
        decoration: InputDecoration(
          hintText: "Search Batch No, Expiry, Date, Reason, User or Qty...",
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 17),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: isDark ? Colors.white54 : Colors.black54, size: 15),
                  onPressed: () {
                    searchController.clear();
                    setState(() => _searchQuery = "");
                  },
                )
              : null,
          filled: true,
          fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF38BDF8)),
          ),
        ),
      ),
    );
  }

  Widget _buildBatchDropdown(bool isDark, Color cardColor, Color borderColor) {
    final bool hasBatchMatch = selectedBatchFilter == "ALL" ||
        widget.batches.any((b) => b.batch == selectedBatchFilter);
    final String effectiveValue = hasBatchMatch ? selectedBatchFilter : "ALL";

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: effectiveValue != "ALL" ? const Color(0xFF38BDF8) : borderColor,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveValue,
          dropdownColor: cardColor,
          icon: const Icon(Icons.inventory_2_rounded, color: Color(0xFF38BDF8), size: 15),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          items: [
            const DropdownMenuItem(value: "ALL", child: Text("All Batches (Consolidated)")),
            ...widget.batches.map(
              (b) => DropdownMenuItem(
                value: b.batch,
                child: Text("Batch: ${b.batch} (${b.adjustmentHistory.length} Adj • ${b.qty.toInt()} Qty)"),
              ),
            ),
          ],
          onChanged: (v) => setState(() => selectedBatchFilter = v ?? "ALL"),
        ),
      ),
    );
  }

  Widget _buildReasonDropdown(bool isDark, Color cardColor, Color borderColor) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selectedReasonFilter != "ALL" ? const Color(0xFFF59E0B) : borderColor,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedReasonFilter,
          dropdownColor: cardColor,
          icon: const Icon(Icons.filter_alt_rounded, color: Color(0xFFFBBF24), size: 15),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          items: const [
            DropdownMenuItem(value: "ALL", child: Text("All Reasons")),
            DropdownMenuItem(value: "Stock Correction", child: Text("Stock Correction")),
            DropdownMenuItem(value: "Breakage", child: Text("Breakage")),
            DropdownMenuItem(value: "Shortage", child: Text("Shortage")),
            DropdownMenuItem(value: "Sample", child: Text("Sample")),
            DropdownMenuItem(value: "Expiry Damage", child: Text("Expiry Damage")),
          ],
          onChanged: (v) => setState(() => selectedReasonFilter = v ?? "ALL"),
        ),
      ),
    );
  }

  Widget _buildFreezeDropdown(bool isDark, Color cardColor, Color borderColor) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _freezeOption != BatchAuditFreezeOption.none
              ? const Color(0xFF38BDF8).withOpacity(0.6)
              : borderColor,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<BatchAuditFreezeOption>(
          value: _freezeOption,
          dropdownColor: cardColor,
          icon: const Icon(Icons.ac_unit_rounded, color: Color(0xFF38BDF8), size: 15),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          items: const [
            DropdownMenuItem(value: BatchAuditFreezeOption.none, child: Text("No Freeze")),
            DropdownMenuItem(value: BatchAuditFreezeOption.srAndBatch, child: Text("Freeze: SR + Batch")),
            DropdownMenuItem(value: BatchAuditFreezeOption.srBatchAndExp, child: Text("Freeze: SR + Batch + Exp")),
            DropdownMenuItem(value: BatchAuditFreezeOption.srBatchAndDate, child: Text("Freeze: SR + Batch + Date")),
            DropdownMenuItem(
              value: BatchAuditFreezeOption.srBatchDateAndPrev,
              child: Text("Freeze: SR + Batch + Date + Prev"),
            ),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _freezeOption = val;
                if (val != BatchAuditFreezeOption.none) {
                  _lastNonZeroFreeze = val;
                }
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFF87171),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      onPressed: () {
        searchController.clear();
        setState(() {
          _searchQuery = "";
          selectedBatchFilter = "ALL";
          selectedReasonFilter = "ALL";
          activeQuickChip = "ALL";
        });
      },
      icon: const Icon(Icons.restart_alt_rounded, size: 15),
      label: const Text("RESET", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Widget _quickFilterChip(String key, String label, bool isDark) {
    final bool isSelected = activeQuickChip == key;
    return InkWell(
      onTap: () => setState(() => activeQuickChip = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0F766E)
              : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2DD4BF)
                : (isDark ? Colors.white10 : Colors.black12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 4. SMOOTH STOCK-STYLE FROZEN & SCROLLABLE HEADERS + ROWS
  // ===========================================================================
  Widget _buildFrozenHeader(List<BatchAuditColumnId> cols, bool isDark, bool isPortrait) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.indigo.shade100.withOpacity(0.7),
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12, width: 1.5),
        ),
      ),
      child: Row(
        children: cols.map((colKey) {
          final def = _columnDefs[colKey]!;
          return _headerCell(def, _effectiveColWidth(colKey, isPortrait), isDark, isFrozenCol: true);
        }).toList(),
      ),
    );
  }

  Widget _buildScrollableHeader(List<BatchAuditColumnId> cols, bool isDark, bool isPortrait) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12, width: 1.5),
        ),
      ),
      child: Row(
        children: cols.map((colKey) {
          final def = _columnDefs[colKey]!;
          return _headerCell(def, _effectiveColWidth(colKey, isPortrait), isDark, isFrozenCol: false);
        }).toList(),
      ),
    );
  }

  Widget _headerCell(BatchAuditColumnDef def, double width, bool isDark, {bool isFrozenCol = false}) {
    final bool isSorted = _sortColumn == def.id;
    return InkWell(
      onTap: () => _onSort(def.id),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: def.isNumeric ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: def.isNumeric ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (isFrozenCol && def.id == BatchAuditColumnId.batchNo) ...[
              const Icon(Icons.push_pin_rounded, size: 11, color: Color(0xFF38BDF8)),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                def.title,
                style: TextStyle(
                  color: isSorted
                      ? const Color(0xFF38BDF8)
                      : (isDark ? Colors.white70 : Colors.black87),
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSorted) ...[
              const SizedBox(width: 3),
              Icon(
                _isAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 11,
                color: const Color(0xFF38BDF8),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFrozenRow(
    DisplayAuditItem item,
    int sr,
    List<BatchAuditColumnId> cols,
    bool isDark,
    bool isPortrait,
  ) {
    final Color evenColor = isDark ? const Color(0xFF131C31) : Colors.indigo.shade50.withOpacity(0.35);
    final Color oddColor = isDark ? const Color(0xFF0F172A) : Colors.white;

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: sr % 2 == 0 ? evenColor : oddColor,
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12, width: 0.5),
        ),
      ),
      child: Row(
        children: cols.map((colKey) {
          final w = _effectiveColWidth(colKey, isPortrait);
          return _renderCell(colKey, item, sr, w, isDark);
        }).toList(),
      ),
    );
  }

  Widget _buildScrollableRow(
    DisplayAuditItem item,
    int sr,
    List<BatchAuditColumnId> cols,
    bool isDark,
    bool isPortrait,
  ) {
    final Color evenColor = isDark ? const Color(0xFF101726) : Colors.grey.shade50;
    final Color oddColor = isDark ? const Color(0xFF0A0F1D) : Colors.white;

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: sr % 2 == 0 ? evenColor : oddColor,
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12, width: 0.5),
        ),
      ),
      child: Row(
        children: cols.map((colKey) {
          final w = _effectiveColWidth(colKey, isPortrait);
          return _renderCell(colKey, item, sr, w, isDark);
        }).toList(),
      ),
    );
  }

  Widget _renderCell(
    BatchAuditColumnId colId,
    DisplayAuditItem item,
    int sr,
    double width,
    bool isDark,
  ) {
    final dStr = DateFormat('dd/MM/yyyy hh:mm a')
        .format(DateTime.fromMillisecondsSinceEpoch(item.record.timestamp));
    final bool isPos = item.record.adjustmentQty > 0;

    switch (colId) {
      case BatchAuditColumnId.srNo:
        return _cellContainer(
          width,
          Text(
            "$sr",
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey.shade600,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          isRight: true,
        );

      case BatchAuditColumnId.batchNo:
        return _cellContainer(
          width,
          InkWell(
            onTap: () => setState(() {
              selectedBatchFilter = selectedBatchFilter == item.batchNo ? "ALL" : item.batchNo;
            }),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    item.batchNo,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1E3A8A),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );

      case BatchAuditColumnId.expiry:
        return _cellContainer(
          width,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withOpacity(0.16),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.exp,
              style: const TextStyle(
                color: Color(0xFFA78BFA),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );

      case BatchAuditColumnId.liveStock:
        return _cellContainer(
          width,
          Text(
            "${item.currentBatchQty.toInt()} Qty",
            style: TextStyle(
              color: item.currentBatchQty > 0 ? const Color(0xFF38BDF8) : Colors.redAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          isRight: true,
        );

      case BatchAuditColumnId.dateTime:
        return _cellContainer(
          width,
          Text(
            dStr,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        );

      case BatchAuditColumnId.prevQty:
        return _cellContainer(
          width,
          Text(
            "${item.record.previousQty.toInt()} Qty",
            style: TextStyle(
              color: isDark ? Colors.white60 : Colors.grey.shade700,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          isRight: true,
        );

      case BatchAuditColumnId.adjQty:
        return _cellContainer(
          width,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isPos
                  ? const Color(0xFF10B981).withOpacity(0.18)
                  : const Color(0xFFEF4444).withOpacity(0.18),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: isPos
                    ? const Color(0xFF10B981).withOpacity(0.4)
                    : const Color(0xFFEF4444).withOpacity(0.4),
              ),
            ),
            child: Text(
              "${isPos ? '+' : ''}${item.record.adjustmentQty.toInt()} Qty",
              style: TextStyle(
                color: isPos ? const Color(0xFF34D399) : const Color(0xFFF87171),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          isRight: true,
        );

      case BatchAuditColumnId.newQty:
        return _cellContainer(
          width,
          Text(
            "${item.record.newQty.toInt()} Qty",
            style: TextStyle(
              color: item.record.newQty >= 0
                  ? (isDark ? Colors.white : Colors.black87)
                  : Colors.redAccent,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          isRight: true,
        );

      case BatchAuditColumnId.reason:
        return _cellContainer(
          width,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.16),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              item.record.reason,
              style: const TextStyle(
                color: Color(0xFFFBBF24),
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );

      case BatchAuditColumnId.adjustedBy:
        return _cellContainer(
          width,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.record.adjustedBy.toLowerCase().contains("dev")
                    ? Icons.military_tech_rounded
                    : Icons.person_rounded,
                size: 13,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  item.record.adjustedBy,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );

      case BatchAuditColumnId.auditId:
        return _cellContainer(
          width,
          Text(
            item.record.id,
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey.shade600,
              fontSize: 9.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        );
      case BatchAuditColumnId.actions:
        return _cellContainer(
          width,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
                onPressed: widget.onModifyRecord == null
                    ? null
                    : () => _showModifyAdjustmentDialog(item),
                icon: const Icon(Icons.edit_rounded, size: 12),
                label: const Text(
                  "MODIFY",
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
                onPressed: widget.onDeleteRecord == null
                    ? null
                    : () => _showDeleteAdjustmentDialog(item),
                icon: const Icon(Icons.delete_forever_rounded, size: 12),
                label: const Text(
                  "CANCEL",
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
    }
  }

  void _showModifyAdjustmentDialog(DisplayAuditItem item) {
    final bool isDark = widget.isWebTheme;
    final TextEditingController qtyC = TextEditingController(
      text: item.record.adjustmentQty % 1 == 0
          ? item.record.adjustmentQty.toInt().toString()
          : item.record.adjustmentQty.toString(),
    );
    final TextEditingController notesC = TextEditingController(text: item.record.notes);
    final List<String> reasons = [
      "Stock Correction",
      "Breakage",
      "Shortage",
      "Sample",
      "Expiry Damage",
    ];
    String selectedReason = reasons.contains(item.record.reason)
        ? item.record.reason
        : "Stock Correction";

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          final double newDelta = double.tryParse(qtyC.text.trim()) ?? 0.0;
          final double deltaDiff = newDelta - item.record.adjustmentQty;
          final double updatedEntryNewQty = item.record.previousQty + newDelta;
          final double updatedLiveStock = item.currentBatchQty + deltaDiff;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
            ),
            title: Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: Color(0xFF38BDF8), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "MODIFY BATCH ADJUSTMENT • ${item.batchNo}",
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "${widget.medicine.name} • Recorded: ${DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(item.record.timestamp))}",
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.indigo.shade100),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _dialogStatCol(
                                "PREV STOCK",
                                "${item.record.previousQty.toInt()} Qty",
                                isDark ? Colors.white70 : Colors.black87,
                                isDark,
                              ),
                              _dialogStatCol(
                                "OLD ADJ DELTA",
                                "${item.record.adjustmentQty >= 0 ? '+' : ''}${item.record.adjustmentQty.toInt()} Qty",
                                const Color(0xFFF59E0B),
                                isDark,
                              ),
                              _dialogStatCol(
                                "NEW ADJ DELTA",
                                "${newDelta >= 0 ? '+' : ''}${newDelta.toInt()} Qty",
                                newDelta >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                isDark,
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _dialogStatCol(
                                "UPDATED ENTRY STOCK",
                                "${updatedEntryNewQty.toInt()} Qty",
                                isDark ? Colors.white : Colors.indigo.shade900,
                                isDark,
                              ),
                              _dialogStatCol(
                                "CURRENT LIVE STOCK",
                                "${item.currentBatchQty.toInt()} Qty",
                                const Color(0xFF38BDF8),
                                isDark,
                              ),
                              _dialogStatCol(
                                "NEW LIVE STOCK",
                                "${updatedLiveStock.toInt()} Qty",
                                updatedLiveStock >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                isDark,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "NEW ADJUSTMENT QTY (+ TO ADD, - TO REDUCE, 0 TO CANCEL)",
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      controller: qtyC,
                      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        hintText: "e.g. +10 or -5 (0 cancels this entry)",
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        labelText: "REASON FOR ADJUSTMENT",
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: reasons
                          .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => selectedReason = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesC,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        labelText: "AUDIT REMARK / NOTES (OPTIONAL)",
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              if (widget.onDeleteRecord != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(c);
                    _showDeleteAdjustmentDialog(item);
                  },
                  icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 16),
                  label: const Text(
                    "DELETE / CANCEL ENTRY",
                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                )
              else
                const SizedBox.shrink(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text(
                      "CLOSE",
                      style: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade700),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final double val = double.tryParse(qtyC.text.trim()) ?? 0.0;
                      widget.onModifyRecord?.call(
                        batchNo: item.batchNo,
                        record: item.record,
                        newAdjQty: val,
                        newReason: selectedReason,
                        newNotes: notesC.text.trim(),
                      );
                      Navigator.pop(c);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            val == 0
                                ? "🗑️ Adjustment entry canceled & stock reverted for Batch ${item.batchNo}!"
                                : "✅ Updated adjustment for Batch ${item.batchNo} to ${val > 0 ? '+$val' : val} ($selectedReason). Synced!",
                          ),
                          backgroundColor: const Color(0xFF059669),
                        ),
                      );
                    },
                    icon: const Icon(Icons.check_circle_rounded, size: 16),
                    label: const Text(
                      "SAVE CHANGES",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogStatCol(String label, String val, Color valColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.grey.shade600,
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            color: valColor,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  void _showDeleteAdjustmentDialog(DisplayAuditItem item) {
    final bool isDark = widget.isWebTheme;
    final double revertedLiveStock = item.currentBatchQty - item.record.adjustmentQty;
    final String sign = item.record.adjustmentQty >= 0 ? "+" : "";

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "CANCEL / DELETE ADJUSTMENT • ${item.batchNo}",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Kya aap is batch adjustment entry ko cancel/delete karna chahte hain? Iska stock impact turant reverse ho jayega aur App + Web dono me sync ho jayega:",
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "• Batch: ${item.batchNo} (${widget.medicine.name})",
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "• Adjustment Entry: $sign${item.record.adjustmentQty.toInt()} Qty (${item.record.reason})",
                      style: const TextStyle(
                        color: Color(0xFFF87171),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "• Live Batch Stock: ${item.currentBatchQty.toInt()} Qty  ➔  After Cancel: ${revertedLiveStock.toInt()} Qty",
                      style: const TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(
              "KEEP ENTRY",
              style: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade700),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              widget.onDeleteRecord?.call(
                batchNo: item.batchNo,
                record: item.record,
              );
              Navigator.pop(c);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "🗑️ Canceled adjustment ($sign${item.record.adjustmentQty.toInt()} Qty) for Batch ${item.batchNo}. Stock reverted & synced!",
                  ),
                  backgroundColor: const Color(0xFFDC2626),
                ),
              );
            },
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text(
              "YES, CANCEL & REVERT STOCK",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cellContainer(double width, Widget child, {bool isRight = false}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 52, color: isDark ? Colors.white24 : Colors.black26),
          const SizedBox(height: 12),
          Text(
            "No Batch Adjustment Records Match Your Filter",
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Whenever a batch stock adjustment is applied, full row-by-row audit history appears here.",
            style: TextStyle(color: isDark ? Colors.white38 : Colors.blueGrey, fontSize: 11.5),
            textAlign: TextAlign.center,
          ),
          if (selectedBatchFilter != "ALL" ||
              selectedReasonFilter != "ALL" ||
              activeQuickChip != "ALL" ||
              _searchQuery.isNotEmpty) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () {
                searchController.clear();
                setState(() {
                  _searchQuery = "";
                  selectedBatchFilter = "ALL";
                  selectedReasonFilter = "ALL";
                  activeQuickChip = "ALL";
                });
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 16, color: Color(0xFF38BDF8)),
              label: const Text(
                "RESET ALL FILTERS",
                style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooterBar(
    int rowCount,
    int frozenCount,
    bool isDark,
    Color cardColor,
    Color borderColor,
  ) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Icon(
            frozenCount > 0 ? Icons.ac_unit_rounded : Icons.lock_open_rounded,
            size: 12,
            color: const Color(0xFF38BDF8),
          ),
          const SizedBox(width: 6),
          Text(
            frozenCount > 0
                ? "Frozen Columns: $frozenCount (Synchronized Vertical Scroll)"
                : "Unfrozen Mode: All Columns Scroll Freely",
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.blueGrey,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            "Showing $rowCount Audit Row(s) • Filter: $selectedBatchFilter",
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
