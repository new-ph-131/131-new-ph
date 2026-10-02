// FILE: lib/web_live_sync/web_challan_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'web_pdf_router_service.dart';

class WebChallanView extends StatefulWidget {
  final VoidCallback onBack;
  final int initialTabIndex; // 2 for Sale Reg, 3 for Pur Reg

  const WebChallanView({
    super.key,
    required this.onBack,
    this.initialTabIndex = 2,
  });

  @override
  State<WebChallanView> createState() => _WebChallanViewState();
}

class _WebChallanViewState extends State<WebChallanView> {
  late int activeIndex;

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
                label: const Text("BACK TO CHALLANS HUB", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.local_shipping_rounded, color: Colors.tealAccent, size: 22),
              const SizedBox(width: 10),
              Text(
                activeIndex == 3 ? "PURCHASE CHALLAN (INWARD) REGISTER" : "SALE CHALLAN (OUTWARD) REGISTER",
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (activeIndex == 3)
            _buildPurchaseRegister(webPh)
          else
            _buildSaleRegister(webPh),
        ],
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
