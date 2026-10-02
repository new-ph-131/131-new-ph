// FILE: lib/web_live_sync/web_purchase_summary_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'web_pdf_router_service.dart';
import 'web_purchase_entry_view.dart';

class WebPurchaseSummaryView extends StatefulWidget {
  final VoidCallback onBack;

  const WebPurchaseSummaryView({super.key, required this.onBack});

  @override
  State<WebPurchaseSummaryView> createState() => _WebPurchaseSummaryViewState();
}

class _WebPurchaseSummaryViewState extends State<WebPurchaseSummaryView> {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  String searchQuery = "";
  bool _isInit = false;
  bool showAllDates = false;

  bool isSelectionMode = false;
  List<String> selectedPurchaseIds = [];
  bool isProcessing = false;
  double progressValue = 0.0;
  String progressText = "";

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final webPh = Provider.of<PharoahWebManager>(context, listen: false);
      final now = DateTime.now();
      toDate = DateTime(now.year, now.month, now.day);
      DateTime thirtyDaysAgo = toDate.subtract(const Duration(days: 30));
      DateTime fyStart = WebAppDateLogic.getFYStart(webPh.financialYear);
      fromDate = thirtyDaysAgo.isBefore(fyStart) ? fyStart : thirtyDaysAgo;
      _isInit = true;
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final activeShop = CompanyProfile.fromMap(webPh.companyProfile);

    final fDateOnly = _dateOnly(fromDate);
    final tDateOnly = _dateOnly(toDate);

    List<Purchase> filteredPurchases = webPh.purchases.reversed.where((p) {
      final pDateOnly = _dateOnly(p.date);
      bool dateMatch = showAllDates || (!pDateOnly.isBefore(fDateOnly) && !pDateOnly.isAfter(tDateOnly));
      bool searchMatch = searchQuery.isEmpty ||
          p.distributorName.toLowerCase().contains(searchQuery.toLowerCase()) || 
          p.billNo.toLowerCase().contains(searchQuery.toLowerCase()) ||
          p.internalNo.toLowerCase().contains(searchQuery.toLowerCase());

      return dateMatch && searchMatch;
    }).toList();

    double totalTaxable = 0.0;
    double totalITC = 0.0;
    double netTotal = 0.0;
    double cashTotal = 0.0;
    double creditTotal = 0.0;

    for (var p in filteredPurchases) {
      double pTaxable = p.items.fold(0.0, (sum, it) => sum + (it.purchaseRate * it.qty - it.discountRupees));
      totalTaxable += pTaxable; 
      totalITC += (p.totalAmount - pTaxable); 
      netTotal += p.totalAmount;
      if (p.paymentMode.toUpperCase() == 'CASH') {
        cashTotal += p.totalAmount;
      } else {
        creditTotal += p.totalAmount;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                label: const Text("BACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.history_rounded, color: Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 10),
              const Text(
                "PURCHASE REGISTER / AUDIT",
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
              const Spacer(),

              // EXACT APP WORKFLOW: PopupMenuButton for Summary PDF Actions
              if (filteredPurchases.isNotEmpty) ...[
                PopupMenuButton<String>(
                  icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.picture_as_pdf_rounded, size: 16, color: Colors.white),
                        SizedBox(width: 6),
                        Text("SUMMARY PDF", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5)),
                        Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
                      ],
                    ),
                  ),
                  tooltip: "Inward Summary Report PDF Actions",
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white12)),
                  onSelected: (val) {
                    if (val == 'print') {
                      WebPdfRouterService.printPurchaseReport(purchases: filteredPurchases, shop: activeShop, from: fromDate, to: toDate);
                    } else if (val == 'download') {
                      WebPdfRouterService.downloadPurchaseReport(purchases: filteredPurchases, shop: activeShop, from: fromDate, to: toDate);
                    }
                  },
                  itemBuilder: (c) => [
                    const PopupMenuItem(
                      value: 'print',
                      child: Row(
                        children: [
                          Icon(Icons.visibility_rounded, size: 18, color: Color(0xFFFBBF24)),
                          SizedBox(width: 10),
                          Text("Open / Print Summary PDF", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.download_rounded, size: 18, color: Colors.greenAccent),
                          SizedBox(width: 10),
                          Text("Download Summary PDF", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _dateTile("FROM DATE", fromDate, (d) => setState(() => fromDate = d), webPh.financialYear)),
                    const SizedBox(width: 12),
                    Expanded(child: _dateTile("TO DATE", toDate, (d) => setState(() => toDate = d), webPh.financialYear)),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: showAllDates ? const Color(0xFF10B981) : Colors.white12,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => setState(() => showAllDates = !showAllDates),
                      icon: Icon(showAllDates ? Icons.visibility_rounded : Icons.all_inclusive_rounded, size: 16),
                      label: Text(showAllDates ? "SHOW 30 DAYS" : "SHOW ALL DATES", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: "Search by Supplier Name, Bill No or Entry ID...", 
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFFF59E0B), size: 18),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 16),
                            onPressed: () => setState(() => searchQuery = ""),
                          )
                        : null,
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) => setState(() => searchQuery = v),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),

          if (filteredPurchases.isEmpty)
            Center(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 45, color: Colors.white24),
                    SizedBox(height: 12),
                    Text(
                      "No inward purchases found matching current filters.\nClick 'SHOW ALL DATES' above to view all bills across all dates.",
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredPurchases.length,
              itemBuilder: (c, i) {
                final p = filteredPurchases[i];
                final supplierObj = webPh.parties.firstWhere(
                  (x) => x.id == p.partyId || x.name == p.distributorName, 
                  orElse: () => Party(id: "temp", name: p.distributorName, group: "Sundry Creditors"),
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: const BoxDecoration(
                        color: Color(0x26F59E0B),
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: const Icon(Icons.downloading_rounded, color: Color(0xFFF59E0B), size: 18),
                    ),
                    title: Row(
                      children: [
                        Text(p.distributorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                        const SizedBox(width: 8),
                        _badge(p.paymentMode.toUpperCase(), p.paymentMode.toUpperCase() == "CASH" ? Colors.greenAccent : Colors.orangeAccent),
                      ],
                    ),
                    subtitle: Text("Bill: ${p.billNo} • Entry: ${p.internalNo} • Date: ${WebAppDateLogic.format(p.date)}", style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min, 
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "₹${p.totalAmount.toStringAsFixed(2)}",
                              style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                            Text(
                              "${p.items.length} items",
                              style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        IconButton(
                          icon: const Icon(Icons.print_outlined, color: Color(0xFF38BDF8), size: 18), 
                          tooltip: "Print Inward Slip",
                          onPressed: () => WebPdfRouterService.printPurchaseInvoice(purchase: p, party: supplierObj, shop: activeShop),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_note_rounded, color: Colors.orangeAccent, size: 20), 
                          tooltip: "Edit / Modify Inward",
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (ctx) => Scaffold(
                              backgroundColor: const Color(0xFF0F172A),
                              body: WebPurchaseEntryView(
                                onBack: () => Navigator.pop(ctx),
                                initialSupplier: supplierObj,
                                initialInternalNo: p.internalNo,
                                initialBillNo: p.billNo,
                                initialDate: p.date,
                                initialEntryDate: p.entryDate,
                                initialMode: p.paymentMode,
                                existingItems: p.items,
                                linkedChallanIds: p.linkedChallanIds,
                                modifyPurchaseId: p.id,
                                isReadOnly: false,
                              ),
                            )));
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent), 
                          tooltip: "Delete Purchase",
                          onPressed: () {
                            webPh.deletePurchase(p.id);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF19243B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF59E0B).withAlpha(100), width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, 
              children: [
                _botCol("CASH INWARD", cashTotal, color: Colors.greenAccent),
                _botCol("CREDIT INWARD", creditTotal, color: Colors.orangeAccent),
                _botCol("TAXABLE AMOUNT", totalTaxable, color: Colors.white70), 
                _botCol("INPUT GST (ITC)", totalITC, color: Colors.greenAccent), 
                _botCol("TOTAL INWARD", netTotal, isNet: true, color: const Color(0xFFFBBF24)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 7.5, fontWeight: FontWeight.w900)),
    );
  }

  Widget _dateTile(String label, DateTime d, Function(DateTime) onPick, String fy) {
    return InkWell(
      onTap: () async { 
        DateTime? p = await showDatePicker(
          context: context,
          initialDate: d,
          firstDate: WebAppDateLogic.getFYStart(fy),
          lastDate: WebAppDateLogic.getFYEnd(fy),
        ); 
        if (p != null) onPick(p); 
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), 
        decoration: BoxDecoration(
          color: Colors.black26, 
          border: Border.all(color: Colors.white12), 
          borderRadius: BorderRadius.circular(8),
        ), 
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
            const Icon(Icons.calendar_month_rounded, color: Color(0xFFF59E0B), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _botCol(String label, double val, {bool isNet = false, Color color = Colors.white}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)), 
        const SizedBox(height: 4),
        Text("₹${val.toStringAsFixed(2)}", style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: isNet ? 18 : 12.5)),
      ],
    );
  }
}
