// FILE: lib/inventory_intel/app_stock/app_stock_analytics_view.dart
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_stock/models/stock_column_model.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'app_batch_traceability_view.dart';
import 'app_stock_analytics_engine.dart';
import 'app_stock_column_sheet.dart';
import 'app_stock_movement_sheet.dart';
import 'app_stock_pdf_and_export.dart';
import 'app_stock_theme.dart';
import 'app_vendor_rate_comparator_sheet.dart';

class AppStockAnalyticsView extends StatefulWidget {
  const AppStockAnalyticsView({super.key});

  @override
  State<AppStockAnalyticsView> createState() => _AppStockAnalyticsViewState();
}

class _AppStockAnalyticsViewState extends State<AppStockAnalyticsView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";
  String _selectedCompany = "ALL";
  String _activeFilter = "ALL"; // ALL, IN_STOCK, ZERO_STOCK, LOW_STOCK, HIKE_ALERT, EXPIRING

  bool _isSheetMode = false; // false = Mobile Smart Cards (Default), true = Marg Excel Sheet
  StockColumnId _sortColumn = StockColumnId.name;
  bool _isAscending = true;
  FreezePaneOption _freezeOption = FreezePaneOption.idAndName;

  final ScrollController _frozenVerticalScroll = ScrollController();
  final ScrollController _scrollableVerticalScroll = ScrollController();
  final ScrollController _horizontalScroll = ScrollController();
  bool _isSyncingScroll = false;

  late Map<StockColumnId, StockColumnDef> _columnDefs;

  @override
  void initState() {
    super.initState();
    _initColumns();
    _scrollableVerticalScroll.addListener(() {
      if (!_isSyncingScroll && _frozenVerticalScroll.hasClients) {
        if ((_frozenVerticalScroll.offset - _scrollableVerticalScroll.offset).abs() > 0.5) {
          _isSyncingScroll = true;
          _frozenVerticalScroll.jumpTo(_scrollableVerticalScroll.offset);
          _isSyncingScroll = false;
        }
      }
    });
    _frozenVerticalScroll.addListener(() {
      if (!_isSyncingScroll && _scrollableVerticalScroll.hasClients) {
        if ((_scrollableVerticalScroll.offset - _frozenVerticalScroll.offset).abs() > 0.5) {
          _isSyncingScroll = true;
          _scrollableVerticalScroll.jumpTo(_frozenVerticalScroll.offset);
          _isSyncingScroll = false;
        }
      }
    });
  }

  void _initColumns() {
    _columnDefs = {
      StockColumnId.srNo: StockColumnDef(id: StockColumnId.srNo, title: "SR", width: 42, isNumeric: true),
      StockColumnId.systemId: StockColumnDef(id: StockColumnId.systemId, title: "CODE", width: 78),
      StockColumnId.name: StockColumnDef(id: StockColumnId.name, title: "PRODUCT NAME", width: 175),
      StockColumnId.company: StockColumnDef(id: StockColumnId.company, title: "COMPANY / MFG", width: 125),
      StockColumnId.packing: StockColumnDef(id: StockColumnId.packing, title: "PACK", width: 75),
      StockColumnId.drugForm: StockColumnDef(id: StockColumnId.drugForm, title: "FORM", width: 70),
      StockColumnId.rackNo: StockColumnDef(id: StockColumnId.rackNo, title: "RACK", width: 70),
      StockColumnId.gst: StockColumnDef(id: StockColumnId.gst, title: "GST%", width: 58, isNumeric: true),
      StockColumnId.currentStock: StockColumnDef(id: StockColumnId.currentStock, title: "STOCK", width: 85, isNumeric: true),
      StockColumnId.purRate: StockColumnDef(id: StockColumnId.purRate, title: "PUR RATE", width: 90, isNumeric: true),
      StockColumnId.mrp: StockColumnDef(id: StockColumnId.mrp, title: "MRP", width: 85, isNumeric: true),
      StockColumnId.purValuation: StockColumnDef(id: StockColumnId.purValuation, title: "PUR VAL", width: 100, isNumeric: true),
      StockColumnId.mrpValuation: StockColumnDef(id: StockColumnId.mrpValuation, title: "MRP VAL", width: 100, isNumeric: true),
      StockColumnId.batchCount: StockColumnDef(id: StockColumnId.batchCount, title: "BATCHES", width: 75, isNumeric: true),
      StockColumnId.nearestExpiry: StockColumnDef(id: StockColumnId.nearestExpiry, title: "NEAR EXP", width: 88),
      StockColumnId.priceVariance: StockColumnDef(id: StockColumnId.priceVariance, title: "VENDOR", width: 95),
      StockColumnId.actions: StockColumnDef(id: StockColumnId.actions, title: "ACTIONS", width: 135),
    };
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _frozenVerticalScroll.dispose();
    _scrollableVerticalScroll.dispose();
    _horizontalScroll.dispose();
    super.dispose();
  }

  void _onSort(StockColumnId col) {
    setState(() {
      if (_sortColumn == col) {
        _isAscending = !_isAscending;
      } else {
        _sortColumn = col;
        _isAscending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    // 1. Dynamic Company Map
    final Map<String, String> companyDisplayMap = {};
    for (final c in ph.companies) {
      if (c.name.trim().isNotEmpty) {
        companyDisplayMap[c.id] = c.name.trim();
      }
    }
    for (final m in ph.medicines) {
      if (m.companyId.trim().isNotEmpty && !companyDisplayMap.containsKey(m.companyId)) {
        companyDisplayMap[m.companyId] = m.companyId.trim();
      }
    }

    // 2. Filter Medicines
    final filteredList = ph.medicines.where((m) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toUpperCase();
        final cName = AppStockAnalyticsEngine.resolveCompanyName(ph, m.companyId).toUpperCase();
        final nameMatch = m.name.toUpperCase().contains(q);
        final codeMatch = m.systemId.toUpperCase().contains(q) || m.id.toUpperCase().contains(q);
        final rackMatch = m.rackNo.toUpperCase().contains(q);
        final compMatch = cName.contains(q);
        if (!nameMatch && !codeMatch && !rackMatch && !compMatch) return false;
      }

      if (_selectedCompany != "ALL") {
        final cName = AppStockAnalyticsEngine.resolveCompanyName(ph, m.companyId).toUpperCase();
        final selUpper = _selectedCompany.toUpperCase();
        if (m.companyId.toUpperCase() != selUpper && cName != selUpper) {
          return false;
        }
      }

      if (_activeFilter == "IN_STOCK" && m.stock <= 0) return false;
      if (_activeFilter == "ZERO_STOCK" && m.stock > 0) return false;
      if (_activeFilter == "LOW_STOCK") {
        if (m.reorderLevel <= 0 || m.stock > m.reorderLevel) return false;
      }
      if (_activeFilter == "HIKE_ALERT") {
        if (!AppStockAnalyticsEngine.hasPriceHike(ph, m)) return false;
      }
      if (_activeFilter == "EXPIRING") {
        if (!AppStockAnalyticsEngine.isExpiringSoon(ph, m, days: 90)) return false;
      }

      return true;
    }).toList();

    // 3. Sort Medicines
    filteredList.sort((a, b) {
      int cmp = 0;
      switch (_sortColumn) {
        case StockColumnId.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case StockColumnId.systemId:
          cmp = a.systemId.compareTo(b.systemId);
          break;
        case StockColumnId.company:
          cmp = AppStockAnalyticsEngine.resolveCompanyName(ph, a.companyId)
              .compareTo(AppStockAnalyticsEngine.resolveCompanyName(ph, b.companyId));
          break;
        case StockColumnId.currentStock:
          cmp = a.stock.compareTo(b.stock);
          break;
        case StockColumnId.purRate:
          cmp = a.purRate.compareTo(b.purRate);
          break;
        case StockColumnId.mrp:
          cmp = a.mrp.compareTo(b.mrp);
          break;
        case StockColumnId.purValuation:
          cmp = AppStockAnalyticsEngine.computePurValuation(ph, a)
              .compareTo(AppStockAnalyticsEngine.computePurValuation(ph, b));
          break;
        case StockColumnId.mrpValuation:
          cmp = AppStockAnalyticsEngine.computeMrpValuation(ph, a)
              .compareTo(AppStockAnalyticsEngine.computeMrpValuation(ph, b));
          break;
        case StockColumnId.gst:
          cmp = a.gst.compareTo(b.gst);
          break;
        default:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _isAscending ? cmp : -cmp;
    });

    // 4. Totals
    final double totalStockUnits = filteredList.fold(0.0, (s, m) => s + m.stock);
    final double totalPurVal = filteredList.fold(
      0.0,
      (s, m) => s + AppStockAnalyticsEngine.computePurValuation(ph, m),
    );
    final double totalMrpVal = filteredList.fold(
      0.0,
      (s, m) => s + AppStockAnalyticsEngine.computeMrpValuation(ph, m),
    );
    final double marginPct = totalMrpVal > 0 ? ((totalMrpVal - totalPurVal) / totalMrpVal) * 100 : 0.0;

    return Scaffold(
      backgroundColor: MargStockTheme.canvas,
      appBar: AppBar(
        backgroundColor: MargStockTheme.headerDark,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Stock Analytics",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              "Marg Workbench • FY ${ph.currentFY.isNotEmpty ? ph.currentFY : 'Active'}",
              style: const TextStyle(fontSize: 10.5, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _isSheetMode ? "Switch to Card View" : "Switch to Excel Sheet View",
            icon: Icon(_isSheetMode ? Icons.view_agenda_rounded : Icons.table_chart_rounded),
            onPressed: () => setState(() => _isSheetMode = !_isSheetMode),
          ),
          IconButton(
            tooltip: "Sort Items",
            icon: const Icon(Icons.sort_rounded),
            onPressed: _showSortSheet,
          ),
          PopupMenuButton<String>(
            tooltip: "Export & Sheet Options",
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              if (value == "COLUMNS") {
                _openColumnConfig();
              } else if (value == "PRINT_PDF") {
                await _printValuationPdf(filteredList, ph);
              } else if (value == "SAVE_CSV") {
                await _saveCsv(filteredList, ph);
              } else if (value == "SHARE_CSV") {
                await _shareCsv(filteredList, ph);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: "PRINT_PDF",
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.print_rounded, color: MargStockTheme.headerDark),
                  title: Text("Print Valuation PDF"),
                ),
              ),
              const PopupMenuItem(
                value: "SAVE_CSV",
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.download_rounded, color: MargStockTheme.stockOk),
                  title: Text("Export Excel / CSV"),
                ),
              ),
              const PopupMenuItem(
                value: "SHARE_CSV",
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.share_rounded, color: MargStockTheme.codeBlue),
                  title: Text("Share CSV Report"),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: "COLUMNS",
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.view_column_rounded, color: MargStockTheme.goldBorder),
                  title: Text("Sheet Columns & Freeze"),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Marg Horizontal 5-KPI Ribbon
          Container(
            color: MargStockTheme.headerDark,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _kpiPill("ITEMS", "${filteredList.length}", Colors.white),
                  const SizedBox(width: 8),
                  _kpiPill("STOCK QTY", formatQty(totalStockUnits), const Color(0xFF6EE7B7)),
                  const SizedBox(width: 8),
                  _kpiPill("PUR. VAL", "₹${totalPurVal.toStringAsFixed(0)}", const Color(0xFFFDE68A)),
                  const SizedBox(width: 8),
                  _kpiPill("MRP VAL", "₹${totalMrpVal.toStringAsFixed(0)}", const Color(0xFF93C5FD)),
                  const SizedBox(width: 8),
                  _kpiPill("MARGIN", "${marginPct.toStringAsFixed(1)}%", const Color(0xFFA7F3D0)),
                ],
              ),
            ),
          ),

          // 2. Search + Company Picker + Quick Mode Bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: const BoxDecoration(
              color: MargStockTheme.cardBg,
              border: Border(bottom: BorderSide(color: MargStockTheme.border)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(fontSize: 13, color: MargStockTheme.textPrimary),
                        decoration: InputDecoration(
                          hintText: "Search name, code, rack, mfg...",
                          hintStyle: const TextStyle(fontSize: 12, color: MargStockTheme.textMuted),
                          prefixIcon: const Icon(Icons.search_rounded, size: 19, color: MargStockTheme.headerMid),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = "");
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: MargStockTheme.canvas,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                            borderSide: const BorderSide(color: MargStockTheme.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                            borderSide: const BorderSide(color: MargStockTheme.border),
                          ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v.trim()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _showCompanyPickerSheet(companyDisplayMap, ph),
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        height: 40,
                        constraints: const BoxConstraints(maxWidth: 145),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: _selectedCompany == "ALL" ? MargStockTheme.canvas : MargStockTheme.goldBg,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: _selectedCompany == "ALL" ? MargStockTheme.border : MargStockTheme.goldBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.business_rounded,
                              size: 16,
                              color: _selectedCompany == "ALL"
                                  ? MargStockTheme.headerDark
                                  : MargStockTheme.goldText,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _selectedCompany == "ALL" ? "All Mfg" : _selectedCompany,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedCompany == "ALL"
                                      ? MargStockTheme.textPrimary
                                      : MargStockTheme.goldText,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 3. 6 Status Filter Chips + View Mode Quick Pill
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _filterChip("ALL", "All (${ph.medicines.length})"),
                      const SizedBox(width: 6),
                      _filterChip("IN_STOCK", "In Stock (>0)"),
                      const SizedBox(width: 6),
                      _filterChip("ZERO_STOCK", "Zero (=0)"),
                      const SizedBox(width: 6),
                      _filterChip("LOW_STOCK", "Low Stock"),
                      const SizedBox(width: 6),
                      _filterChip("HIKE_ALERT", "Rate Hike"),
                      const SizedBox(width: 6),
                      _filterChip("EXPIRING", "Expiring <90d"),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Main Content: Card Mode (Default) OR Marg Excel Sheet Mode
          Expanded(
            child: filteredList.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 48, color: MargStockTheme.textMuted),
                        SizedBox(height: 8),
                        Text(
                          "No inventory items match your filters",
                          style: TextStyle(
                            color: MargStockTheme.textMuted,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : _isSheetMode
                    ? _buildMargExcelSheet(filteredList, ph)
                    : _buildMobileCardList(filteredList, ph),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MODE 1: MOBILE-FIRST MARG STOCK CARDS
  // ===========================================================================
  Widget _buildMobileCardList(List<Medicine> filteredList, PharoahManager ph) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      itemCount: filteredList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (context, index) {
        final m = filteredList[index];
        final cName = AppStockAnalyticsEngine.resolveCompanyName(ph, m.companyId);
        final purVal = AppStockAnalyticsEngine.computePurValuation(ph, m);
        final mrpVal = AppStockAnalyticsEngine.computeMrpValuation(ph, m);
        final batches = ph.getBatchesForMedicine(m);
        final activeBatches = batches.where((b) => b.qty > 0).length;
        final nearestExp = AppStockAnalyticsEngine.getNearestExpiry(ph, m);
        final hasHike = AppStockAnalyticsEngine.hasPriceHike(ph, m);
        final isExpiring = AppStockAnalyticsEngine.isExpiringSoon(ph, m, days: 90);
        final isLow = m.stock > 0 && m.reorderLevel > 0 && m.stock <= m.reorderLevel;

        Color stockColor = MargStockTheme.stockOk;
        Color stockBg = MargStockTheme.stockOkBg;
        if (m.stock <= 0) {
          stockColor = MargStockTheme.stockAlert;
          stockBg = MargStockTheme.stockAlertBg;
        } else if (isLow) {
          stockColor = MargStockTheme.stockLow;
          stockBg = MargStockTheme.stockLowBg;
        }

        return Container(
          decoration: BoxDecoration(
            color: MargStockTheme.cardBg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: hasHike ? MargStockTheme.stockAlert.withOpacity(0.45) : MargStockTheme.border,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + Code + Packing
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.name,
                                style: const TextStyle(
                                  color: MargStockTheme.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  MargStockTheme.badge(
                                    label: m.systemId.isNotEmpty ? m.systemId : m.id,
                                    fg: MargStockTheme.codeBlue,
                                    bg: MargStockTheme.codeBlueBg,
                                  ),
                                  if (m.packing.isNotEmpty)
                                    MargStockTheme.badge(
                                      label: m.packing,
                                      fg: MargStockTheme.headerDark,
                                      bg: MargStockTheme.accentLight,
                                    ),
                                  if (hasHike)
                                    MargStockTheme.badge(
                                      label: "RATE HIKE",
                                      fg: MargStockTheme.stockAlert,
                                      bg: MargStockTheme.stockAlertBg,
                                      icon: Icons.trending_up_rounded,
                                    ),
                                  if (isExpiring)
                                    MargStockTheme.badge(
                                      label: "EXP: $nearestExp",
                                      fg: MargStockTheme.stockLow,
                                      bg: MargStockTheme.stockLowBg,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: stockBg,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: stockColor.withOpacity(0.35)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatQty(m.stock),
                                style: MargStockTheme.tabularNum.copyWith(color: stockColor, fontSize: 14),
                              ),
                              Text(
                                m.stock <= 0 ? "ZERO" : (isLow ? "LOW" : "STOCK"),
                                style: TextStyle(color: stockColor, fontSize: 8.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    // Sub-details: Company, Rack, Batches, Nearest Expiry
                    Text(
                      "$cName  •  Rack: ${m.rackNo.isNotEmpty ? m.rackNo : '-'}  •  $activeBatches Batch(es)  •  Exp: $nearestExp",
                      style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // 4-Column Marg Valuation Strip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: MargStockTheme.zebraRow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: MargStockTheme.divider),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _cardMetric("PUR RATE", "₹${m.purRate.toStringAsFixed(2)}", MargStockTheme.textPrimary),
                          _cardMetric("MRP", "₹${m.mrp.toStringAsFixed(2)}", MargStockTheme.textPrimary),
                          _cardMetric("PUR VAL", "₹${purVal.toStringAsFixed(0)}", MargStockTheme.valuationPurple),
                          _cardMetric("MRP VAL", "₹${mrpVal.toStringAsFixed(0)}", MargStockTheme.headerDark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: MargStockTheme.divider),
              // 3 Deep Action Buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: MargStockTheme.codeBlue,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AppStockMovementSheet(medicine: m, companyName: cName),
                            ),
                          );
                        },
                        icon: const Icon(Icons.history_rounded, size: 16),
                        label: const Text("Passbook", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    Container(width: 1, height: 18, color: MargStockTheme.divider),
                    Expanded(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: MargStockTheme.stockOk,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AppVendorRateComparatorSheet(medicine: m, companyName: cName),
                            ),
                          );
                        },
                        icon: const Icon(Icons.compare_arrows_rounded, size: 16),
                        label: const Text("Vendors", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    Container(width: 1, height: 18, color: MargStockTheme.divider),
                    Expanded(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: MargStockTheme.headerDark,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AppBatchTraceabilityView(medicine: m),
                            ),
                          );
                        },
                        icon: const Icon(Icons.layers_outlined, size: 16),
                        label: const Text("Batches", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // MODE 2: TOGGLEABLE MARG EXCEL SHEET VIEW (FROZEN LEFT + HORIZONTAL SCROLL)
  // ===========================================================================
  Widget _buildMargExcelSheet(List<Medicine> filteredList, PharoahManager ph) {
    final frozenColKeys = <StockColumnId>[];
    if (_freezeOption == FreezePaneOption.idAndName) {
      frozenColKeys.addAll([StockColumnId.srNo, StockColumnId.systemId, StockColumnId.name]);
    } else if (_freezeOption == FreezePaneOption.idNameAndCompany) {
      frozenColKeys.addAll([StockColumnId.srNo, StockColumnId.systemId, StockColumnId.name, StockColumnId.company]);
    } else if (_freezeOption == FreezePaneOption.idNameAndPack) {
      frozenColKeys.addAll([StockColumnId.srNo, StockColumnId.systemId, StockColumnId.name, StockColumnId.packing]);
    }

    final visibleFrozenCols = frozenColKeys.where((k) => _columnDefs[k]?.isVisible ?? true).toList();
    final visibleScrollableCols = _columnDefs.keys
        .where((k) => !frozenColKeys.contains(k) && (_columnDefs[k]?.isVisible ?? true))
        .toList();

    final double frozenPaneWidth = visibleFrozenCols.fold(0.0, (w, k) => w + _colWidth(k));
    final double scrollablePaneWidth = visibleScrollableCols.fold(0.0, (w, k) => w + _colWidth(k));

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            if (visibleFrozenCols.isNotEmpty)
              Container(
                width: frozenPaneWidth.clamp(0.0, constraints.maxWidth * 0.62),
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: MargStockTheme.headerMid, width: 1.5)),
                ),
                child: Column(
                  children: [
                    _sheetHeader(visibleFrozenCols),
                    Expanded(
                      child: ListView.builder(
                        controller: _frozenVerticalScroll,
                        physics: const ClampingScrollPhysics(),
                        itemCount: filteredList.length,
                        itemExtent: 44,
                        itemBuilder: (context, i) => _sheetRow(filteredList[i], i + 1, visibleFrozenCols, ph),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                controller: _horizontalScroll,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: scrollablePaneWidth,
                  height: constraints.maxHeight,
                  child: Column(
                    children: [
                      _sheetHeader(visibleScrollableCols),
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollableVerticalScroll,
                          physics: const ClampingScrollPhysics(),
                          itemCount: filteredList.length,
                          itemExtent: 44,
                          itemBuilder: (context, i) => _sheetRow(filteredList[i], i + 1, visibleScrollableCols, ph),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  double _colWidth(StockColumnId id) {
    final base = _columnDefs[id]?.width ?? 80.0;
    if (id == StockColumnId.name) return 145.0;
    if (id == StockColumnId.systemId) return 70.0;
    return base;
  }

  Widget _sheetHeader(List<StockColumnId> cols) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: MargStockTheme.headerBand,
        border: Border(bottom: BorderSide(color: MargStockTheme.headerMid, width: 1.4)),
      ),
      child: Row(
        children: cols.map((colKey) {
          final def = _columnDefs[colKey]!;
          final bool isSorted = _sortColumn == def.id;
          return InkWell(
            onTap: () => _onSort(def.id),
            child: Container(
              width: _colWidth(colKey),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: def.isNumeric ? Alignment.centerRight : Alignment.centerLeft,
              child: Row(
                mainAxisAlignment: def.isNumeric ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      def.title,
                      style: TextStyle(
                        color: isSorted ? MargStockTheme.headerDark : MargStockTheme.textSecondary,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSorted) ...[
                    const SizedBox(width: 2),
                    Icon(
                      _isAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 11,
                      color: MargStockTheme.headerDark,
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _sheetRow(Medicine m, int sr, List<StockColumnId> cols, PharoahManager ph) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: sr % 2 == 0 ? MargStockTheme.zebraRow : MargStockTheme.cardBg,
        border: const Border(bottom: BorderSide(color: MargStockTheme.divider, width: 0.7)),
      ),
      child: Row(
        children: cols.map((colKey) => _sheetCell(colKey, m, sr, _colWidth(colKey), ph)).toList(),
      ),
    );
  }

  Widget _sheetCell(StockColumnId colId, Medicine m, int sr, double width, PharoahManager ph) {
    final cName = AppStockAnalyticsEngine.resolveCompanyName(ph, m.companyId);
    switch (colId) {
      case StockColumnId.srNo:
        return _cellBox(width, Text("$sr", style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 10.5)), isRight: true);
      case StockColumnId.systemId:
        return _cellBox(
          width,
          Text(
            m.systemId.isNotEmpty ? m.systemId : m.id,
            style: const TextStyle(color: MargStockTheme.codeBlue, fontSize: 10.5, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        );
      case StockColumnId.name:
        return _cellBox(
          width,
          Text(
            m.name,
            style: const TextStyle(color: MargStockTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        );
      case StockColumnId.company:
        return _cellBox(
          width,
          Text(cName, style: const TextStyle(color: MargStockTheme.textSecondary, fontSize: 10.5), overflow: TextOverflow.ellipsis),
        );
      case StockColumnId.packing:
        return _cellBox(
          width,
          MargStockTheme.badge(
            label: m.packing,
            fg: MargStockTheme.headerDark,
            bg: MargStockTheme.accentLight,
          ),
        );
      case StockColumnId.drugForm:
        return _cellBox(width, Text(m.drugForm, style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 10.5)));
      case StockColumnId.rackNo:
        return _cellBox(width, Text(m.rackNo.isNotEmpty ? m.rackNo : "-", style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 10.5)));
      case StockColumnId.gst:
        return _cellBox(width, Text("${m.gst.toInt()}%", style: const TextStyle(color: MargStockTheme.textSecondary, fontSize: 10.5)), isRight: true);
      case StockColumnId.currentStock:
        Color sColor = MargStockTheme.stockOk;
        if (m.stock <= 0) {
          sColor = MargStockTheme.stockAlert;
        } else if (m.reorderLevel > 0 && m.stock <= m.reorderLevel) {
          sColor = MargStockTheme.stockLow;
        }
        return _cellBox(
          width,
          Text(formatQty(m.stock), style: MargStockTheme.tabularNum.copyWith(color: sColor, fontSize: 11.5)),
          isRight: true,
        );
      case StockColumnId.purRate:
        return _cellBox(width, Text("₹${m.purRate.toStringAsFixed(2)}", style: MargStockTheme.tabularNum.copyWith(fontSize: 10.5)), isRight: true);
      case StockColumnId.mrp:
        return _cellBox(width, Text("₹${m.mrp.toStringAsFixed(2)}", style: MargStockTheme.tabularNum.copyWith(fontSize: 10.5)), isRight: true);
      case StockColumnId.purValuation:
        final val = AppStockAnalyticsEngine.computePurValuation(ph, m);
        return _cellBox(width, Text("₹${val.toStringAsFixed(0)}", style: MargStockTheme.tabularNum.copyWith(color: MargStockTheme.valuationPurple, fontSize: 10.5)), isRight: true);
      case StockColumnId.mrpValuation:
        final val = AppStockAnalyticsEngine.computeMrpValuation(ph, m);
        return _cellBox(width, Text("₹${val.toStringAsFixed(0)}", style: MargStockTheme.tabularNum.copyWith(color: MargStockTheme.headerDark, fontSize: 10.5)), isRight: true);
      case StockColumnId.batchCount:
        final count = ph.getBatchesForMedicine(m).where((b) => b.qty > 0).length;
        return _cellBox(width, Text("$count", style: const TextStyle(color: MargStockTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)), isRight: true);
      case StockColumnId.nearestExpiry:
        final exp = AppStockAnalyticsEngine.getNearestExpiry(ph, m);
        return _cellBox(width, Text(exp, style: const TextStyle(color: MargStockTheme.textSecondary, fontSize: 10.5)));
      case StockColumnId.priceVariance:
        final hasHike = AppStockAnalyticsEngine.hasPriceHike(ph, m);
        return _cellBox(
          width,
          hasHike
              ? MargStockTheme.badge(label: "HIKE", fg: MargStockTheme.stockAlert, bg: MargStockTheme.stockAlertBg)
              : const Text("Stable", style: TextStyle(color: MargStockTheme.textMuted, fontSize: 10.5)),
        );
      case StockColumnId.actions:
        return _cellBox(
          width,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.history_rounded, size: 17, color: MargStockTheme.codeBlue),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AppStockMovementSheet(medicine: m, companyName: cName)),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.compare_arrows_rounded, size: 17, color: MargStockTheme.stockOk),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AppVendorRateComparatorSheet(medicine: m, companyName: cName)),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.layers_outlined, size: 17, color: MargStockTheme.headerDark),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AppBatchTraceabilityView(medicine: m)),
                  );
                },
              ),
            ],
          ),
        );
    }
  }

  Widget _cellBox(double width, Widget child, {bool isRight = false}) {
    return Container(
      width: width,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
  }

  // ===========================================================================
  // MODALS & PICKERS
  // ===========================================================================
  void _openColumnConfig() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AppStockColumnSheet(
        columnDefs: _columnDefs,
        currentFreeze: _freezeOption,
        onApply: (newDefs, newFreeze) {
          setState(() {
            _columnDefs = newDefs;
            _freezeOption = newFreeze;
            _isSheetMode = true;
          });
        },
      ),
    );
  }

  void _showCompanyPickerSheet(Map<String, String> companyDisplayMap, PharoahManager ph) {
    final companies = companyDisplayMap.values.toSet().toList()..sort();
    String compQuery = "";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final visible = companies
              .where((name) => compQuery.isEmpty || name.toLowerCase().contains(compQuery.toLowerCase()))
              .toList();
          return Container(
            height: MediaQuery.of(context).size.height * 0.72,
            decoration: const BoxDecoration(
              color: MargStockTheme.cardBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  decoration: const BoxDecoration(
                    color: MargStockTheme.headerDark,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.business_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Filter by Manufacturer / Company",
                          style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(c),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: "Search company name...",
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      filled: true,
                      fillColor: MargStockTheme.canvas,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
                    ),
                    onChanged: (v) => setSheet(() => compQuery = v.trim()),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.all_inclusive_rounded, color: MargStockTheme.headerDark),
                        title: const Text("All Companies", style: TextStyle(fontWeight: FontWeight.bold)),
                        trailing: _selectedCompany == "ALL"
                            ? const Icon(Icons.check_circle_rounded, color: MargStockTheme.stockOk)
                            : null,
                        onTap: () {
                          setState(() => _selectedCompany = "ALL");
                          Navigator.pop(c);
                        },
                      ),
                      const Divider(height: 1),
                      ...visible.map((name) {
                        final isSel = _selectedCompany.toUpperCase() == name.toUpperCase();
                        return ListTile(
                          title: Text(name, style: TextStyle(fontWeight: isSel ? FontWeight.bold : FontWeight.w500)),
                          trailing: isSel
                              ? const Icon(Icons.check_circle_rounded, color: MargStockTheme.stockOk)
                              : null,
                          onTap: () {
                            setState(() => _selectedCompany = name);
                            Navigator.pop(c);
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSortSheet() {
    final options = <({StockColumnId col, String label})>[
      (col: StockColumnId.name, label: "Product Name"),
      (col: StockColumnId.currentStock, label: "Current Stock Qty"),
      (col: StockColumnId.purValuation, label: "Purchase Valuation"),
      (col: StockColumnId.mrpValuation, label: "MRP Valuation"),
      (col: StockColumnId.purRate, label: "Purchase Rate"),
      (col: StockColumnId.mrp, label: "MRP"),
      (col: StockColumnId.company, label: "Company / Mfg"),
      (col: StockColumnId.systemId, label: "Item Code"),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: MargStockTheme.cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: MargStockTheme.headerDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sort_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text("Sort Inventory By", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _isAscending = !_isAscending);
                      Navigator.pop(c);
                    },
                    icon: Icon(
                      _isAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      color: Colors.amberAccent,
                      size: 16,
                    ),
                    label: Text(
                      _isAscending ? "ASC" : "DESC",
                      style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            ...options.map((opt) {
              final isSel = _sortColumn == opt.col;
              return ListTile(
                dense: true,
                title: Text(opt.label, style: TextStyle(fontWeight: isSel ? FontWeight.bold : FontWeight.w500)),
                trailing: isSel
                    ? Icon(
                        _isAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        color: MargStockTheme.headerDark,
                      )
                    : null,
                onTap: () {
                  _onSort(opt.col);
                  Navigator.pop(c);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _printValuationPdf(List<Medicine> filteredList, PharoahManager ph) async {
    final bytes = await AppStockPdfAndExport.generateStockValuationPdfBytes(
      medicines: filteredList,
      ph: ph,
      selectedCompanyName: _selectedCompany == "ALL" ? "All Companies" : _selectedCompany,
      filterTag: _activeFilter,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: "Stock_Report_${DateTime.now().millisecondsSinceEpoch}",
      format: PdfPageFormat.a4.landscape,
    );
  }

  Future<void> _saveCsv(List<Medicine> filteredList, PharoahManager ph) async {
    await AppStockPdfAndExport.saveStockCsv(
      medicines: filteredList,
      ph: ph,
      selectedCompanyName: _selectedCompany == "ALL" ? "All Companies" : _selectedCompany,
      activeFilter: _activeFilter,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Stock CSV exported successfully!"),
        backgroundColor: MargStockTheme.stockOk,
      ),
    );
  }

  Future<void> _shareCsv(List<Medicine> filteredList, PharoahManager ph) async {
    await AppStockPdfAndExport.shareStockCsv(
      medicines: filteredList,
      ph: ph,
      selectedCompanyName: _selectedCompany == "ALL" ? "All Companies" : _selectedCompany,
      activeFilter: _activeFilter,
    );
  }

  Widget _kpiPill(String label, String val, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 8.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 1),
          Text(
            val,
            style: MargStockTheme.tabularNum.copyWith(color: valueColor, fontSize: 13.5),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final bool isSel = _activeFilter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSel ? Colors.white : MargStockTheme.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      selected: isSel,
      selectedColor: MargStockTheme.headerDark,
      backgroundColor: MargStockTheme.canvas,
      side: BorderSide(color: isSel ? MargStockTheme.headerDark : MargStockTheme.border),
      onSelected: (_) => setState(() => _activeFilter = key),
    );
  }

  Widget _cardMetric(String label, String val, Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 1),
        Text(val, style: MargStockTheme.tabularNum.copyWith(color: c, fontSize: 12)),
      ],
    );
  }
}
