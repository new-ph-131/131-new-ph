// FILE: lib/web_live_sync/web_sale_summary_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'web_pdf_router_service.dart';
import 'sub_views/web_billing/web_new_sale_view.dart';

class WebSaleSummaryView extends StatefulWidget {
  final VoidCallback onBack;

  const WebSaleSummaryView({super.key, required this.onBack});

  @override
  State<WebSaleSummaryView> createState() => _WebSaleSummaryViewState();
}

class _WebSaleSummaryViewState extends State<WebSaleSummaryView> {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  String searchQuery = "";
  bool _isInit = false;

  bool isSelectionMode = false;
  List<String> selectedBillIds = [];
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

  Future<void> _handleBatchZipExport(PharoahWebManager webPh) async {
    if (selectedBillIds.isEmpty) return;

    setState(() { 
      isProcessing = true; 
      progressText = "Preparing Invoices ZIP Bundle..."; 
      progressValue = 0.0;
    });

    try {
      List<Sale> billsToZip = webPh.sales.where((s) => selectedBillIds.contains(s.id)).toList();
      final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);

      await WebPdfRouterService.downloadBulkZip(
        documents: billsToZip,
        shop: shopProfile,
        config: webPh.appConfig,
        onProgress: (v, n) {
          if (mounted) {
            setState(() {
              progressValue = v;
              progressText = "Packing: $n";
            });
          }
        },
      );

      setState(() { 
        isProcessing = false; 
        isSelectionMode = false; 
        selectedBillIds.clear(); 
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Invoice ZIP Bundle exported successfully!"), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export Error: $e"), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final activeShop = CompanyProfile.fromMap(webPh.companyProfile);

    final fDateOnly = _dateOnly(fromDate);
    final tDateOnly = _dateOnly(toDate);

    List<Sale> filteredSales = webPh.sales.reversed.where((s) {
      final sDateOnly = _dateOnly(s.date);
      bool dateMatch = !sDateOnly.isBefore(fDateOnly) && !sDateOnly.isAfter(tDateOnly);
      bool searchMatch = searchQuery.isEmpty ||
          s.billNo.toLowerCase().contains(searchQuery.toLowerCase()) || 
          s.partyName.toLowerCase().contains(searchQuery.toLowerCase());
      bool isActive = s.status.isEmpty || s.status.toLowerCase() == "active";

      return isActive && dateMatch && searchMatch;
    }).toList();

    double totalTaxable = 0.0;
    double totalTax = 0.0;
    double netTotal = 0.0;
    double cashTotal = 0.0;
    double creditTotal = 0.0;

    for (var s in filteredSales) {
      double sTax = s.items.fold(0.0, (sum, it) => sum + (it.cgst + it.sgst + it.igst));
      totalTax += sTax; 
      totalTaxable += (s.totalAmount - sTax); 
      netTotal += s.totalAmount;
      if (s.paymentMode.toUpperCase() == 'CASH') {
        cashTotal += s.totalAmount;
      } else {
        creditTotal += s.totalAmount;
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
          _buildHeaderBar(webPh, filteredSales, activeShop),

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
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: "Search by Bill No (e.g. INV-101) or Party / Customer Name...", 
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
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

          if (filteredSales.isEmpty)
            Center(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 45, color: Colors.white24),
                    const SizedBox(height: 12),
                    Text(
                      webPh.sales.isEmpty 
                        ? "No invoices recorded yet in this store database."
                        : "No invoices found between ${DateFormat('dd/MM/yyyy').format(fromDate)} and ${DateFormat('dd/MM/yyyy').format(toDate)}.",
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
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
              itemCount: filteredSales.length,
              itemBuilder: (c, i) {
                final s = filteredSales[i];
                final p = webPh.parties.firstWhere(
                  (x) => (s.partyId.isNotEmpty && x.id == s.partyId) || x.name.trim().toLowerCase() == s.partyName.trim().toLowerCase(), 
                  orElse: () => Party(id: s.partyId.isNotEmpty ? s.partyId : "temp", name: s.partyName, gst: s.partyGstin, state: s.partyState, address: s.partyAddress, city: s.partyCity, phone: s.partyPhone, email: s.partyEmail, dl: s.partyDl),
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelectionMode && selectedBillIds.contains(s.id) ? const Color(0xFF38BDF8) : Colors.white10,
                      width: isSelectionMode && selectedBillIds.contains(s.id) ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    
                    leading: isSelectionMode 
                      ? Checkbox(
                          value: selectedBillIds.contains(s.id), 
                          activeColor: const Color(0xFF38BDF8),
                          onChanged: (v) => setState(() => v! ? selectedBillIds.add(s.id) : selectedBillIds.remove(s.id)),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: const BoxDecoration(
                            color: Color(0x262563EB),
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                          child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF38BDF8), size: 18),
                        ),

                    title: Row(
                      children: [
                        Text(s.partyName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                        const SizedBox(width: 8),
                        _badge(s.paymentMode.toUpperCase(), s.paymentMode.toUpperCase() == "CASH" ? Colors.greenAccent : Colors.blueAccent),
                      ],
                    ),
                    subtitle: _buildSubtitleWidget(s),
                    
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min, 
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "₹${s.totalAmount.toStringAsFixed(2)}",
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                            Text(
                              "${s.items.length} items",
                              style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        
                        if (!isSelectionMode) ...[
                          IconButton(
                            icon: const Icon(Icons.print_outlined, color: Color(0xFF38BDF8), size: 18), 
                            tooltip: "Print Landscape Invoice",
                            onPressed: () => WebPdfRouterService.printSaleInvoice(sale: s, party: p, shop: activeShop, config: webPh.appConfig),
                          ),
                          IconButton(
                            icon: const Icon(Icons.download_rounded, color: Colors.greenAccent, size: 18), 
                            tooltip: "Download PDF File",
                            onPressed: () => WebPdfRouterService.downloadSalePdf(sale: s, party: p, shop: activeShop, config: webPh.appConfig),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_note_rounded, color: Colors.orangeAccent, size: 20), 
                            tooltip: "Edit / Modify Bill",
                            onPressed: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (ctx) => Scaffold(
                                backgroundColor: const Color(0xFF0F172A),
                                body: WebNewSaleView(
                                  onBack: () => Navigator.pop(ctx),
                                  initialParty: p,
                                  initialBillNo: s.billNo,
                                  initialDate: s.date,
                                  initialMode: s.paymentMode,
                                  existingItems: s.items,
                                  linkedChallanIds: s.linkedChallanIds,
                                  modifySaleId: s.id,
                                  isReadOnly: false,
                                ),
                              )));
                              if (context.mounted) setState(() {});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18), 
                            tooltip: "Delete Bill (Reverse Stock)",
                            onPressed: () => _confirmDelete(webPh, s),
                          ),
                        ],
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
              border: Border.all(color: const Color(0xFF2563EB).withAlpha(100), width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, 
              children: [
                _botCol("CASH SALES", cashTotal, color: Colors.greenAccent),
                _botCol("CREDIT SALES", creditTotal, color: Colors.blueAccent),
                _botCol("TAXABLE AMOUNT", totalTaxable, color: Colors.white70), 
                _botCol("TOTAL OUTPUT GST", totalTax, color: Colors.orangeAccent), 
                _botCol("NET TURNOVER", netTotal, isNet: true, color: Colors.greenAccent),
              ],
            ),
          ),

          if (isSelectionMode && selectedBillIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B), 
                  foregroundColor: Colors.black, 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _handleBatchZipExport(webPh),
                icon: const Icon(Icons.folder_zip_rounded, size: 18),
                label: Text("DOWNLOAD ${selectedBillIds.length} SELECTED INVOICES AS ZIP", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderBar(PharoahWebManager webPh, List<Sale> filteredSales, CompanyProfile activeShop) {
    return Row(
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
        const Icon(Icons.description_outlined, color: Color(0xFF38BDF8), size: 22),
        const SizedBox(width: 10),
        const Text(
          "SALES REGISTER / AUDIT",
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
        ),
        const Spacer(),

        // EXACT APP WORKFLOW: PopupMenuButton for Summary PDF Actions
        if (filteredSales.isNotEmpty) ...[
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E),
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
            tooltip: "Summary Report PDF Actions",
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white12)),
            onSelected: (val) {
              if (val == 'print') {
                WebPdfRouterService.printSaleReport(sales: filteredSales, shop: activeShop, from: fromDate, to: toDate);
              } else if (val == 'download') {
                WebPdfRouterService.downloadSaleReport(sales: filteredSales, shop: activeShop, from: fromDate, to: toDate);
              }
            },
            itemBuilder: (c) => [
              const PopupMenuItem(
                value: 'print',
                child: Row(
                  children: [
                    Icon(Icons.visibility_rounded, size: 18, color: Color(0xFF38BDF8)),
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
          const SizedBox(width: 8),
        ],

        if (filteredSales.isNotEmpty)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isSelectionMode ? const Color(0xFFEF4444) : const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: Icon(isSelectionMode ? Icons.close_rounded : Icons.checklist_rtl_rounded, size: 16),
            label: Text(isSelectionMode ? "CANCEL" : "SELECT BILLS (ZIP)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
            onPressed: () => setState(() { 
              isSelectionMode = !isSelectionMode; 
              selectedBillIds.clear(); 
            }),
          ),
      ],
    );
  }

  Widget _buildSubtitleWidget(Sale s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 3),
        Row(
          children: [
            Text("Bill: ${s.billNo} • ${DateFormat('dd/MM/yyyy').format(s.date)}", style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
            const SizedBox(width: 8),
            if (s.extraDiscount > 0)
              _badge("DISC: ₹${s.extraDiscount.toStringAsFixed(2)}", Colors.redAccent),
            if (s.linkedChallanIds.isNotEmpty)
              _badge("MERGED", Colors.orangeAccent),
            if (s.sourceTag.isNotEmpty)
              _badge("IMPORT: ${s.sourceTag}", Colors.lightBlueAccent),
          ],
        ),
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
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
            const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 16),
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

  void _confirmDelete(PharoahWebManager webPh, Sale sale) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white12)),
        title: const Text("Delete Invoice?", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        content: Text(
          "Are you sure you want to delete '${sale.billNo}'?\n\n• Stock will be automatically reversed.\n• Any linked delivery challans will be reverted back to 'Pending'.",
          style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () { 
              if (sale.linkedChallanIds.isNotEmpty) {
                for (var cid in sale.linkedChallanIds) {
                  int idx = webPh.saleChallans.indexWhere((ch) => ch.id == cid);
                  if (idx != -1) {
                    webPh.saleChallans[idx].status = "Pending";
                  }
                }
              }

              webPh.deleteSale(sale.id); 
              Navigator.pop(c); 

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("🗑️ Invoice ${sale.billNo} Deleted & Stock Reversed!"), backgroundColor: Colors.redAccent)
              );
            }, 
            child: const Text("YES, DELETE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
