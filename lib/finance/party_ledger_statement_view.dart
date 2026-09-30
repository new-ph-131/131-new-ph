// FILE: lib/finance/party_ledger_statement_view.dart (UPDATED DISPATCH LOGIC)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../pharoah_date_controller.dart';
import '../app_date_logic.dart';
import '../pdf/pdf_router_service.dart';
import '../../pdf/statements/party_ledger_pdf.dart';

class PartyLedgerStatementView extends StatefulWidget {
  const PartyLedgerStatementView({super.key});
  @override State<PartyLedgerStatementView> createState() => _PartyLedgerStatementViewState();
}

class _PartyLedgerStatementViewState extends State<PartyLedgerStatementView> {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  Party? selectedParty;
  String partyQuery = "";

  @override
  void initState() {
    super.initState();
    final ph = Provider.of<PharoahManager>(context, listen: false);
    toDate = AppDateLogic.getSmartDate(ph.currentFY);
    fromDate = AppDateLogic.getFYStart(ph.currentFY);
  }

  void _generateStatementPdf(PharoahManager ph) async {
    if (selectedParty == null) return;
    final data = ph.getPartyStatementData(partyId: selectedParty!.id, fromDate: fromDate, toDate: toDate);
    await PartyLedgerPdf.generate(shop: ph.activeCompany!, party: selectedParty!, data: data, from: fromDate, to: toDate);
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    List<Map<String, dynamic>> ledgerData = [];
    if (selectedParty != null) {
      ledgerData = ph.getPartyStatementData(partyId: selectedParty!.id, fromDate: fromDate, toDate: toDate);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Text(selectedParty == null ? "Ledger Audit" : selectedParty!.name),
        backgroundColor: const Color(0xFF1A237E),
        actions: [
          if (selectedParty != null) ...[
            // --- 📬 SMART DISPATCH (MAIL) ---
            if (ph.config.isMailActive) // Variable updated
              IconButton(
                icon: Icon(
                  ph.config.isAuditMode ? Icons.forward_to_inbox_rounded : Icons.alternate_email,
                  color: Colors.white,
                ),
                tooltip: ph.config.isAuditMode ? "Mail Statement to CA" : "Mail Statement to Party",
                onPressed: () {
                  PdfRouterService.emailDocument(
                    context: context, doc: ledgerData, party: selectedParty!, ph: ph, type: "LEDGER",
                  );
                },
              ),
            IconButton(icon: const Icon(Icons.picture_as_pdf_rounded), onPressed: () => _generateStatementPdf(ph)),
          ]
        ],
      ),
      body: Column(children: [
        _buildFilterPanel(ph),
        Expanded(child: selectedParty == null ? _buildPartySelector(ph) : _buildLedgerTable(ledgerData)),
      ]),
    );
  }

  Widget _buildFilterPanel(PharoahManager ph) => Container(
    padding: const EdgeInsets.all(15), color: const Color(0xFF1A237E),
    child: Row(children: [
      Expanded(child: _dateBox("FROM", fromDate, (d) => setState(() => fromDate = d), ph.currentFY)),
      const SizedBox(width: 10),
      Expanded(child: _dateBox("TO", toDate, (d) => setState(() => toDate = d), ph.currentFY)),
    ]),
  );

  Widget _buildPartySelector(PharoahManager ph) {
    final list = ph.parties.where((p) => p.name.toLowerCase().contains(partyQuery.toLowerCase())).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.all(15), child: TextField(decoration: const InputDecoration(hintText: "Search Party..."), onChanged: (v) => setState(() => partyQuery = v))),
      Expanded(child: ListView.builder(itemCount: list.length, itemBuilder: (c, i) => ListTile(title: Text(list[i].name), onTap: () => setState(() => selectedParty = list[i]))))
    ]);
  }

  Widget _buildLedgerTable(List<Map<String, dynamic>> data) {
    return ListView.builder(
      itemCount: data.length,
      itemBuilder: (c, i) {
        final row = data[i];
        return ListTile(
          title: Text(row['ref'], style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text("${row['type']} | Bal: ${row['bal'].toStringAsFixed(2)}"),
        );
      },
    );
  }

  Widget _dateBox(String l, DateTime d, Function(DateTime) onPick, String fy) => InkWell(onTap: () async { DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: fy, initialDate: d); if (p != null) onPick(p); }, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text("$l: ${DateFormat('dd/MM/yy').format(d)}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))));
}
