import "dart:convert";
import "dart:typed_data";
import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:intl/intl.dart";
import "package:csv/csv.dart";
import "package:file_saver/file_saver.dart";

import "sub_views/web_stock/product_batch_traceability_screen.dart";
import "web_models.dart";
import "pharoah_web_manager.dart";
import "../logic/batch_cascade_engine.dart";
import "../sync_core/modules/batch_sync_module.dart";
import "../app_date_logic.dart";

class GlobalBatchItem {
  final Medicine medicine;
  final BatchInfo batch;

  GlobalBatchItem({required this.medicine, required this.batch});
}

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

  // Dual Mode Navigation
  bool isGlobalExplorer = true; // true: All-Batch Explorer, false: Product Drill-down

  // Filter: ALL, IN_STOCK, ZERO_STOCK, EXPIRING, EXPIRED, HOLD_BLOCKED, FY_LOCKED
  String activeFilter = "ALL";

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // --- EXPIRY UTILITIES ---
  bool _isNearExpiry(String expStr) {
    try {
      final parts = expStr.split('/');
      if (parts.length != 2) return false;
      int m = int.parse(parts[0]);
      int y = 2000 + int.parse(parts[1]);
      DateTime lastDay = DateTime(y, m + 1, 0);
      DateTime today = DateTime.now();
      int days = lastDay.difference(today).inDays;
      return days >= 0 && days <= 90;
    } catch (_) {
      return false;
    }
  }

  bool _isExpired(String expStr) {
    try {
      final parts = expStr.split('/');
      if (parts.length != 2) return false;
      int m = int.parse(parts[0]);
      int y = 2000 + int.parse(parts[1]);
      DateTime lastDay = DateTime(y, m + 1, 0);
      return lastDay.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // 0. SEARCHABLE PRODUCT SELECTION MODAL
  // ===========================================================================
  Future<Medicine?> _showProductSearchPickerModal(PharoahWebManager webPh) async {
    return await showDialog<Medicine>(
      context: context,
      builder: (ctx) {
        String modalSearch = "";
        return StatefulBuilder(
          builder: (context, setModalState) {
            final q = modalSearch.trim().toLowerCase();
            final results = q.isEmpty
                ? webPh.medicines
                : webPh.medicines.where((m) =>
                    m.name.toLowerCase().contains(q) ||
                    m.systemId.toLowerCase().contains(q) ||
                    m.packing.toLowerCase().contains(q)).toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.white12),
              ),
              title: Row(
                children: [
                  const Icon(Icons.inventory_2_rounded, color: Color(0xFF38BDF8), size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "SEARCH & SELECT PRODUCT ITEM",
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SizedBox(
                width: 580,
                height: 480,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "Search medicine by name, brand, or system ID...",
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                        suffixIcon: modalSearch.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                                onPressed: () => setModalState(() => modalSearch = ""),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.black26,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => setModalState(() => modalSearch = v),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: results.isEmpty
                          ? Center(
                              child: Text(
                                "No products match '$modalSearch'",
                                style: const TextStyle(color: Colors.white38, fontSize: 12),
                              ),
                            )
                          : ListView.separated(
                              itemCount: results.length,
                              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                              itemBuilder: (c, i) {
                                final m = results[i];
                                final batchesCount = webPh.batchHistory[m.identityKey]?.length ?? 0;
                                return ListTile(
                                  dense: true,
                                  leading: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black38,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      m.systemId,
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(
                                    m.name,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    "Pack: ${m.packing} • MRP ₹${m.mrp.toStringAsFixed(2)} • Pur ₹${m.purRate.toStringAsFixed(2)} • Stock: ${m.stock.toInt()} Units",
                                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: batchesCount > 0 ? const Color(0xFF34D399).withOpacity(0.15) : Colors.amber.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "$batchesCount Batches",
                                      style: TextStyle(
                                        color: batchesCount > 0 ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  onTap: () => Navigator.pop(ctx, m),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // 1. REGISTER NEW BATCH DIALOG (WITH D1 SYNC)
  // ===========================================================================
  void _showAddBatchDialog(PharoahWebManager webPh, [Medicine? defaultMed]) {
    Medicine? targetMed = defaultMed ?? selectedMed;
    if (targetMed == null && webPh.medicines.isNotEmpty) {
      targetMed = webPh.medicines.first;
    }
    if (targetMed == null) return;

    Medicine chosenMed = targetMed;
    final batchNoC = TextEditingController();
    final expC = TextEditingController();
    final mrpC = TextEditingController(text: chosenMed.mrp.toStringAsFixed(2));
    final purRateC = TextEditingController(text: chosenMed.purRate.toStringAsFixed(2));
    final rateAC = TextEditingController(text: chosenMed.rateA.toStringAsFixed(2));
    final rateBC = TextEditingController(text: chosenMed.rateB.toStringAsFixed(2));
    final rateCC = TextEditingController(text: chosenMed.rateC.toStringAsFixed(2));
    final openingQtyC = TextEditingController(text: "0");

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white12),
          ),
          title: Row(
            children: [
              const Icon(Icons.add_box_rounded, color: Color(0xFF38BDF8), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "REGISTER NEW BATCH • ${chosenMed.name}",
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (defaultMed == null) ...[
                    InkWell(
                      onTap: () async {
                        final picked = await _showProductSearchPickerModal(webPh);
                        if (picked != null) {
                          setDialogState(() {
                            chosenMed = picked;
                            mrpC.text = picked.mrp.toStringAsFixed(2);
                            purRateC.text = picked.purRate.toStringAsFixed(2);
                            rateAC.text = picked.rateA.toStringAsFixed(2);
                            rateBC.text = picked.rateB.toStringAsFixed(2);
                            rateCC.text = picked.rateC.toStringAsFixed(2);
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "PRODUCT ITEM (CLICK TO SEARCH / CHANGE) *",
                                    style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    "${chosenMed.name} (${chosenMed.systemId}) • Stock: ${chosenMed.stock.toInt()}",
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text("CHANGE", style: TextStyle(color: Color(0xFF60A5FA), fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
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

                final medKey = chosenMed.identityKey;
                if (!webPh.batchHistory.containsKey(medKey)) {
                  webPh.batchHistory[medKey] = [];
                }

                bool exists = webPh.batchHistory[medKey]!.any((b) => b.batch.trim() == bNo);
                if (exists) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Batch '$bNo' already exists for ${chosenMed.name}"),
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
                  packing: chosenMed.packing,
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
      ),
    );
  }

  // ===========================================================================
  // 2. PHARMA COMPLIANCE STATUS TOGGLE DIALOG
  // ===========================================================================
  void _showPharmaStatusDialog(PharoahWebManager webPh, Medicine med, BatchInfo b) {
    String currentStatus = b.status.isNotEmpty ? b.status : "Active";

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white12),
          ),
          title: Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: Color(0xFF38BDF8), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "PHARMA COMPLIANCE STATUS • ${b.batch}",
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Product: ${med.name} (${med.systemId})",
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 14),
              const Text(
                "REGULATORY STATUS:",
                style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: "Active",
                label: "ACTIVE (DISPENSABLE)",
                desc: "Batch is compliant and available for Sale and Billing.",
                color: const Color(0xFF10B981),
                isSelected: currentStatus == "Active",
                onSelect: () => setDialogState(() => currentStatus = "Active"),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: "Hold",
                label: "HOLD / QUARANTINE",
                desc: "Under inspection or sample testing. Blocked from billing.",
                color: const Color(0xFFF59E0B),
                isSelected: currentStatus == "Hold",
                onSelect: () => setDialogState(() => currentStatus = "Hold"),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: "Blocked",
                label: "BLOCKED / RECALLED",
                desc: "Defective or recalled batch. Strictly blocked from distribution.",
                color: const Color(0xFFEF4444),
                isSelected: currentStatus == "Blocked",
                onSelect: () => setDialogState(() => currentStatus = "Blocked"),
              ),
            ],
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                b.status = currentStatus;

                // 📤 Enqueue D1 mutation
                BatchSyncModule.onBatchSaved(
                  batch: b,
                  medIdentityKey: med.identityKey,
                  storeToken: webPh.activeStoreToken,
                  isDelete: false,
                );

                webPh.rebuildInventory();
                Navigator.pop(c);
                setState(() {});

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Batch '${b.batch}' status updated to $currentStatus!"),
                    backgroundColor: const Color(0xFF059669),
                  ),
                );
              },
              child: const Text("APPLY STATUS", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOption({
    required String status,
    required String label,
    required String desc,
    required Color color,
    required bool isSelected,
    required VoidCallback onSelect,
  }) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.black26,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? color : Colors.white12, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? color : Colors.white38,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 3. CASCADE RENAME & EDIT BATCH DIALOG
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
  // 4. SAFE BATCH DELETION WITH FINANCIAL YEAR INTEGRITY CHECK
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
  // 5. STOCK ADJUSTMENT DIALOG
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
  // 6. EXCEL / CSV EXPORT ENGINE
  // ===========================================================================
  Future<void> _exportBatchesCsv(PharoahWebManager webPh, List<GlobalBatchItem> items, String activeFY) async {
    final List<List<dynamic>> rows = [];
    final shopName = (webPh.companyProfile['name'] ?? webPh.companyName ?? 'PHAROAH STORE').toString().toUpperCase();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    rows.add(["STORE:", shopName, "", "EXPORT DATE:", dateStr, "", "ACTIVE FY:", activeFY]);
    rows.add(["REPORT:", "CENTRAL BATCH MASTER INVENTORY AUDIT", "", "FILTER:", activeFilter, "", "TOTAL BATCHES:", items.length]);
    rows.add([]); // empty row

    // Headers
    rows.add([
      "SR NO",
      "ITEM CODE",
      "PRODUCT NAME",
      "PACKING",
      "BATCH NO",
      "EXPIRY",
      "STATUS",
      "PUR. RATE (RS)",
      "MRP (RS)",
      "RATE A (RS)",
      "RATE B (RS)",
      "RATE C (RS)",
      "LIVE STOCK QTY",
      "VALUATION (RS)",
      "FY AUDIT STATUS"
    ]);

    int sr = 1;
    for (var it in items) {
      final m = it.medicine;
      final b = it.batch;
      final purRate = b.purRate > 0 ? b.purRate : b.rate;
      final valuation = b.qty > 0 ? (purRate * b.qty) : 0.0;

      final locking = BatchCascadeEngine.checkActiveFYUsage(
        medicine: m,
        batchNo: b.batch,
        activeFY: activeFY,
        sales: webPh.sales,
        purchases: webPh.purchases,
        saleChallans: webPh.saleChallans,
        purchaseChallans: webPh.purchaseChallans,
        saleReturns: webPh.saleReturns,
        purchaseReturns: webPh.purchaseReturns,
      );

      final fyStatus = locking.isNotEmpty ? "LOCKED (${locking.length} TXN)" : "DELETABLE ORPHAN";

      rows.add([
        sr++,
        m.systemId.isNotEmpty ? m.systemId : m.id,
        m.name.toUpperCase(),
        m.packing,
        b.batch,
        b.exp,
        b.status.isNotEmpty ? b.status.toUpperCase() : "ACTIVE",
        purRate.toStringAsFixed(2),
        b.mrp.toStringAsFixed(2),
        b.rateA.toStringAsFixed(2),
        b.rateB.toStringAsFixed(2),
        b.rateC.toStringAsFixed(2),
        b.qty.toInt(),
        valuation.toStringAsFixed(2),
        fyStatus,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final fileDate = DateFormat('ddMMMyy_HHmm').format(DateTime.now());

    await FileSaver.instance.saveFile(
      name: "Batch_Master_Audit_${activeFilter}_$fileDate",
      bytes: bytes,
      ext: "csv",
      mimeType: MimeType.csv,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Exported ${items.length} batches to Excel CSV successfully!"),
        backgroundColor: const Color(0xFF059669),
      ),
    );
  }

  // ===========================================================================
  // 7. MAIN BUILD
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

    // 1. Gather all batches across the entire inventory
    final List<GlobalBatchItem> allBatches = [];
    double totalStockUnits = 0.0;
    double totalValuation = 0.0;
    double expiryRiskValuation = 0.0;
    int nearExpiryCount = 0;

    for (var m in webPh.medicines) {
      final list = webPh.batchHistory[m.identityKey];
      if (list != null && list.isNotEmpty) {
        for (var b in list) {
          allBatches.add(GlobalBatchItem(medicine: m, batch: b));
          if (b.qty > 0) {
            totalStockUnits += b.qty;
            final double val = (b.purRate > 0 ? b.purRate : b.rate) * b.qty;
            totalValuation += val;
            if (_isNearExpiry(b.exp) || _isExpired(b.exp)) {
              nearExpiryCount++;
              expiryRiskValuation += val;
            }
          }
        }
      }
    }

    // 2. Filter batches based on Search Query and Active Filter Tab
    final query = searchQuery.trim().toLowerCase();

    // Match products for instant live product list dropdown
    final List<Medicine> matchingMeds = query.isEmpty
        ? <Medicine>[]
        : webPh.medicines.where((m) =>
            m.name.toLowerCase().contains(query) ||
            m.systemId.toLowerCase().contains(query) ||
            m.packing.toLowerCase().contains(query)).take(8).toList();

    List<GlobalBatchItem> filteredBatches = allBatches.where((item) {
      final m = item.medicine;
      final b = item.batch;

      // Search match
      if (query.isNotEmpty) {
        final matchesName = m.name.toLowerCase().contains(query);
        final matchesId = m.systemId.toLowerCase().contains(query);
        final matchesBatch = b.batch.toLowerCase().contains(query);
        final matchesExp = b.exp.toLowerCase().contains(query);
        if (!matchesName && !matchesId && !matchesBatch && !matchesExp) {
          return false;
        }
      }

      // If Product Drill-down mode is active, filter only for selected medicine
      if (!isGlobalExplorer && selectedMed != null) {
        if (m.identityKey != selectedMed!.identityKey) return false;
      }

      // Filter tabs
      switch (activeFilter) {
        case "IN_STOCK":
          return b.qty > 0;
        case "ZERO_STOCK":
          return b.qty <= 0;
        case "EXPIRING":
          return _isNearExpiry(b.exp);
        case "EXPIRED":
          return _isExpired(b.exp);
        case "HOLD_BLOCKED":
          return b.status == "Hold" || b.status == "Blocked";
        case "FY_LOCKED":
          final lockings = BatchCascadeEngine.checkActiveFYUsage(
            medicine: m,
            batchNo: b.batch,
            activeFY: activeFY,
            sales: webPh.sales,
            purchases: webPh.purchases,
            saleChallans: webPh.saleChallans,
            purchaseChallans: webPh.purchaseChallans,
            saleReturns: webPh.saleReturns,
            purchaseReturns: webPh.purchaseReturns,
          );
          return lockings.isNotEmpty;
        case "ALL":
        default:
          return true;
      }
    }).toList();

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
          // --- TOP BREADCRUMB & CONTROLS ---
          _buildTopBar(webPh, activeFY, filteredBatches),
          const SizedBox(height: 16),

          // --- VALUATION KPI STRIP ---
          _buildKpiStrip(
            totalBatches: allBatches.length,
            totalStockUnits: totalStockUnits,
            totalValuation: totalValuation,
            expiryRiskValuation: expiryRiskValuation,
            nearExpiryCount: nearExpiryCount,
          ),
          const SizedBox(height: 16),

          // --- TOOLBAR (SEARCH + DUAL MODE SWITCH + FILTER TABS) ---
          _buildFilterToolbar(webPh, filteredBatches, matchingMeds),
          const SizedBox(height: 16),

          // --- PRODUCT FOCUS BANNER (IF IN DRILL-DOWN MODE) ---
          if (!isGlobalExplorer && selectedMed != null) ...[
            _buildProductFocusBanner(webPh, selectedMed!),
            const SizedBox(height: 12),
          ],

          // --- MAIN DATA TABLE OR EMPTY STATE ---
          Expanded(
            child: filteredBatches.isEmpty
                ? _buildEmptyState(webPh)
                : _buildBatchesTable(webPh, filteredBatches, activeFY),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 8. TOP BAR & BREADCRUMBS
  // ===========================================================================
  Widget _buildTopBar(PharoahWebManager webPh, String activeFY, List<GlobalBatchItem> currentItems) {
    return Row(
      children: [
        IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 20),
          tooltip: "Back to Masters Hub",
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "CENTRAL BATCH COMMAND CENTER",
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
              "Autonomous batch mirroring, cascade editing across all transactions, pharma compliance, and FY integrity shielding.",
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        const Spacer(),

        // Export Button
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF34D399),
            side: const BorderSide(color: Color(0xFF34D399)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _exportBatchesCsv(webPh, currentItems, activeFY),
          icon: const Icon(Icons.download_rounded, size: 16),
          label: const Text("EXPORT EXCEL (CSV)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        ),
        const SizedBox(width: 10),

        // New Batch Button
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _showAddBatchDialog(webPh),
          icon: const Icon(Icons.add, size: 16),
          label: const Text("NEW BATCH", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      ],
    );
  }

  // ===========================================================================
  // 9. VALUATION KPI STRIP
  // ===========================================================================
  Widget _buildKpiStrip({
    required int totalBatches,
    required double totalStockUnits,
    required double totalValuation,
    required double expiryRiskValuation,
    required int nearExpiryCount,
  }) {
    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            title: "TOTAL BATCHES",
            value: NumberFormat("#,##0").format(totalBatches),
            subtitle: "Across entire catalog",
            icon: Icons.layers_outlined,
            color: const Color(0xFF38BDF8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            title: "LIVE STOCK UNITS",
            value: NumberFormat("#,##0").format(totalStockUnits),
            subtitle: "Dispensable units",
            icon: Icons.inventory_2_outlined,
            color: const Color(0xFF34D399),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            title: "TOTAL VALUATION",
            value: "₹${NumberFormat("#,##,##0.00").format(totalValuation)}",
            subtitle: "At Purchase Rate",
            icon: Icons.account_balance_wallet_outlined,
            color: const Color(0xFF60A5FA),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            title: "EXPIRY RISK (≤90D)",
            value: "₹${NumberFormat("#,##,##0.00").format(expiryRiskValuation)}",
            subtitle: "$nearExpiryCount batch lots at risk",
            icon: Icons.warning_amber_rounded,
            color: nearExpiryCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 10. FILTER TOOLBAR & DUAL MODE SWITCH
  // ===========================================================================
  Widget _buildFilterToolbar(PharoahWebManager webPh, List<GlobalBatchItem> currentItems, List<Medicine> matchingMeds) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Search Input
              Expanded(
                child: TextField(
                  controller: searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: isGlobalExplorer
                        ? "Search by Medicine Name, Batch No, or System ID..."
                        : "Search batches of '${selectedMed?.name ?? "selected product"}'...",
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 16),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54, size: 14),
                            onPressed: () {
                              searchController.clear();
                              setState(() => searchQuery = "");
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setState(() => searchQuery = v),
                ),
              ),
              const SizedBox(width: 10),

              // Quick Product Catalog Picker Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: const BorderSide(color: Color(0xFF38BDF8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final picked = await _showProductSearchPickerModal(webPh);
                  if (picked != null) {
                    setState(() {
                      selectedMed = picked;
                      isGlobalExplorer = false;
                      searchQuery = "";
                      searchController.clear();
                    });
                  }
                },
                icon: const Icon(Icons.inventory_2_outlined, size: 15),
                label: const Text("PRODUCT CATALOG", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),

              // Mode Toggle (Global Explorer vs Product Focus)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _modeButton(
                      label: "GLOBAL EXPLORER",
                      icon: Icons.public_rounded,
                      isActive: isGlobalExplorer,
                      onTap: () => setState(() {
                        isGlobalExplorer = true;
                      }),
                    ),
                    _modeButton(
                      label: "PRODUCT FOCUS",
                      icon: Icons.filter_center_focus_rounded,
                      isActive: !isGlobalExplorer,
                      onTap: () {
                        if (selectedMed == null && webPh.medicines.isNotEmpty) {
                          selectedMed = webPh.medicines.first;
                        }
                        setState(() {
                          isGlobalExplorer = false;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Matching Products Dropdown / Autocomplete (appears when user searches)
          if (searchQuery.trim().isNotEmpty && matchingMeds.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withOpacity(0.12),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.medication_liquid_rounded, color: Color(0xFF38BDF8), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          "MATCHING PRODUCTS (${matchingMeds.length}) — Click to focus product and manage its batches",
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            setState(() {
                              searchQuery = "";
                              searchController.clear();
                            });
                          },
                          child: const Text("Dismiss", style: TextStyle(color: Colors.white38, fontSize: 10)),
                        ),
                      ],
                    ),
                  ),
                  ...matchingMeds.map((med) {
                    final bList = webPh.batchHistory[med.identityKey] ?? [];
                    final isCur = selectedMed?.identityKey == med.identityKey && !isGlobalExplorer;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          selectedMed = med;
                          isGlobalExplorer = false;
                          searchQuery = "";
                          searchController.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isCur ? const Color(0xFF2563EB).withOpacity(0.18) : Colors.transparent,
                          border: const Border(bottom: BorderSide(color: Colors.white10)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                med.systemId,
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    med.name,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    "Pack: ${med.packing} • MRP ₹${med.mrp.toStringAsFixed(2)} • Pur ₹${med.purRate.toStringAsFixed(2)} • Stock: ${med.stock.toInt()} Units",
                                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: bList.isNotEmpty ? const Color(0xFF34D399).withOpacity(0.15) : Colors.amber.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                bList.isNotEmpty ? "${bList.length} BATCHES" : "0 BATCHES",
                                style: TextStyle(
                                  color: bList.isNotEmpty ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: () {
                                setState(() {
                                  selectedMed = med;
                                  isGlobalExplorer = false;
                                  searchQuery = "";
                                  searchController.clear();
                                });
                              },
                              icon: const Icon(Icons.remove_red_eye_rounded, size: 12),
                              label: const Text("VIEW BATCHES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF38BDF8),
                                side: const BorderSide(color: Color(0xFF38BDF8)),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: () => _showAddBatchDialog(webPh, med),
                              icon: const Icon(Icons.add, size: 12),
                              label: const Text("ADD BATCH", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip("ALL", "ALL BATCHES"),
                _filterChip("IN_STOCK", "IN STOCK (>0)"),
                _filterChip("ZERO_STOCK", "ZERO / SHORT (≤0)"),
                _filterChip("EXPIRING", "EXPIRING SOON (≤90D)"),
                _filterChip("EXPIRED", "EXPIRED"),
                _filterChip("HOLD_BLOCKED", "HOLD / BLOCKED"),
                _filterChip("FY_LOCKED", "FY-LOCKED (PROTECTED)"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isActive ? Colors.white : Colors.white54),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white54,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String filterKey, String label) {
    final bool isSelected = activeFilter == filterKey;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => setState(() => activeFilter = filterKey),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF38BDF8).withOpacity(0.2) : Colors.black12,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isSelected ? const Color(0xFF38BDF8) : Colors.white12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF38BDF8) : Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 11. PRODUCT FOCUS BANNER (WHEN IN DRILL-DOWN MODE)
  // ===========================================================================
  Widget _buildProductFocusBanner(PharoahWebManager webPh, Medicine med) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.medication_rounded, color: Color(0xFF38BDF8), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      med.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "ID: ${med.systemId}",
                        style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
                Text(
                  "PACK: ${med.packing} • CONV: ${med.conversion} • HSN: ${med.hsnCode} • TOTAL STOCK: ${med.stock.toInt()} Units",
                  style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () => _showAddBatchDialog(webPh, med),
            icon: const Icon(Icons.add, size: 14),
            label: const Text("NEW BATCH", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF38BDF8),
              side: const BorderSide(color: Color(0xFF38BDF8)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () async {
              final picked = await _showProductSearchPickerModal(webPh);
              if (picked != null) {
                setState(() {
                  selectedMed = picked;
                  isGlobalExplorer = false;
                });
              }
            },
            icon: const Icon(Icons.swap_horiz_rounded, size: 14),
            label: const Text("CHANGE PRODUCT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF38BDF8),
              side: const BorderSide(color: Color(0xFF38BDF8)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () => setState(() => _viewingTraceabilityMed = med),
            icon: const Icon(Icons.timeline_rounded, size: 14),
            label: const Text("TRACEABILITY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
            tooltip: "Return to Global Explorer",
            onPressed: () => setState(() {
              isGlobalExplorer = true;
            }),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 12. BATCHES DATA TABLE (ENTERPRISE SLATE)
  // ===========================================================================
  Widget _buildBatchesTable(PharoahWebManager webPh, List<GlobalBatchItem> items, String activeFY) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ListView(
          children: [
            // Table Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: const Color(0xFF0F172A),
              child: Row(
                children: [
                  if (isGlobalExplorer)
                    const Expanded(flex: 4, child: Text("PRODUCT NAME & ID", style: _thStyle)),
                  const Expanded(flex: 3, child: Text("BATCH NO", style: _thStyle)),
                  const Expanded(flex: 2, child: Text("EXPIRY", style: _thStyle)),
                  const Expanded(flex: 2, child: Text("PUR. RATE ₹", style: _thStyle)),
                  const Expanded(flex: 2, child: Text("MRP ₹", style: _thStyle)),
                  const Expanded(flex: 3, child: Text("RATE A / B / C", style: _thStyle)),
                  const Expanded(flex: 2, child: Text("LIVE STOCK", style: _thStyle)),
                  const Expanded(flex: 2, child: Text("PHARMA STATUS", style: _thStyle)),
                  const Expanded(flex: 3, child: Text("FY AUDIT STATUS", style: _thStyle)),
                  const Expanded(flex: 3, child: Text("ACTIONS", style: _thStyle)),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),

            // Rows
            ...items.map((item) {
              final m = item.medicine;
              final b = item.batch;

              final lockingRecords = BatchCascadeEngine.checkActiveFYUsage(
                medicine: m,
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
              final bool nearExp = _isNearExpiry(b.exp);
              final bool exp = _isExpired(b.exp);

              Color statusColor = const Color(0xFF10B981);
              if (b.status == "Hold") statusColor = const Color(0xFFF59E0B);
              if (b.status == "Blocked") statusColor = const Color(0xFFEF4444);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    // Product Column (in Global Explorer mode)
                    if (isGlobalExplorer)
                      Expanded(
                        flex: 4,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              selectedMed = m;
                              isGlobalExplorer = false;
                            });
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                "ID: ${m.systemId} • ${m.packing}",
                                style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 9.5),
                              ),
                            ],
                          ),
                        ),
                      ),

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
                          if (nearExp)
                            const Text(
                              "NEAR EXPIRY",
                              style: TextStyle(color: Color(0xFFFBBF24), fontSize: 8.5, fontWeight: FontWeight.bold),
                            )
                          else if (exp)
                            const Text(
                              "EXPIRED",
                              style: TextStyle(color: Color(0xFFF87171), fontSize: 8.5, fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                    ),

                    // Expiry
                    Expanded(
                      flex: 2,
                      child: Text(
                        b.exp,
                        style: TextStyle(
                          color: exp ? const Color(0xFFF87171) : (nearExp ? const Color(0xFFFBBF24) : Colors.white70),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // Pur Rate
                    Expanded(
                      flex: 2,
                      child: Text(
                        "₹${(b.purRate > 0 ? b.purRate : b.rate).toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontFamily: 'monospace'),
                      ),
                    ),

                    // MRP
                    Expanded(
                      flex: 2,
                      child: Text(
                        "₹${b.mrp.toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                    ),

                    // Rates A/B/C
                    Expanded(
                      flex: 3,
                      child: Text(
                        "A: ${b.rateA.toStringAsFixed(1)} | B: ${b.rateB.toStringAsFixed(1)} | C: ${b.rateC.toStringAsFixed(1)}",
                        style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontFamily: 'monospace'),
                      ),
                    ),

                    // Live Stock
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: b.qty > 0 ? const Color(0xFF059669).withOpacity(0.2) : Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "${b.qty.toInt()} Qty",
                          style: TextStyle(
                            color: b.qty > 0 ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),

                    // Pharma Status (Clickable to switch)
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: () => _showPharmaStatusDialog(webPh, m, b),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: statusColor.withOpacity(0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(radius: 3, backgroundColor: statusColor),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  b.status.isNotEmpty ? b.status.toUpperCase() : "ACTIVE",
                                  style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // FY Audit Status Badge
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: () => _showDeleteBatchDialog(webPh, m, b),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
                                size: 11,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  isLockedByFY ? "LOCKED • ${lockingRecords.length} TXN" : "DELETABLE",
                                  style: TextStyle(
                                    color: isLockedByFY ? const Color(0xFFFBBF24) : const Color(0xFF34D399),
                                    fontSize: 9,
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
                            icon: const Icon(Icons.sync_alt_rounded, color: Color(0xFF60A5FA), size: 16),
                            tooltip: "Cascade Rename & Edit Rates",
                            onPressed: () => _showCascadeEditDialog(webPh, m, b),
                          ),
                          IconButton(
                            icon: const Icon(Icons.exposure_rounded, color: Color(0xFFFBBF24), size: 16),
                            tooltip: "Stock Adjustment",
                            onPressed: () => _showAdjustmentDialog(webPh, m, b),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFF87171), size: 16),
                            tooltip: "Delete Batch (FY Guarded)",
                            onPressed: () => _showDeleteBatchDialog(webPh, m, b),
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
  // 13. EMPTY STATE & INPUT HELPER
  // ===========================================================================
  Widget _buildEmptyState(PharoahWebManager webPh) {
    if (!isGlobalExplorer && selectedMed != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          constraints: const BoxConstraints(maxWidth: 540),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inventory_2_outlined, color: Color(0xFF38BDF8), size: 48),
              const SizedBox(height: 14),
              Text(
                "No Batches Registered for ${selectedMed!.name}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                "System ID: ${selectedMed!.systemId} • Pack: ${selectedMed!.packing} • Current Stock: ${selectedMed!.stock.toInt()} Units",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showAddBatchDialog(webPh, selectedMed!),
                icon: const Icon(Icons.add_box_rounded, size: 18),
                label: Text("REGISTER FIRST BATCH FOR ${selectedMed!.name.toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await _showProductSearchPickerModal(webPh);
                      if (picked != null) {
                        setState(() {
                          selectedMed = picked;
                          isGlobalExplorer = false;
                        });
                      }
                    },
                    icon: const Icon(Icons.search, size: 14, color: Colors.white54),
                    label: const Text("Select Another Product", style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ),
                  const Text(" • ", style: TextStyle(color: Colors.white24)),
                  TextButton(
                    onPressed: () => setState(() => isGlobalExplorer = true),
                    child: const Text("Return to Global Explorer", style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, color: Colors.white24, size: 52),
          const SizedBox(height: 12),
          Text(
            "No batches match '$searchQuery' under filter '$activeFilter'",
            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            "Try selecting a different filter tab, clearing your search term, or browsing the Product Catalog.",
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    searchQuery = "";
                    searchController.clear();
                    activeFilter = "ALL";
                  });
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text("RESET FILTERS"),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: const BorderSide(color: Color(0xFF38BDF8)),
                ),
                onPressed: () async {
                  final m = await _showProductSearchPickerModal(webPh);
                  if (m != null) {
                    setState(() {
                      selectedMed = m;
                      isGlobalExplorer = false;
                      searchQuery = "";
                      searchController.clear();
                    });
                  }
                },
                icon: const Icon(Icons.inventory_2_outlined, size: 16),
                label: const Text("BROWSE PRODUCT CATALOG"),
              ),
            ],
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
    fontSize: 9.5,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );
}
