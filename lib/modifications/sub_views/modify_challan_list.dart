// FILE: lib/modifications/sub_views/modify_challan_list.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../pharoah_manager.dart';
import '../../../models.dart';
import '../../../challans/sale_challan_view.dart';
import '../../../challans/purchase_challan_view.dart';
import '../../../pdf/pdf_router_service.dart'; // NAYA IMPORT

class ModifyChallanList extends StatelessWidget {
  final String searchQuery;
  const ModifyChallanList({super.key, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    
    // Combine both Sale and Purchase Challans
    List<dynamic> allChallans = [...ph.saleChallans, ...ph.purchaseChallans];
    
    final filtered = allChallans.where((c) {
      String name = (c is SaleChallan) ? c.partyName : (c as PurchaseChallan).distributorName;
      return c.billNo.toLowerCase().contains(searchQuery.toLowerCase()) || 
             name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    // Sort by Date (Latest First)
    filtered.sort((a, b) => b.date.compareTo(a.date));

    if (filtered.isEmpty) {
      return const Center(child: Text("No challans found matching search.", style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final ch = filtered[i];
        bool isSale = ch is SaleChallan;
        String partyName = isSale ? ch.partyName : (ch as PurchaseChallan).distributorName;
        Color themeColor = isSale ? Colors.blueGrey : Colors.amber.shade800;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: themeColor.withOpacity(0.1),
              child: Text(isSale ? "SC" : "PC", style: TextStyle(color: themeColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            title: Text(partyName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text("${ch.billNo} | ${DateFormat('dd/MM/yy').format(ch.date)}"),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("₹${ch.totalAmount.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.bold, color: themeColor)),
                const Icon(Icons.more_vert, size: 18, color: Colors.grey),
              ],
            ),
            onTap: () => _showActionMenu(context, ph, ch),
          ),
        );
      },
    );
  }

  void _showActionMenu(BuildContext context, PharoahManager ph, dynamic challan) {
    bool isSale = challan is SaleChallan;
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isSale ? "SALE CHALLAN ACTIONS" : "PURCHASE CHALLAN ACTIONS", 
                 style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 10),
            Text(challan.billNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Divider(),
            
            // 1. VIEW
            _menuTile(Icons.visibility, "View Items (Read Only)", Colors.blue, () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => isSale 
                  ? SaleChallanView(existingRecord: challan, isReadOnly: true)
                  : PurchaseChallanView(existingRecord: challan, isReadOnly: true)
              ));
            }),

            // 2. EDIT
            _menuTile(Icons.edit, "Modify / Edit Record", Colors.orange, () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => isSale 
                  ? SaleChallanView(existingRecord: challan)
                  : PurchaseChallanView(existingRecord: challan)
              ));
            }),

            // 3. PRINT (Via Universal Router)
            _menuTile(Icons.print, "Print PDF", Colors.teal, () {
              Navigator.pop(c);
              if (ph.activeCompany != null) {
                // Party find karna (Sale ke liye customer, Purchase ke liye supplier)
                String partyName = isSale ? challan.partyName : challan.distributorName;
                final partyObj = ph.parties.firstWhere(
                  (p) => p.name == partyName, 
                  orElse: () => Party(id: '0', name: partyName)
                );

                // Central Router call
                PdfRouterService.printChallan(
                  challan: challan, 
                  party: partyObj, 
                  ph: ph, 
                  isSaleChallan: isSale
                );
              }
            }),

            // 4. DELETE
            _menuTile(Icons.delete_forever, "Delete Permanently", Colors.red, () {
              Navigator.pop(c);
              _confirmDelete(context, ph, challan);
            }),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData icon, String t, Color c, VoidCallback onTap) => 
      ListTile(leading: Icon(icon, color: c), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)), onTap: onTap);

  void _confirmDelete(BuildContext context, PharoahManager ph, dynamic ch) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Confirm Delete?"),
        content: const Text("This action will remove the challan and reverse the stock impact."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (ch is SaleChallan) ph.deleteSaleChallan(ch.id);
              else ph.deletePurchaseChallan(ch.id);
              Navigator.pop(c);
            }, 
            child: const Text("YES, DELETE", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }
}
