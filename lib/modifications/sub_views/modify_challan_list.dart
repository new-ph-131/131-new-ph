// FILE: lib/modifications/sub_views/modify_challan_list.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../pharoah_manager.dart';
import '../../../models.dart';
import '../../../logic/pharoah_numbering_engine.dart';
import '../../../challans/sale_challan_view.dart';
import '../../../challans/purchase_challan_view.dart';
import '../../../pdf/pdf_router_service.dart'; // NAYA IMPORT

class ModifyChallanList extends StatelessWidget {
  final String searchQuery;
  const ModifyChallanList({super.key, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    
    // Combine both Sale and Purchase Challans (excluding tombstoned)
    List<dynamic> allChallans = [...ph.saleChallans, ...ph.purchaseChallans];

    final filtered = allChallans.where((c) {
      if ((c.isDeleted ?? 0) == 1) return false;
      if (c.status == "Cancelled") return false;
      String name = (c is SaleChallan) ? c.partyName : (c as PurchaseChallan).distributorName;
      return c.billNo.toLowerCase().contains(searchQuery.toLowerCase()) ||
             name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    // Sort by Date (Latest First)
    filtered.sort((a, b) {
      final cmp = b.date.compareTo(a.date);
      return cmp != 0 ? cmp : ((b.updatedAt ?? 0) as int).compareTo((a.updatedAt ?? 0) as int);
    });

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
        final String ofy = isSale ? (ch as SaleChallan).effectiveOriginalFy : (ch as PurchaseChallan).effectiveOriginalFy;
        final bool hasValidDt = isSale ? (ch as SaleChallan).hasValidDate : (ch as PurchaseChallan).hasValidDate;
        final String currFy = normalizeFyString(ph.currentFY);
        final bool isCarry = isStrictCarryForwardFy(ofy, currFy);
        final fwd = ph.getForwardChallanStatus(ch.id, isPurchase: !isSale);
        final String cfTag = (!hasValidDt && ofy.isEmpty) ? "CF / LEGACY" : (ofy.isNotEmpty ? "CF • $ofy" : "CF / LEGACY");
        final String fwdTag = fwd.billedFy != null
            ? "BILLED IN ${fwd.billedFy}"
            : (fwd.shiftedFy != null ? "SHIFTED → ${fwd.shiftedFy}" : "");
        final String envTag = PharoahNumberingEngine.isWebChallanRecord(ch) ? "WEB PORTAL" : "APP";
        final String extraTag = [envTag, if (isCarry) cfTag, if (fwdTag.isNotEmpty) fwdTag].join(" • ");

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
            subtitle: Text(
              "${ch.billNo} | ${DateFormat('dd/MM/yy').format(ch.date)} | ${ch.status.toUpperCase()}${extraTag.isNotEmpty ? ' • $extraTag' : ''}",
              style: const TextStyle(fontSize: 12),
            ),
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
    final fwd = ph.getForwardChallanStatus(challan.id, isPurchase: !isSale);
    final bool isCancelled = challan.status == "Cancelled";
    final bool isBilledLocked = challan.status == "Billed" || fwd.billedFy != null;
    final bool isLocked = isBilledLocked || isCancelled;
    final bool canDelete = !isBilledLocked && (isSale ? ph.canDeleteSaleChallan(challan.id) : ph.canDeletePurchaseChallan(challan.id));
    
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
            _menuTile(
              isBilledLocked ? Icons.lock_outline : Icons.edit,
              isBilledLocked ? "Modify Locked (Billed)" : "Modify / Edit Record",
              isBilledLocked ? Colors.grey : Colors.orange,
              () {
                if (isBilledLocked) {
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("🔒 Locked: Bill already generated. Delete linked Bill first."),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => isSale
                    ? SaleChallanView(existingRecord: challan)
                    : PurchaseChallanView(existingRecord: challan)
                ));
              },
            ),

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

            // 4. DELETE LAST DRAFT / CANCEL MIDDLE CHALLAN
            _menuTile(
              isBilledLocked
                  ? Icons.lock_outline
                  : (canDelete
                      ? Icons.delete_forever
                      : (isCancelled ? Icons.lock_outline : Icons.cancel_outlined)),
              isBilledLocked
                  ? "Delete Locked (Billed)"
                  : (canDelete
                      ? (isCancelled ? "Delete Cancelled (Last)" : "Delete Draft (Last)")
                      : (isCancelled ? "Locked: Cancelled (Middle)" : "Cancel Challan")),
              isBilledLocked
                  ? Colors.grey
                  : (canDelete
                      ? Colors.red
                      : (isCancelled ? Colors.grey : Colors.deepOrange)),
              () {
                if (isBilledLocked) {
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("🔒 Locked: Bill already generated. Delete linked Bill first."),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(c);
                if (canDelete) {
                  _confirmDelete(context, ph, challan);
                } else if (isCancelled) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("🔒 Cancelled challan is retained for audit trail compliance. Only the last challan in series can be deleted."),
                      backgroundColor: Colors.orange,
                    ),
                  );
                } else {
                  _confirmCancel(context, ph, challan);
                }
              },
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData icon, String t, Color c, VoidCallback onTap) => 
      ListTile(leading: Icon(icon, color: c), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)), onTap: onTap);

  void _confirmDelete(BuildContext context, PharoahManager ph, dynamic ch) {
    final bool isSale = ch is SaleChallan;
    final fwd = ph.getForwardChallanStatus(ch.id, isPurchase: !isSale);
    if (ch.status == "Billed" || fwd.billedFy != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🔒 Locked: Bill already generated. Delete linked Bill first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Confirm Delete?"),
        content: Text(
          ch.status == "Cancelled"
              ? "Are you sure? This will permanently delete cancelled challan ${ch.billNo} and reclaim the number."
              : "This action will remove the challan and reverse the stock impact.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final bool ok = isSale
                  ? await ph.deleteSaleChallanAsync(ch.id)
                  : await ph.deletePurchaseChallanAsync(ch.id);
              if (c.mounted) Navigator.pop(c);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: const Text("🔒 Delete blocked: Only the last eligible challan can be permanently deleted."),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: const Text("YES, DELETE", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _confirmCancel(BuildContext context, PharoahManager ph, dynamic ch) {
    final bool isSale = ch is SaleChallan;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Cancel Challan?"),
        content: const Text("This challan will be marked Cancelled for audit trail without reusing its number."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("NO")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () async {
              final bool ok = isSale
                  ? await ph.cancelSaleChallan(ch.id)
                  : await ph.cancelPurchaseChallan(ch.id);
              if (c.mounted) Navigator.pop(c);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? "🚫 Challan Cancelled (audit preserved)." : "🔒 Could not cancel challan."),
                    backgroundColor: ok ? Colors.deepOrange : Colors.orange,
                  ),
                );
              }
            },
            child: const Text("YES, CANCEL", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }
}
