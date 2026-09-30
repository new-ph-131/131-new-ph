import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'pharoah_manager.dart';
import 'models.dart';

class EWayBillManagementView extends StatefulWidget {
  const EWayBillManagementView({super.key});

  @override
  State<EWayBillManagementView> createState() => _EWayBillManagementViewState();
}

class _EWayBillManagementViewState extends State<EWayBillManagementView> {
  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    
    // --- FILTERING HIGH VALUE BILLS ---
    // GST rules suggest E-Way bill is mandatory for transactions above ₹50,000
    List<Sale> highValueBills = ph.sales.where((s) => 
      s.totalAmount >= 50000 && s.status == "Active"
    ).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("E-Way Bill & E-Invoicing"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Info header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            color: Colors.indigo.shade50,
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.indigo, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Showing ${highValueBills.length} active bills exceeding ₹50,000 threshold.",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: highValueBills.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_shipping_outlined, size: 80, color: Colors.grey.shade300),
                        const SizedBox(height: 10),
                        const Text("No bills require E-Way bill generation.", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: highValueBills.length,
                    itemBuilder: (context, index) {
                      final s = highValueBills[index];
                      // Checking details from the updated model
                      bool hasDetails = s.vehicleNo.isNotEmpty || s.transporterId.isNotEmpty;

                      return Card(
                        elevation: 3,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.all(15),
                              title: Text(s.partyName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Inv No: ${s.billNo} | Date: ${DateFormat('dd/MM/yyyy').format(s.date)}"),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Amount: ₹${s.totalAmount.toStringAsFixed(2)}",
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                                  ),
                                  if (hasDetails) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(5)),
                                      child: Text(
                                        "Vehicle: ${s.vehicleNo} | ID: ${s.transporterId}",
                                        style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                                      ),
                                    )
                                  ]
                                ],
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _showTransportDialog(context, s),
                                child: Text(hasDetails ? "EDIT DETAILS" : "ADD DETAILS"),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // --- DIALOG FOR TRANSPORT DATA ENTRY ---
  void _showTransportDialog(BuildContext context, Sale sale) {
    final tNameC = TextEditingController(text: sale.transporterName);
    final tIdC = TextEditingController(text: sale.transporterId);
    final vNoC = TextEditingController(text: sale.vehicleNo);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Transport & E-Way Details"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter details for Government JSON generation.", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 20),
              _dialogField(tNameC, "Transporter Name"),
              _dialogField(tIdC, "Transporter GSTIN / ID"),
              _dialogField(vNoC, "Vehicle Number (e.g. RJ14AB1234)"),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            onPressed: () {
              // Updating the sale object directly (Model fields are already synced)
              setState(() {
                sale.transporterName = tNameC.text.toUpperCase();
                sale.transporterId = tIdC.text.toUpperCase();
                sale.vehicleNo = vNoC.text.toUpperCase();
              });
              
              Provider.of<PharoahManager>(context, listen: false).save();
              Navigator.pop(c);
              _generatePortalJson(sale);
            },
            child: const Text("SAVE & SHARE JSON", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  // --- JSON EXPORT LOGIC FOR PORTAL ---
  void _generatePortalJson(Sale s) {
    // Government Offline Utility Format
    Map<String, dynamic> ewayJson = {
      "version": "1.0.0",
      "billLists": [{
        "userGstin": "YOUR_COMPANY_GSTIN", 
        "supplyType": "Outward",
        "docType": "Invoice",
        "docNo": s.billNo,
        "docDate": DateFormat('dd/MM/yyyy').format(s.date),
        "transporterId": s.transporterId,
        "transporterName": s.transporterName,
        "vehicleNo": s.vehicleNo,
        "totalValue": s.totalAmount,
        "itemList": s.items.map((it) => {
          "itemDesc": it.name,
          "hsnCode": it.hsn,
          "quantity": it.qty,
          "taxableAmount": (it.total - (it.cgst + it.sgst + it.igst)).toStringAsFixed(2),
          "gstRate": it.gstRate
        }).toList()
      }]
    };

    String jsonString = const JsonEncoder.withIndent('  ').convert(ewayJson);
    Share.share(jsonString, subject: 'EWayBill_JSON_${s.billNo}');
  }

  Widget _dialogField(TextEditingController ctrl, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}
