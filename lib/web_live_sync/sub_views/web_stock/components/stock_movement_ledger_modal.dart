// FILE: lib/web_live_sync/sub_views/web_stock/components/stock_movement_ledger_modal.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../pharoah_web_manager.dart';
import '../../web_models.dart';
import '../pdf/web_stock_analysis_pdf.dart';

class StockMovementLedgerModal extends StatefulWidget {
  final Medicine medicine;
  final String companyName;

  const StockMovementLedgerModal({
    super.key,
    required this.medicine,
    required this.companyName,
  });

  @override
  State<StockMovementLedgerModal> createState() => _StockMovementLedgerModalState();
}

class _StockMovementLedgerModalState extends State<StockMovementLedgerModal> {
  String _activeTab = "ALL"; // ALL, IN, OUT, RETURNS
  String _selectedBatch = "ALL_BATCHES";

  @override
  Widget build(BuildContext context) {
    final webPh = context.read<PharoahWebManager>();
    final cleanMedName = widget.medicine.name.trim().toUpperCase();
    final medId = widget.medicine.id;
    final sysId = widget.medicine.systemId;

    // 1. Gather all transaction streams
    List<Map<String, dynamic>> rawTxns = [];

    // Purchases (IN)
    for (var p in webPh.purchases) {
      for (var it in p.items) {
        if (it.medicineID == medId || it.medicineID == sysId || it.name.trim().toUpperCase() == cleanMedName) {
          rawTxns.add({
            'date': p.date,
            'type': 'PURCHASE',
            'typeLabel': 'Purchase Inward',
            'docNo': p.billNo.isNotEmpty ? p.billNo : p.internalNo,
            'party': p.distributorName.isNotEmpty ? p.distributorName : 'Supplier',
            'batch': it.batch.trim(),
            'exp': it.exp,
            'inQty': it.qty + it.freeQty,
            'outQty': 0.0,
            'rate': it.purchaseRate,
            'color': const Color(0xFF10B981),
            'icon': Icons.downloading_rounded,
          });
        }
      }
    }

    // Sales (OUT)
    for (var s in webPh.sales) {
      if (s.status.toUpperCase() == "CANCELLED") continue;
      for (var it in s.items) {
        if (it.medicineID == medId || it.medicineID == sysId || it.name.trim().toUpperCase() == cleanMedName) {
          rawTxns.add({
            'date': s.date,
            'type': 'SALE',
            'typeLabel': 'Sale Invoice',
            'docNo': s.billNo,
            'party': s.partyName.isNotEmpty ? s.partyName : 'Counter Customer',
            'batch': it.batch.trim(),
            'exp': it.exp,
            'inQty': 0.0,
            'outQty': it.qty + it.freeQty,
            'rate': it.rate,
            'color': const Color(0xFF3B82F6),
            'icon': Icons.shopping_cart_checkout_rounded,
          });
        }
      }
    }

    // Sale Challans (OUT)
    for (var c in webPh.saleChallans) {
      for (var it in c.items) {
        if (it.medicineID == medId || it.medicineID == sysId || it.name.trim().toUpperCase() == cleanMedName) {
          rawTxns.add({
            'date': c.date,
            'type': 'SALE_CHALLAN',
            'typeLabel': 'Sale Challan (Out)',
            'docNo': c.billNo,
            'party': c.partyName,
            'batch': it.batch.trim(),
            'exp': it.exp,
            'inQty': 0.0,
            'outQty': it.qty + it.freeQty,
            'rate': it.rate,
            'color': const Color(0xFF14B8A6),
            'icon': Icons.local_shipping_rounded,
          });
        }
      }
    }

    // Purchase Challans (IN)
    for (var c in webPh.purchaseChallans) {
      for (var it in c.items) {
        if (it.medicineID == medId || it.medicineID == sysId || it.name.trim().toUpperCase() == cleanMedName) {
          rawTxns.add({
            'date': c.date,
            'type': 'PUR_CHALLAN',
            'typeLabel': 'Purchase Challan (In)',
            'docNo': c.billNo.isNotEmpty ? c.billNo : c.internalNo,
            'party': c.distributorName.isNotEmpty ? c.distributorName : "Supplier",
            'batch': it.batch.trim(),
            'exp': it.exp,
            'inQty': it.qty + it.freeQty,
            'outQty': 0.0,
            'rate': it.purchaseRate,
            'color': const Color(0xFFF59E0B),
            'icon': Icons.inventory_2_rounded,
          });
        }
      }
    }

    // Sale Returns / Credit Notes (Customer Return = IN +)
    for (var r in webPh.saleReturns) {
      for (var it in r.items) {
        if (it.medicineID == medId || it.medicineID == sysId || it.name.trim().toUpperCase() == cleanMedName) {
          rawTxns.add({
            'date': r.date,
            'type': 'CREDIT_NOTE',
            'typeLabel': 'Credit Note (Return In +)',
            'docNo': r.billNo,
            'party': r.partyName,
            'batch': it.batch.trim(),
            'exp': it.exp,
            'inQty': it.qty,
            'outQty': 0.0,
            'rate': it.rate,
            'color': const Color(0xFFA855F7),
            'icon': Icons.assignment_return_rounded,
          });
        }
      }
    }

    // Purchase Returns / Debit Notes (Distributor Return = OUT -)
    for (var r in webPh.purchaseReturns) {
      for (var it in r.items) {
        if (it.medicineID == medId || it.medicineID == sysId || it.name.trim().toUpperCase() == cleanMedName) {
          rawTxns.add({
            'date': r.date,
            'type': 'DEBIT_NOTE',
            'typeLabel': 'Debit Note (Return Out -)',
            'docNo': r.billNo,
            'party': r.distributorName,
            'batch': it.batch.trim(),
            'exp': it.exp,
            'inQty': 0.0,
            'outQty': it.qty,
            'rate': it.purchaseRate,
            'color': const Color(0xFFEF4444),
            'icon': Icons.remove_shopping_cart_rounded,
          });
        }
      }
    }

    // Sort chronologically ascending to compute running balance
    rawTxns.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    // Extract all unique batch numbers
    final Set<String> allBatches = {};
    for (var t in rawTxns) {
      if ((t['batch'] as String).isNotEmpty) {
        allBatches.add(t['batch'] as String);
      }
    }
    // Also include batches from batchHistory
    final batchesInHistory = webPh.batchHistory[widget.medicine.identityKey] ?? [];
    for (var b in batchesInHistory) {
      if (b.batch.trim().isNotEmpty) {
        allBatches.add(b.batch.trim());
      }
    }

    // Compute Running Balance for all entries
    double running = 0.0;
    for (var t in rawTxns) {
      running += (t['inQty'] as double) - (t['outQty'] as double);
      t['balance'] = running;
    }

    // Filter by Active Tab
    var filteredTxns = rawTxns.where((t) {
      if (_activeTab == "IN") return (t['inQty'] as double) > 0;
      if (_activeTab == "OUT") return (t['outQty'] as double) > 0;
      if (_activeTab == "RETURNS") {
        return t['type'] == 'CREDIT_NOTE' || t['type'] == 'DEBIT_NOTE';
      }
      return true;
    }).toList();

    // Filter by Batch if selected
    if (_selectedBatch != "ALL_BATCHES") {
      filteredTxns = filteredTxns.where((t) => t['batch'] == _selectedBatch).toList();
    }

    // Display newest transactions first
    final displayList = filteredTxns.reversed.toList();

    double totalIn = filteredTxns.fold(0.0, (s, t) => s + (t['inQty'] as double));
    double totalOut = filteredTxns.fold(0.0, (s, t) => s + (t['outQty'] as double));

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.white12),
      ),
      child: Container(
        width: 1100,
        height: 720,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🏆 HEADER WITH AUDIT METRICS
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF60A5FA).withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.menu_book_rounded, color: Color(0xFF60A5FA), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.medicine.name,
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
                              widget.medicine.packing,
                              style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.companyName,
                              style: const TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Code: ${widget.medicine.systemId}  •  Current Stock: ${widget.medicine.stock.toInt()} Units  •  Pur Rate: ₹${widget.medicine.purRate.toStringAsFixed(2)}  •  MRP: ₹${widget.medicine.mrp.toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // PRINT STATEMENT BUTTON
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: const Text("PRINT LEDGER", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    final bytes = await WebStockAnalysisPdf.generateItemMovementLedgerPdf(
                      medicine: widget.medicine,
                      companyName: widget.companyName,
                      movements: rawTxns,
                      webPh: webPh,
                    );
                    await Printing.layoutPdf(
                      onLayout: (_) async => bytes,
                      name: "Ledger_${widget.medicine.name.replaceAll(' ', '_')}",
                      format: PdfPageFormat.a4,
                    );
                  },
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                  tooltip: "Close",
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 📊 SUMMARY KPI BANNER
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  _metricTile("TOTAL INWARD (+)", "${totalIn.toInt()} Units", Icons.arrow_downward_rounded, Colors.greenAccent),
                  _divider(),
                  _metricTile("TOTAL OUTWARD (-)", "${totalOut.toInt()} Units", Icons.arrow_upward_rounded, Colors.orangeAccent),
                  _divider(),
                  _metricTile("NET BALANCE", "${(totalIn - totalOut).toInt()} Units", Icons.account_balance_wallet_rounded, const Color(0xFF38BDF8)),
                  _divider(),
                  _metricTile("ALL TRANSACTIONS", "${rawTxns.length} Records", Icons.receipt_long_rounded, Colors.white70),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 🔍 FILTER CONTROLS & BATCH PICKER
            Row(
              children: [
                _tabFilterButton("ALL TRANSACTIONS", "ALL"),
                const SizedBox(width: 6),
                _tabFilterButton("PURCHASES (IN +)", "IN"),
                const SizedBox(width: 6),
                _tabFilterButton("SALES (OUT -)", "OUT"),
                const SizedBox(width: 6),
                _tabFilterButton("RETURNS & REVERSALS", "RETURNS"),
                const Spacer(),

                // BATCH FILTER DROPDOWN
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedBatch,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      icon: const Icon(Icons.filter_list_rounded, color: Color(0xFFA78BFA), size: 16),
                      items: [
                        const DropdownMenuItem(value: "ALL_BATCHES", child: Text("All Batches")),
                        ...allBatches.map((b) => DropdownMenuItem(value: b, child: Text("Batch: $b"))),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedBatch = val);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 📜 PASSBOOK CHRONOLOGY TABLE
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: displayList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.history_toggle_off_rounded, size: 42, color: Colors.white24),
                            const SizedBox(height: 10),
                            Text(
                              "No movement entries match the current filter.",
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        child: Table(
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          columnWidths: const {
                            0: FlexColumnWidth(1.2), // Date
                            1: FlexColumnWidth(1.8), // Type
                            2: FlexColumnWidth(1.5), // Doc No
                            3: FlexColumnWidth(2.2), // Party
                            4: FlexColumnWidth(1.3), // Batch
                            5: FlexColumnWidth(1.1), // In Qty
                            6: FlexColumnWidth(1.1), // Out Qty
                            7: FlexColumnWidth(1.2), // Rate
                            8: FlexColumnWidth(1.3), // Balance
                          },
                          children: [
                            TableRow(
                              decoration: const BoxDecoration(
                                color: Color(0xFF0F172A),
                                border: Border(bottom: BorderSide(color: Colors.white12)),
                              ),
                              children: [
                                _th("DATE"),
                                _th("TRANSACTION TYPE", isLeft: true),
                                _th("DOC / INVOICE #"),
                                _th("PARTY / CUSTOMER", isLeft: true),
                                _th("BATCH"),
                                _th("IN (+)", isRight: true),
                                _th("OUT (-)", isRight: true),
                                _th("RATE", isRight: true),
                                _th("RUNNING BAL", isRight: true),
                              ],
                            ),
                            for (final t in displayList)
                              TableRow(
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.white10)),
                                ),
                                children: [
                                  _td(DateFormat('dd/MM/yyyy').format(t['date'] as DateTime)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                    child: Row(
                                      children: [
                                        Icon(t['icon'] as IconData, size: 14, color: t['color'] as Color),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            t['typeLabel'].toString(),
                                            style: TextStyle(color: t['color'] as Color, fontSize: 10.5, fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _td(t['docNo'].toString(), isBold: true, color: const Color(0xFF38BDF8)),
                                  _td(t['party'].toString(), isLeft: true),
                                  _td(t['batch'].toString()),
                                  _td(
                                    (t['inQty'] as double) > 0 ? "+${(t['inQty'] as double).toInt()}" : "-",
                                    isRight: true,
                                    isBold: (t['inQty'] as double) > 0,
                                    color: Colors.greenAccent,
                                  ),
                                  _td(
                                    (t['outQty'] as double) > 0 ? "-${(t['outQty'] as double).toInt()}" : "-",
                                    isRight: true,
                                    isBold: (t['outQty'] as double) > 0,
                                    color: Colors.orangeAccent,
                                  ),
                                  _td("₹${(t['rate'] as double).toStringAsFixed(2)}", isRight: true),
                                  _td(
                                    "${(t['balance'] as double).toInt()} Qty",
                                    isRight: true,
                                    isBold: true,
                                    color: (t['balance'] as double) > 0 ? const Color(0xFF38BDF8) : Colors.redAccent,
                                  ),
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
    );
  }

  Widget _metricTile(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8.5, fontWeight: FontWeight.bold)),
              Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        height: 24,
        width: 1,
        color: Colors.white10,
        margin: const EdgeInsets.symmetric(horizontal: 10),
      );

  Widget _tabFilterButton(String title, String tabKey) {
    final isSelected = _activeTab == tabKey;
    return InkWell(
      onTap: () => setState(() => _activeTab = tabKey),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B82F6) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? const Color(0xFF60A5FA) : Colors.white10),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false, bool isRight = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Text(
          t,
          textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center),
          style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold),
        ),
      );

  Widget _td(String t, {bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        child: Text(
          t,
          textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center),
          style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
          overflow: TextOverflow.ellipsis,
        ),
      );
}
