// FILE: lib/web_live_sync/web_ledger_view.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'web_pdf_router_service.dart';

class WebLedgerView extends StatefulWidget {
  final VoidCallback onBack;

  const WebLedgerView({super.key, required this.onBack});

  @override
  State<WebLedgerView> createState() => _WebLedgerViewState();
}

class _WebLedgerViewState extends State<WebLedgerView> {
  Party? selectedParty;
  String searchQuery = "";
  String groupFilter = "ALL"; // ALL, DEBTORS, CREDITORS, DUE_ONLY

  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final webPh = Provider.of<PharoahWebManager>(context, listen: false);
      final now = DateTime.now();
      toDate = DateTime(now.year, now.month, now.day);
      DateTime thirtyDaysAgo = toDate.subtract(const Duration(days: 30));
      DateTime fyStart = WebAppDateLogic.getFYStart(webPh.financialYear);
      fromDate = thirtyDaysAgo.isBefore(fyStart) ? fyStart : thirtyDaysAgo;
      _isInit = true;
    }
  }

  void _copyReminderText(Party party, double balance) {
    String sign = balance >= 0 ? "Debit (देय/Receivable)" : "Credit (जमा/Payable)";
    String text = "प्रिय ${party.name},\n\nआपका Pharoah ERP में कुल बकाया खाता शेष ₹${balance.abs().toStringAsFixed(2)} $sign है। कृपया खाता विवरण जांच कर भुगतान सुनिश्चित करें।\n\nधन्यवाद!";
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("📋 Balance reminder copied for WhatsApp/SMS!"), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final activeShop = CompanyProfile.fromMap(webPh.companyProfile);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: selectedParty == null
          ? _buildPartyOverviewList(webPh)
          : _buildSinglePartyStatement(webPh, activeShop),
    );
  }

  // ===========================================================================
  // 👥 LEVEL 1: ALL PARTIES LEDGER OVERVIEW
  // ===========================================================================
  Widget _buildPartyOverviewList(PharoahWebManager webPh) {
    double totalMarketReceivable = 0.0;
    double totalMarketPayable = 0.0;

    for (var p in webPh.parties) {
      if (p.name == "CASH") continue;
      double bal = webPh.calculatePartyBalance(p);
      if (bal > 0) totalMarketReceivable += bal;
      if (bal < 0) totalMarketPayable += bal.abs();
    }

    final query = searchQuery.trim().toLowerCase();
    final filteredParties = webPh.parties.where((p) {
      if (p.name == "CASH") return false;
      double bal = webPh.calculatePartyBalance(p);

      bool matchesGroup = true;
      if (groupFilter == "DEBTORS") matchesGroup = p.group == "Sundry Debtors";
      if (groupFilter == "CREDITORS") matchesGroup = p.group == "Sundry Creditors";
      if (groupFilter == "DUE_ONLY") matchesGroup = bal != 0;

      bool matchesSearch = query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          p.city.toLowerCase().contains(query) ||
          p.gst.toLowerCase().contains(query) ||
          p.phone.toLowerCase().contains(query);

      return matchesGroup && matchesSearch;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text("BACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 15),
            const Icon(Icons.people_alt_rounded, color: Color(0xFF38BDF8), size: 24),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "KHAATA & PARTY LEDGER AUDIT",
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
                Text(
                  "Real-time receivable (Dr) & payable (Cr) account statements",
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
        const Divider(color: Colors.white10, height: 25),

        // KPI Summary Strip
        Row(
          children: [
            Expanded(
              child: _kpiBox(
                "TOTAL RECEIVABLE (MARKET DR)",
                "₹${totalMarketReceivable.toStringAsFixed(2)}",
                "Customer Outstanding Due",
                Colors.greenAccent,
                const Color(0xFF064E3B),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _kpiBox(
                "TOTAL PAYABLE (SUPPLIER CR)",
                "₹${totalMarketPayable.toStringAsFixed(2)}",
                "Distributor Inward Pending",
                const Color(0xFFF87171),
                const Color(0xFF450A0A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Search & Group Filter Bar
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              TextField(
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: "Search by Party Name, City, Phone or GSTIN...",
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 16),
                          onPressed: () => setState(() => searchQuery = ""),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                onChanged: (v) => setState(() => searchQuery = v),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip("ALL PARTIES", groupFilter == "ALL", () => setState(() => groupFilter = "ALL")),
                    const SizedBox(width: 8),
                    _filterChip("CUSTOMERS (DEBTORS)", groupFilter == "DEBTORS", () => setState(() => groupFilter = "DEBTORS")),
                    const SizedBox(width: 8),
                    _filterChip("SUPPLIERS (CREDITORS)", groupFilter == "CREDITORS", () => setState(() => groupFilter = "CREDITORS")),
                    const SizedBox(width: 8),
                    _filterChip("PENDING DUE ONLY", groupFilter == "DUE_ONLY", () => setState(() => groupFilter = "DUE_ONLY")),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Parties Data Table
        if (filteredParties.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: const Center(
              child: Text("No parties found matching selected filters.", style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final double availableWidth = constraints.maxWidth;
              final double tableWidth = availableWidth > 850 ? availableWidth : 850;

              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: availableWidth < 850 ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: tableWidth,
                    child: Table(
                      columnWidths: const {
                        0: FixedColumnWidth(110),
                        1: FlexColumnWidth(3.0),
                        2: FlexColumnWidth(1.8),
                        3: FlexColumnWidth(1.8),
                        4: FlexColumnWidth(2.0),
                        5: FixedColumnWidth(150),
                      },
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(
                            color: Color(0xFF0F172A),
                            border: Border(bottom: BorderSide(color: Colors.white24, width: 1)),
                          ),
                          children: [
                            _th("GROUP"),
                            _th("PARTY / FIRM NAME", isLeft: true),
                            _th("CITY"),
                            _th("PHONE"),
                            _th("NET BALANCE", isRight: true),
                            _th("ACTION"),
                          ],
                        ),
                        for (int i = 0; i < filteredParties.length; i++) ...[
                          _buildPartyRow(webPh, filteredParties[i], i),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  TableRow _buildPartyRow(PharoahWebManager webPh, Party p, int index) {
    double bal = webPh.calculatePartyBalance(p);
    bool isDr = bal >= 0;

    return TableRow(
      decoration: BoxDecoration(
        color: index % 2 == 1 ? const Color(0x0DFFFFFF) : Colors.transparent,
        border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      children: [
        _tdGroupBadge(p.group),
        _td(p.name, isLeft: true, isBold: true),
        _td(p.city.isEmpty ? '-' : p.city),
        _td(p.phone.isEmpty ? '-' : p.phone),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "₹${bal.abs().toStringAsFixed(2)}",
                  style: TextStyle(
                    color: bal == 0 ? Colors.white70 : (isDr ? Colors.greenAccent : const Color(0xFFF87171)),
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  bal == 0 ? "NIL" : (isDr ? "RECEIVABLE (Dr)" : "PAYABLE (Cr)"),
                  style: TextStyle(
                    color: isDr ? Colors.greenAccent : const Color(0xFFF87171),
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        Center(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () => setState(() => selectedParty = p),
            icon: const Icon(Icons.receipt_long_rounded, size: 14),
            label: const Text("STATEMENT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 📄 LEVEL 2: SINGLE PARTY DETAILED TIMELINE STATEMENT
  // ===========================================================================
  Widget _buildSinglePartyStatement(PharoahWebManager webPh, CompanyProfile activeShop) {
    final statementData = webPh.getPartyStatementData(
      partyId: selectedParty!.id,
      fromDate: fromDate,
      toDate: toDate,
    );

    double currentNetBal = webPh.calculatePartyBalance(selectedParty!);
    bool isDr = currentNetBal >= 0;

    double totalDebits = statementData.where((e) => e['type'] != 'OPENING').fold(0.0, (s, e) => s + ((e['dr'] as num?)?.toDouble() ?? 0.0));
    double totalCredits = statementData.where((e) => e['type'] != 'OPENING').fold(0.0, (s, e) => s + ((e['cr'] as num?)?.toDouble() ?? 0.0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: () => setState(() => selectedParty = null),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text("ALL LEDGERS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 15),
            const Icon(Icons.menu_book_rounded, color: Color(0xFF38BDF8), size: 22),
            const SizedBox(width: 10),
            Text(
              "STATEMENT: ${selectedParty!.name.toUpperCase()}",
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => WebPdfRouterService.printPartyLedger(
                shop: activeShop,
                party: selectedParty!,
                data: statementData,
                from: fromDate,
                to: toDate,
              ),
              icon: const Icon(Icons.print_rounded, size: 16),
              label: const Text("PRINT A4", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: const Color(0xFF38BDF8),
                side: const BorderSide(color: Color(0xFF38BDF8)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => WebPdfRouterService.downloadPartyLedger(
                shop: activeShop,
                party: selectedParty!,
                data: statementData,
                from: fromDate,
                to: toDate,
              ),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text("DOWNLOAD PDF", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _copyReminderText(selectedParty!, currentNetBal),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text("COPY REMINDER", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        const Divider(color: Colors.white10, height: 25),

        // Party Info Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Color(0x332563EB), shape: BoxShape.circle),
                child: const Icon(Icons.person_rounded, color: Color(0xFF38BDF8), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(selectedParty!.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(
                      "${selectedParty!.address.isNotEmpty ? selectedParty!.address : ''}${selectedParty!.city.isNotEmpty ? ', ${selectedParty!.city}' : ''} • GST: ${selectedParty!.gst.isNotEmpty ? selectedParty!.gst : 'N/A'} • DL: ${selectedParty!.dl.isNotEmpty ? selectedParty!.dl : 'N/A'}",
                      style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("CURRENT CLOSING BALANCE", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                  Text(
                    "₹${currentNetBal.abs().toStringAsFixed(2)} ${isDr ? 'Dr' : 'Cr'}",
                    style: TextStyle(
                      color: isDr ? Colors.greenAccent : const Color(0xFFF87171),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Date Picker Bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(child: _dateTile("FROM DATE", fromDate, (d) => setState(() => fromDate = d), webPh.financialYear)),
              const SizedBox(width: 12),
              Expanded(child: _dateTile("TO DATE", toDate, (d) => setState(() => toDate = d), webPh.financialYear)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Statement Table
        LayoutBuilder(
          builder: (context, constraints) {
            final double availableWidth = constraints.maxWidth;
            final double tableWidth = availableWidth > 850 ? availableWidth : 850;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: availableWidth < 850 ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      width: tableWidth,
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(90),
                          1: FlexColumnWidth(3.0),
                          2: FixedColumnWidth(90),
                          3: FixedColumnWidth(110),
                          4: FixedColumnWidth(110),
                          5: FixedColumnWidth(120),
                        },
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(
                              color: Color(0xFF0F172A),
                              border: Border(bottom: BorderSide(color: Colors.white24, width: 1)),
                            ),
                            children: [
                              _th("DATE"),
                              _th("PARTICULARS / REF NO", isLeft: true),
                              _th("TYPE"),
                              _th("DEBIT (Dr +)", isRight: true),
                              _th("CREDIT (Cr -)", isRight: true),
                              _th("BALANCE", isRight: true),
                            ],
                          ),
                          for (int i = 0; i < statementData.length; i++) ...[
                            _buildStatementRow(statementData[i], i),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Statement Summary Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF19243B), Color(0xFF0F172A)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("PERIOD INFLOW (Dr)", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                          Text("₹${totalDebits.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("PERIOD OUTFLOW (Cr)", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                          Text("₹${totalCredits.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text("NET PERIOD CLOSING", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                          Text(
                            "₹${(statementData.isNotEmpty ? (statementData.last['bal'] as double).abs() : 0.0).toStringAsFixed(2)} ${(statementData.isNotEmpty && (statementData.last['bal'] as double) >= 0) ? 'Dr' : 'Cr'}",
                            style: TextStyle(
                              color: (statementData.isNotEmpty && (statementData.last['bal'] as double) >= 0) ? Colors.greenAccent : const Color(0xFFF87171),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  TableRow _buildStatementRow(Map<String, dynamic> row, int index) {
    bool isOp = row['type'] == 'OPENING';
    DateTime dt = row['date'] as DateTime;
    double dr = (row['dr'] as num?)?.toDouble() ?? 0.0;
    double cr = (row['cr'] as num?)?.toDouble() ?? 0.0;
    double bal = (row['bal'] as num?)?.toDouble() ?? 0.0;
    bool isDr = bal >= 0;

    return TableRow(
      decoration: BoxDecoration(
        color: isOp ? const Color(0x1F38BDF8) : (index % 2 == 1 ? const Color(0x0DFFFFFF) : Colors.transparent),
        border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      children: [
        _td(DateFormat('dd/MM/yyyy').format(dt)),
        _td(
          isOp ? row['particulars'] : "${row['particulars'] ?? ''} (${row['ref'] ?? ''})",
          isLeft: true,
          isBold: isOp,
        ),
        _tdTypeBadge(row['type'].toString()),
        _td(dr > 0 ? "₹${dr.toStringAsFixed(2)}" : "-", isRight: true, color: dr > 0 ? Colors.greenAccent : Colors.white54),
        _td(cr > 0 ? "₹${cr.toStringAsFixed(2)}" : "-", isRight: true, color: cr > 0 ? const Color(0xFFF87171) : Colors.white54),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              "₹${bal.abs().toStringAsFixed(2)} ${isDr ? 'Dr' : 'Cr'}",
              style: TextStyle(
                color: isDr ? Colors.greenAccent : const Color(0xFFF87171),
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- UI HELPERS ---
  Widget _kpiBox(String title, String val, String sub, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.black26,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? const Color(0xFF60A5FA) : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false, bool isRight = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    child: Text(
      t,
      textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center),
      style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
    ),
  );

  Widget _td(String t, {bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    child: Text(
      t,
      textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center),
      style: TextStyle(color: color, fontSize: 11.5, fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
      overflow: TextOverflow.ellipsis,
    ),
  );

  Widget _tdGroupBadge(String group) {
    Color bg = const Color(0x332563EB);
    Color fg = const Color(0xFF38BDF8);

    if (group.contains("Creditors")) {
      bg = const Color(0x33F59E0B);
      fg = const Color(0xFFFBBF24);
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(
          group.contains("Debtors") ? "DEBTOR" : (group.contains("Creditors") ? "CREDITOR" : "OTHER"),
          style: TextStyle(color: fg, fontSize: 8, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _tdTypeBadge(String type) {
    Color bg = const Color(0x332563EB);
    Color fg = Colors.blueAccent;

    if (type == "RECEIPT") { bg = const Color(0x3310B981); fg = Colors.greenAccent; }
    if (type == "PAYMENT") { bg = const Color(0x33DC2626); fg = const Color(0xFFF87171); }
    if (type == "CN") { bg = const Color(0x33DC2626); fg = const Color(0xFFF87171); }
    if (type == "DN") { bg = const Color(0x33D97706); fg = const Color(0xFFFBBF24); }
    if (type == "OPENING") { bg = const Color(0x3338BDF8); fg = const Color(0xFF38BDF8); }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(type, style: TextStyle(color: fg, fontSize: 8, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _dateTile(String label, DateTime d, Function(DateTime) onPick, String fy) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: d,
          firstDate: WebAppDateLogic.getFYStart(fy),
          lastDate: WebAppDateLogic.getFYEnd(fy),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.black26, border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 8.5, color: Colors.white54, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(DateFormat('dd/MM/yyyy').format(d), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
              ],
            ),
            const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 16),
          ],
        ),
      ),
    );
  }
}
