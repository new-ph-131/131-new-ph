import 'package:flutter/material.dart';
import '../models/medilente_bill_model.dart';

class MedilentePreviewTable extends StatelessWidget {
  final MedilenteBill bill;

  const MedilentePreviewTable({super.key, required this.bill});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bill.supplierName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "GSTIN: ${bill.supplierGstin} • Date: ${bill.invoiceDate}",
                    style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x2610B981),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: Text(
                  "BILL #${bill.invoiceNo}",
                  style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 750),
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(35),
                  1: FlexColumnWidth(3),
                  2: FixedColumnWidth(70),
                  3: FixedColumnWidth(90),
                  4: FixedColumnWidth(60),
                  5: FixedColumnWidth(65),
                  6: FixedColumnWidth(75),
                  7: FixedColumnWidth(80),
                  8: FixedColumnWidth(55),
                  9: FixedColumnWidth(90),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white12))),
                    children: [
                      _th("SN"), _th("PRODUCT NAME", isLeft: true), _th("PACK"), _th("BATCH"), _th("EXP"),
                      _th("QTY"), _th("RATE ₹"), _th("MRP ₹"), _th("IGST"), _th("AMOUNT ₹")
                    ],
                  ),
                  for (final it in bill.items)
                    TableRow(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                      children: [
                        _td("${it.srNo}"),
                        _td(it.productName, isLeft: true, isBold: true),
                        _td(it.pack),
                        _td(it.batch),
                        _td(it.exp),
                        _td("${it.qty.toInt()}", isBold: true, color: const Color(0xFF10B981)),
                        _td("₹${it.rate.toStringAsFixed(2)}"),
                        _td("₹${it.netMrp.toStringAsFixed(2)}"),
                        _td("${it.igstRate.toInt()}%"),
                        _td("₹${it.amount.toStringAsFixed(2)}", isBold: true, color: Colors.greenAccent),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Taxable: ₹${bill.taxableTotal.toStringAsFixed(2)}   |   IGST (5%): ₹${bill.igstTotal.toStringAsFixed(2)}   |   RoundOff: ₹${bill.roundOff.toStringAsFixed(2)}",
                    style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.bold)),
                Text(
                  "GRAND TOTAL: ₹${bill.grandTotal.toStringAsFixed(2)}",
                  style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
  );
}
