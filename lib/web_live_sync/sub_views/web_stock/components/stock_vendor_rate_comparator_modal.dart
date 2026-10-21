// FILE: lib/web_live_sync/sub_views/web_stock/components/stock_vendor_rate_comparator_modal.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../pharoah_web_manager.dart';
import '../../web_models.dart';

class StockVendorRateComparatorModal extends StatelessWidget {
  final Medicine medicine;
  final String companyName;

  const StockVendorRateComparatorModal({
    super.key,
    required this.medicine,
    required this.companyName,
  });

  @override
  Widget build(BuildContext context) {
    final webPh = context.read<PharoahWebManager>();
    final cleanMedName = medicine.name.trim().toUpperCase();

    // 1. Gather all purchases matching this medicine
    final List<Map<String, dynamic>> inwardRecords = [];
    for (var pur in webPh.purchases) {
      for (var it in pur.items) {
        bool matches = it.medicineID == medicine.id ||
            it.medicineID == medicine.systemId ||
            (it.name.trim().toUpperCase() == cleanMedName &&
                it.packing.trim().toUpperCase() == medicine.packing.trim().toUpperCase());

        if (matches) {
          double effRate = it.purchaseRate;
          if (it.discountPer > 0) {
            effRate = it.purchaseRate * (1 - (it.discountPer / 100));
          } else if (it.discountRupees > 0 && it.qty > 0) {
            effRate = it.purchaseRate - (it.discountRupees / it.qty);
          }
          inwardRecords.add({
            'purchase': pur,
            'item': it,
            'vendor': pur.distributorName.trim().isNotEmpty ? pur.distributorName.trim() : "Direct Supplier",
            'vendorId': pur.partyId,
            'date': pur.date,
            'billNo': pur.billNo.isNotEmpty ? pur.billNo : pur.internalNo,
            'batch': it.batch,
            'exp': it.exp,
            'qty': it.qty,
            'freeQty': it.freeQty,
            'rawRate': it.purchaseRate,
            'discPer': it.discountPer,
            'effRate': effRate,
            'mrp': it.mrp > 0 ? it.mrp : medicine.mrp,
          });
        }
      }
    }

    // Sort inward records newest first
    inwardRecords.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

    // 2. Group by Vendor
    final Map<String, List<Map<String, dynamic>>> vendorMap = {};
    for (var r in inwardRecords) {
      final vName = r['vendor'] as String;
      vendorMap.putIfAbsent(vName, () => []).add(r);
    }

    // 3. Compute Cross-Vendor Metrics
    double overallMinRate = double.infinity;
    double overallMaxRate = 0.0;
    String cheapestVendor = "";
    String costliestVendor = "";

    for (var entry in vendorMap.entries) {
      for (var r in entry.value) {
        double rate = r['effRate'] as double;
        if (rate > 0 && rate < overallMinRate) {
          overallMinRate = rate;
          cheapestVendor = entry.key;
        }
        if (rate > overallMaxRate) {
          overallMaxRate = rate;
          costliestVendor = entry.key;
        }
      }
    }
    if (overallMinRate == double.infinity) overallMinRate = 0.0;

    double rateGap = overallMaxRate - overallMinRate;
    double rateGapPercent = overallMinRate > 0 ? ((rateGap / overallMinRate) * 100) : 0.0;

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.white12),
      ),
      child: Container(
        width: 1050,
        height: 680,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🏷️ HEADER BAR
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.compare_arrows_rounded, color: Color(0xFF34D399), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            medicine.name,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              medicine.packing,
                              style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Company: $companyName  •  MRP: ₹${medicine.mrp.toStringAsFixed(2)}  •  Live Stock: ${medicine.stock.toInt()} Units  •  Code: ${medicine.systemId}",
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                  tooltip: "Close",
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ⚡ RATE VARIANCE & SAVINGS INTELLIGENCE BANNER
            if (vendorMap.length > 1 && rateGap > 0.05) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF1E293B),
                      const Color(0xFF0F766E).withOpacity(0.3),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF14B8A6).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.trending_up_rounded, color: Color(0xFF2DD4BF), size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "CROSS-VENDOR PURCHASE VARIANCE DETECTED",
                            style: TextStyle(color: Color(0xFF2DD4BF), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 2),
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 12, color: Colors.white70),
                              children: [
                                const TextSpan(text: "Best Buy Rate: "),
                                TextSpan(
                                  text: "₹${overallMinRate.toStringAsFixed(2)} ",
                                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                                ),
                                TextSpan(text: "from $cheapestVendor vs Highest Rate: "),
                                TextSpan(
                                  text: "₹${overallMaxRate.toStringAsFixed(2)} ",
                                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                                ),
                                TextSpan(text: "from $costliestVendor."),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          const Text("RATE DIFFERENCE", style: TextStyle(color: Colors.white38, fontSize: 8.5, fontWeight: FontWeight.bold)),
                          Text(
                            "+₹${rateGap.toStringAsFixed(2)} (${rateGapPercent.toStringAsFixed(1)}%)",
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else if (inwardRecords.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.amberAccent, size: 20),
                    SizedBox(width: 10),
                    Text(
                      "No historical purchase inward records found for this product in current memory.",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 🏢 VENDOR CARDS & HISTORICAL RATE HIKE ENGINE
            Expanded(
              child: inwardRecords.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.white24),
                          const SizedBox(height: 12),
                          const Text("No purchase inward transactions available to compare.", style: TextStyle(color: Colors.white38, fontSize: 13)),
                        ],
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // LEFT PANEL: Vendor Summaries (40% width)
                        SizedBox(
                          width: 360,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text("SUPPLIERS / VENDORS", style: TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                                    child: Text("${vendorMap.length}", style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView(
                                  children: vendorMap.entries.map((entry) {
                                    final vName = entry.key;
                                    final recs = entry.value;
                                    final totalUnits = recs.fold(0.0, (sum, r) => sum + (r['qty'] as double) + (r['freeQty'] as double));

                                    // Sort vendor recs by date ascending to detect hike
                                    final dateAsc = List<Map<String, dynamic>>.from(recs);
                                    dateAsc.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

                                    double latestRate = recs.first['effRate'] as double;
                                    double firstRate = dateAsc.first['effRate'] as double;
                                    double priceChange = latestRate - firstRate;
                                    double priceChangePct = firstRate > 0 ? ((priceChange / firstRate) * 100) : 0.0;
                                    bool hasHike = priceChange > 0.05 && dateAsc.length > 1;
                                    bool hasDrop = priceChange < -0.05 && dateAsc.length > 1;

                                    bool isBest = vName == cheapestVendor;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isBest
                                              ? Colors.greenAccent.withOpacity(0.4)
                                              : (hasHike ? Colors.redAccent.withOpacity(0.3) : Colors.white10),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  vName,
                                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isBest)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text("LOWEST RATE", style: TextStyle(color: Colors.greenAccent, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text("LATEST RATE", style: TextStyle(color: Colors.white38, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                                  Text(
                                                    "₹${latestRate.toStringAsFixed(2)}",
                                                    style: TextStyle(
                                                      color: isBest ? Colors.greenAccent : Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  const Text("TOTAL INWARD", style: TextStyle(color: Colors.white38, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                                  Text("${totalUnits.toInt()} Units (${recs.length} bills)", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                                ],
                                              ),
                                            ],
                                          ),

                                          // 🔺 HISTORICAL RATE HIKE / DROP WARNING
                                          if (hasHike) ...[
                                            const SizedBox(height: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.arrow_upward_rounded, color: Colors.redAccent, size: 14),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      "Rate increased from ₹${firstRate.toStringAsFixed(2)} ➔ ₹${latestRate.toStringAsFixed(2)} (+${priceChangePct.toStringAsFixed(1)}%)",
                                                      style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ] else if (hasDrop) ...[
                                            const SizedBox(height: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.green.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.arrow_downward_rounded, color: Colors.greenAccent, size: 14),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      "Rate dropped from ₹${firstRate.toStringAsFixed(2)} ➔ ₹${latestRate.toStringAsFixed(2)} (${priceChangePct.toStringAsFixed(1)}%)",
                                                      style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),

                        // RIGHT PANEL: Detailed Purchase Inward Invoices Table (60% width)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text("INWARD INVOICE CHRONOLOGY", style: TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  Text("${inwardRecords.length} Inward Transactions", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: SingleChildScrollView(
                                    child: Table(
                                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                      columnWidths: const {
                                        0: FlexColumnWidth(1.2), // Date
                                        1: FlexColumnWidth(1.4), // Invoice No
                                        2: FlexColumnWidth(2.0), // Vendor
                                        3: FlexColumnWidth(1.3), // Batch / Exp
                                        4: FlexColumnWidth(1.0), // Qty + Free
                                        5: FlexColumnWidth(1.2), // Rate (Net)
                                        6: FlexColumnWidth(1.0), // Disc %
                                        7: FlexColumnWidth(1.1), // MRP
                                      },
                                      children: [
                                        TableRow(
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF0F172A),
                                            border: Border(bottom: BorderSide(color: Colors.white12)),
                                          ),
                                          children: [
                                            _th("DATE"),
                                            _th("INVOICE #"),
                                            _th("SUPPLIER", isLeft: true),
                                            _th("BATCH (EXP)"),
                                            _th("QTY", isRight: true),
                                            _th("NET RATE", isRight: true),
                                            _th("DISC%", isRight: true),
                                            _th("MRP", isRight: true),
                                          ],
                                        ),
                                        for (final r in inwardRecords)
                                          TableRow(
                                            decoration: const BoxDecoration(
                                              border: Border(bottom: BorderSide(color: Colors.white10)),
                                            ),
                                            children: [
                                              _td(DateFormat('dd/MM/yy').format(r['date'] as DateTime)),
                                              _td(r['billNo'].toString(), isBold: true, color: const Color(0xFF38BDF8)),
                                              _td(r['vendor'].toString(), isLeft: true),
                                              _td("${r['batch']} (${r['exp']})"),
                                              _td(
                                                (r['freeQty'] as double) > 0
                                                    ? "${(r['qty'] as double).toInt()}+${(r['freeQty'] as double).toInt()}"
                                                    : "${(r['qty'] as double).toInt()}",
                                                isRight: true,
                                                isBold: true,
                                              ),
                                              _td(
                                                "₹${(r['effRate'] as double).toStringAsFixed(2)}",
                                                isRight: true,
                                                isBold: true,
                                                color: (r['effRate'] as double) == overallMinRate ? Colors.greenAccent : Colors.white,
                                              ),
                                              _td("${(r['discPer'] as double).toStringAsFixed(1)}%", isRight: true),
                                              _td("₹${(r['mrp'] as double).toStringAsFixed(2)}", isRight: true),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false, bool isRight = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Text(
          t,
          textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center),
          style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold),
        ),
      );

  Widget _td(String t, {bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Text(
          t,
          textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center),
          style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
          overflow: TextOverflow.ellipsis,
        ),
      );
}
