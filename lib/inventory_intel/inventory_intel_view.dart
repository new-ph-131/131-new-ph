import 'package:flutter/material.dart';

class InventoryIntelView extends StatelessWidget {
  const InventoryIntelView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Stock Analytics & Intel"), backgroundColor: Colors.purple.shade700),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card("SHORTAGE REGISTER", "Items below reorder level", Icons.warning_amber_rounded, Colors.red),
          _card("PURCHASE ORDER BUILDER", "Generate PO for distributors", Icons.shopping_cart_checkout, Colors.blue),
          _card("DUMPING / NON-MOVING", "Stock not sold in 90 days", Icons.delete_sweep_outlined, Colors.orange),
          _card("FAST MOVING ITEMS", "Top selling products", Icons.trending_up, Colors.green),
        ],
      ),
    );
  }

  Widget _card(String t, String s, IconData i, Color c) => Card(
    child: ListTile(
      leading: Icon(i, color: c, size: 30),
      title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(s),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
    ),
  );
}
