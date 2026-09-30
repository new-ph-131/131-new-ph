// FILE: lib/modifications/sub_views/modify_purchase_list.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../pharoah_manager.dart';
import '../../../models.dart';
import '../../../purchase/purchase_entry_view.dart';
import '../../../pdf/pdf_router_service.dart'; // NAYA IMPORT

class ModifyPurchaseList extends StatelessWidget {
  final String searchQuery;
  const ModifyPurchaseList({super.key, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final list = ph.purchases.reversed.where((p) => 
      p.billNo.toLowerCase().contains(searchQuery.toLowerCase()) ||
      p.distributorName.toLowerCase().contains(searchQuery.toLowerCase())
    ).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: list.length,
      itemBuilder: (c, i) {
        final p = list[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.orange, child: Text("P", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
            title: Text(p.billNo, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${p.distributorName}\nDate: ${DateFormat('dd/MM/yy').format(p.date)}"),
            trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _showOptions(context, ph, p)),
          ),
        );
      },
    );
  }

  void _showOptions(BuildContext context, PharoahManager ph, Purchase p) {
    bool canDelete = ph.loggedInStaff == null || ph.loggedInStaff!.canDeleteBill;

    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text("Purchase No: ${p.billNo}", style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text("Internal Record Management"),
        ),
        const Divider(),
        
        // 1. EDIT OPTION
        ListTile(leading: const Icon(Icons.edit, color: Colors.blue), title: const Text("Edit Purchase Entry"), onTap: () {
          Navigator.pop(c);
          Navigator.push(context, MaterialPageRoute(builder: (c) => PurchaseEntryView(existingPurchase: p)));
        }),

        // 2. NAYA: PRINT OPTION (Router Integrated)
        ListTile(
          leading: const Icon(Icons.print, color: Colors.teal), 
          title: const Text("Print / Share Inward Bill"), 
          onTap: () {
            Navigator.pop(c);
            // Distributor/Supplier details nikalna
            final supplier = ph.parties.firstWhere(
              (pt) => pt.name == p.distributorName, 
              orElse: () => Party(id: '0', name: p.distributorName)
            );
            
            // Universal Router Call (Professional Landscape Format)
            PdfRouterService.printPurchase(
              purchase: p, 
              supplier: supplier, 
              ph: ph
            );
          }
        ),

        const Divider(),

        // 3. DELETE OPTION
        if (canDelete)
          ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Delete Purchase"), onTap: () {
            ph.deletePurchase(p.id); Navigator.pop(c);
          })
        else
          const ListTile(
            leading: Icon(Icons.lock, color: Colors.grey), 
            title: Text("Delete Restricted", style: TextStyle(color: Colors.grey)),
          ),
        const SizedBox(height: 20),
      ],
    ));
  }
}
