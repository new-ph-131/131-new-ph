// FILE: lib/finance/cash_bank_book_view.dart
// Revision: #PH-REV-744 (APP-CASH-AND-BANK-REGISTER)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../logic/app_accounts_calculator.dart';
import '../pharoah_date_controller.dart';
import 'bank_transaction_model.dart';

class CashBankBookView extends StatefulWidget {
  final int initialTab; // 0: Cash, 1: Bank
  const CashBankBookView({super.key, this.initialTab = 0});

  @override
  State<CashBankBookView> createState() => _CashBankBookViewState();
}

class _CashBankBookViewState extends State<CashBankBookView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Bank? _selectedBank;
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  String _searchQuery = "";
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final ph = Provider.of<PharoahManager>(context, listen: false);
      if (ph.banks.isNotEmpty && _selectedBank == null) {
        _selectedBank = ph.banks.first;
      }
      _isInit = true;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text("Cash & Bank Books", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amberAccent,
          indicatorWeight: 3,
          labelColor: Colors.amberAccent,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.account_balance_wallet_rounded, size: 20), text: "CASH BOOK (रोकड़)"),
            Tab(icon: Icon(Icons.account_balance_rounded, size: 20), text: "BANK REGISTER (बैंक)"),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildFilterBar(ph),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCashBookTab(ph),
                _buildBankBookTab(ph),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(PharoahManager ph) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _dateButton("FROM", _fromDate, (d) => setState(() => _fromDate = d), ph.currentFY),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dateButton("TO", _toDate, (d) => setState(() => _toDate = d), ph.currentFY),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: "Search transactions by party, bill or voucher #...",
              hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.indigo),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => setState(() => _searchQuery = ""),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.black12)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ],
      ),
    );
  }

  Widget _dateButton(String label, DateTime date, Function(DateTime) onPick, String fy) {
    return InkWell(
      onTap: () async {
        DateTime? p = await PharoahDateController.pickDate(
          context: context,
          currentFY: fy,
          initialDate: date,
        );
        if (p != null) onPick(p);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("$label: ${DateFormat('dd/MM/yy').format(date)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.indigo),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 💵 TAB 1: CASH BOOK (CASH-IN-HAND REGISTER)
  // ===========================================================================
  Widget _buildCashBookTab(PharoahManager ph) {
    final rawCashStatement = AppAccountsCalculator.getCashBookStatement(
      fromDate: _fromDate,
      toDate: _toDate,
      sales: ph.sales,
      purchases: ph.purchases,
      vouchers: ph.vouchers,
      openingCash: 0.0,
    );

    final q = _searchQuery.trim().toLowerCase();
    final filtered = rawCashStatement.where((t) {
      if (t['type'] == 'OPENING') return true;
      if (q.isEmpty) return true;
      final part = (t['particulars'] ?? '').toString().toLowerCase();
      final ref = (t['ref'] ?? '').toString().toLowerCase();
      return part.contains(q) || ref.contains(q);
    }).toList();

    double totalIn = rawCashStatement.where((t) => t['type'] != 'OPENING').fold(0.0, (s, t) => s + (t['in'] as double));
    double totalOut = rawCashStatement.where((t) => t['type'] != 'OPENING').fold(0.0, (s, t) => s + (t['out'] as double));
    double openingBal = (rawCashStatement.isNotEmpty && rawCashStatement.first['type'] == 'OPENING')
        ? (rawCashStatement.first['balance'] as double)
        : 0.0;
    double closingBal = openingBal + totalIn - totalOut;

    return Column(
      children: [
        _buildKpiStrip(openingBal, totalIn, totalOut, closingBal, "CASH IN DRAWER"),
        _buildTableHeader("RECEIPT (IN +)", "PAYMENT (OUT -)"),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text("No cash transactions found for selected period.", style: TextStyle(color: Colors.grey, fontSize: 12)))
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.black12),
                  itemBuilder: (context, idx) {
                    final item = filtered[idx];
                    final isOp = item['type'] == 'OPENING';
                    final inAmt = (item['in'] as double?) ?? 0.0;
                    final outAmt = (item['out'] as double?) ?? 0.0;
                    final bal = (item['balance'] as double?) ?? 0.0;

                    if (isOp) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        color: Colors.amber.withOpacity(0.12),
                        child: Row(
                          children: [
                            const Expanded(flex: 5, child: Text("OPENING BALANCE B/F", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            Expanded(flex: 2, child: Text(inAmt > 0 ? "₹${inAmt.toStringAsFixed(2)}" : "-", textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.green))),
                            Expanded(flex: 2, child: Text(outAmt > 0 ? "₹${outAmt.toStringAsFixed(2)}" : "-", textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.red))),
                            Expanded(flex: 3, child: Text("₹${bal.toStringAsFixed(2)}", textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                          ],
                        ),
                      );
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      color: idx % 2 == 1 ? Colors.white : const Color(0xFFF8FAFC),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['particulars'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(DateFormat('dd/MM/yy').format(item['date'] as DateTime), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                      child: Text(item['type'].toString(), style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                                    ),
                                    if (item['ref'] != null && item['ref'].toString().isNotEmpty) ...[
                                      const SizedBox(width: 4),
                                      Text("#${item['ref']}", style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              inAmt > 0 ? "+₹${inAmt.toStringAsFixed(0)}" : "-",
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: inAmt > 0 ? Colors.green.shade700 : Colors.grey),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              outAmt > 0 ? "-₹${outAmt.toStringAsFixed(0)}" : "-",
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: outAmt > 0 ? Colors.red.shade700 : Colors.grey),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              "₹${bal.toStringAsFixed(0)}",
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: bal >= 0 ? Colors.indigo.shade900 : Colors.red.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 🏦 TAB 2: BANK BOOK / PASSBOOK REGISTER
  // ===========================================================================
  Widget _buildBankBookTab(PharoahManager ph) {
    if (ph.banks.isEmpty) {
      return const Center(child: Text("No bank accounts registered yet.", style: TextStyle(color: Colors.grey)));
    }

    final selectedBank = _selectedBank ?? ph.banks.first;

    final rawBankTxns = AppAccountsCalculator.getBankBookStatement(
      bankName: selectedBank.name,
      fromDate: _fromDate,
      toDate: _toDate,
      sales: ph.sales,
      purchases: ph.purchases,
      vouchers: ph.vouchers,
    );

    final q = _searchQuery.trim().toLowerCase();
    final filtered = rawBankTxns.where((t) {
      if (q.isEmpty) return true;
      return t.particulars.toLowerCase().contains(q) || t.reference.toLowerCase().contains(q);
    }).toList();

    double totalIn = rawBankTxns.fold(0.0, (s, t) => s + t.amountIn);
    double totalOut = rawBankTxns.fold(0.0, (s, t) => s + t.amountOut);
    double openingBal = selectedBank.openingBalance;
    double closingBal = openingBal + totalIn - totalOut;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: Colors.indigo.withOpacity(0.06),
          child: Row(
            children: [
              const Icon(Icons.account_balance, color: Colors.indigo, size: 18),
              const SizedBox(width: 8),
              const Text("Bank Account:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Bank>(
                    value: _selectedBank,
                    isDense: true,
                    style: const TextStyle(color: Colors.indigo, fontSize: 12, fontWeight: FontWeight.bold),
                    items: ph.banks.map((b) => DropdownMenuItem(value: b, child: Text("${b.name} (${b.accountNo.isNotEmpty ? b.accountNo : 'Default'})"))).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedBank = v);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildKpiStrip(openingBal, totalIn, totalOut, closingBal, "BANK BALANCE"),
        _buildTableHeader("DEPOSIT (IN +)", "WITHDRAW (OUT -)"),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text("No transactions recorded for this bank in selected period.", style: TextStyle(color: Colors.grey, fontSize: 12)))
              : ListView.separated(
                  itemCount: filtered.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.black12),
                  itemBuilder: (context, idx) {
                    if (idx == 0) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        color: Colors.indigo.withOpacity(0.08),
                        child: Row(
                          children: [
                            const Expanded(flex: 5, child: Text("OPENING BALANCE B/F", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            Expanded(flex: 2, child: Text(openingBal >= 0 ? "₹${openingBal.toStringAsFixed(0)}" : "-", textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.green))),
                            Expanded(flex: 2, child: Text(openingBal < 0 ? "₹${openingBal.abs().toStringAsFixed(0)}" : "-", textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.red))),
                            Expanded(flex: 3, child: Text("₹${openingBal.toStringAsFixed(0)}", textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                          ],
                        ),
                      );
                    }

                    final t = filtered[idx - 1];
                    // Compute running balance up to this transaction
                    double currentBal = openingBal;
                    for (int i = 0; i < idx; i++) {
                      currentBal += (filtered[i].amountIn - filtered[i].amountOut);
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      color: idx % 2 == 1 ? Colors.white : const Color(0xFFF8FAFC),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.particulars, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(DateFormat('dd/MM/yy').format(t.date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                      child: Text(t.type, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                                    ),
                                    if (t.reference.isNotEmpty) ...[
                                      const SizedBox(width: 4),
                                      Text(t.reference, style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              t.amountIn > 0 ? "+₹${t.amountIn.toStringAsFixed(0)}" : "-",
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: t.amountIn > 0 ? Colors.green.shade700 : Colors.grey),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              t.amountOut > 0 ? "-₹${t.amountOut.toStringAsFixed(0)}" : "-",
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: t.amountOut > 0 ? Colors.red.shade700 : Colors.grey),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              "₹${currentBal.toStringAsFixed(0)}",
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: currentBal >= 0 ? Colors.indigo.shade900 : Colors.red.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- REUSABLE SUMMARY STRIP & TABLE HEADER ---
  Widget _buildKpiStrip(double op, double inAmt, double outAmt, double closeAmt, String closeLabel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _kpiItem("OPENING", "₹${op.toStringAsFixed(0)}", Colors.blueGrey),
          _kpiItem("IN (+)", "₹${inAmt.toStringAsFixed(0)}", Colors.green.shade700),
          _kpiItem("OUT (-)", "₹${outAmt.toStringAsFixed(0)}", Colors.red.shade700),
          _kpiItem(closeLabel, "₹${closeAmt.toStringAsFixed(0)}", Colors.indigo.shade900, isBold: true),
        ],
      ),
    );
  }

  Widget _kpiItem(String title, String val, Color color, {bool isBold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
        Text(val, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.w900 : FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildTableHeader(String inLabel, String outLabel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.blueGrey.shade900,
      child: Row(
        children: [
          const Expanded(flex: 5, child: Text("PARTICULARS / REF", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text(inLabel, textAlign: TextAlign.right, style: const TextStyle(color: Colors.greenAccent, fontSize: 9.5, fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text(outLabel, textAlign: TextAlign.right, style: const TextStyle(color: Colors.orangeAccent, fontSize: 9.5, fontWeight: FontWeight.bold))),
          const Expanded(flex: 3, child: Text("RUNNING BAL", textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}
