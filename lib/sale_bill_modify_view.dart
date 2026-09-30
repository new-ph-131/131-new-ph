// FILE: lib/sale_bill_modify_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'sale_entry_view.dart';
import 'pdf/sale_invoice_pdf.dart'; 
import 'package:intl/intl.dart';

class SaleBillModifyView extends StatefulWidget {
  const SaleBillModifyView({super.key});
  @override State<SaleBillModifyView> createState() => _SaleBillModifyViewState();
}

class _SaleBillModifyViewState extends State<SaleBillModifyView> {
  String dur = "Today"; 
  String pF = "All"; 
  Party? sP;

  // ORIGINAL FILTER LOGIC
  List<Sale> getFilteredSales(List<Sale> all) {
    DateTime n = DateTime.now();
    return all.where((s) {
      bool dateMatch = false;
      if (dur == "Today") {
        dateMatch = s.date.day == n.day && s.date.month == n.month && s.date.year == n.year;
      } else if (dur == "Yesterday") {
        DateTime y = n.subtract(const Duration(days: 1));
        dateMatch = s.date.day == y.day && s.date.month == y.month && s.date.year == y.year;
      } else if (dur == "Month") {
        dateMatch = s.date.month == n.month && s.date.year == n.year;
      } else {
        dateMatch = true;
      }
      
      bool partyMatch = true;
      if (pF == "Single") {
        if (sP == null) {
          partyMatch = false; 
        } else {
          partyMatch = s.partyName.trim().toUpperCase() == sP!.name.trim().toUpperCase();
        }
      }
      return dateMatch && partyMatch;
    }).toList().reversed.toList();
  }

  void _showPartySearchDialog(List<Party> allParties) {
    showDialog(
      context: context,
      builder: (context) {
        String dialogSearch = "";
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredList = allParties
                .where((p) => p.name.toLowerCase().contains(dialogSearch.toLowerCase()))
                .toList();

            return AlertDialog(
              title: const Text("Select Party"),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: "Type name to search...",
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setDialogState(() => dialogSearch = v),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredList.length,
                        itemBuilder: (c, i) {
                          return ListTile(
                            title: Text(filteredList[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(filteredList[i].city),
                            onTap: () {
                              setState(() { sP = filteredList[i]; });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final list = getFilteredSales(ph.sales);
    final activeShop = ph.activeCompany;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Modify Sale Bills"),
        backgroundColor: Colors.orange.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
            ),
            child: Row(
              children: [
                Expanded(child: _buildFilterDropdown("DURATION", dur, ["Today", "Yesterday", "Month", "All"], (v) => setState(() => dur = v!))),
                const SizedBox(width: 15),
                Expanded(child: _buildFilterDropdown("FILTER BY", pF, ["All", "Single"], (v) {
                  setState(() { pF = v!; if (pF == "All") sP = null; });
                })),
              ],
            ),
          ),

          if (pF == "Single")
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              child: ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10), 
                  side: BorderSide(color: Colors.orange.shade100, width: 1.5)
                ),
                leading: const Icon(Icons.person_search, color: Colors.orange),
                title: Text(sP?.name ?? "TAP TO SELECT PARTY", style: TextStyle(fontWeight: FontWeight.bold, color: sP == null ? Colors.red : Colors.black87)),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: () => _showPartySearchDialog(ph.parties),
              ),
            ),

          Expanded(
            child: list.isEmpty
                ? const Center(child: Text("No bills found."))
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final s = list[index];
                      bool isCancelled = s.status == "Cancelled";

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 10),
                        color: isCancelled ? Colors.red.shade50 : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          title: Row(
                            children: [
                              Text(s.billNo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                              const Spacer(),
                              Text("₹${s.totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.partyName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                              Text("Date: ${DateFormat('dd/MM/yyyy').format(s.date)} | Mode: ${s.paymentMode}"),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (v) async {
                              final p = ph.parties.firstWhere((x) => x.name == s.partyName, orElse: () => ph.parties[0]);
                              if (v == 'v') Navigator.push(context, MaterialPageRoute(builder: (c) => SaleEntryView(existingSale: s, isReadOnly: true)));
                              if (v == 'm') Navigator.push(context, MaterialPageRoute(builder: (c) => SaleEntryView(existingSale: s)));
                              
                              // NAYA: Active Shop ke sath Print call
                              if (v == 'p' && activeShop != null) SaleInvoicePdf.generate(s, p, activeShop); 
                              
                              if (v == 'c') _confirmAction(context, "Cancel", () => ph.cancelBill(s.id));
                              if (v == 'd') _confirmAction(context, "Delete", () => ph.deleteBill(s.id));
                            },
                            itemBuilder: (c) => [
                              const PopupMenuItem(value: 'v', child: Row(children: [Icon(Icons.visibility, size: 18), SizedBox(width: 10), Text("View Bill")])),
                              const PopupMenuItem(value: 'm', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 10), Text("Edit/Modify")])),
                              const PopupMenuItem(value: 'p', child: Row(children: [Icon(Icons.print, size: 18), SizedBox(width: 10), Text("Print Copy")])),
                              const PopupMenuDivider(),
                              const PopupMenuItem(value: 'c', child: Row(children: [Icon(Icons.block, size: 18, color: Colors.orange), SizedBox(width: 10), Text("Cancel Bill")])),
                              const PopupMenuItem(value: 'd', child: Row(children: [Icon(Icons.delete_forever, size: 18, color: Colors.red), SizedBox(width: 10), Text("Delete Bill")])),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        DropdownButton<String>(
          isExpanded: true,
          value: value,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14)))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _confirmAction(BuildContext context, String action, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("$action Bill?"),
        content: Text("Are you sure you want to $action this bill? This will reverse the stock levels."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("NO")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () { onConfirm(); Navigator.pop(c); },
            child: const Text("YES, PROCEED", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }
}
