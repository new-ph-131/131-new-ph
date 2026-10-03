// FILE: lib/web_live_sync/sub_views/web_accounts/web_bank_book_widget.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../web_app_date_logic.dart';

class WebBankBookWidget extends StatefulWidget {
  final PharoahWebManager webPh;

  const WebBankBookWidget({super.key, required this.webPh});

  @override
  State<WebBankBookWidget> createState() => _WebBankBookWidgetState();
}

class _WebBankBookWidgetState extends State<WebBankBookWidget> {
  Party? selectedBankAccount;
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final now = DateTime.now();
      toDate = DateTime(now.year, now.month, now.day);
      DateTime thirtyDaysAgo = toDate.subtract(const Duration(days: 30));
      DateTime fyStart = WebAppDateLogic.getFYStart(widget.webPh.financialYear);
      fromDate = thirtyDaysAgo.isBefore(fyStart) ? fyStart : thirtyDaysAgo;

      final bankAccounts = widget.webPh.parties.where((p) => p.group == "Bank Accounts").toList();
      if (bankAccounts.isNotEmpty) {
        selectedBankAccount = bankAccounts.first;
      }
      _isInit = true;
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  @override
  Widget build(BuildContext context) {
    final bankAccounts = widget.webPh.parties.where((p) => p.group == "Bank Accounts").toList();

    List<Map<String, dynamic>> statement = [];
    double openBal = selectedBankAccount?.opBal ?? 0.0;

    if (selectedBankAccount != null) {
      final fDateOnly = _dateOnly(fromDate);
      final tDateOnly = _dateOnly(toDate);
      final bName = selectedBankAccount!.name.trim().toUpperCase();

      for (var v in widget.webPh.vouchers.where((v) => v.status == "Active")) {
        if (v.depositedIn.trim().toUpperCase() != bName) continue;
        final vDateOnly = _dateOnly(v.date);

        bool isRec = v.type.toUpperCase() == "RECEIPT";
        double inAmt = isRec ? v.amount : 0.0;
        double outAmt = isRec ? 0.0 : v.amount;

        if (vDateOnly.isBefore(fDateOnly)) {
          openBal += (inAmt - outAmt);
        } else if (!vDateOnly.isAfter(tDateOnly)) {
          statement.add({
            'date': v.date,
            'particulars': "${v.type.toUpperCase()}: ${v.partyName}",
            'reference': v.chequeNo.isNotEmpty ? "${v.voucherNo} • Chq: ${v.chequeNo}" : v.voucherNo,
            'in': inAmt,
            'out': outAmt,
          });
        }
      }
      statement.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    }

    double currentRunning = openBal;
    for (var s in statement) {
      currentRunning += ((s['in'] as double) - (s['out'] as double));
      s['balance'] = currentRunning;
    }

    double totalIn = statement.fold(0.0, (sum, it) => sum + (it['in'] as double));
    double totalOut = statement.fold(0.0, (sum, it) => sum + (it['out'] as double));
    double closingBal = openBal + totalIn - totalOut;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Bank selector and date range
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Party>(
                      value: selectedBankAccount,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      items: bankAccounts.map((b) => DropdownMenuItem(value: b, child: Text(b.name))).toList(),
                      onChanged: (v) => setState(() => selectedBankAccount = v),
                      hint: const Text("Select Bank Account", style: TextStyle(color: Colors.white38)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _dateChip("FROM", fromDate, (d) => setState(() => fromDate = d)),
              const SizedBox(width: 6),
              _dateChip("TO", toDate, (d) => setState(() => toDate = d)),
            ],
          ),
          const SizedBox(height: 14),

          // Tally stats
          Row(
            children: [
              Expanded(child: _statBox("OPENING BALANCE", "₹${openBal.toStringAsFixed(2)}", Colors.white70, Colors.black26)),
              const SizedBox(width: 8),
              Expanded(child: _statBox("PERIOD INFLOW (+)", "₹${totalIn.toStringAsFixed(2)}", Colors.greenAccent, const Color(0xFF064E3B))),
              const SizedBox(width: 8),
              Expanded(child: _statBox("PERIOD OUTFLOW (-)", "₹${totalOut.toStringAsFixed(2)}", const Color(0xFFF87171), const Color(0xFF450A0A))),
              const SizedBox(width: 8),
              Expanded(child: _statBox("CLOSING BALANCE", "₹${closingBal.toStringAsFixed(2)}", closingBal >= 0 ? Colors.greenAccent : const Color(0xFFF87171), const Color(0xFF1E1B4B))),
            ],
          ),
          const Divider(color: Colors.white10, height: 22),

          if (selectedBankAccount == null)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: Text("Select a bank account above to view passbook.", style: TextStyle(color: Colors.white38))))
          else if (statement.isEmpty)
            Padding(padding: const EdgeInsets.all(30), child: Center(child: Text("No transactions recorded for ${selectedBankAccount!.name} in this period.", style: const TextStyle(color: Colors.white38))))
          else
            Table(
              columnWidths: const {
                0: FixedColumnWidth(85),
                1: FlexColumnWidth(3.0),
                2: FlexColumnWidth(2.0),
                3: FixedColumnWidth(100),
                4: FixedColumnWidth(100),
                5: FixedColumnWidth(110),
              },
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFF0F172A), border: Border(bottom: BorderSide(color: Colors.white24))),
                  children: [
                    _th("DATE"),
                    _th("PARTICULARS", isLeft: true),
                    _th("REFERENCE"),
                    _th("DEPOSITS (+)", isRight: true),
                    _th("WITHDRAWALS (-)", isRight: true),
                    _th("BALANCE", isRight: true),
                  ],
                ),
                for (var s in statement)
                  TableRow(
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                    children: [
                      _td(DateFormat('dd/MM/yy').format(s['date'] as DateTime)),
                      _td(s['particulars'].toString(), isLeft: true, isBold: true),
                      _td(s['reference'].toString()),
                      _td(s['in'] > 0 ? "₹${(s['in'] as double).toStringAsFixed(2)}" : "-", isRight: true, color: Colors.greenAccent),
                      _td(s['out'] > 0 ? "₹${(s['out'] as double).toStringAsFixed(2)}" : "-", isRight: true, color: const Color(0xFFF87171)),
                      _td("₹${(s['balance'] as double).toStringAsFixed(2)}", isRight: true, isBold: true),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String val, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: fg.withAlpha(60))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(val, style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _dateChip(String label, DateTime dt, Function(DateTime) onPick) {
    return InkWell(
      onTap: () async {
        final p = await showDatePicker(
          context: context,
          initialDate: dt,
          firstDate: WebAppDateLogic.getFYStart(widget.webPh.financialYear),
          lastDate: WebAppDateLogic.getFYEnd(widget.webPh.financialYear),
        );
        if (p != null) onPick(p);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
        child: Row(
          children: [
            Text("$label: ${DateFormat('dd/MM/yy').format(dt)}", style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF38BDF8)),
          ],
        ),
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false, bool isRight = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
  );
}
