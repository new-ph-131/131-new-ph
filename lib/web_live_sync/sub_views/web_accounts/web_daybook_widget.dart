// FILE: lib/web_live_sync/sub_views/web_accounts/web_daybook_widget.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../pharoah_web_manager.dart';
import '../../web_app_date_logic.dart';
import 'web_accounts_excel_service.dart';

class WebDaybookWidget extends StatefulWidget {
  final PharoahWebManager webPh;

  const WebDaybookWidget({super.key, required this.webPh});

  @override
  State<WebDaybookWidget> createState() => _WebDaybookWidgetState();
}

class _WebDaybookWidgetState extends State<WebDaybookWidget> {
  DateTime selectedDate = DateTime.now();
  String filterType = "ALL"; // ALL, INFLOW, OUTFLOW

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> allEntries = [];

    // 1. Sales
    for (var s in widget.webPh.sales.where((s) => _isSameDay(s.date, selectedDate) && s.status == "Active")) {
      allEntries.add({
        'time': s.date,
        'type': 'SALE',
        'party': s.partyName,
        'ref': 'Bill #${s.billNo}',
        'mode': s.paymentMode,
        'amount': s.totalAmount,
        'isIn': true,
      });
    }

    // 2. Purchases
    for (var p in widget.webPh.purchases.where((p) => _isSameDay(p.date, selectedDate))) {
      allEntries.add({
        'time': p.date,
        'type': 'PURCHASE',
        'party': p.distributorName,
        'ref': 'Inward #${p.internalNo}',
        'mode': p.paymentMode,
        'amount': p.totalAmount,
        'isIn': false,
      });
    }

    // 3. Vouchers
    for (var v in widget.webPh.vouchers.where((v) => _isSameDay(v.date, selectedDate) && v.status == "Active")) {
      bool isRec = v.type.toUpperCase() == "RECEIPT";
      allEntries.add({
        'time': v.date,
        'type': v.type.toUpperCase(),
        'party': v.partyName,
        'ref': 'Voucher #${v.voucherNo}',
        'mode': v.paymentMode,
        'amount': v.amount,
        'isIn': isRec,
      });
    }

    allEntries.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));

    final filtered = allEntries.where((e) {
      if (filterType == "INFLOW") return e['isIn'] == true;
      if (filterType == "OUTFLOW") return e['isIn'] == false;
      return true;
    }).toList();

    double totalIn = allEntries.where((e) => e['isIn'] == true).fold(0.0, (s, e) => s + (e['amount'] as double));
    double totalOut = allEntries.where((e) => e['isIn'] == false).fold(0.0, (s, e) => s + (e['amount'] as double));
    double netDay = totalIn - totalOut;

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
          // Day Summary Header
          Row(
            children: [
              InkWell(
                onTap: () async {
                  final p = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: WebAppDateLogic.getFYStart(widget.webPh.financialYear),
                    lastDate: WebAppDateLogic.getFYEnd(widget.webPh.financialYear),
                  );
                  if (p != null) setState(() => selectedDate = p);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF38BDF8)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_note_rounded, color: Color(0xFF38BDF8), size: 16),
                      const SizedBox(width: 8),
                      Text(DateFormat('EEEE, dd MMMM yyyy').format(selectedDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _filterTag("ALL FLOW", filterType == "ALL", () => setState(() => filterType = "ALL")),
              const SizedBox(width: 6),
              _filterTag("INFLOW ONLY (+)", filterType == "INFLOW", () => setState(() => filterType = "INFLOW"), color: const Color(0xFF10B981)),
              const SizedBox(width: 6),
              _filterTag("OUTFLOW ONLY (-)", filterType == "OUTFLOW", () => setState(() => filterType = "OUTFLOW"), color: const Color(0xFFDC2626)),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: filtered.isEmpty
                    ? null
                    : () => WebAccountsExcelService.exportDaybookCsv(filtered, selectedDate, widget.webPh.companyName),
                icon: const Icon(Icons.file_download_rounded, size: 15),
                label: const Text("EXPORT CSV", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Tally Strip
          Row(
            children: [
              Expanded(child: _statBox("DAY INFLOW (+)", "₹${totalIn.toStringAsFixed(2)}", Colors.greenAccent, const Color(0xFF064E3B))),
              const SizedBox(width: 10),
              Expanded(child: _statBox("DAY OUTFLOW (-)", "₹${totalOut.toStringAsFixed(2)}", const Color(0xFFF87171), const Color(0xFF450A0A))),
              const SizedBox(width: 10),
              Expanded(child: _statBox("NET DAILY FLOW", "₹${netDay.toStringAsFixed(2)}", netDay >= 0 ? Colors.greenAccent : const Color(0xFFF87171), const Color(0xFF1E1B4B))),
            ],
          ),
          const Divider(color: Colors.white10, height: 22),

          // Stream List
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              child: Text("No transactions recorded for ${DateFormat('dd/MM/yyyy').format(selectedDate)}.", style: const TextStyle(color: Colors.white38, fontSize: 12)),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final e = filtered[i];
                bool isIn = e['isIn'] as bool;
                double amt = e['amount'] as double;

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isIn ? const Color(0x3310B981) : const Color(0x33DC2626),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
                        color: isIn ? Colors.greenAccent : const Color(0xFFF87171),
                        size: 16,
                      ),
                    ),
                    title: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                          child: Text(e['type'], style: const TextStyle(color: Colors.white70, fontSize: 8.5, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Text(e['party'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                        const Spacer(),
                        Text(
                          "${isIn ? '+' : '-'} ₹${amt.toStringAsFixed(2)}",
                          style: TextStyle(
                            color: isIn ? Colors.greenAccent : const Color(0xFFF87171),
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text("${e['ref']} • Mode: ${e['mode'] ?? 'N/A'}", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String val, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg.withAlpha(80), borderRadius: BorderRadius.circular(10), border: Border.all(color: fg.withAlpha(80))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _filterTag(String label, bool isSelected, VoidCallback onTap, {Color? color}) {
    Color activeC = color ?? const Color(0xFF2563EB);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeC : Colors.black26,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? activeC : Colors.white12),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontSize: 9.5, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
