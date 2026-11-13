// FILE: lib/inventory_intel/app_stock/app_stock_movement_sheet.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'app_stock_analytics_engine.dart';
import 'app_stock_pdf_and_export.dart';
import 'app_stock_theme.dart';

class AppStockMovementSheet extends StatefulWidget {
  final Medicine medicine;
  final String companyName;
  final String? initialBatch;

  const AppStockMovementSheet({
    super.key,
    required this.medicine,
    required this.companyName,
    this.initialBatch,
  });

  @override
  State<AppStockMovementSheet> createState() => _AppStockMovementSheetState();
}

class _AppStockMovementSheetState extends State<AppStockMovementSheet> {
  String _activeTab = "ALL"; // ALL, IN, OUT, RETURNS
  late String _selectedBatch;

  @override
  void initState() {
    super.initState();
    _selectedBatch = (widget.initialBatch != null && widget.initialBatch!.trim().isNotEmpty)
        ? widget.initialBatch!.trim()
        : "ALL_BATCHES";
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final med = ph.medicines.firstWhere(
      (m) => (m.identityKey.isNotEmpty && m.identityKey == widget.medicine.identityKey) || m.id == widget.medicine.id,
      orElse: () => widget.medicine,
    );
    final result = AppStockAnalyticsEngine.buildMovementTransactions(ph, med);
    final rawTxns = result.rawTxns;
    final allBatches = result.batchLabels;

    // Ensure selectedBatch is valid
    if (_selectedBatch != "ALL_BATCHES" && !allBatches.contains(_selectedBatch)) {
      allBatches.add(_selectedBatch);
    }

    final batchScopedTxns = _selectedBatch == "ALL_BATCHES"
        ? rawTxns
        : rawTxns.where((t) => t['batch'] == _selectedBatch).toList();

    double running = 0.0;
    for (final t in batchScopedTxns) {
      running += (t['inQty'] as double) - (t['outQty'] as double);
      t['balance'] = running;
    }

    final filteredTxns = batchScopedTxns.where((t) {
      if (_activeTab == "IN") return (t['inQty'] as double) > 0;
      if (_activeTab == "OUT") return (t['outQty'] as double) > 0;
      if (_activeTab == "RETURNS") {
        return t['type'] == 'CREDIT_NOTE' || t['type'] == 'DEBIT_NOTE';
      }
      return true;
    }).toList();

    final displayList = filteredTxns.reversed.toList();
    final double totalIn = filteredTxns.fold(0.0, (s, t) => s + (t['inQty'] as double));
    final double totalOut = filteredTxns.fold(0.0, (s, t) => s + (t['outQty'] as double));

    return Scaffold(
      backgroundColor: MargStockTheme.canvas,
      appBar: AppBar(
        backgroundColor: MargStockTheme.headerDark,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              med.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              "360° Passbook • ${widget.companyName} • ${med.packing}",
              style: const TextStyle(fontSize: 10.5, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Print Movement Passbook PDF",
            icon: const Icon(Icons.print_rounded),
            onPressed: () async {
              final bytes = await AppStockPdfAndExport.generateItemMovementLedgerPdfBytes(
                medicine: med,
                companyName: widget.companyName,
                movements: displayList,
                ph: ph,
              );
              await Printing.layoutPdf(
                onLayout: (_) async => bytes,
                name: "Item_Passbook_${med.name}",
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Product Rate Strip
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: MargStockTheme.headerMid,
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _headerInfo("Code", med.systemId.isNotEmpty ? med.systemId : med.id),
                _headerInfo("On Hand", "${formatQty(med.stock)} Qty"),
                _headerInfo("Pur Rate", "₹${med.purRate.toStringAsFixed(2)}"),
                _headerInfo("MRP", "₹${med.mrp.toStringAsFixed(2)}"),
              ],
            ),
          ),

          // 4 Summary KPI Tiles
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            color: MargStockTheme.cardBg,
            child: Row(
              children: [
                _kpiBox("TOTAL IN (+)", "+${formatQty(totalIn)}", MargStockTheme.stockOk, MargStockTheme.stockOkBg),
                const SizedBox(width: 8),
                _kpiBox("TOTAL OUT (-)", "-${formatQty(totalOut)}", MargStockTheme.stockAlert, MargStockTheme.stockAlertBg),
                const SizedBox(width: 8),
                _kpiBox(
                  _selectedBatch == "ALL_BATCHES" ? "CLOSING" : "BATCH BAL",
                  formatQty(_selectedBatch == "ALL_BATCHES" ? med.stock : running),
                  MargStockTheme.codeBlue,
                  MargStockTheme.codeBlueBg,
                ),
                const SizedBox(width: 8),
                _kpiBox("TXNS", "${filteredTxns.length}", MargStockTheme.headerDark, MargStockTheme.accentLight),
              ],
            ),
          ),

          // Tabs + Batch Filter Bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            decoration: const BoxDecoration(
              color: MargStockTheme.cardBg,
              border: Border(bottom: BorderSide(color: MargStockTheme.border)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _tabChip("ALL", "All"),
                            const SizedBox(width: 6),
                            _tabChip("IN", "Inward (+)"),
                            const SizedBox(width: 6),
                            _tabChip("OUT", "Outward (-)"),
                            const SizedBox(width: 6),
                            _tabChip("RETURNS", "Returns"),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: MargStockTheme.canvas,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: MargStockTheme.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedBatch,
                          style: const TextStyle(
                            color: MargStockTheme.textPrimary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                          items: [
                            const DropdownMenuItem(value: "ALL_BATCHES", child: Text("All Batches")),
                            ...allBatches.map((b) => DropdownMenuItem(value: b, child: Text(b))),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedBatch = v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Movement Timeline Cards
          Expanded(
            child: displayList.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_toggle_off_rounded, size: 44, color: MargStockTheme.textMuted),
                        SizedBox(height: 8),
                        Text(
                          "No stock movements found for this filter",
                          style: TextStyle(color: MargStockTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: displayList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final t = displayList[index];
                      final double inQ = (t['inQty'] as double?) ?? 0.0;
                      final double outQ = (t['outQty'] as double?) ?? 0.0;
                      final double rate = (t['rate'] as double?) ?? 0.0;
                      final double bal = (t['balance'] as double?) ?? 0.0;
                      final Color tColor = t['color'] as Color;
                      final IconData tIcon = t['icon'] as IconData;
                      final DateTime dt = t['date'] as DateTime;
                      final bool isOpening = t['type'] == 'OPENING';

                      return Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: MargStockTheme.cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: MargStockTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: tColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Icon(tIcon, size: 15, color: tColor),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t['typeLabel'].toString(),
                                        style: TextStyle(
                                          color: tColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        "${isOpening ? 'Opening' : DateFormat('dd MMM yyyy').format(dt)}  •  Doc: ${t['docNo']}",
                                        style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 10.5),
                                      ),
                                    ],
                                  ),
                                ),
                                if (inQ > 0)
                                  MargStockTheme.badge(
                                    label: "+${formatQty(inQ)}",
                                    fg: MargStockTheme.stockOk,
                                    bg: MargStockTheme.stockOkBg,
                                  ),
                                if (outQ > 0)
                                  MargStockTheme.badge(
                                    label: "-${formatQty(outQ)}",
                                    fg: MargStockTheme.stockAlert,
                                    bg: MargStockTheme.stockAlertBg,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(height: 1, color: MargStockTheme.divider),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t['party'].toString(),
                                    style: const TextStyle(
                                      color: MargStockTheme.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "Batch: ${t['batch']}",
                                  style: const TextStyle(
                                    color: MargStockTheme.textSecondary,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Rate: ₹${rate.toStringAsFixed(2)}${(t['exp']?.toString().isNotEmpty == true) ? '  •  Exp: ${t['exp']}' : ''}",
                                  style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 10.5),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: MargStockTheme.goldBg,
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: MargStockTheme.goldBorder.withOpacity(0.4)),
                                  ),
                                  child: Text(
                                    "Bal: ${formatQty(bal)} Qty",
                                    style: MargStockTheme.tabularNum.copyWith(
                                      fontSize: 10.5,
                                      color: MargStockTheme.goldText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _headerInfo(String label, String val) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("$label: ", style: const TextStyle(color: Colors.white70, fontSize: 11)),
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _kpiBox(String label, String val, Color fg, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: fg.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: fg, fontSize: 8.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              val,
              style: MargStockTheme.tabularNum.copyWith(color: fg, fontSize: 13.5),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabChip(String key, String label) {
    final bool isSel = _activeTab == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSel ? Colors.white : MargStockTheme.textPrimary,
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
        ),
      ),
      selected: isSel,
      selectedColor: MargStockTheme.headerDark,
      backgroundColor: MargStockTheme.canvas,
      side: BorderSide(color: isSel ? MargStockTheme.headerDark : MargStockTheme.border),
      onSelected: (_) => setState(() => _activeTab = key),
    );
  }
}
