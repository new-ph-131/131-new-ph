// FILE: lib/returns/universal_return_hub.dart (UPDATED WITH CA AUDIT NEXUS)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../pdf/pdf_router_service.dart';
import 'sale_return_view.dart';
import 'purchase_return_view.dart';
import '../app_date_logic.dart'; // Naya Import

class UniversalReturnHub extends StatefulWidget {
  const UniversalReturnHub({super.key});
  @override State<UniversalReturnHub> createState() => _UniversalReturnHubState();
}

class _UniversalReturnHubState extends State<UniversalReturnHub> {
  String query = "";

  // --- 🛡️ NAYA AUDIT CODE: SELECTION & PROCESSING STATE ---
  bool isSelectionMode = false;
  List<String> selectedReturnIds = [];
  bool isProcessing = false;
  double progressValue = 0.0;
  String progressText = "";

  // --- 📦 NAYA AUDIT CODE: NO-CRASH BATCH ZIP LOGIC ---
  Future<void> _handleBatchAuditMail(PharoahManager ph) async {
    if (selectedReturnIds.isEmpty) return;

    setState(() { 
      isProcessing = true; 
      progressText = "Packaging Returns for CA..."; 
      progressValue = 0.0;
    });

    try {
      // 1. Combine and filter selected returns
      List<dynamic> allReturns = [...ph.saleReturns, ...ph.purchaseReturns];
      List<dynamic> filteredForZip = allReturns.where((r) => selectedReturnIds.contains(r.id)).toList();

      for (int i = 0; i < filteredForZip.length; i++) {
        await Future.delayed(const Duration(milliseconds: 100)); // रैम प्रोटेक्शन
        setState(() {
          progressValue = (i + 1) / filteredForZip.length;
          progressText = "Processing: ${filteredForZip[i].billNo} (${i + 1}/${filteredForZip.length})";
        });
      }

      // Router call for ZIP & Dispatch
      // Note: We use "SALE" type as template but Router handles CN/DN internally
      await PdfRouterService.sendBatchToCa(
        documents: filteredForZip, 
        ph: ph, 
        type: "RETURN"
      );

      setState(() { 
        isProcessing = false; 
        isSelectionMode = false; 
        selectedReturnIds.clear(); 
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Returns package zipped and mailed to CA!"), backgroundColor: Colors.redAccent)
      );
    } catch (e) {
      setState(() => isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    List<dynamic> allReturns = [...ph.saleReturns, ...ph.purchaseReturns];
    
    final filtered = allReturns.where((r) {
      bool isSR = r is SaleReturn;
      String name = isSR ? r.partyName : (r as PurchaseReturn).distributorName;
      return name.toLowerCase().contains(query.toLowerCase()) || 
             r.billNo.toLowerCase().contains(query.toLowerCase()) ||
             r.totalAmount.toString().contains(query);
    }).toList();

    filtered.sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F4F8),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Returns & Reversals Hub", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text("Audit Ready: ${filtered.length} Records", style: const TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          // --- 🛡️ NAYA AUDIT CODE: TOP RIGHT SELECTOR ---
          if (ph.config.isAuditMode && filtered.isNotEmpty)
            IconButton(
              icon: Icon(isSelectionMode ? Icons.close : Icons.checklist_rounded),
              onPressed: () => setState(() { 
                isSelectionMode = !isSelectionMode; 
                selectedReturnIds.clear(); 
              }),
            ),
        ],
      ),
      body: Stack( // Wrap in Stack for progress overlay
        children: [
          Column(
            children: [
              // ARCHITECT SEARCH BAR (Original preserved)
              Container(
                padding: const EdgeInsets.all(15),
                color: const Color(0xFF1A237E),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                    hintText: "Search Party, Bill No or Amount...",
                    hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),

              Expanded(
                child: filtered.isEmpty 
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      itemBuilder: (c, i) => _buildReturnCard(filtered[i], ph),
                    ),
              ),
            ],
          ),

          // --- 📦 NAYA AUDIT CODE: PROGRESS OVERLAY ---
          if (isProcessing)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.redAccent),
                    const SizedBox(height: 20),
                    Text(progressText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    SizedBox(width: 200, child: LinearProgressIndicator(value: progressValue, color: Colors.redAccent)),
                  ],
                ),
              ),
            ),
        ],
      ),
      // --- 🛡️ NAYA AUDIT CODE: BATCH ZIP BOTTOM BAR ---
      bottomNavigationBar: (isSelectionMode && selectedReturnIds.isNotEmpty)
        ? Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55)),
              onPressed: () => _handleBatchAuditMail(ph),
              icon: const Icon(Icons.folder_zip_rounded),
              label: Text("MAIL ${selectedReturnIds.length} RETURNS AS ZIP TO CA"),
            ),
          )
        : null,
    );
  }

  Widget _buildReturnCard(dynamic ret, PharoahManager ph) {
    bool isSR = ret is SaleReturn;
    String name = isSR ? ret.partyName : (ret as PurchaseReturn).distributorName;
    bool isCancelled = ret.status == "Cancelled";

    return Card(
      color: isCancelled ? Colors.red.shade50 : Colors.white,
      elevation: isCancelled ? 0 : 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: isCancelled ? Colors.red.shade100 : Colors.transparent),
      ),
      child: ListTile(
        onTap: () => _showActionMenu(context, ph, ret),
        // --- 🛡️ NAYA AUDIT CODE: LEADING CHECKBOX ---
        leading: isSelectionMode 
          ? Checkbox(
              value: selectedReturnIds.contains(ret.id), 
              onChanged: (v) => setState(() => v! ? selectedReturnIds.add(ret.id) : selectedReturnIds.remove(ret.id))
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSR ? Colors.red.shade100 : Colors.amber.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(isSR ? "CN" : "DN", style: TextStyle(fontWeight: FontWeight.bold, color: isSR ? Colors.red.shade900 : Colors.amber.shade900, fontSize: 12)),
            ),
        title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, decoration: isCancelled ? TextDecoration.lineThrough : null)),
        subtitle: Text("${ret.billNo} | ${DateFormat('dd/MM/yyyy').format(ret.date)}", style: const TextStyle(fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
           // --- 📬 SMART DISPATCH ICON (Returns Logic) ---
            if (ph.config.isMailActive && !isSelectionMode)
              IconButton(
                icon: Icon(
                  ph.config.isAuditMode ? Icons.forward_to_inbox_rounded : Icons.alternate_email, 
                  color: ph.config.isAuditMode ? Colors.indigo.shade900 : (isSR ? Colors.red.shade700 : Colors.orange.shade800), 
                  size: 22
                ),
                tooltip: ph.config.isAuditMode ? "Forward to CA (Auditor)" : "Send to Party Mail",
                onPressed: () {
                  final partyObj = ph.parties.firstWhere(
                    (p) => p.name == name, 
                    orElse: () => Party(id: 'temp', name: name)
                  );
                  PdfRouterService.emailDocument(
                    context: context, 
                    doc: ret, 
                    party: partyObj, 
                    ph: ph, 
                    type: isSR ? "CN" : "DN"
                  );
                },
              ),
            
            // Standard total (only if not in selection mode to save space)
            if (!isSelectionMode)
              Text("₹${ret.totalAmount.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.w900, color: isCancelled ? Colors.red.shade300 : Colors.black87)),
          ],
        ),
      ),
    );
  }

  void _showActionMenu(BuildContext context, PharoahManager ph, dynamic ret) {
    bool isSR = ret is SaleReturn;
    bool canEdit = ph.loggedInStaff == null || ph.loggedInStaff!.canEditBill;
    bool canDelete = ph.loggedInStaff == null || ph.loggedInStaff!.canDeleteBill;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isSR ? "SALE CREDIT NOTE ACTIONS" : "PURCHASE DEBIT NOTE ACTIONS", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 11)),
            const Divider(),
            _menuTile(Icons.visibility_outlined, "View Items (Audit)", Colors.blue, () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (context) => isSR 
                ? SaleReturnView(existingRecord: ret, isReadOnly: true) 
                : PurchaseReturnView(existingRecord: ret, isReadOnly: true)));
            }),
            if (canEdit && isSR)
              _menuTile(Icons.edit_note_rounded, "Modify / Edit Bill", Colors.orange, () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (context) => SaleReturnView(existingRecord: ret)));
              }),
            _menuTile(Icons.print_rounded, "Print / Share PDF", Colors.teal, () {
              Navigator.pop(c);
              if (isSR) {
                PdfRouterService.printCreditNote(returnObj: ret, party: ph.parties.firstWhere((p) => p.name == ret.partyName), ph: ph);
              } else {
                PdfRouterService.printDebitNote(returnObj: ret, supplier: ph.parties.firstWhere((p) => p.name == ret.distributorName), ph: ph);
              }
            }),
            if (canDelete)
              _menuTile(Icons.delete_forever_rounded, "Delete Permanently", Colors.red, () {
                Navigator.pop(c);
                _confirmDelete(ph, ret, isSR);
              }),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData i, String t, Color c, VoidCallback onTap) => ListTile(leading: Icon(i, color: c), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), onTap: onTap);

  void _confirmDelete(PharoahManager ph, dynamic ret, bool isSR) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Delete Record?"),
      content: const Text("DANGER: This record will be removed from system permanently."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { 
          if(isSR) ph.deleteSaleReturn(ret.id); else ph.deletePurchaseReturn(ret.id);
          Navigator.pop(c); 
        }, child: const Text("YES, DELETE")),
      ],
    ));
  }

  Widget _buildEmptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.history_rounded, size: 60, color: Colors.grey.shade300), const Text("No Return records found.", style: TextStyle(color: Colors.grey))]));
}
