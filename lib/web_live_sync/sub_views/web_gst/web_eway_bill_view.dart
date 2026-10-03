// FILE: lib/web_live_sync/sub_views/web_gst/web_eway_bill_view.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_saver/file_saver.dart';
import '../../web_models.dart';
import '../../pharoah_web_manager.dart';

class WebEwayBillView extends StatefulWidget {
  final PharoahWebManager webPh;
  final VoidCallback onBack;

  const WebEwayBillView({super.key, required this.webPh, required this.onBack});

  @override
  State<WebEwayBillView> createState() => _WebEwayBillViewState();
}

class _WebEwayBillViewState extends State<WebEwayBillView> {
  void _editTransport(Sale s) {
    final tNameC = TextEditingController(text: s.transporterName);
    final tIdC = TextEditingController(text: s.transporterId);
    final vNoC = TextEditingController(text: s.vehicleNo);

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Transport Details • ${s.billNo}", style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _input("Transporter Name", tNameC),
            const SizedBox(height: 10),
            _input("Transporter GSTIN / ID", tIdC),
            const SizedBox(height: 10),
            _input("Vehicle Number (e.g. RJ14AB1234)", vNoC),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
            onPressed: () {
              setState(() {
                s.transporterName = tNameC.text.trim().toUpperCase();
                s.transporterId = tIdC.text.trim().toUpperCase();
                s.vehicleNo = vNoC.text.trim().toUpperCase();
              });
              widget.webPh.pushUpdatedDataToCloud();
              Navigator.pop(c);
              _downloadEwayJson(s);
            },
            child: const Text("SAVE & DOWNLOAD JSON"),
          ),
        ],
      ),
    );
  }

  void _downloadEwayJson(Sale s) async {
    Map<String, dynamic> jsonMap = {
      "version": "1.0.0",
      "billLists": [{
        "userGstin": widget.webPh.companyProfile['gstin'] ?? "YOUR_GSTIN",
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
          "gstRate": it.gstRate,
        }).toList(),
      }]
    };

    String formatted = const JsonEncoder.withIndent('  ').convert(jsonMap);
    await FileSaver.instance.saveFile(
      name: "EWayBill_${s.billNo}",
      bytes: Uint8List.fromList(utf8.encode(formatted)),
      ext: "json",
      mimeType: MimeType.other,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ E-Way Bill JSON for ${s.billNo} downloaded!"), backgroundColor: Colors.green),
      );
    }
  }

  Widget _input(String label, TextEditingController ctrl) => TextField(
    controller: ctrl,
    textCapitalization: TextCapitalization.characters,
    style: const TextStyle(color: Colors.white, fontSize: 12),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
      filled: true,
      fillColor: Colors.black26,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final highValueBills = widget.webPh.sales.where((s) => s.totalAmount >= 50000 && s.status == "Active").toList();

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("E-WAY BILL MANDATORY THRESHOLD (>= ₹50,000)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5)),
              Text("${highValueBills.length} Invoices Found", style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 16),

          if (highValueBills.isEmpty)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("No invoices exceeding ₹50,000 threshold found.", style: TextStyle(color: Colors.white38))))
          else
            ListView.builder(
              shrinkWrap: true,
              itemCount: highValueBills.length,
              itemBuilder: (ctx, i) {
                final s = highValueBills[i];
                bool hasTransport = s.vehicleNo.isNotEmpty || s.transporterId.isNotEmpty;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
                  child: ListTile(
                    dense: true,
                    title: Row(
                      children: [
                        Text(s.partyName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 8),
                        Text("#${s.billNo}", style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11)),
                      ],
                    ),
                    subtitle: Text(
                      hasTransport ? "Vehicle: ${s.vehicleNo} • Transporter: ${s.transporterName}" : "⚠️ Transport details pending",
                      style: TextStyle(color: hasTransport ? Colors.greenAccent : Colors.orangeAccent, fontSize: 10),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("₹${s.totalAmount.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5)),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                          onPressed: () => _editTransport(s),
                          icon: const Icon(Icons.local_shipping_rounded, size: 14),
                          label: Text(hasTransport ? "UPDATE / JSON" : "ADD TRANSPORT"),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
