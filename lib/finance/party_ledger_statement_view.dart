// FILE: lib/finance/party_ledger_statement_view.dart
// Revision: #PH-REV-746 (INTERACTIVE-STATEMENT-HUB-AND-PARITY)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../pharoah_date_controller.dart';
import '../app_date_logic.dart';
import '../pdf/pdf_router_service.dart';
import '../../pdf/statements/party_ledger_pdf.dart';

class PartyLedgerStatementView extends StatefulWidget {
  final Party? initialParty;
  const PartyLedgerStatementView({super.key, this.initialParty});

  @override
  State<PartyLedgerStatementView> createState() => _PartyLedgerStatementViewState();
}

class _PartyLedgerStatementViewState extends State<PartyLedgerStatementView> {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  Party? selectedParty;
  String partyQuery = "";
  String filterType = "ALL"; // ALL, BILLS, SETTLEMENTS

  @override
  void initState() {
    super.initState();
    if (widget.initialParty != null) {
      selectedParty = widget.initialParty;
    }
    final ph = Provider.of<PharoahManager>(context, listen: false);
    toDate = AppDateLogic.getSmartDate(ph.currentFY);
    fromDate = AppDateLogic.getFYStart(ph.currentFY);
  }

  void _generateStatementPdf(PharoahManager ph) async {
    if (selectedParty == null) return;
    final data = ph.getPartyStatementData(partyId: selectedParty!.id, fromDate: fromDate, toDate: toDate);
    await PartyLedgerPdf.generate(shop: ph.activeCompany!, party: selectedParty!, data: data, from: fromDate, to: toDate);
  }

  void _shareStatementWhatsApp(Party p, double openingBal, double totalDr, double totalCr, double closingBal) async {
    final f = DateFormat('dd/MM/yyyy');
    String msg = "📊 *KHAATA STATEMENT - ${p.name.toUpperCase()}*\n"
        "Period: ${f.format(fromDate)} to ${f.format(toDate)}\n"
        "--------------------------------\n"
        "Opening Bal: ₹${openingBal.abs().toStringAsFixed(2)} ${openingBal >= 0 ? 'Dr' : 'Cr'}\n"
        "Total Debits (+): ₹${totalDr.toStringAsFixed(2)}\n"
        "Total Credits (-): ₹${totalCr.toStringAsFixed(2)}\n"
        "Closing Balance: ₹${closingBal.abs().toStringAsFixed(2)} ${closingBal >= 0 ? 'Dr' : 'Cr'}\n"
        "--------------------------------\n"
        "Please find your updated statement summary. Thank you!";
    final phoneDigits = p.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse("https://wa.me/$phoneDigits?text=${Uri.encodeComponent(msg)}");
    if (await canLaunchUrl(uri)) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    List<Map<String, dynamic>> rawLedgerData = [];
    if (selectedParty != null) {
      rawLedgerData = ph.getPartyStatementData(partyId: selectedParty!.id, fromDate: fromDate, toDate: toDate);
    }

    final ledgerData = rawLedgerData.where((e) {
      if (e['type'] == 'OPENING') return true;
      if (filterType == "BILLS") {
        final t = (e['type'] ?? '').toString();
        return t.contains("SALE") || t.contains("PURCHASE") || t.contains("CN") || t.contains("DN");
      }
      if (filterType == "SETTLEMENTS") {
        final t = (e['type'] ?? '').toString();
        return t.contains("RECEIPT") || t.contains("PAYMENT") || t.contains("SETTLE") || t.contains("CONTRA");
      }
      return true;
    }).toList();

    double openingBal = 0.0;
    if (rawLedgerData.isNotEmpty && rawLedgerData.first['type'] == 'OPENING') {
      openingBal = (rawLedgerData.first['balance'] ?? rawLedgerData.first['bal'] ?? 0.0) as double;
    }
    double totalDr = rawLedgerData.where((e) => e['type'] != 'OPENING').fold(0.0, (s, e) => s + ((e['dr'] as num?)?.toDouble() ?? 0.0));
    double totalCr = rawLedgerData.where((e) => e['type'] != 'OPENING').fold(0.0, (s, e) => s + ((e['cr'] as num?)?.toDouble() ?? 0.0));
    double closingBal = rawLedgerData.isNotEmpty ? ((rawLedgerData.last['balance'] ?? rawLedgerData.last['bal'] ?? 0.0) as double) : openingBal;

    final isCashOrBank = selectedParty != null && (
        selectedParty!.name.trim().toUpperCase() == "CASH" ||
        selectedParty!.group.trim().toLowerCase().contains("cash") ||
        selectedParty!.group.trim().toLowerCase().contains("bank"));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectedParty == null ? "Party Ledger Audit" : selectedParty!.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (selectedParty != null)
              Text(
                "${selectedParty!.group} ${selectedParty!.city.isNotEmpty ? '• ' + selectedParty!.city : ''}",
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        actions: [
          if (selectedParty != null) ...[
            IconButton(
              icon: const Icon(Icons.share_rounded, color: Colors.greenAccent),
              tooltip: "Share via WhatsApp",
              onPressed: () => _shareStatementWhatsApp(selectedParty!, openingBal, totalDr, totalCr, closingBal),
            ),
            if (ph.config.isMailActive)
              IconButton(
                icon: Icon(
                  ph.config.isAuditMode ? Icons.forward_to_inbox_rounded : Icons.alternate_email,
                  color: Colors.white,
                ),
                tooltip: ph.config.isAuditMode ? "Mail Statement to CA" : "Mail Statement to Party",
                onPressed: () {
                  PdfRouterService.emailDocument(
                    context: context,
                    doc: rawLedgerData,
                    party: selectedParty!,
                    ph: ph,
                    type: "LEDGER",
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.amberAccent),
              tooltip: "Download PDF Statement",
              onPressed: () => _generateStatementPdf(ph),
            ),
            IconButton(
              icon: const Icon(Icons.people_alt_rounded),
              tooltip: "Switch Party",
              onPressed: () => setState(() => selectedParty = null),
            ),
          ]
        ],
      ),
      body: Column(
        children: [
          _buildFilterPanel(ph),
          if (selectedParty != null) _buildSummaryKpiStrip(openingBal, totalDr, totalCr, closingBal, isCashOrBank),
          if (selectedParty != null) _buildFilterTypeChips(),
          Expanded(
            child: selectedParty == null
                ? _buildPartySelector(ph)
                : _buildLedgerTable(ledgerData, isCashOrBank),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(PharoahManager ph) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    color: const Color(0xFF1E293B),
    child: Row(
      children: [
        Expanded(child: _dateBox("FROM", fromDate, (d) => setState(() => fromDate = d), ph.currentFY)),
        const SizedBox(width: 10),
        Expanded(child: _dateBox("TO", toDate, (d) => setState(() => toDate = d), ph.currentFY)),
      ],
    ),
  );

  Widget _buildSummaryKpiStrip(double opening, double debits, double credits, double closing, bool isCashOrBank) {
    bool isDr = closing >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _kpiItem("OPENING", "₹${opening.abs().toStringAsFixed(0)}", opening >= 0 ? Colors.green.shade700 : Colors.red.shade700, opening >= 0 ? "Dr" : "Cr"),
          _kpiItem("DEBITS (+)", "₹${debits.toStringAsFixed(0)}", Colors.indigo.shade800, "In/Dr"),
          _kpiItem("CREDITS (-)", "₹${credits.toStringAsFixed(0)}", Colors.deepOrange.shade800, "Out/Cr"),
          _kpiItem(
            isCashOrBank ? "CLOSING BAL" : "NET OUTSTANDING",
            "₹${closing.abs().toStringAsFixed(0)}",
            isDr ? Colors.teal.shade800 : Colors.red.shade800,
            isCashOrBank ? (isDr ? "In Hand" : "Overdrawn") : (isDr ? "Receivable Dr" : "Payable Cr"),
          ),
        ],
      ),
    );
  }

  Widget _kpiItem(String title, String val, Color c, String sub) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: c)),
        Text(sub, style: TextStyle(fontSize: 8, color: c, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildFilterTypeChips() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _filterTag("ALL ENTRIES", filterType == "ALL", () => setState(() => filterType = "ALL")),
          const SizedBox(width: 8),
          _filterTag("INVOICES & RETURNS", filterType == "BILLS", () => setState(() => filterType = "BILLS")),
          const SizedBox(width: 8),
          _filterTag("RECEIPTS & SETTLEMENTS", filterType == "SETTLEMENTS", () => setState(() => filterType = "SETTLEMENTS")),
        ],
      ),
    );
  }

  Widget _filterTag(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? const Color(0xFF1E293B) : Colors.black12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.blueGrey,
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildPartySelector(PharoahManager ph) {
    final list = ph.parties.where((p) =>
        p.name.toLowerCase().contains(partyQuery.toLowerCase()) ||
        p.phone.contains(partyQuery) ||
        p.group.toLowerCase().contains(partyQuery.toLowerCase())).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: "Search party by name, phone or group...",
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => partyQuery = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (c, i) {
              final p = list[i];
              final isCash = p.name.trim().toUpperCase() == "CASH" || p.group.trim().toLowerCase().contains("cash");
              final isBank = p.group.trim().toLowerCase().contains("bank");
              final bal = ph.calculatePartyBalance(p);
              final isDr = bal >= 0;

              return Card(
                elevation: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  onTap: () => setState(() => selectedParty = p),
                  leading: CircleAvatar(
                    backgroundColor: isCash
                        ? Colors.teal.shade50
                        : (isBank ? Colors.indigo.shade50 : (isDr ? Colors.green.shade50 : Colors.red.shade50)),
                    child: Icon(
                      isCash ? Icons.account_balance_wallet_rounded : (isBank ? Icons.account_balance_rounded : Icons.person),
                      color: isCash ? Colors.teal.shade800 : (isBank ? Colors.indigo.shade800 : (isDr ? Colors.green : Colors.red)),
                    ),
                  ),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(p.city.isEmpty ? p.group : "${p.group} • ${p.city}", style: const TextStyle(fontSize: 11)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "₹${bal.abs().toStringAsFixed(2)}",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: isDr ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                      Text(
                        isCash ? "IN HAND" : (isBank ? "BANK BAL" : (isDr ? "RECEIVABLE" : "PAYABLE")),
                        style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: isDr ? Colors.green : Colors.red),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLedgerTable(List<Map<String, dynamic>> data, bool isCashOrBank) {
    if (data.isEmpty) {
      return const Center(child: Text("No transactions recorded for selected period.", style: TextStyle(color: Colors.grey)));
    }

    return ListView.separated(
      itemCount: data.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.black12),
      itemBuilder: (c, i) {
        final row = data[i];
        final isOp = row['type'] == 'OPENING';
        final dt = row['date'] as DateTime;
        final ref = (row['ref'] ?? '').toString();
        final type = (row['type'] ?? '').toString();
        final particular = (row['particulars'] ?? type).toString();
        final dr = ((row['dr'] as num?)?.toDouble()) ?? 0.0;
        final cr = ((row['cr'] as num?)?.toDouble()) ?? 0.0;
        final bal = ((row['balance'] ?? row['bal'] ?? 0.0) as num).toDouble();
        final isBalDr = bal >= 0;

        if (isOp) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: Colors.amber.withOpacity(0.12),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text("OPENING BALANCE B/F", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    "₹${bal.abs().toStringAsFixed(2)} ${isBalDr ? 'Dr' : 'Cr'}",
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: isBalDr ? Colors.green.shade800 : Colors.red.shade800),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          color: i % 2 == 1 ? Colors.white : const Color(0xFFF8FAFC),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Col 1: Date & Ref & Badge
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(DateFormat('dd/MM/yy').format(dt), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _getTypeColor(type).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            type,
                            style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: _getTypeColor(type)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      particular,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (ref.isNotEmpty && ref != particular)
                      Text("#$ref", style: const TextStyle(fontSize: 9.5, color: Colors.blueGrey)),
                  ],
                ),
              ),

              // Col 2: Debit / Inward
              Expanded(
                flex: 2,
                child: Text(
                  dr > 0 ? "₹${dr.toStringAsFixed(2)}" : "-",
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: dr > 0 ? Colors.green.shade700 : Colors.grey,
                  ),
                ),
              ),

              // Col 3: Credit / Outward
              Expanded(
                flex: 2,
                child: Text(
                  cr > 0 ? "₹${cr.toStringAsFixed(2)}" : "-",
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: cr > 0 ? Colors.deepOrange.shade700 : Colors.grey,
                  ),
                ),
              ),

              // Col 4: Running Balance
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "₹${bal.abs().toStringAsFixed(2)}",
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: isBalDr ? Colors.teal.shade900 : Colors.red.shade900,
                      ),
                    ),
                    Text(
                      isCashOrBank ? (isBalDr ? "In Hand" : "Deficit") : (isBalDr ? "Dr" : "Cr"),
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: isBalDr ? Colors.teal.shade700 : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getTypeColor(String type) {
    final t = type.toUpperCase();
    if (t.contains("SALE")) return Colors.blue.shade700;
    if (t.contains("PURCHASE")) return Colors.purple.shade700;
    if (t.contains("RECEIPT")) return Colors.green.shade700;
    if (t.contains("PAYMENT") || t.contains("EXPENSE")) return Colors.deepOrange.shade700;
    if (t.contains("CONTRA")) return Colors.teal.shade700;
    if (t.contains("CN") || t.contains("DN") || t.contains("SETTLE")) return Colors.amber.shade800;
    return Colors.grey.shade700;
  }

  Widget _dateBox(String l, DateTime d, Function(DateTime) onPick, String fy) => InkWell(
    onTap: () async {
      DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: fy, initialDate: d);
      if (p != null) onPick(p);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("$l: ${DateFormat('dd/MM/yy').format(d)}", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.white70),
        ],
      ),
    ),
  );
}
