// FILE: lib/web_live_sync/web_challan_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'web_pharoah_numbering_engine.dart';
import 'web_pdf_router_service.dart';
import 'web_challan_stitcher_wizard.dart';

class WebChallanView extends StatefulWidget {
  final VoidCallback onBack;
  final int initialTabIndex; // -1 for 5-Card Hub, 0 for Sale Challan, 1 for Pur Challan, 2 for Sale Reg, 3 for Pur Reg, 4 for Stitcher

  const WebChallanView({
    super.key,
    required this.onBack,
    this.initialTabIndex = -1,
  });

  @override
  State<WebChallanView> createState() => _WebChallanViewState();
}

class _WebChallanViewState extends State<WebChallanView> {
  late int activeIndex;

  // Register State
  DateTime regFromDate = DateTime.now();
  DateTime regToDate = DateTime.now();
  String registerSearch = "";
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    activeIndex = widget.initialTabIndex;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final webPh = Provider.of<PharoahWebManager>(context, listen: false);
      final now = DateTime.now();
      regToDate = DateTime(now.year, now.month, now.day);
      DateTime thirtyDaysAgo = regToDate.subtract(const Duration(days: 30));
      DateTime fyStart = WebAppDateLogic.getFYStart(webPh.financialYear);
      regFromDate = thirtyDaysAgo.isBefore(fyStart) ? fyStart : thirtyDaysAgo;
      _isInit = true;
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar with direct onBack handler
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
                onPressed: () {
                  if (activeIndex != -1) {
                    setState(() => activeIndex = -1);
                  } else {
                    widget.onBack();
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: Text(activeIndex != -1 ? "BACK TO CHALLANS HUB" : "BACK", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.local_shipping_rounded, color: Colors.tealAccent, size: 22),
              const SizedBox(width: 10),
              const Text(
                "CHALLAN MANAGEMENT",
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // --- HUB MODE: 5 BIG MODULE CARDS ---
          if (activeIndex == -1) _build5ChallanCards(webPh),

          // --- DEDICATED SUB-VIEWS ---
          if (activeIndex == 2) _buildSaleRegister(webPh),
          if (activeIndex == 3) _buildPurchaseRegister(webPh),
          if (activeIndex == 4) WebChallanStitcherWizard(onBack: () => setState(() => activeIndex = -1)),
        ],
      ),
    );
  }

  // ===========================================================================
  // 🎴 5 COMPLETE MODULE CARDS (Including Stitcher / Bill)
  // ===========================================================================
  Widget _build5ChallanCards(PharoahWebManager webPh) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = constraints.maxWidth > 1100 ? 5 : (constraints.maxWidth > 700 ? 3 : 1);

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.15,
          children: [
            _appModuleCard(
              title: "Sale Challan",
              subtitle: "Outward Delivery Note",
              icon: Icons.local_shipping_rounded,
              color: Colors.teal,
              onTap: () => widget.onBack(), // Opens direct new sale challan
            ),
            _appModuleCard(
              title: "Pur Challan",
              subtitle: "Inward Purchase Note",
              icon: Icons.inventory_2_rounded,
              color: Colors.orange,
              onTap: () => widget.onBack(), // Opens direct new pur challan
            ),
            _appModuleCard(
              title: "Sale Reg",
              subtitle: "${webPh.saleChallans.length} Outward Records",
              icon: Icons.list_alt_rounded,
              color: Colors.indigo,
              onTap: () => setState(() => activeIndex = 2),
            ),
            _appModuleCard(
              title: "Pur Reg",
              subtitle: "${webPh.purchaseChallans.length} Inward Records",
              icon: Icons.history_edu_rounded,
              color: Colors.amber.shade800,
              onTap: () => setState(() => activeIndex = 3),
            ),
            _appModuleCard(
              title: "Stitcher / Bill",
              subtitle: "Convert Challan to GST Bill",
              icon: Icons.auto_fix_high_rounded,
              color: Colors.purpleAccent,
              onTap: () => setState(() => activeIndex = 4),
            ),
          ],
        );
      },
    );
  }

  Widget _appModuleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withAlpha(100), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(20),
              blurRadius: 14,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withAlpha(35),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // --- SUB-SCREEN: SALE CHALLANS REGISTER (WITH WEB PORTAL BADGE) ---
  Widget _buildSaleRegister(PharoahWebManager webPh) {
    final activeShop = CompanyProfile.fromMap(webPh.companyProfile);
    final fDateOnly = _dateOnly(regFromDate);
    final tDateOnly = _dateOnly(regToDate);

    List<SaleChallan> list = List.from(webPh.saleChallans);
    list.sort((a, b) => b.date.compareTo(a.date));

    final filtered = list.where((c) {
      final cDateOnly = _dateOnly(c.date);
      bool dateMatch = !cDateOnly.isBefore(fDateOnly) && !cDateOnly.isAfter(tDateOnly);
      bool searchMatch = registerSearch.isEmpty ||
          c.partyName.toLowerCase().contains(registerSearch.toLowerCase()) || 
          c.billNo.toString().toLowerCase().contains(registerSearch.toLowerCase());
      return dateMatch && searchMatch;
    }).toList();

    double totalVal = filtered.fold(0.0, (s, c) => s + c.totalAmount);

    return Column(
      children: [
        _buildRegisterFilterBar(
          webPh, 
          onPrintReport: () => WebPdfRouterService.printChallanReport(challans: filtered, shop: activeShop, from: regFromDate, to: regToDate, isSaleChallan: true),
        ),
        const SizedBox(height: 12),
        filtered.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(30), child: Text("No Sale Challans found for selected date range.", style: TextStyle(color: Colors.white38))))
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                itemBuilder: (c, i) {
                  final item = filtered[i];
                  bool isPending = item.status == "Pending";
                  bool isWeb = item.id.startsWith("SCH-WEB") || item.salesmanName == "WEB-PORTAL";

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
                    child: ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: const BoxDecoration(color: Color(0x330F766E), borderRadius: BorderRadius.all(Radius.circular(6))),
                        child: const Text("SALE CH", style: TextStyle(color: Color(0xFF2DD4BF), fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ),
                      title: Row(
                        children: [
                          Text(item.partyName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 8),
                          _statusBadge(item.status.toUpperCase(), isPending),
                          if (isWeb) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0x3338BDF8),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF38BDF8), width: 0.5),
                              ),
                              child: const Text(
                                "WEB PORTAL",
                                style: TextStyle(color: Color(0xFF38BDF8), fontSize: 7.5, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text("Challan No: ${item.billNo} • Date: ${DateFormat('dd/MM/yyyy').format(item.date)} • Items: ${item.items.length}", style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("₹${item.totalAmount.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF2DD4BF), fontWeight: FontWeight.w900, fontSize: 14)),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.print_outlined, color: Color(0xFF38BDF8), size: 18),
                            tooltip: "Print Landscape Challan",
                            onPressed: () {
                              final pObj = webPh.parties.firstWhere((p) => p.name == item.partyName, orElse: () => Party(id: 'temp', name: item.partyName));
                              WebPdfRouterService.printSaleChallan(challan: item, party: pObj, shop: activeShop);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.download_rounded, color: Colors.greenAccent, size: 18),
                            tooltip: "Download PDF",
                            onPressed: () {
                              final pObj = webPh.parties.firstWhere((p) => p.name == item.partyName, orElse: () => Party(id: 'temp', name: item.partyName));
                              WebPdfRouterService.downloadSaleChallanPdf(challan: item, party: pObj, shop: activeShop);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                            tooltip: "Delete Challan",
                            onPressed: () {
                              webPh.deleteSaleChallan(item.id);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🗑️ Sale Challan Removed!"), backgroundColor: Colors.redAccent));
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("TOTAL SALE CHALLANS: ${filtered.length}", style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              Text("REGISTER VALUE: ₹${totalVal.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ],
    );
  }

  // --- SUB-SCREEN: PURCHASE CHALLANS REGISTER (WITH WEB PORTAL BADGE) ---
  Widget _buildPurchaseRegister(PharoahWebManager webPh) {
    final activeShop = CompanyProfile.fromMap(webPh.companyProfile);
    final fDateOnly = _dateOnly(regFromDate);
    final tDateOnly = _dateOnly(regToDate);

    List<PurchaseChallan> list = List.from(webPh.purchaseChallans);
    list.sort((a, b) => b.date.compareTo(a.date));

    final filtered = list.where((c) {
      final cDateOnly = _dateOnly(c.date);
      bool dateMatch = !cDateOnly.isBefore(fDateOnly) && !cDateOnly.isAfter(tDateOnly);
      bool searchMatch = registerSearch.isEmpty ||
          c.distributorName.toLowerCase().contains(registerSearch.toLowerCase()) || 
          c.internalNo.toString().toLowerCase().contains(registerSearch.toLowerCase()) ||
          c.billNo.toString().toLowerCase().contains(registerSearch.toLowerCase());
      return dateMatch && searchMatch;
    }).toList();

    double totalVal = filtered.fold(0.0, (s, c) => s + c.totalAmount);

    return Column(
      children: [
        _buildRegisterFilterBar(
          webPh, 
          onPrintReport: () => WebPdfRouterService.printChallanReport(challans: filtered, shop: activeShop, from: regFromDate, to: regToDate, isSaleChallan: false),
        ),
        const SizedBox(height: 12),
        filtered.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(30), child: Text("No Inward Purchase Challans found.", style: TextStyle(color: Colors.white38))))
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                itemBuilder: (c, i) {
                  final item = filtered[i];
                  bool isPending = item.status == "Pending";
                  bool isWeb = item.id.startsWith("PCH-WEB");

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
                    child: ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: const BoxDecoration(color: Color(0x33D97706), borderRadius: BorderRadius.all(Radius.circular(6))),
                        child: const Text("PUR CH", style: TextStyle(color: Color(0xFFFBBF24), fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ),
                      title: Row(
                        children: [
                          Text(item.distributorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 8),
                          _statusBadge(item.status.toUpperCase(), isPending),
                          if (isWeb) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0x3338BDF8),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF38BDF8), width: 0.5),
                              ),
                              child: const Text(
                                "WEB PORTAL",
                                style: TextStyle(color: Color(0xFF38BDF8), fontSize: 7.5, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text("ID: ${item.internalNo} • Ref: ${item.billNo} • Date: ${DateFormat('dd/MM/yyyy').format(item.date)} • Items: ${item.items.length}", style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("₹${item.totalAmount.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 14)),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.print_outlined, color: Color(0xFF38BDF8), size: 18),
                            tooltip: "Print Inward Slip",
                            onPressed: () {
                              final pObj = webPh.parties.firstWhere((p) => p.name == item.distributorName, orElse: () => Party(id: 'temp', name: item.distributorName));
                              WebPdfRouterService.printPurchaseChallan(challan: item, party: pObj, shop: activeShop);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.download_rounded, color: Colors.greenAccent, size: 18),
                            tooltip: "Download PDF",
                            onPressed: () {
                              final pObj = webPh.parties.firstWhere((p) => p.name == item.distributorName, orElse: () => Party(id: 'temp', name: item.distributorName));
                              WebPdfRouterService.downloadPurchaseChallanPdf(challan: item, party: pObj, shop: activeShop);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                            tooltip: "Delete Challan",
                            onPressed: () {
                              webPh.deletePurchaseChallan(item.id);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🗑️ Inward Challan Removed!"), backgroundColor: Colors.redAccent));
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("TOTAL INWARD CHALLANS: ${filtered.length}", style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              Text("REGISTER VALUE: ₹${totalVal.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterFilterBar(PharoahWebManager webPh, {required VoidCallback onPrintReport}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _dateTile("FROM DATE", regFromDate, (d) => setState(() => regFromDate = d), webPh.financialYear)),
              const SizedBox(width: 10),
              Expanded(child: _dateTile("TO DATE", regToDate, (d) => setState(() => regToDate = d), webPh.financialYear)),
              const SizedBox(width: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: onPrintReport,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text("PRINT REPORT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: const InputDecoration(
              hintText: "Search in Challans Register (Party, Challan No)...",
              hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
              prefixIcon: Icon(Icons.search, color: Color(0xFF0F766E), size: 16),
              filled: true, fillColor: Colors.black26,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (v) => setState(() => registerSearch = v),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String text, bool isPending) {
    Color bg = isPending ? const Color(0x33F59E0B) : const Color(0x3310B981);
    Color fg = isPending ? Colors.orangeAccent : Colors.greenAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4), border: Border.all(color: fg, width: 0.5)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 7.5, fontWeight: FontWeight.w900)),
    );
  }

  Widget _dateTile(String label, DateTime d, Function(DateTime) onPick, String fy) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: d,
          firstDate: WebAppDateLogic.getFYStart(fy),
          lastDate: WebAppDateLogic.getFYEnd(fy),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.black26, border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 8.5, color: Colors.white54, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(DateFormat('dd/MM/yyyy').format(d), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
              ],
            ),
            const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 16),
          ],
        ),
      ),
    );
  }
}
