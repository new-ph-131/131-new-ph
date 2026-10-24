import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../logic/master_cascade_service.dart';
import 'pharoah_web_manager.dart';

class WebSaltMasterView extends StatefulWidget {
  final PharoahWebManager manager;
  final Function(String) onNavigate;
  final bool isDark;

  const WebSaltMasterView({
    super.key,
    required this.manager,
    required this.onNavigate,
    required this.isDark,
  });

  @override
  State<WebSaltMasterView> createState() => _WebSaltMasterViewState();
}

class _WebSaltMasterViewState extends State<WebSaltMasterView> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = "";
  String _filterMode = "ALL"; // ALL, MONO, DUO, MULTI, WITH_PRODUCTS, UNUSED
  String _sortBy = "NAME_ASC"; // NAME_ASC, PRODUCTS_DESC, STOCK_VAL_DESC

  Salt? _selectedSaltForDrawer;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (_searchQuery != _searchCtrl.text.trim()) {
        setState(() => _searchQuery = _searchCtrl.text.trim());
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Map<String, List<Medicine>> _buildSaltProductsMap() {
    final Map<String, List<Medicine>> map = {};
    for (final s in widget.manager.salts) {
      map[s.id] = [];
    }
    for (final m in widget.manager.medicines) {
      for (final s in widget.manager.salts) {
        if (MasterCascadeService.belongsToSalt(m, s)) {
          map.putIfAbsent(s.id, () => []).add(m);
        }
      }
    }
    return map;
  }

  double _calcStockValue(List<Medicine> meds) {
    double total = 0;
    for (final m in meds) {
      for (final b in m.batches) {
        if (b.stockUnits > 0) {
          final pSize = m.packSize > 0 ? m.packSize : 1;
          total += (b.stockUnits / pSize) * b.pRate;
        }
      }
    }
    return total;
  }

  int _calcTotalUnits(List<Medicine> meds) {
    int units = 0;
    for (final m in meds) {
      units += m.totalStockUnits;
    }
    return units;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = widget.isDark;
    final Color bgColor = isDark ? const Color(0xFF0B0F19) : const Color(0xFFF1F5F9);
    final Color cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color textCol = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color subCol = isDark ? Colors.white60 : Colors.black54;
    final Color borderCol = isDark ? Colors.white12 : Colors.black12;

    final allSalts = List<Salt>.from(widget.manager.salts);
    final prodMap = _buildSaltProductsMap();

    int monoCount = 0;
    int combCount = 0;
    int mappedProdsCount = 0;
    double totalPortfolioVal = 0;

    for (final s in allSalts) {
      if (s.type.toUpperCase() == "MONO") {
        monoCount++;
      } else {
        combCount++;
      }
      final pList = prodMap[s.id] ?? [];
      mappedProdsCount += pList.length;
      totalPortfolioVal += _calcStockValue(pList);
    }

    // Filter
    List<Salt> filtered = allSalts.where((s) {
      final pList = prodMap[s.id] ?? [];
      if (_filterMode == "MONO" && s.type.toUpperCase() != "MONO") return false;
      if (_filterMode == "DUO" && s.type.toUpperCase() != "DUO") return false;
      if (_filterMode == "MULTI" && s.type.toUpperCase() != "MULTI") return false;
      if (_filterMode == "WITH_PRODUCTS" && pList.isEmpty) return false;
      if (_filterMode == "UNUSED" && pList.isNotEmpty) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchSalt = s.name.toLowerCase().contains(q) ||
            s.dosage.toLowerCase().contains(q) ||
            s.indication.toLowerCase().contains(q) ||
            s.sideEffects.toLowerCase().contains(q) ||
            s.type.toLowerCase().contains(q);
        final matchBrand = pList.any((m) => m.name.toLowerCase().contains(q));
        return matchSalt || matchBrand;
      }
      return true;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      if (_sortBy == "PRODUCTS_DESC") {
        final ca = (prodMap[a.id] ?? []).length;
        final cb = (prodMap[b.id] ?? []).length;
        if (cb != ca) return cb.compareTo(ca);
      } else if (_sortBy == "STOCK_VAL_DESC") {
        final va = _calcStockValue(prodMap[a.id] ?? []);
        final vb = _calcStockValue(prodMap[b.id] ?? []);
        if (vb != va) return vb.compareTo(va);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => _showSaltDialog(),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selectedSaltForDrawer != null) {
            setState(() => _selectedSaltForDrawer = null);
          } else {
            widget.onNavigate("DASHBOARD");
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double viewportH = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.of(context).size.height;
            return Container(
              height: viewportH,
              color: bgColor,
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: _selectedSaltForDrawer != null ? 7 : 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeaderBar(cardBg, textCol, subCol, borderCol),
                        const SizedBox(height: 14),
                        _buildKpiRow(
                          totalSalts: allSalts.length,
                          monoSalts: monoCount,
                          combSalts: combCount,
                          mappedProds: mappedProdsCount,
                          totalPortfolioVal: totalPortfolioVal,
                          cardBg: cardBg,
                          textCol: textCol,
                          subCol: subCol,
                          borderCol: borderCol,
                        ),
                        const SizedBox(height: 14),
                        _buildFilterToolbar(
                          cardBg,
                          textCol,
                          subCol,
                          borderCol,
                          filtered.length,
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: _buildSaltTable(
                            filtered,
                            prodMap,
                            cardBg,
                            textCol,
                            subCol,
                            borderCol,
                            isDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedSaltForDrawer != null) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: _buildSaltProductsDrawer(
                        _selectedSaltForDrawer!,
                        prodMap[_selectedSaltForDrawer!.id] ?? [],
                        cardBg,
                        textCol,
                        subCol,
                        borderCol,
                        isDark,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeaderBar(Color cardBg, Color textCol, Color subCol, Color borderCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.science_rounded, color: Color(0xFF0D9488), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "SALT / GENERIC MASTER",
                      style: TextStyle(
                        color: textCol,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        "AUTO-CASCADE + SUBSTITUTE FINDER",
                        style: TextStyle(
                          color: Color(0xFF0D9488),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  "Manage chemical compositions, indications & generic formulas — renaming a salt automatically cascades across all linked products & substitutes.",
                  style: TextStyle(color: subCol, fontSize: 12),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _showMergeSaltsDialog(),
            icon: const Icon(Icons.merge_type_rounded, size: 18, color: Color(0xFF8B5CF6)),
            label: const Text(
              "MERGE DUPLICATES",
              style: TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.w800, fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF8B5CF6)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () => _showSaltDialog(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              "ADD NEW SALT (F2)",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: "Close (Esc)",
            onPressed: () => widget.onNavigate("DASHBOARD"),
            icon: Icon(Icons.close_rounded, color: textCol),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow({
    required int totalSalts,
    required int monoSalts,
    required int combSalts,
    required int mappedProds,
    required double totalPortfolioVal,
    required Color cardBg,
    required Color textCol,
    required Color subCol,
    required Color borderCol,
  }) {
    return Row(
      children: [
        _kpiCard(
          "TOTAL FORMULAS",
          "$totalSalts",
          "Active Generic Salts",
          Icons.science_rounded,
          const Color(0xFF0D9488),
          cardBg,
          textCol,
          subCol,
          borderCol,
        ),
        const SizedBox(width: 12),
        _kpiCard(
          "MONO vs COMBINATION",
          "$monoSalts / $combSalts",
          "Single vs Duo/Multi Salts",
          Icons.hub_rounded,
          const Color(0xFF3B82F6),
          cardBg,
          textCol,
          subCol,
          borderCol,
        ),
        const SizedBox(width: 12),
        _kpiCard(
          "MAPPED BRANDS",
          "$mappedProds",
          "Substitute-Ready Medicines",
          Icons.medication_liquid_rounded,
          const Color(0xFF8B5CF6),
          cardBg,
          textCol,
          subCol,
          borderCol,
        ),
        const SizedBox(width: 12),
        _kpiCard(
          "MAPPED STOCK VALUE",
          "₹${totalPortfolioVal.toStringAsFixed(0)}",
          "Stock Value Across Salts",
          Icons.account_balance_wallet_rounded,
          const Color(0xFFF59E0B),
          cardBg,
          textCol,
          subCol,
          borderCol,
        ),
      ],
    );
  }

  Widget _kpiCard(
    String label,
    String value,
    String subtitle,
    IconData icon,
    Color accent,
    Color cardBg,
    Color textCol,
    Color subCol,
    Color borderCol,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderCol),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: subCol,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: textCol,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: subCol, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterToolbar(
    Color cardBg,
    Color textCol,
    Color subCol,
    Color borderCol,
    int showingCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              style: TextStyle(color: textCol, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: "Search by Salt Formula, Strength, Indication, or Substitute Brand Name...",
                hintStyle: TextStyle(color: subCol, fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF0D9488), size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, size: 16, color: subCol),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                filled: true,
                fillColor: widget.isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderCol),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderCol),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _filterChip("ALL", "ALL", textCol, subCol),
          const SizedBox(width: 6),
          _filterChip("MONO", "MONO", textCol, subCol),
          const SizedBox(width: 6),
          _filterChip("DUO", "DUO", textCol, subCol),
          const SizedBox(width: 6),
          _filterChip("MULTI", "MULTI", textCol, subCol),
          const SizedBox(width: 6),
          _filterChip("WITH BRANDS", "WITH_PRODUCTS", textCol, subCol),
          const SizedBox(width: 6),
          _filterChip("UNLINKED", "UNUSED", textCol, subCol),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: borderCol),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sortBy,
                dropdownColor: cardBg,
                style: TextStyle(color: textCol, fontSize: 12, fontWeight: FontWeight.w700),
                items: const [
                  DropdownMenuItem(value: "NAME_ASC", child: Text("Sort: Formula A → Z")),
                  DropdownMenuItem(value: "PRODUCTS_DESC", child: Text("Sort: Most Brands")),
                  DropdownMenuItem(value: "STOCK_VAL_DESC", child: Text("Sort: Highest Stock ₹")),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _sortBy = v);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "$showingCount Salts",
            style: TextStyle(color: subCol, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String mode, Color textCol, Color subCol) {
    final bool selected = _filterMode == mode;
    return InkWell(
      onTap: () => setState(() => _filterMode = mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0D9488) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF0D9488) : subCol.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : textCol,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildSaltTable(
    List<Salt> list,
    Map<String, List<Medicine>> prodMap,
    Color cardBg,
    Color textCol,
    Color subCol,
    Color borderCol,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: borderCol)),
            ),
            child: Row(
              children: [
                Expanded(flex: 4, child: _th("SALT / CHEMICAL FORMULA", subCol)),
                Expanded(flex: 1, child: _th("TYPE", subCol)),
                Expanded(flex: 2, child: _th("STRENGTH / DOSAGE", subCol)),
                Expanded(flex: 2, child: _th("THERAPEUTIC INDICATION", subCol)),
                Expanded(flex: 2, child: _th("SUBSTITUTE BRANDS", subCol)),
                Expanded(flex: 2, child: _th("STOCK VALUE", subCol)),
                SizedBox(width: 170, child: _th("MASTER ACTIONS", subCol, alignRight: true)),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.science_outlined, size: 48, color: subCol),
                        const SizedBox(height: 10),
                        Text(
                          "No salts match the current search or filter",
                          style: TextStyle(color: subCol, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: borderCol),
                    itemBuilder: (ctx, i) {
                      final s = list[i];
                      final meds = prodMap[s.id] ?? [];
                      final stockVal = _calcStockValue(meds);
                      final stockUnits = _calcTotalUnits(meds);
                      final isSelected = _selectedSaltForDrawer?.id == s.id;

                      Color typeColor = const Color(0xFF10B981);
                      if (s.type.toUpperCase() == "DUO") typeColor = const Color(0xFF3B82F6);
                      if (s.type.toUpperCase() == "MULTI") typeColor = const Color(0xFF8B5CF6);

                      return InkWell(
                        onTap: () => setState(() => _selectedSaltForDrawer = s),
                        child: Container(
                          color: isSelected
                              ? const Color(0xFF0D9488).withValues(alpha: 0.08)
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.science_rounded,
                                        color: Color(0xFF0D9488),
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s.name,
                                            style: TextStyle(
                                              color: textCol,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                          if (s.sideEffects.isNotEmpty)
                                            Text(
                                              "Note: ${s.sideEffects}",
                                              style: TextStyle(color: subCol, fontSize: 10.5),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: typeColor.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      s.type.toUpperCase(),
                                      style: TextStyle(
                                        color: typeColor,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  s.dosage.isEmpty ? "—" : s.dosage,
                                  style: TextStyle(
                                    color: textCol,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  s.indication.isEmpty ? "—" : s.indication,
                                  style: TextStyle(color: subCol, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: InkWell(
                                    onTap: () => setState(() => _selectedSaltForDrawer = s),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: meds.isNotEmpty
                                            ? const Color(0xFF0D9488).withValues(alpha: 0.12)
                                            : Colors.grey.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        "${meds.length} Brands",
                                        style: TextStyle(
                                          color: meds.isNotEmpty ? const Color(0xFF0D9488) : subCol,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "₹${stockVal.toStringAsFixed(0)}",
                                      style: TextStyle(
                                        color: textCol,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      "$stockUnits Units",
                                      style: TextStyle(color: subCol, fontSize: 10.5),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 170,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      tooltip: "View Substitute Brands & Assign Products",
                                      onPressed: () => setState(() => _selectedSaltForDrawer = s),
                                      icon: const Icon(
                                        Icons.medication_liquid_rounded,
                                        color: Color(0xFF0D9488),
                                        size: 19,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: "Modify Salt (Cascades Across Products)",
                                      onPressed: () => _showSaltDialog(existing: s),
                                      icon: const Icon(
                                        Icons.edit_note_rounded,
                                        color: Color(0xFF3B82F6),
                                        size: 21,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: "Delete / Reassign Salt",
                                      onPressed: () => _confirmDeleteSalt(s, meds),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.redAccent,
                                        size: 19,
                                      ),
                                    ),
                                  ],
                                ),
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
    );
  }

  Widget _th(String text, Color subCol, {bool alignRight = false}) {
    return Text(
      text,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        color: subCol,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSaltProductsDrawer(
    Salt salt,
    List<Medicine> meds,
    Color cardBg,
    Color textCol,
    Color subCol,
    Color borderCol,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488).withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: borderCol)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "SUBSTITUTE BRANDS EXPLORER",
                        style: TextStyle(
                          color: Color(0xFF0D9488),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        salt.name,
                        style: TextStyle(color: textCol, fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        "${meds.length} Substitute Brands • ${salt.dosage.isEmpty ? salt.type : '${salt.type} • ${salt.dosage}'}",
                        style: TextStyle(color: subCol, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showBulkLinkProductsToSaltDialog(salt),
                  icon: const Icon(Icons.add_link_rounded, size: 16),
                  label: const Text(
                    "LINK BRANDS",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () => setState(() => _selectedSaltForDrawer = null),
                  icon: Icon(Icons.close_rounded, color: textCol, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: meds.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        "No products linked to ${salt.name} yet.\nClick 'LINK BRANDS' to map medicines to this generic formula.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: subCol, fontSize: 12.5),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: meds.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: borderCol),
                    itemBuilder: (ctx, i) {
                      final m = meds[i];
                      final compName = widget.manager.resolveCompanyName(m);
                      return ListTile(
                        dense: true,
                        title: Text(
                          m.name,
                          style: TextStyle(
                            color: textCol,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          "Co: $compName • Pack: ${m.pack} • Stock: ${m.displayStock}",
                          style: TextStyle(color: subCol, fontSize: 11),
                        ),
                        trailing: Text(
                          "MRP ₹${m.batches.isNotEmpty ? m.batches.first.mrp.toStringAsFixed(2) : '0.00'}",
                          style: const TextStyle(
                            color: Color(0xFF0D9488),
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showSaltDialog({Salt? existing}) {
    final bool isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? "");
    final dosageCtrl = TextEditingController(text: existing?.dosage ?? "");
    final indCtrl = TextEditingController(text: existing?.indication ?? "");
    final sideCtrl = TextEditingController(text: existing?.sideEffects ?? "");
    String selectedType = existing?.type.toUpperCase() ?? "MONO";
    if (!["MONO", "DUO", "MULTI"].contains(selectedType)) {
      selectedType = "MONO";
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                const Icon(Icons.science_rounded, color: Color(0xFF0D9488)),
                const SizedBox(width: 10),
                Text(
                  isEdit ? "MODIFY SALT FORMULA (CASCADE)" : "CREATE NEW SALT FORMULA",
                  style: TextStyle(
                    color: widget.isDark ? Colors.white : Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isEdit)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.auto_fix_high_rounded, color: Color(0xFF0D9488), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Master Cascade Active: Updating this Salt formula will automatically update all linked Products across Web & Mobile App.",
                                style: TextStyle(
                                  color: Color(0xFF0D9488),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _dialogField("Chemical / Generic Salt Formula *", nameCtrl, autofocus: true),
                    const SizedBox(height: 12),
                    Text(
                      "COMPOSITION TYPE",
                      style: TextStyle(
                        color: widget.isDark ? Colors.white60 : Colors.black54,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: ["MONO", "DUO", "MULTI"].map((t) {
                        final active = selectedType == t;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: InkWell(
                              onTap: () => setDialogState(() => selectedType = t),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: active ? const Color(0xFF0D9488) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: active ? const Color(0xFF0D9488) : Colors.grey.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  t,
                                  style: TextStyle(
                                    color: active
                                        ? Colors.white
                                        : (widget.isDark ? Colors.white : Colors.black87),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _dialogField("Standard Strength / Dosage (e.g. 500mg / 650mg)", dosageCtrl),
                    const SizedBox(height: 10),
                    _dialogField("Therapeutic Indication (e.g. Antipyretic, Antibiotic)", indCtrl),
                    const SizedBox(height: 10),
                    _dialogField("Side Effects / Clinical Notes", sideCtrl),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("CANCEL"),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onPressed: () async {
                  final newName = nameCtrl.text.trim().toUpperCase();
                  if (newName.isEmpty) return;

                  final saltObj = Salt(
                    id: existing?.id ?? "SLT_${DateTime.now().millisecondsSinceEpoch}",
                    name: newName,
                    type: selectedType,
                    dosage: dosageCtrl.text.trim(),
                    indication: indCtrl.text.trim(),
                    sideEffects: sideCtrl.text.trim(),
                    updatedAt: DateTime.now().millisecondsSinceEpoch,
                    version: (existing?.version ?? 0) + 1,
                  );

                  await widget.manager.saveOrUpdateSalt(
                    saltObj,
                    oldName: existing?.name,
                  );

                  if (mounted) {
                    setState(() {
                      if (_selectedSaltForDrawer?.id == saltObj.id) {
                        _selectedSaltForDrawer = saltObj;
                      }
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEdit
                              ? "Salt '${saltObj.name}' updated & cascaded across linked products!"
                              : "Salt '${saltObj.name}' created & synced!",
                        ),
                        backgroundColor: const Color(0xFF0D9488),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text(isEdit ? "UPDATE & CASCADE" : "SAVE SALT"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogField(String label, TextEditingController ctrl, {bool autofocus = false}) {
    final textCol = widget.isDark ? Colors.white : Colors.black87;
    return TextField(
      controller: ctrl,
      autofocus: autofocus,
      style: TextStyle(color: textCol, fontSize: 13, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: widget.isDark ? Colors.white60 : Colors.black54,
          fontSize: 12,
        ),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _confirmDeleteSalt(Salt salt, List<Medicine> linkedMeds) {
    Salt? targetReassign;
    final otherSalts = widget.manager.salts.where((s) => s.id != salt.id).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(
              "Delete Salt '${salt.name}'?",
              style: TextStyle(
                color: widget.isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    linkedMeds.isEmpty
                        ? "No products are currently linked to this salt. It will be permanently removed and synced across Web & Mobile App."
                        : "There are ${linkedMeds.length} products linked to '${salt.name}'. You can optionally reassign those products to another salt before deleting:",
                    style: TextStyle(
                      color: widget.isDark ? Colors.white70 : Colors.black87,
                      fontSize: 13,
                    ),
                  ),
                  if (linkedMeds.isNotEmpty && otherSalts.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<Salt?>(
                      value: targetReassign,
                      dropdownColor: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
                      decoration: InputDecoration(
                        labelText: "Reassign Linked Products To (Optional)",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<Salt?>(
                          value: null,
                          child: Text("Clear Salt on Linked Products"),
                        ),
                        ...otherSalts.map(
                          (s) => DropdownMenuItem<Salt?>(
                            value: s,
                            child: Text(s.name),
                          ),
                        ),
                      ],
                      onChanged: (v) => setDialogState(() => targetReassign = v),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("CANCEL"),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (targetReassign != null) {
                    await widget.manager.mergeSalts(
                      source: salt,
                      target: targetReassign!,
                    );
                  } else {
                    await widget.manager.deleteSaltMaster(salt.id);
                  }
                  if (mounted) {
                    setState(() {
                      if (_selectedSaltForDrawer?.id == salt.id) {
                        _selectedSaltForDrawer = null;
                      }
                    });
                    Navigator.pop(ctx);
                  }
                },
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: Text(targetReassign != null ? "REASSIGN & DELETE" : "DELETE SALT"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showMergeSaltsDialog() {
    if (widget.manager.salts.length < 2) return;
    Salt? sourceSalt = widget.manager.salts.first;
    Salt? targetSalt = widget.manager.salts.length > 1 ? widget.manager.salts[1] : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.merge_type_rounded, color: Color(0xFF8B5CF6)),
                SizedBox(width: 10),
                Text(
                  "MERGE DUPLICATE SALTS",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Move all linked products from Source Salt into Target Salt and remove the duplicate Source Salt:",
                    style: TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Salt>(
                    value: sourceSalt,
                    decoration: const InputDecoration(
                      labelText: "Duplicate Source Salt (Will Be Removed)",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: widget.manager.salts
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => sourceSalt = v),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<Salt>(
                    value: targetSalt,
                    decoration: const InputDecoration(
                      labelText: "Master Target Salt (Will Keep All Brands)",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: widget.manager.salts
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => targetSalt = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (sourceSalt == null || targetSalt == null || sourceSalt!.id == targetSalt!.id) {
                    return;
                  }
                  await widget.manager.mergeSalts(source: sourceSalt!, target: targetSalt!);
                  if (mounted) {
                    setState(() => _selectedSaltForDrawer = targetSalt);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Merged '${sourceSalt!.name}' into '${targetSalt!.name}'!"),
                        backgroundColor: const Color(0xFF8B5CF6),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.merge_type_rounded, size: 18),
                label: const Text("MERGE & SYNC"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBulkLinkProductsToSaltDialog(Salt salt) {
    String filterQ = "";
    final Set<String> selectedIds = {};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final candidates = widget.manager.medicines.where((m) {
            if (MasterCascadeService.belongsToSalt(m, salt)) return false;
            if (filterQ.isEmpty) return true;
            return m.name.toLowerCase().contains(filterQ.toLowerCase()) ||
                m.salt.toLowerCase().contains(filterQ.toLowerCase());
          }).toList();

          return AlertDialog(
            backgroundColor: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(
              "Link Brands to ${salt.name}",
              style: TextStyle(
                color: widget.isDark ? Colors.white : Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    onChanged: (v) => setDialogState(() => filterQ = v.trim()),
                    decoration: InputDecoration(
                      hintText: "Search products to link to ${salt.name}...",
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: math.min(candidates.length, 100),
                      itemBuilder: (ctx, i) {
                        final m = candidates[i];
                        final checked = selectedIds.contains(m.id);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text("Current Salt: ${m.salt.isEmpty ? 'None' : m.salt}"),
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) {
                                selectedIds.add(m.id);
                              } else {
                                selectedIds.remove(m.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                ),
                onPressed: selectedIds.isEmpty
                    ? null
                    : () async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        for (final m in widget.manager.medicines) {
                          if (selectedIds.contains(m.id)) {
                            m.saltId = salt.id;
                            m.salt = salt.name;
                            m.updatedAt = now;
                            m.version += 1;
                            await widget.manager.orchestrator.syncProduct(m);
                          }
                        }
                        await widget.manager.pushUpdatedDataToCloud();
                        if (mounted) {
                          setState(() {});
                          Navigator.pop(ctx);
                        }
                      },
                child: Text("LINK ${selectedIds.length} BRANDS"),
              ),
            ],
          );
        },
      ),
    );
  }
}
