import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../pdf/purchase_pdf.dart';
import 'purchase_entry_view.dart';

class PurchaseModifyView extends StatefulWidget {
  const PurchaseModifyView({super.key});
  @override State<PurchaseModifyView> createState() => _PurchaseModifyViewState();
}

class _PurchaseModifyViewState extends State<PurchaseModifyView> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final list = ph.purchases.reversed.where((p) => 
      p.distributorName.toLowerCase().contains(searchQuery.toLowerCase()) || 
      p.billNo.toLowerCase().contains(searchQuery.toLowerCase())
    ).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Purchase Register"), 
        backgroundColor: Colors.orange.shade800, 
        foregroundColor: Colors.white,
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(
          decoration: const InputDecoration(
            hintText: "Search Supplier or Bill No...", 
            prefixIcon: Icon(Icons.search), 
            filled: true, fillColor: Colors.white, 
            border: OutlineInputBorder()
          ), 
          onChanged: (v) => setState(() => searchQuery = v)
        )),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(10), 
            itemCount: list.length, 
            itemBuilder: (context, index) {
              final p = list[index];
              // Supplier find karna for PDF
              final supplier = ph.parties.firstWhere(
                (pt) => pt.name == p.distributorName, 
                orElse: () => Party(id: "", name: p.distributorName)
              );
              return Card(
                elevation: 2, 
                margin: const EdgeInsets.only(bottom: 10), 
                child: ListTile(
                  title: Text(p.distributorName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Bill: ${p.billNo} | Date: ${DateFormat('dd/MM/yy').format(p.date)}\nTotal: ₹${p.totalAmount.toStringAsFixed(2)}"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.print, color: Colors.blueGrey), 
                        onPressed: () => PurchasePdf.generate(p, supplier)
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue), 
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => PurchaseEntryView(existingPurchase: p)))
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red), 
                        onPressed: () => _confirmDelete(context, ph, p)
                      ),
                    ],
                  ),
                )
              );
            }
          )
        )
      ]),
    );
  }

  void _confirmDelete(BuildContext context, PharoahManager ph, Purchase p) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Purchase?"),
        content: const Text("Isse aapka stock automatic kam ho jayega. Kya aap ise delete karna chahte hain?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("NO")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () { ph.deletePurchase(p.id); Navigator.pop(c); }, 
            child: const Text("YES, DELETE", style: TextStyle(color: Colors.white))
          )
        ],
      ),
    );
  }
}
