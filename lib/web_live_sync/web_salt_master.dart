// FILE: lib/web_live_sync/web_salt_master.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'pharoah_web_manager.dart';
import 'web_models.dart';
import '../logic/master_cascade_service.dart';

class WebSaltMasterView extends StatefulWidget {
  final VoidCallback onBack;

  const WebSaltMasterView({
    super.key,
    required this.onBack,
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

  Map<String, List<Medicine>> _buildSaltProductsMap(PharoahWebManager webPh) {
    final Map<String, List<Medicine>> map = {};
    for (final s in webPh.salts) {
      map[s.id] = [];
    }
    for (final m in webPh.medicines) {
      for (final s in webPh.salts) {
        if (MasterCascadeService.belongsToSalt(m, s)) {
          map.putIfAbsent(s.id, () => []).add(m);
        }
      }
    }
    return map;
  }

  double _calcStockValue(List<Medicine> meds) {
    double total = 0.0;
    for (final m in meds) {
      if (m.stock > 0) {
        total += m.stock * (m.purRate > 0 ? m.purRate : m.rateA);
      }
    }
    return total;
  }

  double _calcTotalUnits(List<Medicine> meds) {
    double units = 0.0;
    for (final m in meds) {
      if (m.stock > 0) {
        units += m.stock;
      }
    }
    return units;
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    const Color bgColor = Color(0xFF0B0F19);
    const Color cardBg = Color(0xFF1E293B);
    const Color textCol = Colors.white;
    const Color subCol = Colors.white60;
    const Color borderCol = Colors.white12;

    final allSalts = List<Salt>.from(webPh.salts);
    final prodMap = _buildSaltProductsMap(webPh);

    int monoCount = 0;
    int combCount = 0;
    int mappedProdsCount = 0;
    double totalPortfolioVal = 0.0;

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
            s.type.toLowerCase().contains(q) ||
            s.id.toLowerCase().contains(q);
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
        const SingleActivator(LogicalKeyboardKey.f2): () => _showSaltDialog(webPh),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selectedSaltForDrawer != null) {
            setState(() => _selectedSaltForDrawer = null);
          } else {
            widget.onBack();
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
                        _buildHeaderBar(webPh, cardBg, textCol, subCol, borderCol),
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
                            webPh,
                            filtered,
                            prodMap,
                            cardBg,
                            textCol,
                            subCol,
                            borderCol,
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
                        webPh,
                        _selectedSaltForDrawer!,
                        prodMap[_selectedSaltForDrawer!.id] ?? [],
                        cardBg,
                        textCol,
                        subCol,
                        borderCol,
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

  Widget _buildHeaderBar(
    PharoahWebManager webPh,
    Color cardBg,
    Color textCol,
    Color subCol,
    Color borderCol,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol),
      ),
      child: Row(
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white12,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text("BACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 14),
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
                  "Manage chemical compositions & generic formulas — renaming a Salt automatically cascades across all linked products & substitutes.",
                  style: TextStyle(color: subCol, fontSize: 12),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _showMergeSaltsDialog(webPh),
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
            onPressed: () => _showSaltDialog(webPh),
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
                hintText: "Search by Salt Formula, Composition Type, or Substitute Brand Name...",
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
                fillColor: Colors.white.withValues(alpha: 0.04),
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
    PharoahWebManager webPh,
    List<Salt> list,
    Map<String, List<Medicine>> prodMap,
    Color cardBg,
    Color textCol,
    Color subCol,
    Color borderCol,
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
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Expanded(flex: 4, child: _th("SALT / CHEMICAL FORMULA", subCol)),
                Expanded(flex: 2, child: _th("COMPOSITION TYPE", subCol)),
                Expanded(flex: 3, child: _th("SAMPLE SUBSTITUTE BRANDS", subCol)),
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
                      final sampleBrands = meds.take(3).map((m) => m.name).join(", ");

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
                                          Text(
                                            "ID: ${s.id} • v${s.version}",
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
                                flex: 2,
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
                                flex: 3,
                                child: Text(
                                  sampleBrands.isEmpty ? "No brands linked yet" : sampleBrands,
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
                                      "${stockUnits.toStringAsFixed(0)} Units",
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
                                      onPressed: () => _showSaltDialog(webPh, existing: s),
                                      icon: const Icon(
                                        Icons.edit_note_rounded,
                                        color: Color(0xFF3B82F6),
                                        size: 21,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: "Delete / Reassign Salt",
                                      onPressed: () => _confirmDeleteSalt(webPh, s, meds),
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
    PharoahWebManager webPh,
    Salt salt,
    List<Medicine> meds,
    Color cardBg,
    Color textCol,
    Color subCol,
    Color borderCol,
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
                        "${meds.length} Substitute Brands • Type: ${salt.type.toUpperCase()}",
                        style: TextStyle(color: subCol, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showBulkLinkProductsToSaltDialog(webPh, salt),
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
                      final compName = webPh.resolveCompanyName(m.companyId);
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
                          "Co: $compName • Pack: ${m.packing} • Stock: ${m.stock.toStringAsFixed(0)}",
                          style: TextStyle(color: subCol, fontSize: 11),
                        ),
                        trailing: Text(
                          "MRP ₹${m.mrp.toStringAsFixed(2)}",
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

  void _showSaltDialog(PharoahWebManager webPh, {Salt? existing}) {
    final bool isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? "");
    String selectedType = existing?.type.toUpperCase() ?? "MONO";
    if (!["MONO", "DUO", "MULTI"].contains(selectedType)) {
      selectedType = "MONO";
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                const Icon(Icons.science_rounded, color: Color(0xFF0D9488)),
                const SizedBox(width: 10),
                Text(
                  isEdit ? "MODIFY SALT FORMULA (CASCADE)" : "CREATE NEW SALT FORMULA",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
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
                    const SizedBox(height: 14),
                    const Text(
                      "COMPOSITION TYPE",
                      style: TextStyle(
                        color: Colors.white60,
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
                                    color: active
                                        ? const Color(0xFF0D9488)
                                        : Colors.grey.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  t,
                                  style: const TextStyle(
                                    color: Colors.white,
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
                onPressed: () {
                  final newName = nameCtrl.text.trim().toUpperCase();
                  if (newName.isEmpty) return;

                  final saltObj = Salt(
                    id: existing?.id ?? "SLT_${DateTime.now().millisecondsSinceEpoch}",
                    name: newName,
                    type: selectedType,
                    updatedAt: DateTime.now().millisecondsSinceEpoch,
                    version: (existing?.version ?? 0) + 1,
                  );

                  final cascaded = webPh.saveOrUpdateSalt(
                    saltObj,
                    previousName: existing?.name,
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
                              ? "Salt '${saltObj.name}' updated & cascaded across $cascaded linked products!"
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
    return TextField(
      controller: ctrl,
      autofocus: autofocus,
      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Colors.white60,
          fontSize: 12,
        ),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _confirmDeleteSalt(PharoahWebManager webPh, Salt salt, List<Medicine> linkedMeds) {
    Salt? targetReassign;
    final otherSalts = webPh.salts.where((s) => s.id != salt.id).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(
              "Delete Salt '${salt.name}'?",
              style: const TextStyle(
                color: Colors.white,
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
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  if (linkedMeds.isNotEmpty && otherSalts.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<Salt?>(
                      value: targetReassign,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        labelText: "Reassign Linked Products To (Optional)",
                        labelStyle: const TextStyle(color: Colors.white60),
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
                onPressed: () {
                  if (targetReassign != null) {
                    webPh.mergeSalts(
                      source: salt,
                      target: targetReassign!,
                    );
                  } else {
                    webPh.deleteSaltMaster(salt.id);
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

  void _showMergeSaltsDialog(PharoahWebManager webPh) {
    if (webPh.salts.length < 2) return;
    Salt? sourceSalt = webPh.salts.first;
    Salt? targetSalt = webPh.salts.length > 1 ? webPh.salts[1] : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.merge_type_rounded, color: Color(0xFF8B5CF6)),
                SizedBox(width: 10),
                Text(
                  "MERGE DUPLICATE SALTS",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
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
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Salt>(
                    value: sourceSalt,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                    decoration: const InputDecoration(
                      labelText: "Duplicate Source Salt (Will Be Removed)",
                      labelStyle: TextStyle(color: Colors.white60),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: webPh.salts
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => sourceSalt = v),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<Salt>(
                    value: targetSalt,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                    decoration: const InputDecoration(
                      labelText: "Master Target Salt (Will Keep All Brands)",
                      labelStyle: TextStyle(color: Colors.white60),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: webPh.salts
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
                onPressed: () {
                  if (sourceSalt == null || targetSalt == null || sourceSalt!.id == targetSalt!.id) {
                    return;
                  }
                  webPh.mergeSalts(source: sourceSalt!, target: targetSalt!);
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

  void _showBulkLinkProductsToSaltDialog(PharoahWebManager webPh, Salt salt) {
    String filterQ = "";
    final Set<String> selectedIds = {};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final candidates = webPh.medicines.where((m) {
            if (MasterCascadeService.belongsToSalt(m, salt)) return false;
            if (filterQ.isEmpty) return true;
            final curSalt = webPh.resolveSaltName(m.saltId);
            return m.name.toLowerCase().contains(filterQ.toLowerCase()) ||
                curSalt.toLowerCase().contains(filterQ.toLowerCase());
          }).toList();

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(
              "Link Brands to ${salt.name}",
              style: const TextStyle(
                color: Colors.white,
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
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: "Search products to link to ${salt.name}...",
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
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
                        final curSalt = webPh.resolveSaltName(m.saltId);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          title: Text(
                            m.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            "Current Salt: ${curSalt.isEmpty ? 'None' : curSalt}",
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                          ),
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
                    : () {
                        for (final m in webPh.medicines) {
                          if (selectedIds.contains(m.id)) {
                            m.saltId = salt.id;
                            webPh.updateMedicine(m);
                          }
                        }
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
