// FILE: lib/modifications/sub_views/modify_sales_list.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../pharoah_manager.dart';
import '../../../models.dart';
import '../../../sale_entry_view.dart';
import '../../../pdf/pdf_router_service.dart'; // CENTRAL ROUTER

class ModifySalesList extends StatelessWidget {
  final String searchQuery;
  const ModifySalesList({super.key, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    
    // Sirf Active bills filter karna aur Search Query lagana
    final list = ph.sales.reversed.where((s) => 
      (s.billNo.toLowerCase().contains(searchQuery.toLowerCase()) ||
       s.partyName.toLowerCase().contains(searchQuery.toLowerCase()))
    ).toList();

    if (list.isEmpty) {
      return const Center(child: Text("No sales records found.", style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: list.length,
      itemBuilder: (c, i) {
        final s = list[i];
        bool isCancelled = s.status == "Cancelled";

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          color: isCancelled ? Colors.red.shade50 : Colors.white,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isCancelled ? Colors.red : Colors.green,
              child: Text("S", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            title: Text(s.billNo, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${s.partyName}\n${DateFormat('dd/MM/yy').format(s.date)} | ₹${s.totalAmount.toStringAsFixed(2)}"),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showOptions(context, ph, s),
            ),
          ),
        );
      },
    );
  }

  void _showOptions(BuildContext context, PharoahManager ph, Sale s) {
    // STAFF PERMISSIONS CHECK
    bool canEdit = ph.loggedInStaff == null || ph.loggedInStaff!.canEditBill;
    bool canDelete = ph.loggedInStaff == null || ph.loggedInStaff!.canDeleteBill;

    showModalBottomSheet(
      context: context, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Actions for ${s.billNo}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            
            // 1. PRINT OPTION (SMART ROUTING)
            ListTile(
              leading: const Icon(Icons.print, color: Colors.teal), 
              title: const Text("Print / Share PDF", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Uses your preferred Layout (Architect/Standard)"),
              onTap: () {
                Navigator.pop(c);
                // Party find karna snapshot ya master se
                final partyObj = ph.parties.firstWhere(
                  (p) => p.name == s.partyName, 
                  orElse: () => Party(id: 'temp', name: s.partyName, gst: s.partyGstin, state: s.partyState)
                );
                
                // 🔥 PERFECT ROUTER CALL: Yeh automatic check karega ki Architect Mode ON hai ya nahi
                PdfRouterService.printSale(
                  sale: s, 
                  party: partyObj, 
                  ph: ph
                );
              }
            ),

            // 2. EDIT OPTION
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue), 
                title: const Text("Edit / Modify Bill"), 
                onTap: () {
                  Navigator.pop(c);
                  Navigator.push(context, MaterialPageRoute(builder: (c) => SaleEntryView(existingSale: s)));
                }
              ),

            const Divider(),

            // 3. DELETE OPTION
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red), 
                title: const Text("Delete Bill Permanently", style: TextStyle(color: Colors.red)), 
                onTap: () {
                  Navigator.pop(c);
                  _confirmDelete(context, ph, s);
                }
              ),
            
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, PharoahManager ph, Sale s) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Confirm Delete?"),
        content: Text("Are you sure you want to delete ${s.billNo}? This will reverse the stock impact."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () { ph.deleteBill(s.id); Navigator.pop(c); }, 
            child: const Text("YES, DELETE", style: TextStyle(color: Colors.white))
          )
        ],
      ),
    );
  }
}
