// FILE: lib/web_live_sync/web_challan_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'web_pdf_router_service.dart';
import 'sub_views/web_challans/web_sale_challan_billing_view.dart';
import 'sub_views/web_challans/web_purchase_challan_billing_view.dart';
import 'sub_views/web_challans/web_sale_challan_view.dart';
import 'sub_views/web_challans/web_purchase_challan_view.dart';

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

  // --- SUB-SCREEN: SALE CHALLANS REGISTER (WITH MODIFY & DELETE GUARDS) ---
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
          onPrintReport: () => WebPdfRouterService.printChallanReport(
            challans: filtered, 
            shop: activeShop, 
            from: regFromDate, 
            to: regToDate, 
            isSaleChallan: true
          ),
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
                  bool isBilled = item.status == "Billed";
                  bool isWeb = item.id.startsWith("SCH-WEB") || (item.salesmanName == "WEB-PORTAL");

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isBilled ? Colors.teal.withOpacity(0.3) : Colors.white10),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isBilled ? const Color(0x3314B8A6) : const Color(0x33F59E0B), 
                          shape: BoxShape.circle,
                        ),
                        child: Text("${i + 1}", style: TextStyle(color: isBilled ? Colors.tealAccent : Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.partyName, 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _statusBadge(item.status.toUpperCase(), isPending),
                          if (isWeb) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0x332DD4BF),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF2DD4BF), width: 0.5),
                              ),
                              child: const Text(
                                "WEB PORTAL",
                                style: TextStyle(color: Color(0xFF2DD4BF), fontSize: 7.5, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        "Challan No: ${item.billNo} • Date: ${DateFormat('dd/MM/yyyy').format(item.date)} • Items: ${item.items.length}", 
                        style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("₹${item.totalAmount.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF2DD4BF), fontWeight: FontWeight.w900, fontSize: 14)),
                          const SizedBox(width: 10),
                          // 👁️ VIEW ITEMS (READ-ONLY)
                          IconButton(
                            icon: const Icon(Icons.visibility_outlined, color: Colors.cyanAccent, size: 18),
                            tooltip: "View Challan Items",
                            onPressed: () => _openSaleChallanDetails(context, webPh, item, isReadOnly: true),
                          ),
                          // ✏️ EDIT / MODIFY CHALLAN (GUARDED)
                          IconButton(
                            icon: Icon(
                              Icons.edit_note_rounded, 
                              color: isBilled ? Colors.white24 : Colors.orangeAccent, 
                              size: 20
                            ),
                            tooltip: isBilled ? "Locked: Already Billed" : "Modify Challan",
                            onPressed: () {
                              if (isBilled) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("🔒 Locked: Sale Bill has already been generated from this Challan!"),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }
                              _openSaleChallanDetails(context, webPh, item, isReadOnly: false);
                            },
                          ),
                          // 🖨️ PRINT
                          IconButton(
                            icon: const Icon(Icons.print_outlined, color: Color(0xFF38BDF8), size: 18),
                            tooltip: "Print Outward Note",
                            onPressed: () {
                              final pObj = webPh.parties.firstWhere(
                                (p) => p.name == item.partyName, 
                                orElse: () => Party(id: 'temp', name: item.partyName, gst: item.partyGstin, state: item.partyState)
                              );
                              WebPdfRouterService.printSaleChallan(challan: item, party: pObj, shop: activeShop);
                            },
                          ),
                          // 📥 DOWNLOAD PDF
                          IconButton(
                            icon: const Icon(Icons.download_rounded, color: Colors.greenAccent, size: 18),
                            tooltip: "Download PDF",
                            onPressed: () {
                              final pObj = webPh.parties.firstWhere(
                                (p) => p.name == item.partyName, 
                                orElse: () => Party(id: 'temp', name: item.partyName, gst: item.partyGstin, state: item.partyState)
                              );
                              WebPdfRouterService.downloadSaleChallanPdf(challan: item, party: pObj, shop: activeShop);
                            },
                          ),
                          // 🗑️ DELETE (WITH CONFIRMATION & BILL CHECK)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                            tooltip: "Delete Challan",
                            onPressed: () => _confirmDeleteSaleChallan(context, webPh, item),
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
              Text("TOTAL OUTWARD CHALLANS: ${filtered.length}", style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              Text("REGISTER VALUE: ₹${totalVal.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ],
    );
  }

  // --- SUB-SCREEN: PURCHASE CHALLANS REGISTER (WITH MODIFY & DELETE GUARDS) ---
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
          c.internalNo.toLowerCase().contains(registerSearch.toLowerCase()) || 
          c.billNo.toLowerCase().contains(registerSearch.toLowerCase());
      return dateMatch && searchMatch;
    }).toList();

    double totalVal = filtered.fold(0.0, (s, c) => s + c.totalAmount);

    return Column(
      children: [
        _buildRegisterFilterBar(
          webPh, 
          onPrintReport: () => WebPdfRouterService.printChallanReport(
            challans: filtered, 
            shop: activeShop, 
            from: regFromDate, 
            to: regToDate, 
            isSaleChallan: false
          ),
        ),
        const SizedBox(height: 12),
        filtered.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(30), child: Text("No Inward Challans found for selected date range.", style: TextStyle(color: Colors.white38))))
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                itemBuilder: (c, i) {
                  final item = filtered[i];
                  bool isPending = item.status == "Pending";
                  bool isBilled = item.status == "Billed";
                  bool isWeb = item.id.startsWith("PCH-WEB") || item.internalNo.startsWith("PCH-WEB") || item.remarks.contains("WEB-PORTAL");

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isBilled ? Colors.amber.withOpacity(0.3) : Colors.white10),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isBilled ? const Color(0x33F59E0B) : const Color(0x3338BDF8), 
                          shape: BoxShape.circle,
                        ),
                        child: Text("${i + 1}", style: TextStyle(color: isBilled ? Colors.amberAccent : const Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.distributorName, 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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
                      subtitle: Text(
                        "ID: ${item.internalNo} • Ref: ${item.billNo} • Date: ${DateFormat('dd/MM/yyyy').format(item.date)} • Items: ${item.items.length}", 
                        style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("₹${item.totalAmount.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 14)),
                          const SizedBox(width: 10),
                          // 👁️ VIEW ITEMS (READ-ONLY)
                          IconButton(
                            icon: const Icon(Icons.visibility_outlined, color: Colors.cyanAccent, size: 18),
                            tooltip: "View Inward Details",
                            onPressed: () => _openPurchaseChallanDetails(context, webPh, item, isReadOnly: true),
                          ),
                          // ✏️ EDIT / MODIFY INWARD CHALLAN (GUARDED)
                          IconButton(
                            icon: Icon(
                              Icons.edit_note_rounded, 
                              color: isBilled ? Colors.white24 : Colors.orangeAccent, 
                              size: 20
                            ),
                            tooltip: isBilled ? "Locked: Already Invoiced" : "Modify Inward Challan",
                            onPressed: () {
                              if (isBilled) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("🔒 Locked: Purchase Invoice has already been generated from this Inward Challan!"),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }
                              _openPurchaseChallanDetails(context, webPh, item, isReadOnly: false);
                            },
                          ),
                          // 🖨️ PRINT
                          IconButton(
                            icon: const Icon(Icons.print_outlined, color: Color(0xFF38BDF8), size: 18),
                            tooltip: "Print Inward Slip",
                            onPressed: () {
                              final pObj = webPh.parties.firstWhere(
                                (p) => p.name == item.distributorName, 
                                orElse: () => Party(id: 'temp', name: item.distributorName)
                              );
                              WebPdfRouterService.printPurchaseChallan(challan: item, party: pObj, shop: activeShop);
                            },
                          ),
                          // 📥 DOWNLOAD PDF
                          IconButton(
                            icon: const Icon(Icons.download_rounded, color: Colors.greenAccent, size: 18),
                            tooltip: "Download PDF",
                            onPressed: () {
                              final pObj = webPh.parties.firstWhere(
                                (p) => p.name == item.distributorName, 
                                orElse: () => Party(id: 'temp', name: item.distributorName)
                              );
                              WebPdfRouterService.downloadPurchaseChallanPdf(challan: item, party: pObj, shop: activeShop);
                            },
                          ),
                          // 🗑️ DELETE (WITH CONFIRMATION & BILL CHECK)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                            tooltip: "Delete Inward Challan",
                            onPressed: () => _confirmDeletePurchaseChallan(context, webPh, item),
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

  // --- ROUTING HANDLERS ---
  void _openSaleChallanDetails(BuildContext context, PharoahWebManager webPh, SaleChallan ch, {required bool isReadOnly}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => WebSaleChallanView(
          onBack: () => Navigator.pop(c),
          existingRecord: ch,
          isReadOnly: isReadOnly,
        ),
      ),
    );
  }

  void _openPurchaseChallanDetails(BuildContext context, PharoahWebManager webPh, PurchaseChallan ch, {required bool isReadOnly}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => WebPurchaseChallanView(
          onBack: () => Navigator.pop(c),
          existingRecord: ch,
          isReadOnly: isReadOnly,
        ),
      ),
    );
  }

  // --- SAFE DELETION DIALOGS ---
  void _confirmDeleteSaleChallan(BuildContext context, PharoahWebManager webPh, SaleChallan ch) {
    bool isBilled = ch.status == "Billed";

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white12)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            const Text("Delete Sale Challan?", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Challan No: ${ch.billNo} • Customer: ${ch.partyName}",
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isBilled
                  ? "⚠️ WARNING: This challan is already marked as BILLED. Deleting it may cause mismatches with existing sale bills!"
                  : "Are you sure you want to permanently delete this challan? This will remove the record and reverse stock impact.",
              style: TextStyle(color: isBilled ? Colors.orangeAccent : Colors.white60, fontSize: 11.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              webPh.deleteSaleChallan(ch.id);
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("🗑️ Sale Challan Deleted Permanently!"), backgroundColor: Colors.redAccent),
              );
            },
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text("YES, DELETE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePurchaseChallan(BuildContext context, PharoahWebManager webPh, PurchaseChallan ch) {
    bool isBilled = ch.status == "Billed";

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white12)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            const Text("Delete Inward Challan?", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Inward Ref: ${ch.billNo} • Supplier: ${ch.distributorName}",
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isBilled
                  ? "⚠️ WARNING: This inward challan is already converted to a Purchase Bill. Deleting it may impact purchase records!"
                  : "Are you sure you want to permanently delete this inward entry? This will reverse stock and delete the record.",
              style: TextStyle(color: isBilled ? Colors.orangeAccent : Colors.white60, fontSize: 11.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              webPh.deletePurchaseChallan(ch.id);
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("🗑️ Inward Challan Deleted Permanently!"), backgroundColor: Colors.redAccent),
              );
            },
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text("YES, DELETE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
