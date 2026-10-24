// FILE: lib/web_live_sync/web_company_master.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'pharoah_web_manager.dart';
import 'web_models.dart';
import '../logic/master_cascade_service.dart';

class _CompanyStats {
  final Company company;
  final List<Medicine> linkedMedicines;
  final double totalStockUnits;
  final double purValuation;
  final double mrpValuation;

  _CompanyStats({
    required this.company,
    required this.linkedMedicines,
    required this.totalStockUnits,
    required this.purValuation,
    required this.mrpValuation,
  });
}

class WebCompanyMasterView extends StatefulWidget {
  final VoidCallback onBack;
  const WebCompanyMasterView({super.key, required this.onBack});

  @override
  State<WebCompanyMasterView> createState() => _WebCompanyMasterViewState();
}

class _WebCompanyMasterViewState extends State<WebCompanyMasterView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _activeFilter = "ALL"; // ALL, WITH_ITEMS, IN_STOCK, EMPTY
  String _sortBy = "NAME"; // NAME, ITEMS, VALUATION

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_CompanyStats> _computeCompanyStats(PharoahWebManager webPh) {
    final List<_CompanyStats> result = [];
    for (final c in webPh.companies) {
      final meds = webPh.medicines.where((m) => MasterCascadeService.belongsToCompany(m, c)).toList();
      double stockUnits = 0.0;
      double purVal = 0.0;
      double mrpVal = 0.0;
      for (final m in meds) {
        if (m.stock > 0) {
          stockUnits += m.stock;
          purVal += m.stock * (m.purRate > 0 ? m.purRate : m.rateA);
          mrpVal += m.stock * m.mrp;
        }
      }
      result.add(_CompanyStats(
        company: c,
        linkedMedicines: meds,
        totalStockUnits: stockUnits,
        purValuation: purVal,
        mrpValuation: mrpVal,
      ));
    }
    return result;
  }

  void _showAddOrEditCompanyDialog(PharoahWebManager webPh, {Company? comp, int linkedCount = 0}) {
    final nameC = TextEditingController(text: comp?.name ?? "");
    final String? previousName = comp?.name;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.business_rounded, color: Color(0xFFF59E0B), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                comp == null ? "REGISTER NEW COMPANY / BRAND" : "MODIFY COMPANY BRAND (CASCADE SYNC)",
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (comp != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sync_alt_rounded, color: Color(0xFF38BDF8), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Master Cascade Active: Renaming '${comp.name}' will automatically update all $linkedCount linked product(s), stock reports, and shortage records across Web & Mobile App.",
                          style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              const Text(
                "COMPANY / MANUFACTURER NAME *",
                style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: nameC,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: "e.g. CIPLA LTD / SUN PHARMA / MANKIND",
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                  prefixIcon: const Icon(Icons.domain_rounded, color: Color(0xFFF59E0B), size: 18),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final cleanName = nameC.text.trim().toUpperCase();
              if (cleanName.isEmpty) return;
              final mutated = webPh.saveOrUpdateCompany(
                Company(
                  id: comp?.id ?? "",
                  name: cleanName,
                  version: comp?.version ?? 1,
                  updatedAt: comp?.updatedAt ?? 0,
                ),
                previousName: previousName,
              );
              Navigator.pop(ctx);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF059669),
                  content: Text(
                    comp == null
                        ? "Company '$cleanName' registered & synced to Cloud D1!"
                        : "Company updated to '$cleanName' • Cascaded to $mutated product(s) & synced!",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: Text(comp == null ? "SAVE COMPANY" : "UPDATE & CASCADE", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  void _showDeleteCompanyDialog(PharoahWebManager webPh, _CompanyStats stats) {
    final comp = stats.company;
    final linkedCount = stats.linkedMedicines.length;
    String? reassignCompId;
    final otherCompanies = webPh.companies.where((c) => c.id != comp.id).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Colors.white12),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "DELETE COMPANY '${comp.name}'?",
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  linkedCount > 0
                      ? "'${comp.name}' is currently linked to $linkedCount product(s) in your catalog. You can optionally reassign those products to another company before deleting."
                      : "Are you sure you want to permanently delete '${comp.name}'? This deletion will sync across Web & Mobile App.",
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
                if (linkedCount > 0 && otherCompanies.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    "OPTIONAL: REASSIGN LINKED PRODUCTS TO ANOTHER COMPANY",
                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    value: reassignCompId,
                    dropdownColor: const Color(0xFF0F172A),
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    hint: const Text("Leave Unassigned (Clear Company on Products)", style: TextStyle(color: Colors.white38, fontSize: 11)),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text("Clear Company on Linked Products", style: TextStyle(color: Colors.white54)),
                      ),
                      ...otherCompanies.map((c) => DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(c.name),
                          )),
                    ],
                    onChanged: (v) => setDialogState(() => reassignCompId = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final affected = webPh.deleteCompanyMaster(comp.id, reassignToCompanyId: reassignCompId);
                Navigator.pop(ctx);
                setState(() {});
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFFDC2626),
                    content: Text("Deleted '${comp.name}' ($affected product(s) updated) & synced to D1!"),
                  ),
                );
              },
              icon: const Icon(Icons.delete_forever_rounded, size: 16),
              label: const Text("CONFIRM DELETE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  void _showMergeCompaniesModal(PharoahWebManager webPh) {
    if (webPh.companies.length < 2) return;
    Company? sourceComp;
    Company? targetComp;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.white12)),
          title: const Row(
            children: [
              Icon(Icons.merge_type_rounded, color: Color(0xFF38BDF8), size: 22),
              SizedBox(width: 10),
              Text("MERGE DUPLICATE COMPANY BRANDS", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Select a duplicate/old Company to merge into your primary Company. All linked products & shortages will automatically transfer to the target Company.",
                  style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
                ),
                const SizedBox(height: 16),
                const Text("1. SOURCE COMPANY (WILL BE MERGED & REMOVED)", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButtonFormField<Company>(
                  value: sourceComp,
                  dropdownColor: const Color(0xFF0F172A),
                  isExpanded: true,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  hint: const Text("Select Duplicate Company", style: TextStyle(color: Colors.white38, fontSize: 11)),
                  items: webPh.companies.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                  onChanged: (v) => setDialogState(() => sourceComp = v),
                ),
                const SizedBox(height: 14),
                const Text("2. TARGET PRIMARY COMPANY (WILL KEEP ALL PRODUCTS)", style: TextStyle(color: Color(0xFF34D399), fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButtonFormField<Company>(
                  value: targetComp,
                  dropdownColor: const Color(0xFF0F172A),
                  isExpanded: true,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  hint: const Text("Select Target Primary Company", style: TextStyle(color: Colors.white38, fontSize: 11)),
                  items: webPh.companies
                      .where((c) => sourceComp == null || c.id != sourceComp!.id)
                      .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => targetComp = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
              onPressed: (sourceComp == null || targetComp == null || sourceComp!.id == targetComp!.id)
                  ? null
                  : () {
                      final moved = webPh.mergeCompanies(source: sourceComp!, target: targetComp!);
                      Navigator.pop(ctx);
                      setState(() {});
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF059669),
                          content: Text("Merged '${sourceComp!.name}' into '${targetComp!.name}' ($moved products moved)!"),
                        ),
                      );
                    },
              icon: const Icon(Icons.merge_rounded, size: 16),
              label: const Text("MERGE BRANDS NOW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCompanyProductsDrawer(PharoahWebManager webPh, _CompanyStats stats) {
    String assignSearch = "";
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final currentLinked = webPh.medicines.where((m) => MasterCascadeService.belongsToCompany(m, stats.company)).toList();
          final otherMeds = webPh.medicines
              .where((m) =>
                  !MasterCascadeService.belongsToCompany(m, stats.company) &&
                  (assignSearch.isEmpty || m.name.toLowerCase().contains(assignSearch.toLowerCase())))
              .take(25)
              .toList();

          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.white12)),
            title: Row(
              children: [
                const Icon(Icons.inventory_2_rounded, color: Color(0xFFF59E0B), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${stats.company.name} • PRODUCT PORTFOLIO (${currentLinked.length} ITEMS)",
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        "Company ID: ${stats.company.id} • Total Stock Value: ₹${NumberFormat('#,##,##0.00').format(stats.purValuation)}",
                        style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
            content: SizedBox(
              width: 720,
              height: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("LINKED PRODUCTS UNDER THIS COMPANY", style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: currentLinked.isEmpty
                          ? const Center(child: Text("No products currently mapped to this company.", style: TextStyle(color: Colors.white38, fontSize: 12)))
                          : ListView.separated(
                              itemCount: currentLinked.length,
                              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                              itemBuilder: (_, idx) {
                                final m = currentLinked[idx];
                                return ListTile(
                                  dense: true,
                                  title: Text("${m.name} (${m.packing})", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                  subtitle: Text(
                                    "ID: ${m.systemId} • Salt: ${webPh.resolveSaltName(m.saltId)} • MRP: ₹${m.mrp.toStringAsFixed(2)} • Pur: ₹${m.purRate.toStringAsFixed(2)}",
                                    style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: (m.stock > 0 ? const Color(0xFF10B981) : Colors.redAccent).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          "${m.stock.toInt()} Units",
                                          style: TextStyle(color: m.stock > 0 ? const Color(0xFF34D399) : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10.5),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: "Unlink product from ${stats.company.name}",
                                        icon: const Icon(Icons.link_off_rounded, color: Colors.white38, size: 16),
                                        onPressed: () {
                                          m.companyId = "";
                                          webPh.updateMedicine(m);
                                          setModalState(() {});
                                          setState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text("QUICK ASSIGN EXISTING PRODUCT TO THIS COMPANY", style: TextStyle(color: Color(0xFFFBBF24), fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: "Search product name to assign to ${stats.company.name}...",
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFFFBBF24), size: 16),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onChanged: (v) => setModalState(() => assignSearch = v),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ListView.builder(
                        itemCount: otherMeds.length,
                        itemBuilder: (_, idx) {
                          final m = otherMeds[idx];
                          final curComp = webPh.resolveCompanyName(m.companyId);
                          return ListTile(
                            dense: true,
                            title: Text("${m.name} (${m.packing})", style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                            subtitle: Text("Current Company: $curComp", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            trailing: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                              ),
                              onPressed: () {
                                m.companyId = stats.company.id;
                                webPh.updateMedicine(m);
                                setModalState(() {});
                                setState(() {});
                              },
                              icon: const Icon(Icons.add_link_rounded, size: 14),
                              label: const Text("LINK HERE", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final allStats = _computeCompanyStats(webPh);

    final int activeBrandsCount = allStats.where((s) => s.linkedMedicines.isNotEmpty).length;
    final int totalLinkedProducts = allStats.fold(0, (sum, s) => sum + s.linkedMedicines.length);
    final double totalPurValuation = allStats.fold(0.0, (sum, s) => sum + s.purValuation);
    final double totalMrpValuation = allStats.fold(0.0, (sum, s) => sum + s.mrpValuation);

    List<_CompanyStats> filtered = allStats.where((s) {
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final matchName = s.company.name.toLowerCase().contains(q);
        final matchId = s.company.id.toLowerCase().contains(q);
        final matchMed = s.linkedMedicines.any((m) => m.name.toLowerCase().contains(q));
        if (!matchName && !matchId && !matchMed) return false;
      }
      switch (_activeFilter) {
        case "WITH_ITEMS":
          return s.linkedMedicines.isNotEmpty;
        case "IN_STOCK":
          return s.totalStockUnits > 0;
        case "EMPTY":
          return s.linkedMedicines.isEmpty;
        default:
          return true;
      }
    }).toList();

    if (_sortBy == "ITEMS") {
      filtered.sort((a, b) => b.linkedMedicines.length.compareTo(a.linkedMedicines.length));
    } else if (_sortBy == "VALUATION") {
      filtered.sort((a, b) => b.purValuation.compareTo(a.purValuation));
    } else {
      filtered.sort((a, b) => a.company.name.compareTo(b.company.name));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenH = MediaQuery.of(context).size.height;
        final double boundedHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : (screenH - 104.0).clamp(580.0, 1400.0);

        return SizedBox(
          width: double.infinity,
          height: boundedHeight,
          child: Container(
            width: double.infinity,
            height: boundedHeight,
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TOP HEADER BAR
                Row(
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
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.business_rounded, color: Color(0xFFF59E0B), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "COMPANY & MANUFACTURER MASTER",
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                          ),
                          Text(
                            "Central Brand Command • Automatic Cascade Rename Across Products, Stock & Shortages • Real-Time D1 Sync",
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(color: Color(0xFF38BDF8)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _showMergeCompaniesModal(webPh),
                      icon: const Icon(Icons.merge_type_rounded, size: 17),
                      label: const Text("MERGE DUPLICATES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _showAddOrEditCompanyDialog(webPh),
                      icon: const Icon(Icons.add_business_rounded, size: 17),
                      label: const Text("ADD NEW COMPANY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 2. KPI STRIP
                Row(
                  children: [
                    Expanded(
                      child: _kpiCard(
                        title: "TOTAL REGISTERED BRANDS",
                        value: "${allStats.length}",
                        subtitle: "Synced in Company Master",
                        icon: Icons.domain_rounded,
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _kpiCard(
                        title: "ACTIVE BRANDS IN CATALOG",
                        value: "$activeBrandsCount",
                        subtitle: "${allStats.length - activeBrandsCount} unused brand entries",
                        icon: Icons.verified_rounded,
                        color: const Color(0xFF38BDF8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _kpiCard(
                        title: "MAPPED CATALOG PRODUCTS",
                        value: "$totalLinkedProducts / ${webPh.medicines.length}",
                        subtitle: "Auto-cascaded on brand edit",
                        icon: Icons.medication_rounded,
                        color: const Color(0xFFA78BFA),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _kpiCard(
                        title: "BRAND STOCK VALUATION",
                        value: "₹${NumberFormat('#,##,##0').format(totalPurValuation)}",
                        subtitle: "MRP Value: ₹${NumberFormat('#,##,##0').format(totalMrpValuation)}",
                        icon: Icons.account_balance_wallet_rounded,
                        color: const Color(0xFF34D399),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 3. SEARCH, FILTER CHIPS & SORT BAR
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                              hintText: "Search by Company Name, ID, or any Product under that Company...",
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
                              prefixIcon: const Icon(Icons.search, color: Color(0xFFF59E0B), size: 17),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, color: Colors.white54, size: 14),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = "");
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: Colors.black26,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            ),
                            onChanged: (v) => setState(() => _searchQuery = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _filterChip("ALL (${allStats.length})", "ALL"),
                      const SizedBox(width: 6),
                      _filterChip("WITH PRODUCTS ($activeBrandsCount)", "WITH_ITEMS"),
                      const SizedBox(width: 6),
                      _filterChip("IN STOCK", "IN_STOCK"),
                      const SizedBox(width: 6),
                      _filterChip("UNUSED (${allStats.length - activeBrandsCount})", "EMPTY"),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _sortBy,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            items: const [
                              DropdownMenuItem(value: "NAME", child: Text("SORT: NAME (A-Z)")),
                              DropdownMenuItem(value: "ITEMS", child: Text("SORT: MOST PRODUCTS")),
                              DropdownMenuItem(value: "VALUATION", child: Text("SORT: HIGHEST VALUE")),
                            ],
                            onChanged: (v) => setState(() => _sortBy = v!),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 4. STICKY-HEADER VIRTUALIZED TABLE
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                            color: const Color(0xFF090D16),
                            child: const Row(
                              children: [
                                Expanded(flex: 2, child: Text("COMPANY ID", style: _thStyle)),
                                Expanded(flex: 4, child: Text("COMPANY / MANUFACTURER NAME", style: _thStyle)),
                                Expanded(flex: 2, child: Text("LINKED ITEMS", style: _thStyle)),
                                Expanded(flex: 2, child: Text("LIVE STOCK", style: _thStyle)),
                                Expanded(flex: 3, child: Text("STOCK VALUATION (PUR ₹)", style: _thStyle)),
                                Expanded(flex: 5, child: Text("TOP CATALOG PRODUCTS PREVIEW", style: _thStyle)),
                                Expanded(flex: 4, child: Text("ACTIONS", style: _thStyle)),
                              ],
                            ),
                          ),
                          const Divider(color: Colors.white12, height: 1),
                          Expanded(
                            child: filtered.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.business_outlined, color: Colors.white24, size: 48),
                                        const SizedBox(height: 10),
                                        const Text("No companies match your current search or filter.", style: TextStyle(color: Colors.white54, fontSize: 13)),
                                        const SizedBox(height: 12),
                                        ElevatedButton.icon(
                                          onPressed: () => _showAddOrEditCompanyDialog(webPh),
                                          icon: const Icon(Icons.add, size: 16),
                                          label: const Text("ADD NEW COMPANY"),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (ctx, i) {
                                      final st = filtered[i];
                                      final comp = st.company;
                                      final sampleProducts = st.linkedMedicines.take(3).map((m) => m.name).join(", ");
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                        decoration: const BoxDecoration(
                                          border: Border(bottom: BorderSide(color: Colors.white10)),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                comp.id,
                                                style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 4,
                                              child: InkWell(
                                                onTap: () => _showCompanyProductsDrawer(webPh, st),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.domain_rounded, color: Color(0xFFF59E0B), size: 16),
                                                    const SizedBox(width: 8),
                                                    Flexible(
                                                      child: Text(
                                                        comp.name,
                                                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: InkWell(
                                                  onTap: () => _showCompanyProductsDrawer(webPh, st),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: (st.linkedMedicines.isNotEmpty ? const Color(0xFF38BDF8) : Colors.white24).withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: (st.linkedMedicines.isNotEmpty ? const Color(0xFF38BDF8) : Colors.white24).withOpacity(0.35),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      "${st.linkedMedicines.length} Products",
                                                      style: TextStyle(
                                                        color: st.linkedMedicines.isNotEmpty ? const Color(0xFF38BDF8) : Colors.white38,
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                "${st.totalStockUnits.toInt()} Units",
                                                style: TextStyle(
                                                  color: st.totalStockUnits > 0 ? const Color(0xFF34D399) : Colors.white38,
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "₹${NumberFormat('#,##,##0.00').format(st.purValuation)}",
                                                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                                  ),
                                                  Text(
                                                    "MRP: ₹${NumberFormat('#,##,##0').format(st.mrpValuation)}",
                                                    style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              flex: 5,
                                              child: Text(
                                                sampleProducts.isNotEmpty ? sampleProducts : "Click 'PRODUCTS' to link items",
                                                style: TextStyle(
                                                  color: sampleProducts.isNotEmpty ? Colors.white70 : Colors.white24,
                                                  fontSize: 11,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 4,
                                              child: Row(
                                                children: [
                                                  ElevatedButton.icon(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFF0F766E),
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                    onPressed: () => _showCompanyProductsDrawer(webPh, st),
                                                    icon: const Icon(Icons.inventory_2_outlined, size: 13),
                                                    label: const Text("PRODUCTS", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  ElevatedButton.icon(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFF2563EB),
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                    onPressed: () => _showAddOrEditCompanyDialog(webPh, comp: comp, linkedCount: st.linkedMedicines.length),
                                                    icon: const Icon(Icons.edit_note_rounded, size: 14),
                                                    label: const Text("MODIFY", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  ElevatedButton.icon(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFFDC2626),
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                    onPressed: () => _showDeleteCompanyDialog(webPh, st),
                                                    icon: const Icon(Icons.delete_outline_rounded, size: 13),
                                                    label: const Text("DELETE", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                                                  ),
                                                ],
                                              ),
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
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filterChip(String label, String key) {
    final bool active = _activeFilter == key;
    return InkWell(
      onTap: () => setState(() => _activeFilter = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF59E0B).withOpacity(0.2) : Colors.black26,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? const Color(0xFFF59E0B) : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFFFBBF24) : Colors.white60,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, fontFamily: 'monospace')),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 9.5), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _thStyle = TextStyle(
    color: Colors.white54,
    fontSize: 9.5,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );
}
