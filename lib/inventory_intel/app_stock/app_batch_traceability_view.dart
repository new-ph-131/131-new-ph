// FILE: lib/inventory_intel/app_stock/app_batch_traceability_view.dart
import 'package:flutter/material.dart';
import 'package:pharoah_erp/app_date_logic.dart';
import 'package:pharoah_erp/expiry_master.dart';
import 'package:pharoah_erp/inventory_logic_center.dart';
import 'package:pharoah_erp/logic/batch_cascade_engine.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:pharoah_erp/sync_core/modules/batch_sync_module.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_stock/batch_audit_workbench.dart';
import 'package:provider/provider.dart';
import 'app_stock_analytics_engine.dart';
import 'app_stock_movement_sheet.dart';
import 'app_stock_theme.dart';

class AppBatchTraceabilityView extends StatefulWidget {
  final Medicine medicine;

  const AppBatchTraceabilityView({
    super.key,
    required this.medicine,
  });

  @override
  State<AppBatchTraceabilityView> createState() => _AppBatchTraceabilityViewState();
}

class _AppBatchTraceabilityViewState extends State<AppBatchTraceabilityView> {
  String _selectedFilter = 'ALL'; // ALL, ACTIVE, ZERO, ADJUSTED
  String _batchSearchQuery = '';
  final TextEditingController _batchSearchCtrl = TextEditingController();

  @override
  void dispose() {
    _batchSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final med = ph.medicines.firstWhere(
      (m) => (m.identityKey.isNotEmpty && m.identityKey == widget.medicine.identityKey) || m.id == widget.medicine.id,
      orElse: () => widget.medicine,
    );
    final companyName = AppStockAnalyticsEngine.resolveCompanyName(ph, med.companyId);
    final batches = ph.getBatchesForMedicine(med);

    final double totalQty = batches.fold(0.0, (s, b) => s + b.qty);
    final double totalPurVal = batches.fold(0.0, (s, b) {
      final double r = (b.purRate > 0 ? b.purRate : b.rate) > 0
          ? (b.purRate > 0 ? b.purRate : b.rate)
          : med.purRate;
      return s + (b.qty > 0 ? b.qty * r : 0.0);
    });
    final double totalMrpVal = batches.fold(0.0, (s, b) {
      final double r = b.mrp > 0 ? b.mrp : med.mrp;
      return s + (b.qty > 0 ? b.qty * r : 0.0);
    });

    final filteredBatches = batches.where((b) {
      if (_selectedFilter == 'ACTIVE' && b.qty <= 0) return false;
      if (_selectedFilter == 'ZERO' && b.qty != 0) return false;
      if (_selectedFilter == 'ADJUSTED' &&
          b.adjustmentHistory.isEmpty &&
          b.adjustmentQty == 0) {
        return false;
      }
      if (_batchSearchQuery.isNotEmpty) {
        final q = _batchSearchQuery.toLowerCase();
        final match = b.batch.toLowerCase().contains(q) ||
            b.exp.toLowerCase().contains(q) ||
            b.adjReason.toLowerCase().contains(q);
        if (!match) return false;
      }
      return true;
    }).toList();

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
              "Batch Traceability • $companyName • ${med.packing}",
              style: const TextStyle(fontSize: 10.5, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Audit History",
            icon: const Icon(Icons.fact_check_rounded),
            onPressed: () => _openAuditWorkbench(ph, med),
          ),
          IconButton(
            tooltip: "Register New Batch",
            icon: const Icon(Icons.add_box_rounded),
            onPressed: () => _showAddBatchDialog(context, ph, med),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Summary KPI Strip
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(
              color: MargStockTheme.cardBg,
              border: Border(bottom: BorderSide(color: MargStockTheme.border)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _kpiTile("BATCHES", "${batches.length}", MargStockTheme.headerDark, MargStockTheme.accentLight),
                    const SizedBox(width: 6),
                    _kpiTile("LIVE QTY", formatQty(totalQty), MargStockTheme.stockOk, MargStockTheme.stockOkBg),
                    const SizedBox(width: 6),
                    _kpiTile("PUR VAL", "₹${totalPurVal.toStringAsFixed(0)}", MargStockTheme.valuationPurple, const Color(0xFFEDE9FE)),
                    const SizedBox(width: 6),
                    _kpiTile("MRP VAL", "₹${totalMrpVal.toStringAsFixed(0)}", MargStockTheme.goldText, MargStockTheme.goldBg),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _batchSearchCtrl,
                  style: const TextStyle(fontSize: 13, color: MargStockTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: "Search batch number, expiry, reason...",
                    hintStyle: const TextStyle(fontSize: 12, color: MargStockTheme.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded, size: 19, color: MargStockTheme.headerMid),
                    suffixIcon: _batchSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _batchSearchCtrl.clear();
                              setState(() => _batchSearchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: MargStockTheme.canvas,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: MargStockTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: MargStockTheme.border),
                    ),
                  ),
                  onChanged: (v) => setState(() => _batchSearchQuery = v.trim()),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('ALL', 'All (${batches.length})'),
                      const SizedBox(width: 6),
                      _filterChip('ACTIVE', 'In Stock (>0)'),
                      const SizedBox(width: 6),
                      _filterChip('ZERO', 'Zero (=0)'),
                      const SizedBox(width: 6),
                      _filterChip('ADJUSTED', 'Adjusted'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Batch List
          Expanded(
            child: filteredBatches.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.layers_clear_rounded, size: 46, color: MargStockTheme.textMuted),
                        SizedBox(height: 8),
                        Text(
                          "No batches matching current filter",
                          style: TextStyle(color: MargStockTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredBatches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final b = filteredBatches[index];
                      return _buildBatchCard(context, ph, med, companyName, b);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: MargStockTheme.headerDark,
        foregroundColor: Colors.white,
        onPressed: () => _showAddBatchDialog(context, ph, med),
        icon: const Icon(Icons.add_box_rounded, size: 20),
        label: const Text("NEW BATCH", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _buildBatchCard(
    BuildContext context,
    PharoahManager ph,
    Medicine med,
    String companyName,
    BatchInfo b,
  ) {
    final String displayBatch = b.batch.trim().isEmpty ? "NO BATCH" : b.batch.trim();
    final ExpiryStatus expStatus = ExpiryMaster.getStatus(b.exp);
    Color expFg = MargStockTheme.stockOk;
    Color expBg = MargStockTheme.stockOkBg;
    if (expStatus == ExpiryStatus.expired) {
      expFg = MargStockTheme.stockAlert;
      expBg = MargStockTheme.stockAlertBg;
    } else if (expStatus == ExpiryStatus.nearExpiry) {
      expFg = MargStockTheme.stockLow;
      expBg = MargStockTheme.stockLowBg;
    }

    final double effPurRate = (b.purRate > 0 ? b.purRate : b.rate) > 0
        ? (b.purRate > 0 ? b.purRate : b.rate)
        : med.purRate;
    final double effMrp = b.mrp > 0 ? b.mrp : med.mrp;
    final double purVal = b.qty > 0 ? b.qty * effPurRate : 0.0;
    final double mrpVal = b.qty > 0 ? b.qty * effMrp : 0.0;
    final bool hasBatchInMap = _ownsBatchInHistory(ph, med, b);

    return Container(
      decoration: BoxDecoration(
        color: MargStockTheme.cardBg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: MargStockTheme.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: MargStockTheme.codeBlueBg,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: MargStockTheme.codeBlue.withOpacity(0.3)),
                      ),
                      child: Text(
                        displayBatch,
                        style: const TextStyle(
                          color: MargStockTheme.codeBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    MargStockTheme.badge(
                      label: "EXP: ${b.exp.isEmpty ? 'N/A' : b.exp}",
                      fg: expFg,
                      bg: expBg,
                    ),
                    if (b.adjustmentHistory.isNotEmpty || b.adjustmentQty != 0) ...[
                      const SizedBox(width: 6),
                      MargStockTheme.badge(
                        label: "ADJ ${b.adjustmentQty >= 0 ? '+' : ''}${formatQty(b.adjustmentQty)}",
                        fg: MargStockTheme.goldText,
                        bg: MargStockTheme.goldBg,
                      ),
                    ],
                    const Spacer(),
                    Text(
                      "${formatQty(b.qty)} Qty",
                      style: MargStockTheme.tabularNum.copyWith(
                        fontSize: 14,
                        color: b.qty > 0 ? MargStockTheme.stockOk : MargStockTheme.stockAlert,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: MargStockTheme.zebraRow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MargStockTheme.divider),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _cellMetric("OPENING", formatQty(b.openingQty), MargStockTheme.textSecondary),
                      _cellMetric("PUR RATE", "₹${effPurRate.toStringAsFixed(2)}", MargStockTheme.textPrimary),
                      _cellMetric("MRP", "₹${effMrp.toStringAsFixed(2)}", MargStockTheme.textPrimary),
                      _cellMetric("PUR VAL", "₹${purVal.toStringAsFixed(0)}", MargStockTheme.valuationPurple),
                      _cellMetric("MRP VAL", "₹${mrpVal.toStringAsFixed(0)}", MargStockTheme.headerDark),
                    ],
                  ),
                ),
                if (b.rateA > 0 || b.rateB > 0 || b.rateC > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    "Sale Rates:  A ₹${b.rateA.toStringAsFixed(2)}  •  B ₹${b.rateB.toStringAsFixed(2)}  •  C ₹${b.rateC.toStringAsFixed(2)}",
                    style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: MargStockTheme.divider),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _actionBtn(
                    icon: Icons.tune_rounded,
                    label: "Adjust",
                    color: MargStockTheme.goldText,
                    onTap: () => _showAdjustStockDialog(context, ph, med, b),
                  ),
                  if (hasBatchInMap) ...[
                    const SizedBox(width: 6),
                    _actionBtn(
                      icon: Icons.edit_rounded,
                      label: "Edit",
                      color: MargStockTheme.codeBlue,
                      onTap: () => _showEditBatchDialog(context, ph, med, b),
                    ),
                  ],
                  const SizedBox(width: 6),
                  _actionBtn(
                    icon: Icons.fact_check_rounded,
                    label: b.adjustmentHistory.isNotEmpty
                        ? "Audit (${b.adjustmentHistory.length})"
                        : "Audit",
                    color: MargStockTheme.headerDark,
                    onTap: () => _openAuditWorkbench(ph, med, b.batch),
                  ),
                  const SizedBox(width: 6),
                  _actionBtn(
                    icon: Icons.history_rounded,
                    label: "Trail",
                    color: MargStockTheme.accentTeal,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AppStockMovementSheet(
                            medicine: med,
                            companyName: companyName,
                            initialBatch: displayBatch,
                          ),
                        ),
                      );
                    },
                  ),
                  if (hasBatchInMap) ...[
                    const SizedBox(width: 6),
                    _actionBtn(
                      icon: Icons.delete_outline_rounded,
                      label: "Delete",
                      color: MargStockTheme.stockAlert,
                      onTap: () => _showDeleteBatchDialog(context, ph, med, b),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _ownsBatchInHistory(PharoahManager ph, Medicine med, BatchInfo b) {
    final list = ph.batchHistory[med.identityKey];
    if (list == null) return false;
    return list.any((x) => identical(x, b) || x.batch.trim().toUpperCase() == b.batch.trim().toUpperCase());
  }

  void _openAuditWorkbench(PharoahManager ph, Medicine med, [String? batchNo]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => Consumer<PharoahManager>(
          builder: (ctx, livePh, _) => Scaffold(
            body: SafeArea(
              child: BatchAuditWorkbench(
                medicine: med,
                batches: livePh.getBatchesForMedicine(med),
                initialBatchNo: batchNo,
                onBack: () => Navigator.pop(c),
                isWebTheme: false,
                onModifyRecord: ({
                  required String batchNo,
                  required BatchAdjustmentRecord record,
                  required double newAdjQty,
                  required String newReason,
                  required String newNotes,
                }) {
                  livePh.modifyBatchAdjustmentRecord(
                    medId: med.identityKey,
                    batchNo: batchNo,
                    recordId: record.id,
                    newAdjQty: newAdjQty,
                    newReason: newReason,
                    newNotes: newNotes,
                  );
                },
                onDeleteRecord: ({
                  required String batchNo,
                  required BatchAdjustmentRecord record,
                }) {
                  livePh.deleteBatchAdjustmentRecord(
                    medId: med.identityKey,
                    batchNo: batchNo,
                    recordId: record.id,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddBatchDialog(BuildContext context, PharoahManager ph, Medicine med) {
    final batchNoC = TextEditingController();
    final expC = TextEditingController();
    final mrpC = TextEditingController(text: med.mrp > 0 ? med.mrp.toStringAsFixed(2) : "");
    final rateC = TextEditingController(text: med.purRate > 0 ? med.purRate.toStringAsFixed(2) : "");
    final openingQtyC = TextEditingController(text: "0");

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.add_box_rounded, color: MargStockTheme.headerDark, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Register Batch • ${med.name}",
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: batchNoC,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: "Batch Number",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: expC,
                decoration: const InputDecoration(
                  labelText: "Expiry (MM/YY or N/A)",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: rateC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Pur Rate",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: mrpC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "MRP",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: openingQtyC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Opening Stock Qty",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: MargStockTheme.headerDark,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final bNo = batchNoC.text.trim().toUpperCase();
              final exp = expC.text.trim();
              if (exp.isNotEmpty) {
                final expWarn = ExpiryMaster.getValidationWarning(exp);
                if (expWarn != null && expWarn.startsWith("Error")) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(expWarn), backgroundColor: MargStockTheme.stockAlert),
                  );
                  return;
                }
              }
              final medKey = med.identityKey;
              ph.batchHistory.putIfAbsent(medKey, () => []);
              final mrp = double.tryParse(mrpC.text) ?? 0.0;
              final pur = double.tryParse(rateC.text) ?? 0.0;
              final exists = InventoryLogicCenter.findMatchingBatchIndex(
                    ph.batchHistory[medKey]!,
                    batchNo: bNo,
                    exp: exp,
                    mrp: mrp,
                    purRate: pur,
                    exactEmptyBatchLot: true,
                  ) !=
                  -1;
              if (exists) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Batch '${bNo.isEmpty ? 'NO BATCH' : bNo}' already exists!"),
                    backgroundColor: MargStockTheme.stockAlert,
                  ),
                );
                return;
              }
              final q = double.tryParse(openingQtyC.text) ?? 0.0;
              final a = mrp > 0 ? mrp : pur;
              final newBatch = BatchInfo(
                batch: bNo,
                exp: exp,
                packing: med.packing,
                mrp: mrp,
                rate: pur,
                purRate: pur,
                rateA: a,
                rateB: a * 0.95,
                rateC: a * 0.92,
                openingQty: q,
                qty: q,
                isShell: false,
                status: "Active",
              );
              ph.batchHistory[medKey]!.add(newBatch);
              final storeToken = ph.activeCompany?.id ?? "";
              if (storeToken.isNotEmpty) {
                BatchSyncModule.onBatchSaved(
                  batch: newBatch,
                  medIdentityKey: medKey,
                  storeToken: storeToken,
                  isDelete: false,
                );
              }
              ph.rebuildInventory();
              ph.save();
              Navigator.pop(c);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Batch '${bNo.isEmpty ? 'NO BATCH' : bNo}' registered & synced!"),
                  backgroundColor: MargStockTheme.stockOk,
                ),
              );
            },
            child: const Text("SAVE & SYNC"),
          ),
        ],
      ),
    );
  }

  void _showAdjustStockDialog(BuildContext context, PharoahManager ph, Medicine med, BatchInfo b) {
    final qtyC = TextEditingController();
    final notesC = TextEditingController();
    String reason = "Stock Correction";

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              const Icon(Icons.tune_rounded, color: MargStockTheme.goldBorder, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Adjust Batch: ${b.batch.isEmpty ? 'NO BATCH' : b.batch}",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Current Batch Stock: ${formatQty(b.qty)} Qty",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: MargStockTheme.headerDark),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: qtyC,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  decoration: const InputDecoration(
                    labelText: "Qty Change (+ to Add, - to Reduce)",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: reason,
                  decoration: const InputDecoration(
                    labelText: "Reason",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: ["Stock Correction", "Breakage", "Shortage", "Sample", "Expiry Damage"]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlg(() => reason = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesC,
                  decoration: const InputDecoration(
                    labelText: "Audit Notes (Optional)",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: MargStockTheme.goldBorder,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final val = double.tryParse(qtyC.text.trim()) ?? 0.0;
                if (val == 0) return;

                // Resolve actual owning key in batchHistory so we do not duplicate legacy-keyed batches
                String owningKey = med.identityKey;
                final candidates = [
                  if (med.identityKey.trim().isNotEmpty) med.identityKey.trim(),
                  if (med.systemId.trim().isNotEmpty) med.systemId.trim(),
                  if (med.id.trim().isNotEmpty) med.id.trim(),
                  if (med.name.trim().isNotEmpty) med.name.trim(),
                  if (med.name.trim().isNotEmpty) med.name.trim().toUpperCase(),
                ];
                bool foundInMap = false;
                for (final k in candidates) {
                  final existingList = ph.batchHistory[k];
                  if (existingList != null &&
                      existingList.any((x) => x.batch.trim().toUpperCase() == b.batch.trim().toUpperCase())) {
                    owningKey = k;
                    foundInMap = true;
                    break;
                  }
                }
                if (!foundInMap) {
                  ph.batchHistory.putIfAbsent(owningKey, () => []).add(b);
                }

                ph.adjustBatchStock(
                  medId: owningKey,
                  batchNo: b.batch,
                  adjQty: val,
                  reason: reason,
                  adjustedBy: ph.loggedInStaff?.name ?? "Admin",
                  notes: notesC.text.trim(),
                );
                Navigator.pop(c);
                setState(() {});
              },
              child: const Text("UPDATE STOCK"),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditBatchDialog(BuildContext context, PharoahManager ph, Medicine med, BatchInfo b) {
    final oldBatchNo = b.batch;
    final batchC = TextEditingController(text: b.batch);
    final expC = TextEditingController(text: b.exp);
    final purC = TextEditingController(text: (b.purRate > 0 ? b.purRate : b.rate).toStringAsFixed(2));
    final mrpC = TextEditingController(text: b.mrp.toStringAsFixed(2));
    final rateAC = TextEditingController(text: b.rateA.toStringAsFixed(2));
    final rateBC = TextEditingController(text: b.rateB.toStringAsFixed(2));
    final rateCC = TextEditingController(text: b.rateC.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          "Edit & Cascade • ${b.batch.isEmpty ? 'NO BATCH' : b.batch}",
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: batchC,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: "Batch No", border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: expC,
                decoration: const InputDecoration(labelText: "Expiry (MM/YY)", border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: purC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "Pur Rate", border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: mrpC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "MRP", border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: rateAC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "Rate A", border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: rateBC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "Rate B", border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: rateCC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "Rate C", border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: MargStockTheme.headerDark,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final newBatchNo = batchC.text.trim().toUpperCase();
              final newExp = expC.text.trim();
              final newPur = double.tryParse(purC.text) ?? b.purRate;
              final newMrp = double.tryParse(mrpC.text) ?? b.mrp;
              final newA = double.tryParse(rateAC.text) ?? b.rateA;
              final newB = double.tryParse(rateBC.text) ?? b.rateB;
              final newC = double.tryParse(rateCC.text) ?? b.rateC;

              final storeToken = ph.activeCompany?.id ?? "";
              final mutated = BatchCascadeEngine.cascadeBatchUpdate(
                medicine: med,
                oldBatchNo: oldBatchNo,
                newBatchNo: newBatchNo,
                newExp: newExp,
                newMrp: newMrp,
                newPurRate: newPur,
                newRateA: newA,
                newRateB: newB,
                newRateC: newC,
                batchHistory: ph.batchHistory,
                sales: ph.sales,
                purchases: ph.purchases,
                saleChallans: ph.saleChallans,
                purchaseChallans: ph.purchaseChallans,
                saleReturns: ph.saleReturns,
                purchaseReturns: ph.purchaseReturns,
                medicines: ph.medicines,
                storeToken: storeToken,
                companyId: storeToken,
              );
              ph.rebuildInventory();
              ph.save();
              Navigator.pop(c);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Batch updated! Cascaded across $mutated line item(s)."),
                  backgroundColor: MargStockTheme.stockOk,
                ),
              );
            },
            child: const Text("SAVE & CASCADE"),
          ),
        ],
      ),
    );
  }

  void _showDeleteBatchDialog(BuildContext context, PharoahManager ph, Medicine med, BatchInfo b) {
    final activeFY = ph.currentFY.isNotEmpty ? ph.currentFY : AppDateLogic.getCurrentFYString();
    final lockingRecords = BatchCascadeEngine.checkActiveFYUsage(
      medicine: med,
      batchNo: b.batch,
      activeFY: activeFY,
      sales: ph.sales,
      purchases: ph.purchases,
      saleChallans: ph.saleChallans,
      purchaseChallans: ph.purchaseChallans,
      saleReturns: ph.saleReturns,
      purchaseReturns: ph.purchaseReturns,
    );

    if (lockingRecords.isNotEmpty) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              const Icon(Icons.lock_rounded, color: MargStockTheme.stockAlert, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "DELETION LOCKED • FY $activeFY",
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: MargStockTheme.stockAlert),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Batch '${b.batch}' is used in ${lockingRecords.length} active transaction(s) in $activeFY.",
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: lockingRecords.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final rec = lockingRecords[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          "${rec.documentType} #${rec.billNo}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                        ),
                        subtitle: Text(
                          "${rec.partyName} • ${AppDateLogic.format(rec.date)} • Qty: ${formatQty(rec.qty)}",
                          style: const TextStyle(fontSize: 10.5),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: MargStockTheme.headerDark, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(c),
              child: const Text("CLOSE"),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text("Delete Batch?", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Text(
          "Delete batch '${b.batch.isEmpty ? 'NO BATCH' : b.batch}' (Qty: ${formatQty(b.qty)})? A cloud tombstone will be created.",
          style: const TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: MargStockTheme.stockAlert, foregroundColor: Colors.white),
            onPressed: () {
              final storeToken = ph.activeCompany?.id ?? "";
              final result = BatchCascadeEngine.deleteBatchSafe(
                medicine: med,
                batchNo: b.batch,
                exp: b.exp,
                mrp: b.mrp,
                purRate: b.purRate > 0 ? b.purRate : b.rate,
                activeFY: activeFY,
                batchHistory: ph.batchHistory,
                sales: ph.sales,
                purchases: ph.purchases,
                saleChallans: ph.saleChallans,
                purchaseChallans: ph.purchaseChallans,
                saleReturns: ph.saleReturns,
                purchaseReturns: ph.purchaseReturns,
                medicines: ph.medicines,
                storeToken: storeToken,
                companyId: storeToken,
              );
              ph.save();
              Navigator.pop(c);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.message),
                  backgroundColor: result.success ? MargStockTheme.stockOk : MargStockTheme.stockAlert,
                ),
              );
            },
            child: const Text("CONFIRM DELETE"),
          ),
        ],
      ),
    );
  }

  Widget _kpiTile(String label, String val, Color fg, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: fg.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: fg, fontSize: 8.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(val, style: MargStockTheme.tabularNum.copyWith(color: fg, fontSize: 12), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final isSel = _selectedFilter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSel ? Colors.white : MargStockTheme.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      selected: isSel,
      selectedColor: MargStockTheme.headerDark,
      backgroundColor: MargStockTheme.canvas,
      side: BorderSide(color: isSel ? MargStockTheme.headerDark : MargStockTheme.border),
      onSelected: (_) => setState(() => _selectedFilter = key),
    );
  }

  Widget _cellMetric(String label, String val, Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: MargStockTheme.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(val, style: MargStockTheme.tabularNum.copyWith(color: c, fontSize: 11.5)),
      ],
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.45)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
