import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'pdf_service.dart';
import 'sale_entry_view.dart';

class ReportsView extends StatefulWidget {
  const ReportsView({super.key});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    
    // Most recent sales at the top
    final allSales = ph.sales.reversed.toList();

    // Filter sales based on Search Query (Bill No or Party Name)
    final filteredSales = allSales.where((s) {
      final query = searchQuery.toLowerCase();
      return s.billNo.toLowerCase().contains(query) || 
             s.partyName.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Sales Reports & History"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // --- SEARCH BAR ---
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.blue.shade50,
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search by Bill No or Party Name...",
                prefixIcon: const Icon(Icons.search, color: Colors.blue),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
          ),

          // --- SALES LIST ---
          Expanded(
            child: filteredSales.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey.shade300),
                        const SizedBox(height: 10),
                        const Text("No bills found matching your search.", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredSales.length,
                    itemBuilder: (context, index) {
                      final sale = filteredSales[index];
                      final isCancelled = sale.status == "Cancelled";

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        color: isCancelled ? Colors.red.shade50 : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                          title: Row(
                            children: [
                              Text(
                                sale.billNo,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue),
                              ),
                              const Spacer(),
                              Text(
                                "₹${sale.totalAmount.toStringAsFixed(2)}",
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                sale.partyName,
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    DateFormat('dd/MM/yyyy').format(sale.date),
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isCancelled ? Colors.red.shade100 : Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      sale.status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 9, 
                                        fontWeight: FontWeight.bold, 
                                        color: isCancelled ? Colors.red.shade800 : Colors.green.shade800
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // PRINT BUTTON
                              IconButton(
                                icon: const Icon(Icons.print, color: Colors.blueGrey),
                                onPressed: () {
                                  final p = ph.parties.firstWhere(
                                    (x) => x.name == sale.partyName, 
                                    orElse: () => ph.parties[0]
                                  );
                                  PdfService.generateInvoice(sale, p);
                                },
                              ),
                              // ACTION POPUP
                              PopupMenuButton<String>(
                                onSelected: (val) {
                                  if (val == 'view') {
                                    Navigator.push(context, MaterialPageRoute(builder: (c) => SaleEntryView(existingSale: sale, isReadOnly: true)));
                                  } else if (val == 'edit') {
                                    Navigator.push(context, MaterialPageRoute(builder: (c) => SaleEntryView(existingSale: sale)));
                                  }
                                },
                                itemBuilder: (c) => [
                                  const PopupMenuItem(value: 'view', child: Text("View Details")),
                                  const PopupMenuItem(value: 'edit', child: Text("Edit Bill")),
                                ],
                              ),
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
}
