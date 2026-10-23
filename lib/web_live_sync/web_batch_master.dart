import "sub_views/web_stock/product_batch_traceability_screen.dart";
// FILE: lib/web_live_sync/web_batch_master.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'web_models.dart';
import 'pharoah_web_manager.dart';
import '../logic/batch_cascade_engine.dart';
import '../sync_core/modules/batch_sync_module.dart';
import '../app_date_logic.dart';

class WebBatchMasterView extends StatefulWidget {
  final VoidCallback onBack;

  const WebBatchMasterView({super.key, required this.onBack});

  @override
  State<WebBatchMasterView> createState() => _WebBatchMasterViewState();
}

class _WebBatchMasterViewState extends State<WebBatchMasterView> {
  Medicine? _viewingTraceabilityMed;
  final TextEditingController searchController = TextEditingController();
  Medicine? selectedMed;
  String searchQuery = "";

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // 1. REGISTER NEW BATCH DIALOG (WITH D1 SYNC)
  // ===========================================================================
  void _showAddBatchDialog(PharoahWebManager webPh, Medicine med) {
    final batchNoC = TextEditingController();
    final expC = TextEditingController();
    final mrpC = TextEditingController(text: med.mrp.toStringAsFixed(2));
    final purRateC = TextEditingController(text: med.purRate.toStringAsFixed(2));
    final rateAC = TextEditingController(text: med.rateA.toStringAsFixed(2));
    final rateBC = TextEditingController(text: med.rateB.toStringAsFixed(2));
    final rateCC = TextEditingController(text: med.rateC.toStringAsFixed(2));
    final openingQtyC = TextEditingController(text: "0");

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Row(
          children: [
            const Icon(Icons.add_box_rounded, color: Color(0xFF38BDF8), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "REGISTER NEW BATCH • ${med.name}",
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _inputField("BATCH NUMBER (CASE-SENSITIVE) *", batchNoC, isCaps: true),
                const SizedBox(height: 12),
                _inputField("EXPIRY (MM/YY) *", expC, isNum: true),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _inputField("MRP ₹", mrpC, isNum: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _inputField("PUR. RATE ₹", purRateC, isNum: true)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _inputField("RATE A ₹", rateAC, isNum: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField("RATE B ₹", rateBC, isNum: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField("RATE C ₹", rateCC, isNum: true)),
                  ],
                ),
                const SizedBox(height: 12),
                _inputField("INITIAL OPENING STOCK QTY", openingQtyC, isNum: true),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final bNo = batchNoC.text.trim();
              final exp = expC.text.trim();
              if (bNo.isEmpty || exp.isEmpty) return;

              final medKey = med.identityKey;
              if (!webPh.batchHistory.containsKey(medKey)) {
                webPh.batchHistory[medKey] = [];
              }

              bool exists = webPh.batchHistory[medKey]!.any((b) => b.batch.trim() == bNo);
              if (exists) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Batch '$bNo' already exists for ${med.name}"),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              double q = double.tryParse(openingQtyC.text) ?? 0.0;
              double pur = double.tryParse(purRateC.text) ?? 0.0;
              double mrp = double.tryParse(mrpC.text) ?? 0.0;
              double a = double.tryParse(rateAC.text) ?? (mrp > 0 ? mrp : pur);
              double b = double.tryParse(rateBC.text) ?? (a * 0.95);
              double rateCVal = double.tryParse(rateCC.text) ?? (a * 0.92);

              final newBatch = BatchInfo(
                batch: bNo,
                exp: exp,
                packing: med.packing,
                mrp: mrp,
                rate: pur,
                purRate: pur,
                rateA: a,
                rateB: b,
                rateC: rateCVal,
                openingQty: q,
                qty: q,
                isShell: false,
                status: "Active",
              );

              webPh.batchHistory[medKey]!.add(newBatch);

              // 📤 Enqueue D1 mutation
              BatchSyncModule.onBatchSaved(
                batch: newBatch,
                medIdentityKey: medKey,
                storeToken: webPh.activeStoreToken,
                isDelete: false,
              );

              webPh.rebuildInventory();
              Navigator.pop(c);
              setState(() {});

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Batch '$bNo' registered and synced!"),
                  backgroundColor: const Color(0xFF059669),
                ),
              );
            },
            child: const Text("SAVE & SYNC BATCH", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. CASCADE RENAME & EDIT BATCH DIALOG
  // ===========================================================================
  void _showCascadeEditDialog(PharoahWebManager webPh, Medicine med, BatchInfo b) {
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
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Row(
          children: [
            const Icon(Icons.sync_alt_rounded, color: Color(0xFFF59E0B), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "CASCADE EDIT BATCH • $oldBatchNo",
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Renaming or modifying this batch will cascade across all historical Sales, Purchases, Challans, and Returns, recalculating live stock automatically.",
                          style: TextStyle(color: Color(0xFFFDE68A), fontSize: 11, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _inputField("BATCH NUMBER (RENAME)", batchNoC, isCaps: true),
                const SizedBox(height: 12),
                _inputField("EXPIRY (MM/YY)", expC, isNum: true),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _inputField("MRP ₹", mrpC, isNum: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _inputField("PUR. RATE ₹", purRateC, isNum: true)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _inputField("RATE A ₹", rateAC, isNum: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField("RATE B ₹", rateBC, isNum: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField("RATE C ₹", rateCC, isNum: true)),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final newBatchNo = batchNoC.text.trim();
              final newExp = expC.text.trim();
              if (newBatchNo.isEmpty || newExp.isEmpty) return;

              final double newMrp = double.tryParse(mrpC.text) ?? b.mrp;
              final double newPur = double.tryParse(purRateC.text) ?? b.purRate;
              final double newA = double.tryParse(rateAC.text) ?? b.rateA;
              final double newB = double.tryParse(rateBC.text) ?? b.rateB;
              final double newC = double.tryParse(rateCC.text) ?? b.rateC;

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
                batchHistory: webPh.batchHistory,
                sales: webPh.sales,
                purchases: webPh.purchases,
                saleChallans: webPh.saleChallans,
                purchaseChallans: webPh.purchaseChallans,
                saleReturns: webPh.saleReturns,
                purchaseReturns: webPh.purchaseReturns,
                medicines: webPh.medicines,
                storeToken: webPh.activeStoreToken,
                companyId: webPh.activeStoreToken,
              );

              webPh.rebuildInventory();
              Navigator.pop(c);
              setState(() {});

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Batch updated! Cascaded changes to $mutatedCount transaction line item(s)."),
                  backgroundColor: const Color(0xFF059669),
                ),
              );
            },
            child: const Text("APPLY CASCADE UPDATE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. SAFE BATCH DELETION WITH FINANCIAL YEAR INTEGRITY CHECK
  // ===========================================================================
  void _showDeleteBatchDialog(PharoahWebManager webPh, Medicine med, BatchInfo b) {
    final activeFY = webPh.financialYear.isNotEmpty
        ? webPh.financialYear
        : AppDateLogic.getCurrentFYString();

    final lockingRecords = BatchCascadeEngine.checkActiveFYUsage(
      medicine: med,
      batchNo: b.batch,
      activeFY: activeFY,
      sales: webPh.sales,
      purchases: webPh.purchases,
      saleChallans: webPh.saleChallans,
      purchaseChallans: webPh.purchaseChallans,
      saleReturns: webPh.saleReturns,
      purchaseReturns: webPh.purchaseReturns,
    );

    if (lockingRecords.isNotEmpty) {
      // 🔒 DELETION BLOCKED: SHOW DETAILED AUDIT MODAL
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.lock_rounded, color: Color(0xFFEF4444), size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "DELETION LOCKED • ACTIVE FY $activeFY",
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Batch '${b.batch}' cannot be deleted because it is recorded in ${lockingRecords.length} active transaction(s) in Financial Year $activeFY.",
                  style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  "AUDIT LOCK BREAKDOWN:",
                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 240),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: lockingRecords.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (_, i) {
                      final rec = lockingRecords[i];
                      return ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            rec.documentType,
                            style: const TextStyle(color: Color(0xFFF87171), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          "Bill #${rec.billNo} • ${rec.partyName}",
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "Date: ${AppDateLogic.format(rec.date)} | Qty: ${rec.qty.toInt()} | Rate: ₹${rec.rate.toStringAsFixed(2)}",
                          style: const TextStyle(color: Colors.white54, fontSize: 10),
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
                backgroundColor: const Color(0xFF334155),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(c),
              child: const Text("ACKNOWLEDGE & CLOSE"),
            ),
          ],
        ),
      );
      return;
    }

    // 🟢 ZERO RECORDS IN ACTIVE FY: SAFE DELETION CONFIRMATION
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Text(
              "DELETE BATCH • ${b.batch}",
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Zero transactions found for batch '${b.batch}' in active Financial Year $activeFY.",
                style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Are you sure you want to permanently delete this batch? A persistent tombstone will be recorded to prevent cloud resurrection.",
                style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final result = BatchCascadeEngine.deleteBatchSafe(
                medicine: med,
                batchNo: b.batch,
                activeFY: activeFY,
                batchHistory: webPh.batchHistory,
                sales: webPh.sales,
                purchases: webPh.purchases,
                saleChallans: webPh.saleChallans,
                purchaseChallans: webPh.purchaseChallans,
                saleReturns: webPh.saleReturns,
                purchaseReturns: webPh.purchaseReturns,
                medicines: webPh.medicines,
                storeToken: webPh.activeStoreToken,
                companyId: webPh.activeStoreToken,
              );

              webPh.rebuildInventory();
              Navigator.pop(c);
              setState(() {});

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.message),
                  backgroundColor: result.success ? const Color(0xFF059669) : Colors.redAccent,
                ),
              );
            },
            child: const Text("CONFIRM DELETE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 4. STOCK ADJUSTMENT DIALOG
  // ===========================================================================
  void _showAdjustmentDialog(PharoahWebManager webPh, Medicine med, BatchInfo b) {
    final qtyC = TextEditingController();
    String reason = "Stock Correction";

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.white12),
            ),
            title: Text(
              "ADJUST STOCK • BATCH: ${b.batch}",
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Current Live Stock: ${b.qty.toInt()} Qty",
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 15),
                  _inputField("QTY CHANGE (+ TO ADD, - TO REDUCE)", qtyC, isNum: true),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: reason,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: "REASON FOR ADJUSTMENT",
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    items: ["Stock Correction", "Breakage", "Shortage", "Sample", "Expiry Damage"]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setDialogState(() => reason = v!),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  double val = double.tryParse(qtyC.text) ?? 0.0;
                  if (val != 0) {
                    b.adjustmentQty += val;
                    b.adjReason = reason;

                    // 📤 Enqueue D1 mutation
                    BatchSyncModule.onBatchSaved(
                      batch: b,
                      medIdentityKey: med.identityKey,
                      storeToken: webPh.activeStoreToken,
                      isDelete: false,
                    );

                    webPh.rebuildInventory();
                  }
                  Navigator.pop(c);
                  setState(() {});
                },
                child: const Text("APPLY ADJUSTMENT", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // 5. MAIN BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final activeFY = webPh.financialYear.isNotEmpty ? webPh.financialYear : AppDateLogic.getCurrentFYString();

    if (_viewingTraceabilityMed != null) {
      return ProductBatchTraceabilityScreen(
        medicine: _viewingTraceabilityMed!,
        onBack: () => setState(() => _viewingTraceabilityMed = null),
      );
    }

    final query = searchQuery.trim().toLowerCase();
    final matchingMeds = query.isEmpty
        ? <Medicine>[]
        : webPh.medicines.where((m) =>
            m.name.toLowerCase().contains(query) ||
            m.systemId.toLowerCase().contains(query)).take(8).toList();

    List<BatchInfo> batches = [];
    if (selectedMed != null) {
      batches = webPh.batchHistory[selectedMed!.identityKey] ?? [];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- HEADER & BREADCRUMBS ---
          Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 20),
                tooltip: "Back to Hub",
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        "CENTRAL BATCH MASTER",
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.4)),
                        ),
                        child: Text(
                          "ACTIVE FY: $activeFY",
                          style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    "Autonomous batch mirroring, cascade editing across all transactions, and FY integrity shielding.",
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // --- PRODUCT SEARCH SECTION ---
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: "Type product name or system ID to manage batches...",
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                                  onPressed: () {
                                    searchController.clear();
                                    setState(() => searchQuery = "");
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.black26,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                        onChanged: (v) => setState(() => searchQuery = v),
                      ),
                    ),
                    if (selectedMed != null) ...[
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _showAddBatchDialog(webPh, selectedMed!),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text("NEW BATCH", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF38BDF8),
                          side: const BorderSide(color: Color(0xFF38BDF8)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => setState(() => _viewingTraceabilityMed = selectedMed),
                        icon: const Icon(Icons.timeline_rounded, size: 18),
                        label: const Text("TRACEABILITY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ],
                ),

                // Search Results Dropdown
                if (matchingMeds.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: matchingMeds.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (c, i) {
                        final m = matchingMeds[i];
                        return ListTile(
                          dense: true,
                          title: Text(m.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          subtitle: Text("ID: ${m.systemId} • Pack: ${m.packing} • Stock: ${m.stock.toInt()}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 16),
                          onTap: () {
                            setState(() {
                              selectedMed = m;
                              searchQuery = "";
                              searchController.text = m.name;
                            });
                          },
                        );
                      },
                    ),
                  ),

                // Selected Product Summary Strip
                if (selectedMed != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.medication_rounded, color: Color(0xFF38BDF8), size: 20),
                          const SizedBox(width: 10),
                          Text(
                            selectedMed!.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            "PACK: ${selectedMed!.packing} • HSN: ${selectedMed!.hsnCode} • TOTAL STOCK: ${selectedMed!.stock.toInt()}",
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                            onPressed: () {
                              setState(() {
                                selectedMed = null;
                                searchController.clear();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- BATCHES TABLE OR EMPTY STATE ---
          Expanded(
            child: selectedMed == null
                ? _buildEmptyState()
                : batches.isEmpty
                    ? _buildNoBatchesState(webPh, selectedMed!)
                    : _buildBatchesTable(webPh, selectedMed!, batches, activeFY),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 6. BATCHES DATA TABLE (ENTERPRISE SLATE)
  // ===========================================================================
  Widget _buildBatchesTable(PharoahWebManager webPh, Medicine med, List<BatchInfo> batches, String activeFY) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView(
          children: [
            // Table Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFF0F172A),
              child: Row(
                children: const [
                  Expanded(flex: 3, child: Text("BATCH NUMBER", style: _thStyle)),
                  Expanded(flex: 2, child: Text("EXPIRY", style: _thStyle)),
                  Expanded(flex: 2, child: Text("PUR. RATE ₹", style: _thStyle)),
                  Expanded(flex: 2, child: Text("MRP ₹", style: _thStyle)),
                  Expanded(flex: 3, child: Text("RATE A / B / C", style: _thStyle)),
                  Expanded(flex: 2, child: Text("LIVE STOCK", style: _thStyle)),
                  Expanded(flex: 3, child: Text("FY AUDIT STATUS", style: _thStyle)),
                  Expanded(flex: 3, child: Text("ACTIONS", style: _thStyle)),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),

            // Rows
            ...batches.map((b) {
              final lockingRecords = BatchCascadeEngine.checkActiveFYUsage(
                medicine: med,
                batchNo: b.batch,
                activeFY: activeFY,
                sales: webPh.sales,
                purchases: webPh.purchases,
                saleChallans: webPh.saleChallans,
                purchaseChallans: webPh.purchaseChallans,
                saleReturns: webPh.saleReturns,
                purchaseReturns: webPh.purchaseReturns,
              );

              final bool isLockedByFY = lockingRecords.isNotEmpty;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    // Batch No
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.batch,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                          ),
                          Text(
                            b.status,
                            style: TextStyle(
                              color: b.status == "Active" ? const Color(0xFF34D399) : Colors.orangeAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Expiry
                    Expanded(
                      flex: 2,
                      child: Text(
                        b.exp,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),

                    // Pur Rate
                    Expanded(
                      flex: 2,
                      child: Text(
                        "₹${b.purRate.toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),

                    // MRP
                    Expanded(
                      flex: 2,
                      child: Text(
                        "₹${b.mrp.toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                    ),

                    // Rates A/B/C
                    Expanded(
                      flex: 3,
                      child: Text(
                        "A: ${b.rateA.toStringAsFixed(1)} | B: ${b.rateB.toStringAsFixed(1)} | C: ${b.rateC.toStringAsFixed(1)}",
                        style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ),

                    // Live Stock
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: b.qty > 0 ? const Color(0xFF059669).withOpacity(0.2) : Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "${b.qty.toInt()} Qty",
                          style: TextStyle(
                            color: b.qty > 0 ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),

                    // FY Audit Status Badge
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: () => _showDeleteBatchDialog(webPh, med, b),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isLockedByFY
                                ? const Color(0xFFF59E0B).withOpacity(0.15)
                                : const Color(0xFF10B981).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isLockedByFY
                                  ? const Color(0xFFF59E0B).withOpacity(0.4)
                                  : const Color(0xFF10B981).withOpacity(0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isLockedByFY ? Icons.lock_rounded : Icons.check_circle_outline,
                                color: isLockedByFY ? const Color(0xFFFBBF24) : const Color(0xFF34D399),
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  isLockedByFY ? "LOCKED • ${lockingRecords.length} TXN" : "DELETABLE",
                                  style: TextStyle(
                                    color: isLockedByFY ? const Color(0xFFFBBF24) : const Color(0xFF34D399),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Actions
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.sync_alt_rounded, color: Color(0xFF60A5FA), size: 18),
                            tooltip: "Cascade Rename & Edit",
                            onPressed: () => _showCascadeEditDialog(webPh, med, b),
                          ),
                          IconButton(
                            icon: const Icon(Icons.exposure_rounded, color: Color(0xFFFBBF24), size: 18),
                            tooltip: "Stock Adjustment",
                            onPressed: () => _showAdjustmentDialog(webPh, med, b),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFF87171), size: 18),
                            tooltip: "Delete Batch (FY Protected)",
                            onPressed: () => _showDeleteBatchDialog(webPh, med, b),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 7. EMPTY STATES & HELPERS
  // ===========================================================================
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.inventory_2_outlined, color: Colors.white24, size: 54),
          SizedBox(height: 12),
          Text(
            "Select or search a medicine above to inspect and manage its batches.",
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNoBatchesState(PharoahWebManager webPh, Medicine med) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.layers_clear_outlined, color: Colors.white24, size: 48),
          const SizedBox(height: 10),
          Text(
            "No active batches found for '${med.name}'",
            style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
            onPressed: () => _showAddBatchDialog(webPh, med),
            icon: const Icon(Icons.add, size: 18),
            label: const Text("REGISTER FIRST BATCH"),
          ),
        ],
      ),
    );
  }

  Widget _inputField(String label, TextEditingController c, {bool isNum = false, bool isCaps = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: c,
          textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
          keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black26,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  static const _thStyle = TextStyle(
    color: Colors.white54,
    fontSize: 10,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );
}
