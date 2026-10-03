// FILE: lib/web_live_sync/sub_views/web_gst/web_gstr2_view.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../web_models.dart';
import '../../pharoah_web_manager.dart';

class WebGstr2View extends StatefulWidget {
  final PharoahWebManager webPh;
  final VoidCallback onBack;

  const WebGstr2View({super.key, required this.webPh, required this.onBack});

  @override
  State<WebGstr2View> createState() => _WebGstr2ViewState();
}

class _WebGstr2ViewState extends State<WebGstr2View> {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final now = DateTime.now();
      toDate = DateTime(now.year, now.month, now.day);
      fromDate = DateTime(now.year, now.month, 1);
      _isInit = true;
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  @override
  Widget build(BuildContext context) {
    final fDate = _dateOnly(fromDate);
    final tDate = _dateOnly(toDate);

    final purchases = widget.webPh.purchases.where((p) {
      final d = _dateOnly(p.date);
      return !d.isBefore(fDate) && !d.isAfter(tDate);
    }).toList();

    double totalTaxable = 0.0;
    double totalItc = 0.0;
    for (var p in purchases) {
      double t = p.items.fold(0.0, (s, i) => s + (i.purchaseRate * i.qty));
      totalTaxable += t;
      totalItc += (p.totalAmount - t);
    }

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _dateChip("FROM", fromDate, (d) => setState(() => fromDate = d)),
              const SizedBox(width: 8),
              _dateChip("TO", toDate, (d) => setState(() => toDate = d)),
              const Spacer(),
              Text("TAXABLE: ₹${totalTaxable.toStringAsFixed(2)}   |   ELIGIBLE ITC: ₹${totalItc.toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 16),

          if (purchases.isEmpty)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("No inward purchase bills found in date range.", style: TextStyle(color: Colors.white38))))
          else
            SingleChildScrollView(
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(85),
                  1: FixedColumnWidth(110),
                  2: FlexColumnWidth(3),
                  3: FixedColumnWidth(110),
                  4: FixedColumnWidth(110),
                  5: FixedColumnWidth(120),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFF0F172A), border: Border(bottom: BorderSide(color: Colors.white24))),
                    children: [_th("DATE"), _th("BILL NO"), _th("SUPPLIER NAME", isLeft: true), _th("TAXABLE ₹", isRight: true), _th("ITC TAX ₹", isRight: true), _th("TOTAL ₹", isRight: true)],
                  ),
                  for (var p in purchases) _buildPurchaseRow(p),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateChip(String label, DateTime dt, Function(DateTime) onPick) {
    return InkWell(
      onTap: () async {
        final p = await showDatePicker(context: context, initialDate: dt, firstDate: DateTime(2020), lastDate: DateTime(2035));
        if (p != null) onPick(p);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
        child: Text("$label: ${DateFormat('dd/MM/yy').format(dt)}", style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false, bool isRight = false}) => Padding(
    padding: const EdgeInsets.all(10),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
  );

  TableRow _buildPurchaseRow(Purchase p) {
    double tRow = p.items.fold(0.0, (s, i) => s + (i.purchaseRate * i.qty));
    double itc = p.totalAmount - tRow;
    return TableRow(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
      children: [
        _td(DateFormat('dd/MM/yy').format(p.date)),
        _td(p.billNo, isBold: true),
        _td(p.distributorName, isLeft: true),
        _td("₹${tRow.toStringAsFixed(2)}", isRight: true),
        _td("₹${itc.toStringAsFixed(2)}", isRight: true, color: Colors.greenAccent),
        _td("₹${p.totalAmount.toStringAsFixed(2)}", isRight: true, isBold: true),
      ],
    );
  }

}
