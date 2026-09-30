import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'purchase/purchase_billing_view.dart';
import 'billing_view.dart';
import 'party_master.dart';

class AiVerificationDashboard extends StatefulWidget {
  final List<File> images;
  final Map<String, dynamic> aiData;
  final String mode; // "PURCHASE" or "SALE"

  const AiVerificationDashboard({
    super.key,
    required this.images,
    required this.aiData,
    required this.mode,
  });

  @override
  State<AiVerificationDashboard> createState() => _AiVerificationDashboardState();
}

class _AiVerificationDashboardState extends State<AiVerificationDashboard> {
  late TextEditingController billNoC;
  late TextEditingController partyNameC;
  Party? matchedParty;
  List<dynamic> extractedItems = [];
  bool isOnline = false;

  @override
  void initState() {
    super.initState();
    isOnline = widget.aiData['status'] == "ONLINE";
    billNoC = TextEditingController(text: widget.aiData['billNo']?.toString() ?? "");
    partyNameC = TextEditingController(text: widget.aiData['partyName']?.toString() ?? "");
    
    if (widget.aiData['items'] != null) {
      extractedItems = widget.aiData['items'];
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptPartyMatch();
    });
  }

  // Logic to find if the extracted party name exists in our ERP
  void _attemptPartyMatch() {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    String aiName = partyNameC.text.trim().toLowerCase();
    
    if (aiName.isEmpty) return;

    try {
      // Trying to find a match where AI name is part of our Party name or vice-versa
      matchedParty = ph.parties.firstWhere(
        (p) => p.name.toLowerCase().contains(aiName) || aiName.contains(p.name.toLowerCase())
      );
      setState(() {});
    } catch (e) {
      matchedParty = null;
    }
  }

  void _proceedToBilling() {
    if (matchedParty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select or create a Party first!"), backgroundColor: Colors.orange)
      );
      return;
    }

    if (widget.mode == "PURCHASE") {
      // Pre-filling Purchase Items
      List<PurchaseItem> pItems = extractedItems.map((it) {
        return PurchaseItem(
          id: DateTime.now().millisecondsSinceEpoch.toString() + it['name'].toString(),
          srNo: extractedItems.indexOf(it) + 1,
          medicineID: "temp", // Will be matched in next screen
          name: it['name']?.toString().toUpperCase() ?? "UNKNOWN",
          packing: "N/A",
          batch: "AUTO",
          exp: "12/26",
          hsn: "0000",
          mrp: (double.tryParse(it['rate']?.toString() ?? "0") ?? 0) * 1.2,
          qty: double.tryParse(it['qty']?.toString() ?? "1") ?? 1,
          purchaseRate: double.tryParse(it['rate']?.toString() ?? "0") ?? 0,
          gstRate: 12,
          total: double.tryParse(it['total']?.toString() ?? "0") ?? 0
        );
      }).toList();

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => PurchaseBillingView(
        distributor: matchedParty!,
        internalNo: "AI-PUR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}",
        distBillNo: billNoC.text,
        billDate: DateTime.now(),
        entryDate: DateTime.now(),
        mode: "CREDIT",
        existingItems: pItems,
      )));
    } else {
      // Pre-filling Sale Items
      List<BillItem> sItems = extractedItems.map((it) {
        return BillItem(
          id: DateTime.now().millisecondsSinceEpoch.toString() + it['name'].toString(),
          srNo: extractedItems.indexOf(it) + 1,
          medicineID: "temp",
          name: it['name']?.toString().toUpperCase() ?? "UNKNOWN",
          packing: "N/A",
          batch: "AUTO",
          exp: "12/26",
          hsn: "0000",
          mrp: (double.tryParse(it['rate']?.toString() ?? "0") ?? 0) * 1.2,
          qty: double.tryParse(it['qty']?.toString() ?? "1") ?? 1,
          rate: double.tryParse(it['rate']?.toString() ?? "0") ?? 0,
          gstRate: 12,
          total: double.tryParse(it['total']?.toString() ?? "0") ?? 0
        );
      }).toList();

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => BillingView(
        party: matchedParty!,
        billNo: billNoC.text,
        billDate: DateTime.now(),
        mode: "CASH",
        existingItems: sItems,
      )));
    }
  }

  @override
  Widget build(BuildContext context) {
    Color themeColor = widget.mode == "PURCHASE" ? Colors.orange.shade800 : Colors.blue.shade900;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Verify AI Extraction"),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 1. IMAGE PREVIEW HEADER
          Container(
            height: 140,
            color: Colors.black,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.images.length,
              itemBuilder: (c, i) => Padding(
                padding: const EdgeInsets.all(4.0),
                child: Image.file(widget.images[i], fit: BoxFit.contain),
              ),
            ),
          ),

          // 2. STATUS BANNER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            color: isOnline ? Colors.green.shade50 : Colors.orange.shade50,
            child: Row(children: [
              // FIXED: Icons.warning small letter use kiya hai ab error nahi aayega
              Icon(isOnline ? Icons.auto_awesome : Icons.warning_rounded, size: 16, color: isOnline ? Colors.green : Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.aiData['message'] ?? "", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isOnline ? Colors.green.shade900 : Colors.orange.shade900))),
            ]),
          ),

          // 3. DATA ENTRY FORM
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("BILL INFO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey, letterSpacing: 1)),
                  const SizedBox(height: 10),
                  TextField(controller: billNoC, decoration: const InputDecoration(labelText: "Invoice / Bill Number", border: OutlineInputBorder(), filled: true, fillColor: Colors.white)),
                  const SizedBox(height: 20),

                  // PARTY SELECTION BOX
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: matchedParty != null ? Colors.green : Colors.red.shade200)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Extracted Party: ${partyNameC.text}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        const Divider(),
                        if (matchedParty != null)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.check_circle, color: Colors.green),
                            title: Text(matchedParty!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("${matchedParty!.city} | ${matchedParty!.gst}"),
                            trailing: TextButton(onPressed: () => setState(() => matchedParty = null), child: const Text("CHANGE")),
                          )
                        else
                          Column(
                            children: [
                              const Text("No exact match found in your records.", style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white),
                                onPressed: () async {
                                  final res = await Navigator.push(context, MaterialPageRoute(builder: (c) => const PartyMasterView(isSelectionMode: true)));
                                  if (res != null && res is Party) setState(() { matchedParty = res; });
                                },
                                icon: const Icon(Icons.add_business),
                                label: const Text("SELECT OR CREATE PARTY"),
                              )
                            ],
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // ITEMS DISPLAY
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text("ITEMS EXTRACTED (${extractedItems.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey, letterSpacing: 1)),
                    if(!isOnline) const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                  ]),
                  const SizedBox(height: 10),

                  if (isOnline && extractedItems.isNotEmpty)
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: extractedItems.length,
                      itemBuilder: (c, i) {
                        final it = extractedItems[i];
                        return Card(
                          child: ListTile(
                            title: Text(it['name']?.toString() ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("Qty: ${it['qty']} | Rate: ₹${it['rate']}"),
                            trailing: Text("₹${it['total']}", style: TextStyle(fontWeight: FontWeight.bold, color: themeColor)),
                          ),
                        );
                      },
                    )
                  else if (!isOnline)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("RAW TEXT FROM BILL:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(widget.aiData['raw_text'] ?? "No text found", style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                          const Divider(),
                          const Text("Note: Cloud AI was offline. Please enter items manually on next screen.", style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.blueGrey)),
                        ],
                      ),
                    )
                  else
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No items could be extracted.", style: TextStyle(color: Colors.grey)))),
                ],
              ),
            ),
          ),

          // 4. ACTION BUTTON
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _proceedToBilling,
              child: const Text("CONFIRM & PRE-FILL BILL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          )
        ],
      ),
    );
  }
}
