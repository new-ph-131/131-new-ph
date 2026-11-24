// FILE: lib/modifications/sub_views/modify_returns_list.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../pharoah_manager.dart';
import '../../../models.dart';
import '../../../returns/sale_return_view.dart';
import '../../../returns/purchase_return_view.dart';
import '../../../pdf/pdf_router_service.dart'; // NAYA IMPORT

class ModifyReturnsList extends StatelessWidget {
  final String searchQuery;
  const ModifyReturnsList({super.key, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    
    // Combine both Sale and Purchase Returns
    List<dynamic> allReturns = [...ph.saleReturns, ...ph.purchaseReturns];

    final filtered = allReturns.where((r) {
      if (r.isDeleted == 1) return false;
      String name = (r is SaleReturn) ? r.partyName : (r as PurchaseReturn).distributorName;
      return r.billNo.toLowerCase().contains(searchQuery.toLowerCase()) || 
             name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text("No returns found matching search.", style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final ret = filtered[i];
        bool isSaleRet = ret is SaleReturn;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isSaleRet ? Colors.red.shade700 : Colors.brown,
              child: Text(isSaleRet ? "SR" : "PR", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            title: Text(ret.billNo, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isSaleRet ? (ret as SaleReturn).partyName : (ret as PurchaseReturn).distributorName),
                Text("Amt: ₹${ret.totalAmount.toStringAsFixed(2)} | Date: ${DateFormat('dd/MM').format(ret.date)}", style: const TextStyle(fontSize: 10)),
              ],
            ),
            trailing: const Icon(Icons.more_vert),
            onTap: () => _showActionMenu(context, ph, ret),
          ),
        );
      },
    );
  }

  void _showActionMenu(BuildContext context, PharoahManager ph, dynamic returnObj) {
    bool isSaleRet = returnObj is SaleReturn;
    bool canEdit = ph.loggedInStaff == null || ph.loggedInStaff!.canEditBill;
    bool canDelete = ph.loggedInStaff == null || ph.loggedInStaff!.canDeleteBill;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text("Return No: ${returnObj.billNo}", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(isSaleRet ? "Sale Credit Note" : "Purchase Debit Note"),
          ),
          const Divider(),
          
          if (canEdit)
            ListTile(
              leading: Icon(returnObj.status == "Cancelled" ? Icons.visibility_outlined : Icons.edit, color: Colors.blue),
              title: Text(returnObj.status == "Cancelled" ? "View Cancelled Return (Read-Only)" : "Edit / Modify Return"),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(
                  builder: (c) => isSaleRet
                      ? SaleReturnView(existingRecord: returnObj as SaleReturn)
                      : PurchaseReturnView(existingRecord: returnObj as PurchaseReturn),
                ));
              },
            ),

          // NAYA: PRINT OPTION (Router Integrated)
          ListTile(
            leading: const Icon(Icons.print, color: Colors.teal),
            title: const Text("Print / Share Return PDF"),
            onTap: () async {
              Navigator.pop(c);
              if (isSaleRet) {
                final sr = returnObj as SaleReturn;
                final party = ph.parties.firstWhere(
                  (p) => (sr.partyId.isNotEmpty && p.id == sr.partyId) ||
                         p.name.trim().toLowerCase() == sr.partyName.trim().toLowerCase(),
                  orElse: () => Party(
                    id: sr.partyId.isNotEmpty ? sr.partyId : "0",
                    name: sr.partyName,
                    gst: sr.partyGstin,
                    state: sr.partyState.isNotEmpty ? sr.partyState : (ph.activeCompany?.state ?? "Rajasthan"),
                  ),
                );
                await PdfRouterService.printCreditNote(returnObj: sr, party: party, ph: ph);
              } else {
                final pr = returnObj as PurchaseReturn;
                final supplier = ph.parties.firstWhere(
                  (p) => (pr.partyId.isNotEmpty && p.id == pr.partyId) ||
                         p.name.trim().toLowerCase() == pr.distributorName.trim().toLowerCase(),
                  orElse: () => Party(
                    id: pr.partyId.isNotEmpty ? pr.partyId : "0",
                    name: pr.distributorName,
                    gst: pr.partyGstin,
                    state: pr.partyState.isNotEmpty ? pr.partyState : (ph.activeCompany?.state ?? "Rajasthan"),
                  ),
                );
                await PdfRouterService.printDebitNote(returnObj: pr, supplier: supplier, ph: ph);
              }
            },
          ),

          if (canDelete)
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("Delete Return Record"),
              onTap: () { Navigator.pop(c); _confirmDelete(context, ph, returnObj); },
            ),
          
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, PharoahManager ph, dynamic ret) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Return?"),
        content: const Text("This will reverse the balance and stock adjustment."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (ret is SaleReturn) ph.deleteSaleReturn(ret.id);
              else ph.deletePurchaseReturn(ret.id);
              Navigator.pop(c);
            }, 
            child: const Text("YES, DELETE", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }
}
