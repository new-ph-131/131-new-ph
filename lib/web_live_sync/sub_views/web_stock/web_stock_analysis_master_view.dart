// Responsive layout updated
// FILE: lib/web_live_sync/sub_views/web_stock/web_stock_analysis_master_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/web_models.dart';
import 'models/stock_column_model.dart';
import 'components/stock_column_config_dialog.dart';
import 'components/stock_vendor_rate_comparator_modal.dart';
import 'components/stock_movement_ledger_modal.dart';
import 'services/stock_excel_export_service.dart';
import 'pdf/web_stock_analysis_pdf.dart';
import 'product_batch_traceability_screen.dart';

class WebStockAnalysisMasterView extends StatefulWidget {
  final VoidCallback onBack;
  final String initialViewKey;

  const WebStockAnalysisMasterView({
    super.key,
    required this.onBack,
    this.initialViewKey = "GO_STOCK",
  });

  @override
  State<WebStockAnalysisMasterView> createState() => _WebStockAnalysisMasterViewState();
}

class _WebStockAnalysisMasterViewState extends State<WebStockAnalysisMasterView> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _frozenVerticalScroll = ScrollController();
  final ScrollController _scrollableVerticalScroll = ScrollController();
  final ScrollController _horizontalScroll = ScrollController();

  String _searchQuery = "";
  String _selectedCompany = "ALL"; // "ALL" or specific company name/id
  String _activeFilter = "ALL"; // ALL, IN_STOCK, ZERO_STOCK, LOW_STOCK, HIKE_ALERT, EXPIRING
  
  StockColumnId _sortColumn = StockColumnId.name;
  bool _isAscending = true;
  FreezePaneOption _freezeOption = FreezePaneOption.idAndName;

  Medicine? _batchTraceabilityMed;

  // Column definitions with initial defaults
  late Map<StockColumnId, StockColumnDef> _columnDefs;

  @override
  void initState() {
    super.initState();
    _initColumns();

    // Link vertical scrolling between frozen and non-frozen panes
    _scrollableVerticalScroll.addListener(() {
      if (_frozenVerticalScroll.hasClients &&
          _frozenVerticalScroll.offset != _scrollableVerticalScroll.offset) {
        _frozenVerticalScroll.jumpTo(_scrollableVerticalScroll.offset);
      }
    });
    _frozenVerticalScroll.addListener(() {
      if (_scrollableVerticalScroll.hasClients &&
          _scrollableVerticalScroll.offset != _frozenVerticalScroll.offset) {
        _scrollableVerticalScroll.jumpTo(_frozenVerticalScroll.offset);
      }
    });
  }

  void _initColumns() {
    _columnDefs = {
      StockColumnId.srNo: StockColumnDef(id: StockColumnId.srNo, title: "SR", width: 50, isNumeric: true),
      StockColumnId.systemId: StockColumnDef(id: StockColumnId.systemId, title: "ITEM CODE", width: 95),
      StockColumnId.name: StockColumnDef(id: StockColumnId.name, title: "PRODUCT NAME", width: 220),
      StockColumnId.company: StockColumnDef(id: StockColumnId.company, title: "COMPANY / MFG", width: 140),
      StockColumnId.packing: StockColumnDef(id: StockColumnId.packing, title: "PACK", width: 80),
      StockColumnId.drugForm: StockColumnDef(id: StockColumnId.drugForm, title: "FORM", width: 75),
      StockColumnId.rackNo: StockColumnDef(id: StockColumnId.rackNo, title: "RACK", width: 75),
      StockColumnId.gst: StockColumnDef(id: StockColumnId.gst, title: "GST%", width: 65, isNumeric: true),
      StockColumnId.currentStock: StockColumnDef(id: StockColumnId.currentStock, title: "STOCK", width: 90, isNumeric: true),
      StockColumnId.purRate: StockColumnDef(id: StockColumnId.purRate, title: "PUR. RATE", width: 100, isNumeric: true),
      StockColumnId.mrp: StockColumnDef(id: StockColumnId.mrp, title: "MRP", width: 95, isNumeric: true),
      StockColumnId.purValuation: StockColumnDef(id: StockColumnId.purValuation, title: "PUR. VAL", width: 110, isNumeric: true),
      StockColumnId.mrpValuation: StockColumnDef(id: StockColumnId.mrpValuation, title: "MRP VAL", width: 110, isNumeric: true),
      StockColumnId.batchCount: StockColumnDef(id: StockColumnId.batchCount, title: "BATCHES", width: 85, isNumeric: true),
      StockColumnId.nearestExpiry: StockColumnDef(id: StockColumnId.nearestExpiry, title: "NEAR EXPIRY", width: 105),
      StockColumnId.priceVariance: StockColumnDef(id: StockColumnId.priceVariance, title: "VENDOR INTEL", width: 115),
      StockColumnId.actions: StockColumnDef(id: StockColumnId.actions, title: "AUDIT & ACTIONS", width: 165),
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

  String _resolveCompanyName(PharoahWebManager webPh, String companyId) {
    if (companyId.isEmpty) return "Unassigned";
    try {
      return webPh.companies
          .firstWhere((c) => c.id == companyId || c.name.toUpperCase() == companyId.toUpperCase())
          .name;
    } catch (_) {
      return companyId;
    }
  }

  bool _hasPriceHike(PharoahWebManager webPh, Medicine med) {
    final cleanName = med.name.trim().toUpperCase();
    final matchingInwards = <Map<String, dynamic>>[];
    for (var p in webPh.purchases) {
      for (var it in p.items) {
        if (it.medicineID == med.id || it.name.trim().toUpperCase() == cleanName) {
          matchingInwards.add({'date': p.date, 'rate': it.purchaseRate});
        }
      }
    }
    if (matchingInwards.length < 2) return false;
    matchingInwards.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    return matchingInwards.last['rate'] > matchingInwards.first['rate'];
  }

  String _getNearestExpiry(PharoahWebManager webPh, Medicine med) {
    final batches = webPh.batchHistory[med.identityKey] ?? [];
    final active = batches.where((b) => b.qty > 0 && b.exp.trim().isNotEmpty).toList();
    if (active.isEmpty) return "-";
    active.sort((a, b) => a.exp.compareTo(b.exp));
    return active.first.exp;
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
    final webPh = Provider.of<PharoahWebManager>(context);

    // If user clicked into batch traceability view
    if (_batchTraceabilityMed != null) {
      return ProductBatchTraceabilityScreen(
        medicine: _batchTraceabilityMed!,
        onBack: () => setState(() => _batchTraceabilityMed = null),
      );
    }

    // 1. Build dynamic list of companies
    final Map<String, String> companyDisplayMap = {};
    for (var c in webPh.companies) {
      if (c.name.trim().isNotEmpty) {
        companyDisplayMap[c.id] = c.name.trim();
      }
    }
    for (var m in webPh.medicines) {
      if (m.companyId.trim().isNotEmpty && !companyDisplayMap.containsKey(m.companyId)) {
        companyDisplayMap[m.companyId] = m.companyId.trim();
      }
    }

    // 2. Filter Medicines
    final filteredList = webPh.medicines.where((m) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toUpperCase();
        final cName = _resolveCompanyName(webPh, m.companyId).toUpperCase();
        bool nameMatch = m.name.toUpperCase().contains(q);
        bool codeMatch = m.systemId.toUpperCase().contains(q) || m.id.toUpperCase().contains(q);
        bool rackMatch = m.rackNo.toUpperCase().contains(q);
        bool compMatch = cName.contains(q);
        if (!nameMatch && !codeMatch && !rackMatch && !compMatch) return false;
      }

      // Company filter
      if (_selectedCompany != "ALL") {
        final cName = _resolveCompanyName(webPh, m.companyId).toUpperCase();
        final selectedUpper = _selectedCompany.toUpperCase();
        if (m.companyId.toUpperCase() != selectedUpper && cName != selectedUpper) {
          return false;
        }
      }

      // Status Filter Chips
      if (_activeFilter == "IN_STOCK" && m.stock <= 0) return false;
      if (_activeFilter == "ZERO_STOCK" && m.stock > 0) return false;
      if (_activeFilter == "LOW_STOCK") {
        if (m.reorderLevel <= 0 || m.stock > m.reorderLevel) return false;
      }
      if (_activeFilter == "HIKE_ALERT") {
        if (!_hasPriceHike(webPh, m)) return false;
      }
      if (_activeFilter == "EXPIRING") {
        final exp = _getNearestExpiry(webPh, m);
        if (exp == "-") return false;
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
          cmp = _resolveCompanyName(webPh, a.companyId).compareTo(_resolveCompanyName(webPh, b.companyId));
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
          cmp = (a.stock * a.purRate).compareTo(b.stock * b.purRate);
          break;
        case StockColumnId.mrpValuation:
          cmp = (a.stock * a.mrp).compareTo(b.stock * b.mrp);
          break;
        case StockColumnId.gst:
          cmp = a.gst.compareTo(b.gst);
          break;
        default:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _isAscending ? cmp : -cmp;
    });

    // 4. Compute Totals
    double totalStockUnits = filteredList.fold(0.0, (s, m) => s + m.stock);
    double totalPurVal = filteredList.fold(0.0, (s, m) => s + (m.stock * m.purRate));
    double totalMrpVal = filteredList.fold(0.0, (s, m) => s + (m.stock * m.mrp));
    double marginPct = totalMrpVal > 0 ? ((totalMrpVal - totalPurVal) / totalMrpVal) * 100 : 0.0;

    // 5. Partition columns into Frozen vs Scrollable based on _freezeOption
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

    double frozenPaneWidth = visibleFrozenCols.fold(0.0, (w, k) => w + (_columnDefs[k]?.width ?? 80.0));
    double scrollablePaneWidth = visibleScrollableCols.fold(0.0, (w, k) => w + (_columnDefs[k]?.width ?? 80.0));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D),
      body: Column(
        children: [
          // 🏆 TOP BRAND BAR & AUDIT METRICS BANNER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF131C31),
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  tooltip: "Back to Inventory Hub",
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.table_chart_rounded, color: Color(0xFFA78BFA), size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "EXCEL STOCK WORKBENCH & INVENTORY INTEL",
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Live Stock Traceability • Multi-Vendor Variance • Movement Passbook",
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                    ),
                  ],
                ),
                const Spacer(),

                // 📊 METRICS TILES
                _topMetricTile("ITEMS", "${filteredList.length}", const Color(0xFF38BDF8)),
                _verticalDivider(),
                _topMetricTile("TOTAL STOCK", "${totalStockUnits.toInt()}", Colors.greenAccent),
                _verticalDivider(),
                _topMetricTile("PUR. VALUATION", "₹${totalPurVal.toStringAsFixed(0)}", const Color(0xFFA78BFA)),
                _verticalDivider(),
                _topMetricTile("MRP VALUATION", "₹${totalMrpVal.toStringAsFixed(0)}", Colors.amberAccent),
                _verticalDivider(),
                _topMetricTile("MARGIN", "${marginPct.toStringAsFixed(1)}%", Colors.cyanAccent),
              ],
            ),
          ),

          // 🎛️ CONTROL TOOLBAR (COMPANY FILTER, SEARCH, FREEZE, COLUMNS, EXPORT)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                // 🔍 LIVE SEARCH INPUT
                SizedBox(
                  width: 260,
                  height: 38,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: "Search name, code, rack...",
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFA78BFA), size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16, color: Colors.white54),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = "");
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  ),
                ),
                const SizedBox(width: 14),

                // 🏢 COMPANY FILTER DROPDOWN (KEY USER REQUIREMENT!)
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _selectedCompany != "ALL" ? const Color(0xFF7C3AED) : Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCompany,
                      dropdownColor: const Color(0xFF1E293B),
                      icon: const Icon(Icons.business_rounded, color: Color(0xFFA78BFA), size: 18),
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      items: [
                        const DropdownMenuItem(
                          value: "ALL",
                          child: Text("All Companies (Filter)", style: TextStyle(color: Colors.white)),
                        ),
                        ...companyDisplayMap.entries.map(
                          (e) => DropdownMenuItem(
                            value: e.value,
                            child: Text(
                              e.value,
                              style: const TextStyle(color: Colors.white70),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCompany = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // 🧊 FREEZE PANE DROPDOWN SELECTOR
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<FreezePaneOption>(
                      value: _freezeOption,
                      dropdownColor: const Color(0xFF1E293B),
                      icon: const Icon(Icons.ac_unit_rounded, color: Color(0xFF38BDF8), size: 16),
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      items: const [
                        DropdownMenuItem(value: FreezePaneOption.none, child: Text("No Freeze")),
                        DropdownMenuItem(value: FreezePaneOption.idAndName, child: Text("Freeze ID + Name")),
                        DropdownMenuItem(value: FreezePaneOption.idNameAndCompany, child: Text("Freeze ID + Name + Mfg")),
                        DropdownMenuItem(value: FreezePaneOption.idNameAndPack, child: Text("Freeze ID + Name + Pack")),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _freezeOption = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // 👁️ COLUMNS CHOOSER BUTTON
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  icon: const Icon(Icons.view_column_rounded, size: 16, color: Color(0xFFA78BFA)),
                  label: const Text("COLUMNS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (c) => StockColumnConfigDialog(
                        columnDefs: _columnDefs,
                        currentFreeze: _freezeOption,
                        onApply: (newDefs, newFreeze) {
                          setState(() {
                            _columnDefs = newDefs;
                            _freezeOption = newFreeze;
                          });
                        },
                      ),
                    );
                  },
                ),
                const Spacer(),

                // 🖨️ PRINT PDF BUTTON
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: const Text("PRINT REPORT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    final bytes = await WebStockAnalysisPdf.generateStockValuationReportBytes(
                      medicines: filteredList,
                      webPh: webPh,
                      selectedCompanyName: _selectedCompany == "ALL" ? "All Companies" : _selectedCompany,
                      filterTag: _activeFilter,
                    );
                    await Printing.layoutPdf(
                      onLayout: (_) async => bytes,
                      name: "Stock_Report_${DateTime.now().millisecondsSinceEpoch}",
                      format: PdfPageFormat.a4.landscape,
                    );
                  },
                ),
                const SizedBox(width: 8),

                // 📥 EXCEL / CSV EXPORT
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.file_download_rounded, size: 16),
                  label: const Text("EXPORT CSV", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    await StockExcelExportService.exportStockCsv(
                      medicines: filteredList,
                      webPh: webPh,
                      selectedCompanyName: _selectedCompany == "ALL" ? "All Companies" : _selectedCompany,
                      activeFilter: _activeFilter,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("✅ Stock CSV Exported Successfully!"), backgroundColor: Color(0xFF059669)),
                    );
                  },
                ),
              ],
            ),
          ),

          // 🏷️ FILTER CHIPS STRIP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            color: const Color(0xFF0A0F1D),
            child: Row(
              children: [
                _filterChip("ALL", "All Products (${webPh.medicines.length})"),
                const SizedBox(width: 6),
                _filterChip("IN_STOCK", "In Stock (>0)"),
                const SizedBox(width: 6),
                _filterChip("ZERO_STOCK", "Zero Stock (=0)"),
                const SizedBox(width: 6),
                _filterChip("LOW_STOCK", "Low Stock (<= Reorder)"),
                const SizedBox(width: 6),
                _filterChip("HIKE_ALERT", "Price Hike Alert 🔺"),
                const SizedBox(width: 6),
                _filterChip("EXPIRING", "Expiring Soon (<90 Days)"),
              ],
            ),
          ),

          // 📊 THE EXCEL DATAGRID SPREADSHEET TABLE
          Expanded(
            child: filteredList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 52, color: Colors.white24),
                        const SizedBox(height: 12),
                        const Text("No products match the selected filters or search query.", style: TextStyle(color: Colors.white54, fontSize: 13)),
                        if (_selectedCompany != "ALL" || _activeFilter != "ALL" || _searchQuery.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {
                                _searchQuery = "";
                                _selectedCompany = "ALL";
                                _activeFilter = "ALL";
                              });
                            },
                            child: const Text("RESET ALL FILTERS", style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  )
                : Row(
                    children: [
                      // 1. FROZEN LEFT PANE (Locks on Horizontal Scroll)
                      if (visibleFrozenCols.isNotEmpty)
                        Container(
                          width: frozenPaneWidth,
                          decoration: BoxDecoration(
                            color: const Color(0xFF131C31),
                            border: Border(
                              right: BorderSide(color: const Color(0xFF38BDF8).withOpacity(0.4), width: 2),
                            ),
                          ),
                          child: Column(
                            children: [
                              // Frozen Header
                              _buildFrozenHeader(visibleFrozenCols),
                              // Frozen Rows (Vertical Scroll synced)
                              Expanded(
                                child: ListView.builder(
                                  controller: _frozenVerticalScroll,
                                  itemCount: filteredList.length,
                                  itemExtent: 44,
                                  itemBuilder: (context, index) {
                                    final m = filteredList[index];
                                    return _buildFrozenRow(m, index + 1, visibleFrozenCols, webPh);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                      // 2. SCROLLABLE RIGHT PANE
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _horizontalScroll,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: scrollablePaneWidth,
                            child: Column(
                              children: [
                                // Scrollable Header
                                _buildScrollableHeader(visibleScrollableCols),
                                // Scrollable Rows (Vertical Scroll synced)
                                Expanded(
                                  child: ListView.builder(
                                    controller: _scrollableVerticalScroll,
                                    itemCount: filteredList.length,
                                    itemExtent: 44,
                                    itemBuilder: (context, index) {
                                      final m = filteredList[index];
                                      return _buildScrollableRow(m, index + 1, visibleScrollableCols, webPh);
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
        ],
      ),
    );
  }

  // --- TOP METRICS HELPER ---
  Widget _topMetricTile(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 1),
          Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _verticalDivider() => Container(height: 22, width: 1, color: Colors.white10);

  // --- FILTER CHIP ---
  Widget _filterChip(String filterKey, String label) {
    final isSelected = _activeFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _activeFilter = filterKey),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7C3AED) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? const Color(0xFFA78BFA) : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 9.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // --- FROZEN HEADER & ROWS ---
  Widget _buildFrozenHeader(List<StockColumnId> cols) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Colors.white12, width: 1.5)),
      ),
      child: Row(
        children: cols.map((colKey) {
          final def = _columnDefs[colKey]!;
          return _headerCell(def);
        }).toList(),
      ),
    );
  }

  Widget _buildFrozenRow(Medicine m, int sr, List<StockColumnId> cols, PharoahWebManager webPh) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: sr % 2 == 0 ? const Color(0xFF131C31) : const Color(0xFF0F172A),
        border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        children: cols.map((colKey) {
          final def = _columnDefs[colKey]!;
          return _renderCell(colKey, m, sr, def.width, webPh);
        }).toList(),
      ),
    );
  }

  // --- SCROLLABLE HEADER & ROWS ---
  Widget _buildScrollableHeader(List<StockColumnId> cols) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Colors.white12, width: 1.5)),
      ),
      child: Row(
        children: cols.map((colKey) {
          final def = _columnDefs[colKey]!;
          return _headerCell(def);
        }).toList(),
      ),
    );
  }

  Widget _buildScrollableRow(Medicine m, int sr, List<StockColumnId> cols, PharoahWebManager webPh) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: sr % 2 == 0 ? const Color(0xFF101726) : const Color(0xFF0A0F1D),
        border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        children: cols.map((colKey) {
          final def = _columnDefs[colKey]!;
          return _renderCell(colKey, m, sr, def.width, webPh);
        }).toList(),
      ),
    );
  }

  Widget _headerCell(StockColumnDef def) {
    bool isSorted = _sortColumn == def.id;
    return InkWell(
      onTap: () => _onSort(def.id),
      child: Container(
        width: def.width,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: def.isNumeric ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: def.isNumeric ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                def.title,
                style: TextStyle(
                  color: isSorted ? const Color(0xFF38BDF8) : Colors.white60,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSorted) ...[
              const SizedBox(width: 4),
              Icon(
                _isAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 12,
                color: const Color(0xFF38BDF8),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- CELL RENDERER FOR ALL COLUMNS ---
  Widget _renderCell(StockColumnId colId, Medicine m, int sr, double width, PharoahWebManager webPh) {
    final cName = _resolveCompanyName(webPh, m.companyId);

    switch (colId) {
      case StockColumnId.srNo:
        return _cellContainer(width, Text("$sr", style: const TextStyle(color: Colors.white38, fontSize: 10)), isRight: true);

      case StockColumnId.systemId:
        return _cellContainer(
          width,
          Text(m.systemId.isNotEmpty ? m.systemId : m.id, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold)),
        );

      case StockColumnId.name:
        return _cellContainer(
          width,
          Tooltip(
            message: m.name,
            child: Text(m.name, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          ),
        );

      case StockColumnId.company:
        return _cellContainer(
          width,
          Tooltip(
            message: cName,
            child: Text(cName, style: const TextStyle(color: Colors.white70, fontSize: 10), overflow: TextOverflow.ellipsis),
          ),
        );

      case StockColumnId.packing:
        return _cellContainer(
          width,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: m.packing.startsWith("1*") ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              m.packing,
              style: TextStyle(
                color: m.packing.startsWith("1*") ? Colors.greenAccent : Colors.orangeAccent,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );

      case StockColumnId.drugForm:
        return _cellContainer(width, Text(m.drugForm, style: const TextStyle(color: Colors.white54, fontSize: 10)));

      case StockColumnId.rackNo:
        return _cellContainer(width, Text(m.rackNo.isNotEmpty ? m.rackNo : "-", style: const TextStyle(color: Colors.white54, fontSize: 10)));

      case StockColumnId.gst:
        return _cellContainer(width, Text("${m.gst.toInt()}%", style: const TextStyle(color: Colors.white70, fontSize: 10.5)), isRight: true);

      case StockColumnId.currentStock:
        Color sColor = Colors.greenAccent;
        if (m.stock <= 0) {
          sColor = Colors.redAccent;
        } else if (m.reorderLevel > 0 && m.stock <= m.reorderLevel) {
          sColor = Colors.amberAccent;
        }
        return _cellContainer(
          width,
          Text("${m.stock.toInt()} Qty", style: TextStyle(color: sColor, fontSize: 11.5, fontWeight: FontWeight.bold)),
          isRight: true,
        );

      case StockColumnId.purRate:
        return _cellContainer(width, Text("₹${m.purRate.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white70, fontSize: 11)), isRight: true);

      case StockColumnId.mrp:
        return _cellContainer(width, Text("₹${m.mrp.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)), isRight: true);

      case StockColumnId.purValuation:
        final val = m.stock * m.purRate;
        return _cellContainer(width, Text("₹${val.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.bold)), isRight: true);

      case StockColumnId.mrpValuation:
        final val = m.stock * m.mrp;
        return _cellContainer(width, Text("₹${val.toStringAsFixed(2)}", style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)), isRight: true);

      case StockColumnId.batchCount:
        final batches = webPh.batchHistory[m.identityKey] ?? [];
        final count = batches.where((b) => b.qty > 0).length;
        return _cellContainer(width, Text("$count Batches", style: const TextStyle(color: Colors.white70, fontSize: 10)), isRight: true);

      case StockColumnId.nearestExpiry:
        final exp = _getNearestExpiry(webPh, m);
        return _cellContainer(width, Text(exp, style: const TextStyle(color: Colors.white70, fontSize: 10)));

      case StockColumnId.priceVariance:
        bool hasHike = _hasPriceHike(webPh, m);
        return _cellContainer(
          width,
          hasHike
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                  child: const Text("🔺 RATE HIKE", style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                )
              : const Text("Stable", style: TextStyle(color: Colors.white38, fontSize: 10)),
        );

      case StockColumnId.actions:
        return _cellContainer(
          width,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 📊 360° Movement Ledger
              IconButton(
                icon: const Icon(Icons.history_rounded, size: 17, color: Color(0xFF38BDF8)),
                tooltip: "360° Movement Passbook",
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (c) => StockMovementLedgerModal(
                      medicine: m,
                      companyName: cName,
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),

              // ⚖️ Vendor Price Comparator
              IconButton(
                icon: const Icon(Icons.compare_arrows_rounded, size: 17, color: Color(0xFF34D399)),
                tooltip: "Vendor Price Comparison & Hike Radar",
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (c) => StockVendorRateComparatorModal(
                      medicine: m,
                      companyName: cName,
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),

              // 📦 Batches View / Adjustment
              IconButton(
                icon: const Icon(Icons.layers_outlined, size: 17, color: Color(0xFFA78BFA)),
                tooltip: "Batch Details & Valuation",
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  setState(() => _batchTraceabilityMed = m);
                },
              ),
            ],
          ),
        );
    }
  }

  Widget _cellContainer(double width, Widget child, {bool isRight = false}) {
    return Container(
      width: width,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
  }
}
