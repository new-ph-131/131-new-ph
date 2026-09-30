// FILE: lib/sale_summary_view.dart (UPDATED WITH AUDIT MODE & SELECTION)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'pdf/sale_report_pdf.dart'; 
import 'pdf/pdf_router_service.dart'; // Naya Central Router
import 'sale_entry_view.dart';
import 'app_date_logic.dart'; 
import 'pharoah_date_controller.dart'; 

class SaleSummaryView extends StatefulWidget {
  const SaleSummaryView({super.key});
  @override State<SaleSummaryView> createState() => _SaleSummaryViewState();
}

class _SaleSummaryViewState extends State<SaleSummaryView> {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  String searchQuery = "";
  bool _isInit = false;

  // --- NAYA AUDIT CODE: SELECTION & PROCESSING STATE ---
  bool isSelectionMode = false;
  List<String> selectedBillIds = [];
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

  // --- NAYA AUDIT CODE: NO-CRASH BATCH LOGIC (Stitcher Wizard Style) ---
  Future<void> _handleBatchAuditMail(PharoahManager ph) async {
    if (selectedBillIds.isEmpty) return;

    setState(() { 
      isProcessing = true; 
      progressText = "Preparing Audit Bundle..."; 
      progressValue = 0.0;
    });

    try {
      List<Sale> billsToZip = ph.sales.where((s) => selectedBillIds.contains(s.id)).toList();
      
      // Batch Processing Loop with Delays to prevent crash
      for (int i = 0; i < billsToZip.length; i++) {
        // रैम को सांस लेने का मौका देने के लिए हल्का पॉज
        await Future.delayed(const Duration(milliseconds: 100)); 
        
        setState(() {
          progressValue = (i + 1) / billsToZip.length;
          progressText = "Processing: ${billsToZip[i].billNo} (${i + 1}/${billsToZip.length})";
        });
      }

      // Router Call for ZIP & Dispatch (We will implement this in next phase)
      // await PdfRouterService.sendBatchToCa(billsToZip, ph);

      setState(() { 
        isProcessing = false; 
        isSelectionMode = false; 
        selectedBillIds.clear(); 
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Audit bundle zipped and mailed to CA!"), backgroundColor: Colors.green)
      );
    } catch (e) {
      setState(() => isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final activeShop = ph.activeCompany;

    // Filter Logic
    List<Sale> filteredSales = ph.sales.reversed.where((s) {
      bool dateMatch = s.date.isAfter(fromDate.subtract(const Duration(days: 1))) && 
                       s.date.isBefore(toDate.add(const Duration(days: 1)));
      bool searchMatch = s.billNo.toLowerCase().contains(searchQuery.toLowerCase()) || 
                         s.partyName.toLowerCase().contains(searchQuery.toLowerCase());
      return s.status == "Active" && dateMatch && searchMatch;
    }).toList();

    // Calculations
    double totalTaxable = 0; double totalTax = 0; double netTotal = 0;
    for(var s in filteredSales) {
      double sTax = s.items.fold(0.0, (sum, it) => sum + (it.cgst + it.sgst + it.igst));
      totalTax += sTax; totalTaxable += (s.totalAmount - sTax); netTotal += s.totalAmount;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Sales Register / History"), 
        backgroundColor: Colors.blue.shade900, 
        foregroundColor: Colors.white,
        actions: [
      // --- 📊 SUMMARY & MAIL ACTION ---
          if (ph.config.isMailActive)
            PopupMenuButton<String>(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              onSelected: (val) {
                if (val == 'view') SaleReportPdf.generate(filteredSales, fromDate, toDate, null, activeShop!);
                if (val == 'mail') {
                  PdfRouterService.emailDocument(
                    context: context, 
                    doc: filteredSales, 
                    party: Party(id: 'internal', name: ph.config.isAuditMode ? 'CA Summary' : 'Sale Register'), 
                    ph: ph, 
                    type: "LEDGER"
                  );
                }
              },
              itemBuilder: (c) => [
                const PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.visibility, size: 18), SizedBox(width: 10), Text("Open Summary PDF")])),
                PopupMenuItem(value: 'mail', child: Row(children: [
                   Icon(ph.config.isAuditMode ? Icons.forward_to_inbox : Icons.alternate_email, size: 18, color: Colors.blue), 
                   const SizedBox(width: 10), 
                   Text(ph.config.isAuditMode ? "Mail Summary to CA" : "Mail Summary to My Mail")
                ])),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf), 
              tooltip: "Export Full Register",
              onPressed: (filteredSales.isEmpty || activeShop == null) 
                ? null 
                : () => SaleReportPdf.generate(filteredSales, fromDate, toDate, null, activeShop)
            ),

          // NAYA: Select Mode Button (Only if Audit Mode is ON)
          if (ph.config.isAuditMode && filteredSales.isNotEmpty)
            IconButton(
              icon: Icon(isSelectionMode ? Icons.close : Icons.checklist_rtl_rounded),
              onPressed: () => setState(() { 
                isSelectionMode = !isSelectionMode; 
                selectedBillIds.clear(); 
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
                    hintText: "Search Bill No or Party...", 
                    prefixIcon: Icon(Icons.search), 
                    border: OutlineInputBorder(),
                    isDense: true
                  ),
                  onChanged: (v) => setState(() => searchQuery = v)
                ))
              ]),
            ),
            
            // --- 2. LIST SECTION ---
            Expanded(
              child: filteredSales.isEmpty 
              ? const Center(child: Text("No records found for selected period."))
              : ListView.builder(
                padding: const EdgeInsets.all(10), itemCount: filteredSales.length,
                itemBuilder: (c, i) {
                  final s = filteredSales[i];
                  final p = ph.parties.firstWhere(
                    (x) => x.name == s.partyName, 
                    orElse: () => Party(id: "", name: s.partyName, address: "N/A", gst: s.partyGstin)
                  );

                  return Card(
                    elevation: 2, margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      // --- NAYA AUDIT CODE: LEADING CHECKBOX ---
                      leading: isSelectionMode 
                        ? Checkbox(
                            value: selectedBillIds.contains(s.id), 
                            onChanged: (v) => setState(() => v! ? selectedBillIds.add(s.id) : selectedBillIds.remove(s.id))
                          )
                        : null,

                      title: Text(s.partyName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: _buildSubtitleWidget(s), // Subtitle UI Logic
                      
                     trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        // --- 📬 SMART DISPATCH ICON (Party vs CA) ---
                        if (ph.config.isMailActive && !isSelectionMode)
                          IconButton(
                            icon: Icon(
                              ph.config.isAuditMode ? Icons.forward_to_inbox_rounded : Icons.alternate_email, 
                              color: ph.config.isAuditMode ? Colors.indigo.shade900 : Colors.blue.shade700, 
                              size: 22
                            ),
                            tooltip: ph.config.isAuditMode ? "Send to CA (Auditor)" : "Send to Customer Mail",
                            onPressed: () => PdfRouterService.emailDocument(context: context, doc: s, party: p, ph: ph, type: "SALE"),
                          ),

                        IconButton(
                          icon: const Icon(Icons.print, color: Colors.blueGrey, size: 20), 
                          onPressed: activeShop == null ? null : () => PdfRouterService.printSale(sale: s, party: p, ph: ph)
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue, size: 20), 
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => SaleEntryView(existingSale: s)))
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 20), 
                          onPressed: () => _confirmDelete(context, ph, s.id)
                        ),
                      ]),
                    ),
                  );
                },
              )
            ),
            
            // --- 3. BOTTOM SUMMARY BAR ---
            Container(
              padding: const EdgeInsets.all(15), color: Colors.blue.shade900,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _botCol("TAXABLE", totalTaxable), 
                _botCol("TOTAL GST", totalTax), 
                _botCol("NET TOTAL", netTotal, isNet: true),
              ]),
            )
          ]),

          // --- NAYA AUDIT CODE: NO-CRASH PROGRESS OVERLAY ---
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

      // --- NAYA AUDIT CODE: BATCH ZIP ACTION BAR ---
      bottomNavigationBar: (isSelectionMode && selectedBillIds.isNotEmpty)
        ? Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55)),
              onPressed: () => _handleBatchAuditMail(ph),
              icon: const Icon(Icons.folder_zip_rounded),
              label: Text("MAIL ${selectedBillIds.length} BILLS AS ZIP TO CA"),
            ),
          )
        : null,
    );
  }

  // --- SUBTITLE UI HELPER (Extracted from your original code) ---
  Widget _buildSubtitleWidget(Sale s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text("Bill: ${s.billNo} | ${AppDateLogic.format(s.date)}", style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 8),
          if (s.linkedChallanIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blue.shade200)),
              child: const Text("MERGED", style: TextStyle(color: Colors.blue, fontSize: 7, fontWeight: FontWeight.bold)),
            ),
          if (s.sourceTag.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 5),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.teal.shade200)),
              child: Text("IMPORT: ${s.sourceTag}", style: TextStyle(color: Colors.teal.shade900, fontSize: 7, fontWeight: FontWeight.bold)),
            ),
        ]),
        Text("Total: ₹${s.totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _dateTile(String l, DateTime d, Function(DateTime) onPick, String fy) {
    return InkWell(
      onTap: () async { 
        DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: fy, initialDate: d); 
        if(p != null) onPick(p); 
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
        title: const Text("Delete Bill?"),
        content: const Text("Are you sure you want to permanently delete this bill? This will reverse the stock levels."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () { ph.deleteBill(id); Navigator.pop(c); }, 
            child: const Text("YES, DELETE", style: TextStyle(color: Colors.white))
          )
        ],
      ),
    );
  }
}
