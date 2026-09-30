// FILE: lib/finance/party_wise_stock_view.dart (UPDATED DISPATCH LOGIC)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../pharoah_date_controller.dart';
import '../app_date_logic.dart';
import '../../pdf/statements/party_stock_pdf.dart';
import '../pdf/pdf_router_service.dart';

class PartyWiseStockView extends StatefulWidget {
  const PartyWiseStockView({super.key});
  @override State<PartyWiseStockView> createState() => _PartyWiseStockViewState();
}

class _PartyWiseStockViewState extends State<PartyWiseStockView> {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  String mode = "SALE_ONLY"; 
  String partySearch = "";

  @override
  void initState() {
    super.initState();
    final ph = Provider.of<PharoahManager>(context, listen: false);
    toDate = AppDateLogic.getSmartDate(ph.currentFY);
    fromDate = AppDateLogic.getFYStart(ph.currentFY);
  }

  bool _isInRange(DateTime d) => 
      d.isAfter(fromDate.subtract(const Duration(seconds: 1))) && 
      d.isBefore(toDate.add(const Duration(days: 1)));

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    Map<String, List<Map<String, dynamic>>> groupedData = {};

    for (var s in ph.sales.where((s) => s.status == "Active" && _isInRange(s.date))) {
      if (!groupedData.containsKey(s.partyName)) groupedData[s.partyName] = [];
      for (var it in s.items) {
        groupedData[s.partyName]!.add({'name': it.name, 'qty': it.qty, 'free': it.freeQty, 'rate': it.rate, 'total': it.total, 'type': 'SALE'});
      }
    }

    if (mode == "MIXED") {
      for (var p in ph.purchases.where((p) => _isInRange(p.date))) {
        if (!groupedData.containsKey(p.distributorName)) groupedData[p.distributorName] = [];
        for (var it in p.items) {
          groupedData[p.distributorName]!.add({'name': it.name, 'qty': it.qty, 'free': it.freeQty, 'rate': it.purchaseRate, 'total': it.total, 'type': 'PUR'});
        }
      }
    }

    var filteredParties = groupedData.keys.where((k) => k.toLowerCase().contains(partySearch.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text("Party Stock Statement"),
        backgroundColor: Colors.teal.shade800,
        actions: [
          // --- 📬 SMART DISPATCH (MAIL) ---
          if (ph.config.isMailActive) // Variable updated
            IconButton(
              icon: Icon(
                ph.config.isAuditMode ? Icons.forward_to_inbox_rounded : Icons.alternate_email,
                color: Colors.white,
              ),
              tooltip: ph.config.isAuditMode ? "Forward to CA (Auditor)" : "Send to My Mail",
              onPressed: () {
                PdfRouterService.emailDocument(
                  context: context,
                  doc: {'grouped': groupedData, 'from': fromDate, 'to': toDate, 'mode': mode},
                  party: Party(id: 'internal', name: ph.config.isAuditMode ? 'Audit Analysis' : 'Party Stock Analysis'),
                  ph: ph, type: "STOCK",
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf), 
            onPressed: () async {
              await PartyStockPdf.generate(shop: ph.activeCompany!, groupedData: groupedData, from: fromDate, to: toDate, mode: mode);
            }
          )
        ],
      ),
      body: Column(children: [
        _buildFilterHeader(ph),
        Expanded(
          child: filteredParties.isEmpty 
            ? const Center(child: Text("No records found."))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filteredParties.length,
                itemBuilder: (c, i) => _buildPartyCard(filteredParties[i], groupedData[filteredParties[i]]!),
              ),
        ),
      ]),
    );
  }

  Widget _buildFilterHeader(PharoahManager ph) => Container(
    padding: const EdgeInsets.all(15), color: Colors.teal.shade800,
    child: Column(children: [
      Row(children: [
        Expanded(child: _dateTile("FROM", fromDate, (d) => setState(() => fromDate = d), ph.currentFY)),
        const SizedBox(width: 10),
        Expanded(child: _dateTile("TO", toDate, (d) => setState(() => toDate = d), ph.currentFY)),
      ]),
      const SizedBox(height: 12),
      TextField(
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(hintText: "Search Party...", prefixIcon: const Icon(Icons.search, color: Colors.white), filled: true, fillColor: Colors.white.withOpacity(0.1), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), isDense: true),
        onChanged: (v) => setState(() => partySearch = v),
      )
    ]),
  );

  Widget _buildPartyCard(String name, List<Map<String, dynamic>> items) {
    double t = items.fold(0, (s, e) => s + e['total']);
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      child: Column(children: [
        ListTile(title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
        const Divider(),
        ...items.take(3).map((it) => ListTile(dense: true, title: Text(it['name']), trailing: Text(it['total'].toStringAsFixed(2)))),
        Padding(padding: const EdgeInsets.all(10), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text("TOTAL: ₹${t.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal))])),
      ]),
    );
  }

  Widget _dateTile(String l, DateTime d, Function(DateTime) onPick, String fy) => InkWell(
    onTap: () async { DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: fy, initialDate: d); if (p != null) onPick(p); }, 
    child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8)), child: Text("$l: ${DateFormat('dd/MM').format(d)}", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))
  );
}
