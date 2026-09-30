import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';

class PurchaseViewOnly extends StatelessWidget {
  final Purchase purchase;

  const PurchaseViewOnly({super.key, required this.purchase});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: Text("Purchase ID: ${purchase.internalNo}"),
        backgroundColor: Colors.deepOrange.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Supplier Info
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(purchase.distributorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepOrange)),
                  Text(DateFormat('dd/MM/yyyy').format(purchase.date), style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
                const Divider(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text("Supplier Bill: ${purchase.billNo}"),
                  Text("Mode: ${purchase.paymentMode}"),
                ]),
              ],
            ),
          ),
          // Items List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: purchase.items.length,
              itemBuilder: (c, i) {
                final it = purchase.items[i];
                return Card(
                  child: ListTile(
                    title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Batch: ${it.batch} | Exp: ${it.exp} | Qty: ${it.qty.toInt()}"),
                    trailing: Text("₹${it.total.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ),
          // Grand Total
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.orange.shade50,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("TOTAL PURCHASE", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("₹${purchase.totalAmount.toStringAsFixed(2)}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.deepOrange.shade900)),
            ]),
          ),
        ],
      ),
    );
  }
}
