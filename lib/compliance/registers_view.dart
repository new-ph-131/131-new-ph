// FILE: lib/compliance/registers_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';

class RegistersView extends StatelessWidget {
  final String registerType; // "H1" or "Narcotic"
  const RegistersView({super.key, required this.registerType});

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    
    // logic: Scan all sales and filter items based on Master Flag
    List<Map<String, dynamic>> filteredItems = [];

    for (var sale in ph.sales.where((s) => s.status == "Active")) {
      for (var item in sale.items) {
        // Find medicine in master to check flags
        try {
          final med = ph.medicines.firstWhere((m) => m.id == item.medicineID);
          
          bool shouldAdd = false;
          if (registerType == "H1" && med.isScheduleH1) shouldAdd = true;
          if (registerType == "Narcotic" && med.isNarcotic) shouldAdd = true;

          if (shouldAdd) {
            filteredItems.add({
              'date': sale.date,
              'billNo': sale.billNo,
              'party': sale.partyName,
              'item': item.name,
              'batch': item.batch,
              'qty': item.qty + item.freeQty,
            });
          }
        } catch (e) {
          // Medicine not found in master (deleted), skip
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Schedule $registerType Register"),
        backgroundColor: registerType == "H1" ? Colors.teal.shade800 : Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: filteredItems.isEmpty
          ? _buildEmptyState()
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                  columns: const [
                    DataColumn(label: Text('DATE')),
                    DataColumn(label: Text('BILL NO')),
                    DataColumn(label: Text('PARTY NAME')),
                    DataColumn(label: Text('PRODUCT')),
                    DataColumn(label: Text('BATCH')),
                    DataColumn(label: Text('QTY')),
                  ],
                  rows: filteredItems.map((data) => DataRow(cells: [
                    DataCell(Text(DateFormat('dd/MM/yy').format(data['date']))),
                    DataCell(Text(data['billNo'])),
                    DataCell(Text(data['party'])),
                    DataCell(Text(data['item'], style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text(data['batch'])),
                    DataCell(Text(data['qty'].toInt().toString())),
                  ])).toList(),
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_turned_in_outlined, size: 80, color: Colors.grey.shade200),
          const SizedBox(height: 10),
          const Text("No entries found for this category.", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
