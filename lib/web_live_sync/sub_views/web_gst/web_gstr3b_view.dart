// FILE: lib/web_live_sync/sub_views/web_gst/web_gstr3b_view.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../pharoah_web_manager.dart';

class WebGstr3bView extends StatefulWidget {
  final PharoahWebManager webPh;
  final VoidCallback onBack;

  const WebGstr3bView({super.key, required this.webPh, required this.onBack});

  @override
  State<WebGstr3bView> createState() => _WebGstr3bViewState();
}

class _WebGstr3bViewState extends State<WebGstr3bView> {
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

    final activeSales = widget.webPh.sales.where((s) {
      final d = _dateOnly(s.date);
      return s.status == "Active" && !d.isBefore(fDate) && !d.isAfter(tDate);
    }).toList();

    final activePurchases = widget.webPh.purchases.where((p) {
      final d = _dateOnly(p.date);
      return !d.isBefore(fDate) && !d.isAfter(tDate);
    }).toList();

    // 1. Outward Supplies Tax (Sales)
    double sTaxable = 0.0; double sCgst = 0.0; double sSgst = 0.0; double sIgst = 0.0;
    for (var s in activeSales) {
      for (var it in s.items) {
        double tax = it.cgst + it.sgst + it.igst;
        sTaxable += (it.total - tax);
        sCgst += it.cgst;
        sSgst += it.sgst;
        sIgst += it.igst;
      }
    }
    double totalOutputTax = sCgst + sSgst + sIgst;

    // 2. Inward Eligible ITC (Purchases)
    double pTaxable = 0.0; double pCgst = 0.0; double pSgst = 0.0; double pIgst = 0.0;
    for (var p in activePurchases) {
      for (var it in p.items) {
        double tRow = it.purchaseRate * it.qty;
        double tax = it.total - tRow;
        pTaxable += tRow;
        pCgst += (tax / 2);
        pSgst += (tax / 2);
      }
    }
    double totalItc = pCgst + pSgst + pIgst;

    // 3. Net Tax Liability / Refund
    double netPayable = totalOutputTax - totalItc;

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _dateChip("FROM", fromDate, (d) => setState(() => fromDate = d)),
              const SizedBox(width: 8),
              _dateChip("TO", toDate, (d) => setState(() => toDate = d)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0x332563EB), borderRadius: BorderRadius.circular(8)),
                child: Text("TAX PERIOD: ${DateFormat('MMMM yyyy').format(fromDate).toUpperCase()}", style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Table(
            border: TableBorder.all(color: Colors.white12, width: 1),
            columnWidths: const {
              0: FlexColumnWidth(4),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(2),
              4: FlexColumnWidth(2),
              5: FlexColumnWidth(2.5),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFF0F172A)),
                children: [_th("NATURE OF SUPPLIES", isLeft: true), _th("TAXABLE VALUE", isRight: true), _th("IGST", isRight: true), _th("CGST", isRight: true), _th("SGST", isRight: true), _th("TOTAL TAX", isRight: true)],
              ),
              TableRow(
                decoration: const BoxDecoration(color: Colors.black12),
                children: [
                  _td("3.1 (a) Outward Taxable Supplies (Sales)", isLeft: true, isBold: true),
                  _td("₹${sTaxable.toStringAsFixed(2)}", isRight: true),
                  _td("₹${sIgst.toStringAsFixed(2)}", isRight: true),
                  _td("₹${sCgst.toStringAsFixed(2)}", isRight: true),
                  _td("₹${sSgst.toStringAsFixed(2)}", isRight: true),
                  _td("₹${totalOutputTax.toStringAsFixed(2)}", isRight: true, isBold: true, color: Colors.orangeAccent),
                ],
              ),
              TableRow(
                decoration: const BoxDecoration(color: Colors.black12),
                children: [
                  _td("4. (A) Eligible ITC on Inward Supplies (Purchases)", isLeft: true, isBold: true),
                  _td("₹${pTaxable.toStringAsFixed(2)}", isRight: true),
                  _td("₹${pIgst.toStringAsFixed(2)}", isRight: true),
                  _td("₹${pCgst.toStringAsFixed(2)}", isRight: true),
                  _td("₹${pSgst.toStringAsFixed(2)}", isRight: true),
                  _td("₹${totalItc.toStringAsFixed(2)}", isRight: true, isBold: true, color: Colors.greenAccent),
                ],
              ),
              TableRow(
                decoration: BoxDecoration(color: netPayable > 0 ? const Color(0x33DC2626) : const Color(0x3310B981)),
                children: [
                  _td(netPayable > 0 ? "5. NET GST PAYABLE IN CASH / CHALLAN" : "5. NET ITC CREDIT CARRY FORWARD", isLeft: true, isBold: true, color: Colors.white),
                  _td("-", isRight: true),
                  _td("₹${(sIgst - pIgst).toStringAsFixed(2)}", isRight: true, isBold: true),
                  _td("₹${(sCgst - pCgst).toStringAsFixed(2)}", isRight: true, isBold: true),
                  _td("₹${(sSgst - pSgst).toStringAsFixed(2)}", isRight: true, isBold: true),
                  _td("₹${netPayable.abs().toStringAsFixed(2)}", isRight: true, isBold: true, color: netPayable > 0 ? Colors.redAccent : Colors.greenAccent),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("COMPUTATION SUMMARY", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                    Text(netPayable > 0 ? "You have a tax liability to pay via portal." : "No tax payment needed. Input credit surplus.", style: TextStyle(color: netPayable > 0 ? Colors.orangeAccent : Colors.greenAccent, fontSize: 12)),
                  ],
                ),
                Text(
                  netPayable > 0 ? "PAYABLE: ₹${netPayable.toStringAsFixed(2)}" : "SURPLUS ITC: ₹${netPayable.abs().toStringAsFixed(2)}",
                  style: TextStyle(color: netPayable > 0 ? Colors.redAccent : Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.w900),
                ),
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
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
  );
}
