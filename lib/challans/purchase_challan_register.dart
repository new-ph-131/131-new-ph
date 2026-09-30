// FILE: lib/challans/purchase_challan_register.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../pharoah_date_controller.dart';
import '../app_date_logic.dart';
import 'purchase_challan_view.dart';
import '../pdf/pdf_router_service.dart';
import '../pdf/purchase_challan_report_pdf.dart'; // <--- Report Import

class PurchaseChallanRegister extends StatefulWidget {
  const PurchaseChallanRegister({super.key});

  @override
  State<PurchaseChallanRegister> createState() => _PurchaseChallanRegisterState();
}

class _PurchaseChallanRegisterState extends State<PurchaseChallanRegister> {
  String searchQuery = "";
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final ph = Provider.of<PharoahManager>(context, listen: false);
      // Smart Date Logic (Financial Year aware)
      toDate = AppDateLogic.getSmartDate(ph.currentFY);
      fromDate = toDate.subtract(const Duration(days: 30));
      DateTime fyStart = AppDateLogic.getFYStart(ph.currentFY);
      if (fromDate.isBefore(fyStart)) fromDate = fyStart;
      _isInit = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    // Filter Logic: Search + Date Range
    final list = ph.purchaseChallans.reversed.where((ch) {
      bool matchesSearch = ch.distributorName.toLowerCase().contains(searchQuery.toLowerCase()) || 
                           ch.billNo.toLowerCase().contains(searchQuery.toLowerCase());
      bool matchesDate = ch.date.isAfter(fromDate.subtract(const Duration(days: 1))) && 
                         ch.date.isBefore(toDate.add(const Duration(days: 1)));
      return matchesSearch && matchesDate;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F1),
      appBar: AppBar(
        title: const Text("Purchase Challan Register"),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        // ==========================================================
        // ACTION SECTION 1: TOP RIGHT PDF REPORT BUTTON
        // ==========================================================
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined), 
            tooltip: "Export Register PDF",
            onPressed: () async {
              if (ph.activeCompany != null && list.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Generating Inward Report...")));
                await PurchaseChallanReportPdf.generate(list, fromDate, toDate, ph.activeCompany!);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data found to export!")));
              }
            }
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterPanel(ph),
          Expanded(
            child: list.isEmpty 
              ? const Center(child: Text("No Purchase Challans found."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (context, index) => _buildChallanCard(list[index], ph),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(PharoahManager ph) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.amber.shade900,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Column(
        children: [
          TextField(
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => searchQuery = v),
            decoration: InputDecoration(
              hintText: "Search Supplier or Bill No...",
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
              prefixIcon: const Icon(Icons.search, color: Colors.white70),
              filled: true, fillColor: Colors.white.withOpacity(0.15),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              _dateChip("FROM: ${DateFormat('dd/MM/yy').format(fromDate)}", () async {
                DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: ph.currentFY, initialDate: fromDate);
                if(p != null) setState(() => fromDate = p);
              }),
              const SizedBox(width: 10),
              _dateChip("TO: ${DateFormat('dd/MM/yy').format(toDate)}", () async {
                DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: ph.currentFY, initialDate: toDate);
                if(p != null) setState(() => toDate = p);
              }),
            ],
          )
        ],
      ),
    );
  }

  Widget _dateChip(String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white24)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_month, size: 12, color: Colors.white70),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChallanCard(PurchaseChallan ch, PharoahManager ph) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: () => _showActionMenu(ch, ph), // <--- Tap trigger for Menu
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.inventory_2_rounded, color: Colors.amber.shade900),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ch.distributorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text("Ref: ${ch.billNo} • ID: ${ch.internalNo}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    Text(DateFormat('dd MMM yyyy').format(ch.date), style: TextStyle(color: Colors.amber.shade900, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
           // --- 📬 SMART DISPATCH (MAIL) ---
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ph.config.isMailActive)
                    IconButton(
                      icon: Icon(
                        ph.config.isAuditMode ? Icons.forward_to_inbox_rounded : Icons.alternate_email, 
                        color: ph.config.isAuditMode ? Colors.indigo.shade900 : Colors.amber.shade900, 
                        size: 22
                      ),
                      tooltip: ph.config.isAuditMode ? "Forward to CA (Auditor)" : "Mail to Supplier",
                      onPressed: () {
                        final partyObj = ph.parties.firstWhere(
                          (p) => p.name == ch.distributorName, 
                          orElse: () => Party(id: 'temp', name: ch.distributorName)
                        );
                        PdfRouterService.emailDocument(
                          context: context,
                          doc: ch,
                          party: partyObj,
                          ph: ph,
                          type: "CHALLAN",
                        );
                      },
                    ),
                  const SizedBox(width: 5),
                  Text("₹${ch.totalAmount.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.amber.shade900)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // ACTION SECTION 2: BOTTOM SHEET MENU (VIEW / EDIT / PRINT / DELETE)
  // ==========================================================================
  void _showActionMenu(PurchaseChallan ch, PharoahManager ph) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 5, width: 40, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            Text(ch.distributorName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text("Challan: ${ch.billNo}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const Divider(height: 30),

            // 1. VIEW (READ-ONLY)
            _menuTile(Icons.visibility_outlined, "View Inward Details", Colors.blue, () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (c) => PurchaseChallanView(existingRecord: ch, isReadOnly: true)));
            }),

            // 2. EDIT
            _menuTile(Icons.edit_note_rounded, "Modify / Edit Items", Colors.orange, () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (c) => PurchaseChallanView(existingRecord: ch)));
            }),

            // 3. PRINT PDF
            // 3. PRINT PDF (Via Universal Router)
_menuTile(Icons.print_rounded, "Print / Share PDF", Colors.teal, () async {
  Navigator.pop(c);
  if(ph.activeCompany != null) {
    final party = ph.parties.firstWhere((p) => p.name == ch.distributorName, orElse: () => Party(id: '0', name: ch.distributorName));
    
    // Router ab decide karega ki Inward Challan kaisa dikhna chahiye
    await PdfRouterService.printChallan(
      challan: ch, 
      party: party, 
      ph: ph, 
      isSaleChallan: false // False matlab Inward/Purchase Challan
    );
  }
}),

            // 4. DELETE
            _menuTile(Icons.delete_forever_rounded, "Delete Permanently", Colors.red, () {
              Navigator.pop(c);
              _confirmDelete(ch, ph);
            }),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData icon, String t, Color c, VoidCallback onTap) => 
      ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: c.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: c, size: 20)), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), onTap: onTap);

  void _confirmDelete(PurchaseChallan ch, PharoahManager ph) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Record?"),
        content: const Text("This will reverse stock and remove the entry permanently."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () {
            ph.deletePurchaseChallan(ch.id);
            Navigator.pop(c);
          }, child: const Text("YES, DELETE", style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
}
