// FILE: lib/purchase/purchase_summary_view.dart (FINAL AUDIT UPDATED)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../pdf/pdf_router_service.dart';
import '../pdf/purchase_report_pdf.dart'; 
import 'purchase_entry_view.dart'; 
import '../app_date_logic.dart'; 
import '../pharoah_date_controller.dart'; 

class PurchaseSummaryView extends StatefulWidget {
  const PurchaseSummaryView({super.key});
  @override State<PurchaseSummaryView> createState() => _PurchaseSummaryViewState();
}

class _PurchaseSummaryViewState extends State<PurchaseSummaryView> {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  String searchQuery = "";
  bool _isInit = false;

  // --- 🛡️ NAYA AUDIT CODE: SELECTION & PROCESSING STATE ---
  bool isSelectionMode = false;
  List<String> selectedPurchaseIds = [];
  bool isProcessing = false;
  double progressValue = 0.0;
  String progressText = "";

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final ph = Provider.of<PharoahManager>(context, listen: false);
      toDate = AppDateLogic.getSmartDate(ph.currentFY);
      DateTime thirtyDaysAgo = toDate.subtract(const Duration(days: 30));
      DateTime fyStart = AppDateLogic.getFYStart(ph.currentFY);
      fromDate = thirtyDaysAgo.isBefore(fyStart) ? fyStart : thirtyDaysAgo;
      _isInit = true;
    }
  }

  // --- 📦 NAYA AUDIT CODE: NO-CRASH BATCH ZIP LOGIC (Challan Stitcher Style) ---
  Future<void> _handleBatchAuditMail(PharoahManager ph) async {
    if (selectedPurchaseIds.isEmpty) return;

    setState(() { 
      isProcessing = true; 
      progressText = "Preparing Inward Audit Bundle..."; 
      progressValue = 0.0;
    });

    try {
      List<Purchase> purchasesToZip = ph.purchases.where((p) => selectedPurchaseIds.contains(p.id)).toList();
      
      // Safe Loop with delays to prevent UI freeze/crash
      for (int i = 0; i < purchasesToZip.length; i++) {
        await Future.delayed(const Duration(milliseconds: 100)); 
        setState(() {
          progressValue = (i + 1) / purchasesToZip.length;
          progressText = "Packing Bill: ${purchasesToZip[i].billNo} (${i + 1}/${purchasesToZip.length})";
        });
      }

      // Router Call for ZIP & Dispatch
      await PdfRouterService.sendBatchToCa(
        documents: purchasesToZip, 
        ph: ph, 
        type: "PURCHASE"
      );

      setState(() { 
        isProcessing = false; 
        isSelectionMode = false; 
        selectedPurchaseIds.clear(); 
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Inward bundle zipped and mailed to CA!"), backgroundColor: Colors.orange)
      );
    } catch (e) {
      setState(() => isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  @override Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final activeShop = ph.activeCompany;
    
    // Filter logic
    List<Purchase> filteredPur = ph.purchases.reversed.where((p) {
      bool dateMatch = p.date.isAfter(fromDate.subtract(const Duration(days: 1))) && 
                       p.date.isBefore(toDate.add(const Duration(days: 1)));
      bool searchMatch = p.distributorName.toLowerCase().contains(searchQuery.toLowerCase()) || 
                         p.billNo.toLowerCase().contains(searchQuery.toLowerCase());
      return dateMatch && searchMatch;
    }).toList();

    // Summary Totals
    double totalTaxable = 0; double totalTax = 0; double netTotal = 0;
    for(var p in filteredPur) {
      double pTaxable = p.items.fold(0, (sum, it) => sum + (it.purchaseRate * it.qty));
      totalTaxable += pTaxable; 
      totalTax += (p.totalAmount - pTaxable); 
      netTotal += p.totalAmount;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Purchase Register"), 
        backgroundColor: Colors.orange.shade800, 
        foregroundColor: Colors.white,
        actions: [
          // --- 📊 PURCHASE SUMMARY & MAIL ACTION ---
          if (ph.config.isMailActive)
            PopupMenuButton<String>(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              onSelected: (val) {
                if (val == 'view') PurchaseReportPdf.generate(filteredPur, fromDate, toDate, null, activeShop!);
                if (val == 'mail') {
                  PdfRouterService.emailDocument(
                    context: context, 
                    doc: filteredPur, 
                    party: Party(id: 'internal', name: ph.config.isAuditMode ? 'Inward Audit' : 'Purchase Register'), 
                    ph: ph, 
                    type: "LEDGER"
                  );
                }
              },
              itemBuilder: (c) => [
                const PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.visibility, size: 18), SizedBox(width: 10), Text("Open Summary PDF")])),
                PopupMenuItem(value: 'mail', child: Row(children: [
                   Icon(ph.config.isAuditMode ? Icons.forward_to_inbox : Icons.alternate_email, size: 18, color: Colors.orange), 
                   const SizedBox(width: 10), 
                   Text(ph.config.isAuditMode ? "Mail Summary to CA" : "Mail Summary to My Mail")
                ])),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf), 
              onPressed: (filteredPur.isEmpty || activeShop == null) 
                ? null 
                : () => PurchaseReportPdf.generate(filteredPur, fromDate, toDate, null, activeShop)
            ),

          // NAYA: Select Mode Button (Only visible if Audit Switch is ON)
          if (ph.config.isAuditMode && filteredPur.isNotEmpty)
            IconButton(
              icon: Icon(isSelectionMode ? Icons.close : Icons.checklist_rtl_rounded),
              onPressed: () => setState(() { 
                isSelectionMode = !isSelectionMode; 
                selectedPurchaseIds.clear(); 
              }),
            ),
        ],
      ),
      body: Stack( // NAYA: Stack used for Progress Overlay
        children: [
          Column(children: [
            // --- 1. FILTER SECTION ---
            Container(
              padding: const EdgeInsets.all(12), color: Colors.white,
              child: Column(children: [
                Row(children: [
                  Expanded(child: _dateTile("FROM", fromDate, (d) => setState(()=> fromDate = d), ph.currentFY)),
                  const SizedBox(width: 10),
                  Expanded(child: _dateTile("TO", toDate, (d) => setState(()=> toDate = d), ph.currentFY)),
                ]),
                Padding(padding: const EdgeInsets.only(top: 10), child: TextField(
                  decoration: const InputDecoration(
                    hintText: "Search Supplier/Bill...", 
                    prefixIcon: Icon(Icons.search, color: Colors.orange), 
                    border: OutlineInputBorder(), 
                    isDense: true
                  ), 
                  onChanged: (v) => setState(() => searchQuery = v)
                ))
              ]),
            ),
            
            // --- 2. LIST SECTION ---
            Expanded(
              child: filteredPur.isEmpty 
              ? const Center(child: Text("No records found for selected period."))
              : ListView.builder(
                padding: const EdgeInsets.all(10), itemCount: filteredPur.length,
                itemBuilder: (c, i) {
                  final p = filteredPur[i];
                  final supplier = ph.parties.firstWhere(
                    (pt) => pt.name == p.distributorName, 
                    orElse: () => Party(id: "", name: p.distributorName)
                  );

                  return Card(
                    elevation: 2, margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      // --- 🛡️ NAYA AUDIT CODE: LEADING CHECKBOX ---
                      leading: isSelectionMode 
                        ? Checkbox(
                            value: selectedPurchaseIds.contains(p.id), 
                            onChanged: (v) => setState(() => v! ? selectedPurchaseIds.add(p.id) : selectedPurchaseIds.remove(p.id))
                          )
                        : null,

                      title: Text(p.distributorName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: _buildSubtitleWidget(p),
                      
                     trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        // --- 📬 SMART DISPATCH ICON (Supplier vs CA) ---
                        if (ph.config.isMailActive && !isSelectionMode)
                          IconButton(
                            icon: Icon(
                              ph.config.isAuditMode ? Icons.forward_to_inbox_rounded : Icons.alternate_email, 
                              color: ph.config.isAuditMode ? Colors.indigo.shade900 : Colors.orange.shade900, 
                              size: 22
                            ),
                            tooltip: ph.config.isAuditMode ? "Forward to CA (Auditor)" : "Send to Supplier Mail",
                            onPressed: () => PdfRouterService.emailDocument(context: context, doc: p, party: supplier, ph: ph, type: "SALE"),
                          ),

                        IconButton(
                          icon: const Icon(Icons.print, color: Colors.blueGrey, size: 20), 
                          onPressed: activeShop == null ? null : () => PdfRouterService.printPurchase(purchase: p, supplier: supplier, ph: ph)
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue, size: 20), 
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => PurchaseEntryView(existingPurchase: p)))
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 20), 
                          onPressed: () => _confirmDelete(context, ph, p.id)
                        ),
                      ]),
                    ),
                  );
                },
              )
            ),
            
            // --- 3. BOTTOM SUMMARY BAR ---
            Container(
              padding: const EdgeInsets.all(15), color: Colors.deepOrange.shade900,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _botCol("TAXABLE", totalTaxable), 
                _botCol("TOTAL ITC", totalTax), 
                _botCol("NET TOTAL", netTotal, isNet: true),
              ]),
            )
          ]),

          // --- 📦 NAYA AUDIT CODE: PROGRESS OVERLAY ---
          if (isProcessing)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.orange),
                    const SizedBox(height: 20),
                    Text(progressText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    SizedBox(width: 200, child: LinearProgressIndicator(value: progressValue, color: Colors.orange)),
                  ],
                ),
              ),
            ),
        ],
      ),

      // --- 🛡️ NAYA AUDIT CODE: BATCH ZIP ACTION BAR ---
      bottomNavigationBar: (isSelectionMode && selectedPurchaseIds.isNotEmpty)
        ? Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55)),
              onPressed: () => _handleBatchAuditMail(ph),
              icon: const Icon(Icons.folder_zip_rounded),
              label: Text("MAIL ${selectedPurchaseIds.length} INWARDS AS ZIP TO CA"),
            ),
          )
        : null,
    );
  }

  // --- SUBTITLE UI HELPER ---
  Widget _buildSubtitleWidget(Purchase p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text("Bill: ${p.billNo} | ${AppDateLogic.format(p.date)}", style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 8),
          if (p.linkedChallanIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange.shade200)),
              child: const Text("MERGED", style: TextStyle(color: Colors.orange, fontSize: 7, fontWeight: FontWeight.bold)),
            ),
          if (p.sourceTag.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 5),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.indigo.shade200)),
              child: Text("IMPORT: ${p.sourceTag}", style: TextStyle(color: Colors.indigo.shade900, fontSize: 7, fontWeight: FontWeight.bold)),
            ),
        ]),
        Text("Total: ₹${p.totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _dateTile(String l, DateTime d, Function(DateTime) onPick, String fy) {
    return InkWell(
      onTap: () async { 
        DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: fy, initialDate: d); 
        if(p!=null) onPick(p); 
      },
      child: Container(
        padding: const EdgeInsets.all(8), 
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(5)), 
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)), 
          Text(DateFormat('dd/MM/yyyy').format(d), style: const TextStyle(fontWeight: FontWeight.bold))
        ])
      ),
    );
  }

  Widget _botCol(String l, double v, {bool isNet = false}) {
    return Column(children: [Text(l, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)), Text("₹${v.toStringAsFixed(2)}", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isNet ? 16 : 12))]);
  }

  void _confirmDelete(BuildContext context, PharoahManager ph, String id) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Purchase?"),
        content: const Text("Are you sure you want to delete this purchase record? Stock will be adjusted back."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red), 
            onPressed: () { ph.deletePurchase(id); Navigator.pop(c); }, 
            child: const Text("YES, DELETE", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
  }
}
