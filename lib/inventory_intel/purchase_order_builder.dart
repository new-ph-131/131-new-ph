// FILE: lib/inventory_intel/purchase_order_builder.dart (Updated Logic)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';

class PurchaseOrderBuilder extends StatefulWidget {
  const PurchaseOrderBuilder({super.key});

  @override
  State<PurchaseOrderBuilder> createState() => _PurchaseOrderBuilderState();
}

class _PurchaseOrderBuilderState extends State<PurchaseOrderBuilder> {
  Party? selectedDistributor;
  String? filterByCompany; // "All" or specific brand
  List<Map<String, dynamic>> orderList = []; // Real-time order items
  String medSearchQuery = "";

  // --- LOGIC: INITIALIZE ORDER FROM SHORTAGE ---
  void _loadFromShortage(PharoahManager ph) {
    orderList.clear();
    for (var s in ph.shortages) {
      if (filterByCompany == null || filterByCompany == "ALL" || s.companyName == filterByCompany) {
        orderList.add({
          'id': s.medicineId,
          'name': s.medicineName,
          'company': s.companyName,
          'qty': s.qtyRequired,
        });
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Create Purchase Order"),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (orderList.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: () {
                // Future: PDF Generation Service
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Generating PO PDF...")));
              },
            )
        ],
      ),
      body: Column(
        children: [
          // --- 1. SELECTION HEADER ---
          _buildSelectionHeader(ph),

          // --- 2. THE ORDER LIST ---
          Expanded(
            child: orderList.isEmpty 
              ? _buildEmptyState() 
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: orderList.length,
                  itemBuilder: (c, i) => _buildOrderItemTile(i),
                ),
          ),
          
          // --- 3. MANUAL ADD BAR ---
          if (selectedDistributor != null) _buildManualAddBar(ph),
        ],
      ),
    );
  }

  Widget _buildSelectionHeader(PharoahManager ph) {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: Column(
        children: [
          // Distributor Picker
          InkWell(
            onTap: () => _showDistributorPicker(ph),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(border: Border.all(color: Colors.blue.shade200), borderRadius: BorderRadius.circular(10), color: Colors.blue.shade50),
              child: Row(
                children: [
                  const Icon(Icons.business, color: Colors.blue),
                  const SizedBox(width: 15),
                  Text(selectedDistributor?.name ?? "TAP TO SELECT SUPPLIER", style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Company Filter
          if (selectedDistributor != null)
            Row(
              children: [
                const Text("Order For:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 15),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: filterByCompany ?? "ALL",
                    items: ["ALL", ...ph.medicines.map((m) => m.companyId).toSet()]
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.toUpperCase(), style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) {
                      setState(() { filterByCompany = v; _loadFromShortage(ph); });
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildOrderItemTile(int index) {
    final item = orderList[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("Brand: ${item['company']}"),
        trailing: SizedBox(
          width: 100,
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () {
                setState(() { if(orderList[index]['qty'] > 1) orderList[index]['qty']--; });
              }),
              Text(item['qty'].toInt().toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.green), onPressed: () {
                setState(() { orderList[index]['qty']++; });
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualAddBar(PharoahManager ph) {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(hintText: "Add more items manually...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onTap: () => _showManualMedicinePicker(ph),
              readOnly: true,
            ),
          ),
        ],
      ),
    );
  }

  void _showDistributorPicker(PharoahManager ph) {
    showModalBottomSheet(
      context: context,
      builder: (c) => ListView(
        children: ph.parties.where((p) => p.group == "Sundry Creditors").map((p) => ListTile(
          title: Text(p.name),
          onTap: () { setState(() => selectedDistributor = p); Navigator.pop(c); _loadFromShortage(ph); },
        )).toList(),
      ),
    );
  }

  void _showManualMedicinePicker(PharoahManager ph) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Container(
        height: 400,
        child: ListView.builder(
          itemCount: ph.medicines.length,
          itemBuilder: (c, i) => ListTile(
            title: Text(ph.medicines[i].name),
            subtitle: Text(ph.medicines[i].companyId),
            onTap: () {
              setState(() {
                orderList.add({
                  'id': ph.medicines[i].id,
                  'name': ph.medicines[i].name,
                  'company': ph.medicines[i].companyId,
                  'qty': 1,
                });
              });
              Navigator.pop(c);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() => Center(child: Text("No items in order list. Select a supplier and company."));
}
