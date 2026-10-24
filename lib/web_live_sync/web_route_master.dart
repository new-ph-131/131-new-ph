// FILE: lib/web_live_sync/web_route_master.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'pharoah_web_manager.dart';
import 'web_models.dart';
import '../logic/master_cascade_service.dart';

class WebRouteMasterView extends StatefulWidget {
  final VoidCallback onBack;

  const WebRouteMasterView({
    super.key,
    required this.onBack,
  });

  @override
  State<WebRouteMasterView> createState() => _WebRouteMasterViewState();
}

class _WebRouteMasterViewState extends State<WebRouteMasterView> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = "";
  String _filterMode = "ALL"; // ALL, ACTIVE, HIGH_RECEIVABLES, EMPTY
  String _sortBy = "NAME_ASC"; // NAME_ASC, PARTIES_DESC, RECEIVABLES_DESC

  RouteArea? _selectedRouteForDrawer;

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

  Map<String, List<Party>> _buildRoutePartiesMap(PharoahWebManager webPh) {
    final Map<String, List<Party>> map = {};
    for (final r in webPh.routes) {
      map[r.id] = [];
    }
    for (final p in webPh.parties) {
      for (final r in webPh.routes) {
        if (MasterCascadeService.belongsToRoute(p, r)) {
          map.putIfAbsent(r.id, () => []).add(p);
        }
      }
    }
    return map;
  }

  double _getPartyLiveBalance(PharoahWebManager webPh, Party p) {
    double bal = p.opBal;
    for (final s in webPh.sales) {
      if (s.partyId == p.id && s.paymentMode.toUpperCase() == "CREDIT") {
        bal += s.netTotal;
      }
    }
    for (final v in webPh.vouchers) {
      if (v.partyId == p.id) {
        if (v.type.toUpperCase() == "RECEIPT") {
          bal -= v.amount;
        } else if (v.type.toUpperCase() == "PAYMENT") {
          bal += v.amount;
        }
      }
    }
    return bal;
  }

  double _calcRouteReceivables(PharoahWebManager webPh, List<Party> parties) {
    double sum = 0.0;
    for (final p in parties) {
      final bal = _getPartyLiveBalance(webPh, p);
      if (bal > 0) sum += bal;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    const Color bgColor = Color(0xFF0B0F19);
    const Color cardBg = Color(0xFF1E293B);
    const Color textCol = Colors.white;
    const Color subCol = Colors.white60;
    const Color borderCol = Colors.white12;

    final allRoutes = List<RouteArea>.from(webPh.routes);
    final partyMap = _buildRoutePartiesMap(webPh);

    int activeRoutesCount = 0;
    int mappedPartiesCount = 0;
    double totalRouteReceivables = 0.0;

    for (final r in allRoutes) {
      final pList = partyMap[r.id] ?? [];
      if (pList.isNotEmpty) {
        activeRoutesCount++;
        mappedPartiesCount += pList.length;
        totalRouteReceivables += _calcRouteReceivables(webPh, pList);
      }
    }

    int unassignedPartiesCount = webPh.parties.where((p) {
      final rt = p.route.trim().toUpperCase();
      return rt.isEmpty || rt == "ALL" || rt == "DEFAULT";
    }).length;

    // Filter
    List<RouteArea> filtered = allRoutes.where((r) {
      final pList = partyMap[r.id] ?? [];
      final rec = _calcRouteReceivables(webPh, pList);
      if (_filterMode == "ACTIVE" && pList.isEmpty) return false;
      if (_filterMode == "HIGH_RECEIVABLES" && rec <= 0) return false;
      if (_filterMode == "EMPTY" && pList.isNotEmpty) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchRoute = r.name.toLowerCase().contains(q) || r.id.toLowerCase().contains(q);
        final matchParty = pList.any(
          (p) => p.name.toLowerCase().contains(q) || p.phone.toLowerCase().contains(q),
        );
        return matchRoute || matchParty;
      }
      return true;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      if (_sortBy == "PARTIES_DESC") {
        final ca = (partyMap[a.id] ?? []).length;
        final cb = (partyMap[b.id] ?? []).length;
        if (cb != ca) return cb.compareTo(ca);
      } else if (_sortBy == "RECEIVABLES_DESC") {
        final ra = _calcRouteReceivables(webPh, partyMap[a.id] ?? []);
        final rb = _calcRouteReceivables(webPh, partyMap[b.id] ?? []);
        if (rb != ra) return rb.compareTo(ra);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => _showRouteDialog(webPh),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selectedRouteForDrawer != null) {
            setState(() => _selectedRouteForDrawer = null);
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
                    flex: _selectedRouteForDrawer != null ? 7 : 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeaderBar(webPh, cardBg, textCol, subCol, borderCol),
                        const SizedBox(height: 14),
                        _buildKpiRow(
                          totalRoutes: allRoutes.length,
                          activeRoutes: activeRoutesCount,
                          mappedParties: mappedPartiesCount,
                          unassignedParties: unassignedPartiesCount,
                          totalReceivables: totalRouteReceivables,
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
                          child: _buildRouteTable(
                            webPh,
                            filtered,
                            partyMap,
                            cardBg,
                            textCol,
                            subCol,
                            borderCol,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedRouteForDrawer != null) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: _buildRoutePartiesDrawer(
                        webPh,
                        _selectedRouteForDrawer!,
                        partyMap[_selectedRouteForDrawer!.id] ?? [],
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
              color: const Color(0xFFE11D48).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.route_rounded, color: Color(0xFFE11D48), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "ROUTE / AREA MASTER",
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
                        color: const Color(0xFFE11D48).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        "AUTO-CASCADE + COLLECTION ANALYTICS",
                        style: TextStyle(
                          color: Color(0xFFE11D48),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  "Manage delivery & collection beats — renaming a Route automatically cascades across all linked Parties on Web & Mobile App.",
                  style: TextStyle(color: subCol, fontSize: 12),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _showMergeRoutesDialog(webPh),
            icon: const Icon(Icons.merge_type_rounded, size: 18, color: Color(0xFF8B5CF6)),
            label: const Text(
              "MERGE ROUTES",
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
            onPressed: () => _showRouteDialog(webPh),
            icon: const Icon(Icons.add_location_alt_rounded, size: 18),
            label: const Text(
              "ADD NEW ROUTE (F2)",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
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
    required int totalRoutes,
    required int activeRoutes,
    required int mappedParties,
    required int unassignedParties,
    required double totalReceivables,
    required Color cardBg,
    required Color textCol,
    required Color subCol,
    required Color borderCol,
  }) {
    return Row(
      children: [
        _kpiCard(
          "TOTAL ROUTES / BEATS",
          "$totalRoutes",
          "$activeRoutes Active Delivery Beats",
          Icons.route_rounded,
          const Color(0xFFE11D48),
          cardBg,
          textCol,
          subCol,
          borderCol,
        ),
        const SizedBox(width: 12),
        _kpiCard(
          "MAPPED PARTIES",
          "$mappedParties",
          "Customers Assigned to Routes",
          Icons.storefront_rounded,
          const Color(0xFF3B82F6),
          cardBg,
          textCol,
          subCol,
          borderCol,
        ),
        const SizedBox(width: 12),
        _kpiCard(
          "UNASSIGNED PARTIES",
          "$unassignedParties",
          "Parties Without Specific Route",
          Icons.person_off_rounded,
          const Color(0xFFF59E0B),
          cardBg,
          textCol,
          subCol,
          borderCol,
        ),
        const SizedBox(width: 12),
        _kpiCard(
          "ROUTE RECEIVABLES",
          "₹${totalReceivables.toStringAsFixed(0)}",
          "Total Outstanding Across Routes",
          Icons.currency_rupee_rounded,
          const Color(0xFF10B981),
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
                hintText: "Search Route / Area Name or Party Name / Mobile...",
                hintStyle: TextStyle(color: subCol, fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFE11D48), size: 20),
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
          _filterChip("ALL ROUTES", "ALL", textCol, subCol),
          const SizedBox(width: 6),
          _filterChip("ACTIVE BEATS", "ACTIVE", textCol, subCol),
          const SizedBox(width: 6),
          _filterChip("WITH RECEIVABLES", "HIGH_RECEIVABLES", textCol, subCol),
          const SizedBox(width: 6),
          _filterChip("EMPTY", "EMPTY", textCol, subCol),
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
                  DropdownMenuItem(value: "NAME_ASC", child: Text("Sort: Route A → Z")),
                  DropdownMenuItem(value: "PARTIES_DESC", child: Text("Sort: Most Parties")),
                  DropdownMenuItem(value: "RECEIVABLES_DESC", child: Text("Sort: Highest Outstanding ₹")),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _sortBy = v);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "$showingCount Routes",
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
          color: selected ? const Color(0xFFE11D48) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFFE11D48) : subCol.withValues(alpha: 0.3),
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

  Widget _buildRouteTable(
    PharoahWebManager webPh,
    List<RouteArea> list,
    Map<String, List<Party>> partyMap,
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
                Expanded(flex: 4, child: _th("ROUTE / COLLECTION AREA", subCol)),
                Expanded(flex: 2, child: _th("MAPPED PARTIES", subCol)),
                Expanded(flex: 3, child: _th("SAMPLE CUSTOMERS ON BEAT", subCol)),
                Expanded(flex: 2, child: _th("OUTSTANDING RECEIVABLES", subCol)),
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
                        Icon(Icons.route_outlined, size: 48, color: subCol),
                        const SizedBox(height: 10),
                        Text(
                          "No routes match the current search or filter",
                          style: TextStyle(color: subCol, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: borderCol),
                    itemBuilder: (ctx, i) {
                      final r = list[i];
                      final parties = partyMap[r.id] ?? [];
                      final receivables = _calcRouteReceivables(webPh, parties);
                      final isSelected = _selectedRouteForDrawer?.id == r.id;

                      final previewNames = parties.take(3).map((p) => p.name).join(", ");

                      return InkWell(
                        onTap: () => setState(() => _selectedRouteForDrawer = r),
                        child: Container(
                          color: isSelected
                              ? const Color(0xFFE11D48).withValues(alpha: 0.08)
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
                                        color: const Color(0xFFE11D48).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.location_on_rounded,
                                        color: Color(0xFFE11D48),
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            r.name,
                                            style: TextStyle(
                                              color: textCol,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                          Text(
                                            "ID: ${r.id} • v${r.version}",
                                            style: TextStyle(color: subCol, fontSize: 10.5),
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
                                  child: InkWell(
                                    onTap: () => setState(() => _selectedRouteForDrawer = r),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: parties.isNotEmpty
                                            ? const Color(0xFFE11D48).withValues(alpha: 0.12)
                                            : Colors.grey.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        "${parties.length} Parties",
                                        style: TextStyle(
                                          color: parties.isNotEmpty ? const Color(0xFFE11D48) : subCol,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  previewNames.isEmpty ? "No parties assigned yet" : previewNames,
                                  style: TextStyle(color: subCol, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  "₹${receivables.toStringAsFixed(0)}",
                                  style: TextStyle(
                                    color: receivables > 0 ? const Color(0xFF10B981) : textCol,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 170,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      tooltip: "View & Assign Parties on Route",
                                      onPressed: () => setState(() => _selectedRouteForDrawer = r),
                                      icon: const Icon(
                                        Icons.groups_rounded,
                                        color: Color(0xFFE11D48),
                                        size: 19,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: "Rename Route (Cascades Across All Parties)",
                                      onPressed: () => _showRouteDialog(webPh, existing: r),
                                      icon: const Icon(
                                        Icons.edit_note_rounded,
                                        color: Color(0xFF3B82F6),
                                        size: 21,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: "Delete / Reassign Route",
                                      onPressed: () => _confirmDeleteRoute(webPh, r, parties),
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

  Widget _buildRoutePartiesDrawer(
    PharoahWebManager webPh,
    RouteArea route,
    List<Party> parties,
    Color cardBg,
    Color textCol,
    Color subCol,
    Color borderCol,
  ) {
    final totalDue = _calcRouteReceivables(webPh, parties);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE11D48).withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE11D48).withValues(alpha: 0.1),
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
                        "ROUTE PARTY LEDGER EXPLORER",
                        style: TextStyle(
                          color: Color(0xFFE11D48),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        route.name,
                        style: TextStyle(color: textCol, fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        "${parties.length} Parties • Receivables: ₹${totalDue.toStringAsFixed(0)}",
                        style: TextStyle(color: subCol, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showBulkAssignPartiesToRouteDialog(webPh, route),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                  label: const Text(
                    "ASSIGN PARTIES",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE11D48),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () => setState(() => _selectedRouteForDrawer = null),
                  icon: Icon(Icons.close_rounded, color: textCol, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: parties.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        "No parties assigned to ${route.name} yet.\nClick 'ASSIGN PARTIES' to map customers to this beat.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: subCol, fontSize: 12.5),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: parties.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: borderCol),
                    itemBuilder: (ctx, i) {
                      final p = parties[i];
                      final bal = _getPartyLiveBalance(webPh, p);
                      return ListTile(
                        dense: true,
                        title: Text(
                          p.name,
                          style: TextStyle(
                            color: textCol,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          "Ph: ${p.phone.isEmpty ? 'N/A' : p.phone} • ${p.address.isEmpty ? 'No Address' : p.address}",
                          style: TextStyle(color: subCol, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          "₹${bal.toStringAsFixed(0)}",
                          style: TextStyle(
                            color: bal > 0 ? const Color(0xFF10B981) : subCol,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
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

  void _showRouteDialog(PharoahWebManager webPh, {RouteArea? existing}) {
    final bool isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? "");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.route_rounded, color: Color(0xFFE11D48)),
            const SizedBox(width: 10),
            Text(
              isEdit ? "MODIFY ROUTE (CASCADE UPDATE)" : "CREATE NEW ROUTE / BEAT",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isEdit)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE11D48).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE11D48).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.auto_fix_high_rounded, color: Color(0xFFE11D48), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Master Cascade Active: Renaming this Route will automatically update all linked Parties across Web & Mobile App.",
                          style: TextStyle(
                            color: Color(0xFFE11D48),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  labelText: "Route / Area / Market Beat Name *",
                  labelStyle: const TextStyle(color: Colors.white60),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
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
              backgroundColor: const Color(0xFFE11D48),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            onPressed: () {
              final newName = nameCtrl.text.trim().toUpperCase();
              if (newName.isEmpty) return;

              final routeObj = RouteArea(
                id: existing?.id ?? "RT_${DateTime.now().millisecondsSinceEpoch}",
                name: newName,
                updatedAt: DateTime.now().millisecondsSinceEpoch,
                version: (existing?.version ?? 0) + 1,
              );

              final cascaded = webPh.saveOrUpdateRoute(
                routeObj,
                previousName: existing?.name,
              );

              if (mounted) {
                setState(() {
                  if (_selectedRouteForDrawer?.id == routeObj.id) {
                    _selectedRouteForDrawer = routeObj;
                  }
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isEdit
                          ? "Route '${routeObj.name}' updated & cascaded across $cascaded linked parties!"
                          : "Route '${routeObj.name}' created & synced!",
                    ),
                    backgroundColor: const Color(0xFFE11D48),
                  ),
                );
              }
            },
            icon: const Icon(Icons.save_rounded, size: 18),
            label: Text(isEdit ? "UPDATE & CASCADE" : "SAVE ROUTE"),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteRoute(PharoahWebManager webPh, RouteArea route, List<Party> linkedParties) {
    RouteArea? targetReassign;
    final otherRoutes = webPh.routes.where((r) => r.id != route.id).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(
              "Delete Route '${route.name}'?",
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
                    linkedParties.isEmpty
                        ? "No parties are currently assigned to this route. It will be permanently deleted across Web & Mobile App."
                        : "There are ${linkedParties.length} parties assigned to '${route.name}'. You can optionally move those parties to another route before deleting:",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  if (linkedParties.isNotEmpty && otherRoutes.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<RouteArea?>(
                      value: targetReassign,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 12.5),
                      decoration: InputDecoration(
                        labelText: "Reassign Parties To Route (Optional)",
                        labelStyle: const TextStyle(color: Colors.white60),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<RouteArea?>(
                          value: null,
                          child: Text("Reset to ALL / Unassigned"),
                        ),
                        ...otherRoutes.map(
                          (r) => DropdownMenuItem<RouteArea?>(
                            value: r,
                            child: Text(r.name),
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
                    webPh.mergeRoutes(
                      source: route,
                      target: targetReassign!,
                    );
                  } else {
                    webPh.deleteRouteMaster(route.id);
                  }
                  if (mounted) {
                    setState(() {
                      if (_selectedRouteForDrawer?.id == route.id) {
                        _selectedRouteForDrawer = null;
                      }
                    });
                    Navigator.pop(ctx);
                  }
                },
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: Text(targetReassign != null ? "REASSIGN & DELETE" : "DELETE ROUTE"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showMergeRoutesDialog(PharoahWebManager webPh) {
    if (webPh.routes.length < 2) return;
    RouteArea? sourceRoute = webPh.routes.first;
    RouteArea? targetRoute = webPh.routes.length > 1 ? webPh.routes[1] : null;

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
                  "MERGE DUPLICATE ROUTES",
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
                    "Move all parties from Source Route into Target Route and delete the duplicate Source Route:",
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<RouteArea>(
                    value: sourceRoute,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                    decoration: const InputDecoration(
                      labelText: "Duplicate Source Route (Will Be Removed)",
                      labelStyle: TextStyle(color: Colors.white60),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: webPh.routes
                        .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => sourceRoute = v),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<RouteArea>(
                    value: targetRoute,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                    decoration: const InputDecoration(
                      labelText: "Master Target Route (Will Keep All Parties)",
                      labelStyle: TextStyle(color: Colors.white60),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: webPh.routes
                        .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => targetRoute = v),
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
                  if (sourceRoute == null || targetRoute == null || sourceRoute!.id == targetRoute!.id) {
                    return;
                  }
                  webPh.mergeRoutes(source: sourceRoute!, target: targetRoute!);
                  if (mounted) {
                    setState(() => _selectedRouteForDrawer = targetRoute);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Merged '${sourceRoute!.name}' into '${targetRoute!.name}'!"),
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

  void _showBulkAssignPartiesToRouteDialog(PharoahWebManager webPh, RouteArea route) {
    String filterQ = "";
    final Set<String> selectedIds = {};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final candidates = webPh.parties.where((p) {
            if (MasterCascadeService.belongsToRoute(p, route)) return false;
            if (filterQ.isEmpty) return true;
            return p.name.toLowerCase().contains(filterQ.toLowerCase()) ||
                p.route.toLowerCase().contains(filterQ.toLowerCase()) ||
                p.phone.toLowerCase().contains(filterQ.toLowerCase());
          }).toList();

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(
              "Assign Parties to ${route.name}",
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
                      hintText: "Search parties to assign to ${route.name}...",
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
                        final p = candidates[i];
                        final checked = selectedIds.contains(p.id);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          title: Text(
                            p.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            "Current Route: ${p.route.isEmpty ? 'ALL' : p.route} • Ph: ${p.phone}",
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) {
                                selectedIds.add(p.id);
                              } else {
                                selectedIds.remove(p.id);
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
                  backgroundColor: const Color(0xFFE11D48),
                  foregroundColor: Colors.white,
                ),
                onPressed: selectedIds.isEmpty
                    ? null
                    : () {
                        for (final p in webPh.parties) {
                          if (selectedIds.contains(p.id)) {
                            p.route = route.name;
                            webPh.updateParty(p);
                          }
                        }
                        if (mounted) {
                          setState(() {});
                          Navigator.pop(ctx);
                        }
                      },
                child: Text("ASSIGN ${selectedIds.length} PARTIES"),
              ),
            ],
          );
        },
      ),
    );
  }
}
