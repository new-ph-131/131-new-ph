// FILE: lib/batch_master_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'app_date_logic.dart';
import 'logic/batch_cascade_engine.dart';
import 'sync_core/modules/batch_sync_module.dart';
import 'web_live_sync/sub_views/web_stock/batch_audit_workbench.dart';

class BatchMasterView extends StatefulWidget {
  const BatchMasterView({super.key});

  @override
  State<BatchMasterView> createState() => _BatchMasterViewState();
}

class _BatchMasterViewState extends State<BatchMasterView> {
  Medicine? selectedMed;
  String searchQuery = "";
  final TextEditingController searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _openAuditWorkbench(PharoahManager ph, Medicine med, [String? batchNo]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => Scaffold(
          body: SafeArea(
            child: BatchAuditWorkbench(
              medicine: med,
              batches: ph.batchHistory[med.identityKey] ?? [],
              initialBatchNo: batchNo,
              onBack: () => Navigator.pop(c),
              isWebTheme: false,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. ADD MANUAL BATCH DIALOG (WITH D1 SYNC)
  // ===========================================================================
  void _showAddBatchDialog(PharoahManager ph, Medicine med) {
    final batchNoC = TextEditingController();
    final expC = TextEditingController();
    final mrpC = TextEditingController(text: med.mrp > 0 ? med.mrp.toStringAsFixed(2) : "");
    final rateC = TextEditingController(text: med.purRate > 0 ? med.purRate.toStringAsFixed(2) : "");
    final openingQtyC = TextEditingController(text: "0");

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.add_box_rounded, color: Colors.indigo, size: 22),
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
                  labelText: "Batch Number *",
                  hintText: "e.g. B-1029",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: expC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Expiry (MM/YY) *",
                  hintText: "e.g. 12/28",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: mrpC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "MRP ₹",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: rateC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Pur. Rate ₹",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: openingQtyC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Opening Stock Qty",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  helperText: "Initial stock available in store",
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade900,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final bNo = batchNoC.text.trim().toUpperCase();
              final exp = expC.text.trim();
              if (bNo.isEmpty || exp.isEmpty) return;

              final medKey = med.identityKey;
              if (!ph.batchHistory.containsKey(medKey)) {
                ph.batchHistory[medKey] = [];
              }

              bool exists = ph.batchHistory[medKey]!.any((b) => b.batch.trim().toUpperCase() == bNo);
              if (exists) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error: Batch '$bNo' already exists!"), backgroundColor: Colors.red),
                );
                return;
              }

              final mrp = double.tryParse(mrpC.text) ?? 0.0;
              final pur = double.tryParse(rateC.text) ?? 0.0;
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

              // 📤 Enqueue D1 mutation
              final storeToken = ph.activeCompany != null ? ph.activeCompany!.id : "";
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
                SnackBar(content: Text("Batch '$bNo' registered & synced!"), backgroundColor: Colors.green),
              );
            },
            child: const Text("SAVE & SYNC"),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. CASCADE RENAME & EDIT BATCH DIALOG
  // ===========================================================================
  void _showCascadeEditDialog(PharoahManager ph, Medicine med, BatchInfo b) {
    final oldBatchNo = b.batch;
    final batchNoC = TextEditingController(text: b.batch);
    final expC = TextEditingController(text: b.exp);
    final mrpC = TextEditingController(text: b.mrp.toStringAsFixed(2));
    final purRateC = TextEditingController(text: b.purRate.toStringAsFixed(2));
    final rateAC = TextEditingController(text: b.rateA.toStringAsFixed(2));
    final rateBC = TextEditingController(text: b.rateB.toStringAsFixed(2));
    final rateCC = TextEditingController(text: b.rateC.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.sync_alt_rounded, color: Colors.orange, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Cascade Edit • $oldBatchNo",
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline, color: Colors.amber, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Renaming will update this batch across all historical Invoices, Challans, and Returns automatically.",
                        style: TextStyle(fontSize: 11, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: batchNoC,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: "Batch Number (Rename)",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: expC,
                decoration: const InputDecoration(
                  labelText: "Expiry (MM/YY)",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: mrpC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "MRP ₹",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: purRateC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Pur. Rate ₹",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: rateAC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Rate A ₹",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: rateBC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Rate B ₹",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: rateCC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Rate C ₹",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
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
              backgroundColor: Colors.indigo.shade900,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final newBatchNo = batchNoC.text.trim().toUpperCase();
              final newExp = expC.text.trim();
              if (newBatchNo.isEmpty || newExp.isEmpty) return;

              final double newMrp = double.tryParse(mrpC.text) ?? b.mrp;
              final double newPur = double.tryParse(purRateC.text) ?? b.purRate;
              final double newA = double.tryParse(rateAC.text) ?? b.rateA;
              final double newB = double.tryParse(rateBC.text) ?? b.rateB;
              final double newC = double.tryParse(rateCC.text) ?? b.rateC;

              final storeToken = ph.activeCompany != null ? ph.activeCompany!.id : "";
              final companyId = ph.activeCompany != null ? ph.activeCompany!.id : "";

              final mutatedCount = BatchCascadeEngine.cascadeBatchUpdate(
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
                companyId: companyId,
              );

              ph.save();
              Navigator.pop(c);
              setState(() {});

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Batch updated! Cascaded changes across $mutatedCount transaction line item(s)."),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text("APPLY CASCADE"),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. SAFE BATCH DELETION WITH FINANCIAL YEAR INTEGRITY CHECK
  // ===========================================================================
  void _showDeleteBatchDialog(PharoahManager ph, Medicine med, BatchInfo b) {
    final activeFY = ph.currentFY.isNotEmpty
        ? ph.currentFY
        : AppDateLogic.getCurrentFYString();

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
      // 🔒 LOCKED BY ACTIVE FY: SHOW AUDIT BREAKDOWN MODAL
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.red, width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.lock_rounded, color: Colors.red, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Locked • Active FY $activeFY",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red),
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
                  "Batch '${b.batch}' cannot be deleted because it is recorded in ${lockingRecords.length} active transaction(s) during Financial Year $activeFY.",
                  style: const TextStyle(fontSize: 12, height: 1.3),
                ),
                const SizedBox(height: 12),
                const Text(
                  "TRANSACTION AUDIT RECORDS:",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8),
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: lockingRecords.length,
                    separatorBuilder: (_, __) => Divider(color: Colors.grey.shade200, height: 1),
                    itemBuilder: (_, i) {
                      final rec = lockingRecords[i];
                      return ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            rec.documentType,
                            style: TextStyle(color: Colors.red.shade800, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          "Bill #${rec.billNo} • ${rec.partyName}",
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "Date: ${AppDateLogic.format(rec.date)} | Qty: ${rec.qty.toInt()} | Rate: ₹${rec.rate.toStringAsFixed(2)}",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(c),
              child: const Text("ACKNOWLEDGE"),
            ),
          ],
        ),
      );
      return;
    }

    // 🟢 ZERO ACTIVE FY RECORDS: PROCEED WITH SAFE DELETION
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            Text("Delete Batch • ${b.batch}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Zero transactions found for batch '${b.batch}' in Financial Year $activeFY.",
              style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Are you sure you want to permanently delete this batch? A persistent tombstone will be registered so it will not return on cloud sync.",
              style: TextStyle(fontSize: 11, color: Colors.black87, height: 1.3),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final storeToken = ph.activeCompany != null ? ph.activeCompany!.id : "";
              final companyId = ph.activeCompany != null ? ph.activeCompany!.id : "";

              final result = BatchCascadeEngine.deleteBatchSafe(
                medicine: med,
                batchNo: b.batch,
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
                companyId: companyId,
              );

              ph.save();
              Navigator.pop(c);
              setState(() {});

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.message),
                  backgroundColor: result.success ? Colors.green : Colors.red,
                ),
              );
            },
            child: const Text("CONFIRM DELETE"),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 4. STOCK ADJUSTMENT DIALOG
  // ===========================================================================
  void _showAdjustmentDialog(PharoahManager ph, Medicine med, BatchInfo b) {
    final qtyC = TextEditingController();
    String reason = "Stock Correction";

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text("Adjust Stock • ${b.batch}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Current Live Stock: ${b.qty.toInt()} Qty", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyC,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  decoration: const InputDecoration(
                    labelText: "Qty Change (+ to Add, - to Reduce)",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: reason,
                  decoration: const InputDecoration(
                    labelText: "Reason",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: ["Stock Correction", "Breakage", "Shortage", "Sample", "Expiry Damage"]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setDialogState(() => reason = v!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  double val = double.tryParse(qtyC.text) ?? 0.0;
                  if (val != 0) {
                    ph.adjustBatchStock(medId: med.identityKey, batchNo: b.batch, adjQty: val, reason: reason);

                    // 📤 Enqueue D1 mutation
                    final storeToken = ph.activeCompany != null ? ph.activeCompany!.id : "";
                    if (storeToken.isNotEmpty) {
                      BatchSyncModule.onBatchSaved(
                        batch: b,
                        medIdentityKey: med.identityKey,
                        storeToken: storeToken,
                        isDelete: false,
                      );
                    }
                  }
                  Navigator.pop(c);
                  setState(() {});
                },
                child: const Text("UPDATE STOCK"),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // 5. MAIN UI BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final activeFY = ph.currentFY.isNotEmpty ? ph.currentFY : AppDateLogic.getCurrentFYString();

    List<Medicine> filteredMeds = ph.medicines.where((m) =>
      m.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
      m.systemId.toLowerCase().contains(searchQuery.toLowerCase())
    ).take(10).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Central Batch Master", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text("Active FY: $activeFY", style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. PRODUCT SEARCH BAR & SELECTION CARD
          _buildSearchAndSelectionCard(ph, filteredMeds),

          // 2. BATCHES EXECUTIVE CARDS
          Expanded(
            child: selectedMed == null
                ? _buildEmptyState()
                : _buildBatchList(ph, selectedMed!, activeFY),
          ),
        ],
      ),
      floatingActionButton: selectedMed != null
          ? FloatingActionButton.extended(
              onPressed: () => _showAddBatchDialog(ph, selectedMed!),
              backgroundColor: Colors.indigo.shade900,
              icon: const Icon(Icons.add_box_rounded, color: Colors.white),
              label: const Text("NEW BATCH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _buildSearchAndSelectionCard(PharoahManager ph, List<Medicine> filteredMeds) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectedMed == null) ...[
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: "Search medicine by name or ID...",
                prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          searchController.clear();
                          setState(() => searchQuery = "");
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
            if (searchQuery.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filteredMeds.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) => ListTile(
                    dense: true,
                    title: Text(filteredMeds[i].name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text("ID: ${filteredMeds[i].systemId} • Pack: ${filteredMeds[i].packing} • Stock: ${filteredMeds[i].stock.toInt()}"),
                    trailing: const Icon(Icons.chevron_right, size: 16),
                    onTap: () {
                      setState(() {
                        selectedMed = filteredMeds[i];
                        searchQuery = "";
                        searchController.clear();
                      });
                    },
                  ),
                ),
              ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medication_rounded, color: Colors.indigo, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selectedMed!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text("ID: ${selectedMed!.systemId} • Pack: ${selectedMed!.packing} • Total Stock: ${selectedMed!.stock.toInt()}", style: TextStyle(color: Colors.grey.shade700, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (ph.config.developerAllowBatchHistoryToUser && ph.config.userEnableBatchHistory) ...[
                    IconButton(
                      icon: const Icon(Icons.table_chart_rounded, color: Color(0xFF0F766E)),
                      tooltip: "Batch Adjustment Audit History",
                      onPressed: () => _openAuditWorkbench(ph, selectedMed!),
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.red),
                    onPressed: () => setState(() => selectedMed = null),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBatchList(PharoahManager ph, Medicine med, String activeFY) {
    List<BatchInfo> batches = ph.batchHistory[med.identityKey] ?? [];

    if (batches.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, color: Colors.grey.shade400, size: 48),
            const SizedBox(height: 8),
            Text("No batches found for '${med.name}'", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade900, foregroundColor: Colors.white),
              onPressed: () => _showAddBatchDialog(ph, med),
              icon: const Icon(Icons.add, size: 16),
              label: const Text("REGISTER FIRST BATCH"),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: batches.length,
      itemBuilder: (c, i) {
        final b = batches[i];
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

        final bool isLockedByFY = lockingRecords.isNotEmpty;

        return Card(
          elevation: 1.5,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Batch Name & Stock
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.batch,
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.indigo.shade900),
                        ),
                        Text(
                          "Exp: ${b.exp} | MRP: ₹${b.mrp.toStringAsFixed(2)} | Pur: ₹${b.purRate.toStringAsFixed(2)}",
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                    _stockBadge(b.qty),
                  ],
                ),
                const SizedBox(height: 8),

                // Rate A/B/C and FY Status chip
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "A: ₹${b.rateA.toStringAsFixed(1)} | B: ₹${b.rateB.toStringAsFixed(1)} | C: ₹${b.rateC.toStringAsFixed(1)}",
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontFamily: 'monospace'),
                      ),
                    ),
                    InkWell(
                      onTap: () => _showDeleteBatchDialog(ph, med, b),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isLockedByFY ? Colors.amber.shade50 : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: isLockedByFY ? Colors.amber.shade300 : Colors.green.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isLockedByFY ? Icons.lock_rounded : Icons.check_circle_outline,
                              color: isLockedByFY ? Colors.amber.shade800 : Colors.green.shade800,
                              size: 11,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              isLockedByFY ? "FY-LOCKED (${lockingRecords.length})" : "DELETABLE",
                              style: TextStyle(
                                color: isLockedByFY ? Colors.amber.shade900 : Colors.green.shade900,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),

                // Action Buttons Row
                Row(
                  children: [
                    _actionBtn("CASCADE EDIT", Icons.sync_alt_rounded, Colors.indigo, () => _showCascadeEditDialog(ph, med, b)),
                    const SizedBox(width: 8),
                    _actionBtn("ADJUST", Icons.exposure, Colors.orange.shade800, () => _showAdjustmentDialog(ph, med, b)),
                    if (ph.config.developerAllowBatchHistoryToUser && ph.config.userEnableBatchHistory) ...[
                      const SizedBox(width: 8),
                      _actionBtn("AUDIT", Icons.table_chart_rounded, const Color(0xFF0F766E), () => _openAuditWorkbench(ph, med, b.batch)),
                    ],
                    const SizedBox(width: 8),
                    _actionBtn("DELETE", Icons.delete_outline, Colors.red.shade700, () => _showDeleteBatchDialog(ph, med, b)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stockBadge(double qty) {
    bool isNeg = qty <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isNeg ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isNeg ? Colors.red.shade200 : Colors.green.shade200),
      ),
      child: Column(
        children: [
          Text(isNeg ? "SHORT" : "LIVE STOCK", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isNeg ? Colors.red.shade700 : Colors.green.shade700)),
          Text(qty.toInt().toString(), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: isNeg ? Colors.red.shade900 : Colors.green.shade900, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 13, color: color),
        label: Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          side: BorderSide(color: color.withOpacity(0.4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, color: Colors.grey.shade400, size: 48),
          const SizedBox(height: 8),
          Text("Search and select a product to manage its batches.", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ],
      ),
    );
  }
}
