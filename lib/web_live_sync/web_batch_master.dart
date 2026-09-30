// FILE: lib/web_live_sync/web_batch_master.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_expiry_master.dart';

class WebBatchMasterView extends StatefulWidget {
  final VoidCallback onBack;

  const WebBatchMasterView({super.key, required this.onBack});

  @override
  State<WebBatchMasterView> createState() => _WebBatchMasterViewState();
}

class _WebBatchMasterViewState extends State<WebBatchMasterView> {
  Medicine? selectedMed;
  String searchQuery = "";

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
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Text(
          "ADD MANUAL BATCH • ${med.name}",
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 480,
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
                _inputField("INITIAL / OPENING STOCK QTY", openingQtyC, isNum: true),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (batchNoC.text.trim().isEmpty || expC.text.trim().isEmpty) return;

              double q = double.tryParse(openingQtyC.text) ?? 0.0;
              double pur = double.tryParse(purRateC.text) ?? 0.0;
              double mrp = double.tryParse(mrpC.text) ?? 0.0;
              double a = double.tryParse(rateAC.text) ?? mrp;
              double b = double.tryParse(rateBC.text) ?? (a * 0.95);
              double rateCVal = double.tryParse(rateCC.text) ?? (a * 0.92);

              final newBatch = BatchInfo(
                batch: batchNoC.text.trim(),
                exp: expC.text.trim(),
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

              if (!webPh.batchHistory.containsKey(med.identityKey)) {
                webPh.batchHistory[med.identityKey] = [];
              }

              bool exists = webPh.batchHistory[med.identityKey]!.any((b) => b.batch.trim() == newBatch.batch.trim());
              if (!exists) {
                webPh.batchHistory[med.identityKey]!.add(newBatch);
                webPh.rebuildInventory();
              }

              Navigator.pop(c);
              setState(() {});
            },
            child: const Text("SAVE BATCH", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

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
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.white12),
            ),
            title: Text(
              "ADJUST STOCK • BATCH: ${b.batch}",
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Current Live Stock: ${b.qty.toInt()} Qty",
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
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
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold),
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  double val = double.tryParse(qtyC.text) ?? 0.0;
                  if (val != 0) {
                    b.adjustmentQty += val;
                    b.adjReason = reason;
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

  void _showEditMetadataDialog(PharoahWebManager webPh, Medicine med, BatchInfo b) {
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
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Text(
          "EDIT BATCH PRICING • ${b.batch}",
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              b.exp = expC.text.trim();
              b.mrp = double.tryParse(mrpC.text) ?? b.mrp;
              b.purRate = double.tryParse(purRateC.text) ?? b.purRate;
              b.rate = b.purRate;
              b.rateA = double.tryParse(rateAC.text) ?? b.rateA;
              b.rateB = double.tryParse(rateBC.text) ?? b.rateB;
              b.rateC = double.tryParse(rateCC.text) ?? b.rateC;

              webPh.rebuildInventory();
              Navigator.pop(c);
              setState(() {});
            },
            child: const Text("SAVE PRICING", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final filteredMeds = webPh.medicines.where((m) =>
        m.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
        m.systemId.toLowerCase().contains(searchQuery.toLowerCase())).toList();

    List<BatchInfo> batches = [];
    if (selectedMed != null) {
      batches = webPh.batchHistory[selectedMed!.identityKey] ?? [];
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.layers_rounded, color: Color(0xFF38BDF8), size: 22),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "CENTRAL BATCH & EXPIRY MASTER",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  Text(
                    "Select medicine to trace, adjust stock or modify batch pricing",
                    style: TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
              const Spacer(),
              if (selectedMed != null)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () => _showAddBatchDialog(webPh, selectedMed!),
                  icon: const Icon(Icons.add_box_rounded, size: 18),
                  label: const Text("ADD BATCH TO ITEM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                ),
            ],
          ),
          const Divider(color: Colors.white10, height: 25),

          // Product Selector Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: selectedMed == null
                ? Autocomplete<Medicine>(
                    displayStringForOption: (m) => "${m.name} (${m.packing}) - Stock: ${m.stock.toInt()}",
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text.isEmpty) return const Iterable.empty();
                      return filteredMeds.where((m) =>
                          m.name.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                          m.systemId.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                    },
                    onSelected: (m) => setState(() => selectedMed = m),
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          hintText: "Type Medicine Name or ID to select product...",
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 11.5),
                          prefixIcon: Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      );
                    },
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0x332563EB),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.medication_rounded, color: Color(0xFF38BDF8), size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${selectedMed!.name} (${selectedMed!.packing})",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                            Text(
                              "ID: ${selectedMed!.systemId} • Total Inventory Stock: ${selectedMed!.stock.toInt()} Qty",
                              style: const TextStyle(color: Colors.cyanAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
                        tooltip: "Clear Product Selection",
                        onPressed: () => setState(() => selectedMed = null),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),

          // Batches Table
          Expanded(
            child: selectedMed == null
                ? const Center(
                    child: Text(
                      "Search and select a medicine above to view and manage its batch records.",
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                : (batches.isEmpty
                    ? const Center(
                        child: Text(
                          "No batches recorded for this medicine.\nClick 'Add Batch To Item' to create one.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      )
                    : SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 800),
                          child: Table(
                            columnWidths: const {
                              0: FixedColumnWidth(120),
                              1: FixedColumnWidth(110),
                              2: FixedColumnWidth(90),
                              3: FixedColumnWidth(90),
                              4: FixedColumnWidth(90),
                              5: FixedColumnWidth(110),
                              6: FixedColumnWidth(140),
                            },
                            children: [
                              TableRow(
                                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                                children: [
                                  _th("BATCH NO", isLeft: true),
                                  _th("EXPIRY"),
                                  _th("MRP"),
                                  _th("PUR. RATE"),
                                  _th("RATE A"),
                                  _th("LIVE STOCK"),
                                  _th("ACTIONS"),
                                ],
                              ),
                              for (final b in batches)
                                TableRow(
                                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                                  children: [
                                    _td(b.batch, isLeft: true, isBold: true),
                                    _tdExpiry(b.exp),
                                    _td("₹${b.mrp.toStringAsFixed(2)}"),
                                    _td("₹${b.purRate.toStringAsFixed(2)}"),
                                    _td("₹${b.rateA.toStringAsFixed(2)}"),
                                    _td("${b.qty.toInt()} Qty", isBold: true, color: b.qty > 0 ? Colors.greenAccent : Colors.redAccent),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orangeAccent,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            elevation: 0,
                                          ),
                                          onPressed: () => _showAdjustmentDialog(webPh, selectedMed!, b),
                                          icon: const Icon(Icons.exposure_rounded, size: 14),
                                          label: const Text("ADJUST", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 6),
                                        IconButton(
                                          icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF38BDF8)),
                                          tooltip: "Edit Pricing",
                                          onPressed: () => _showEditMetadataDialog(webPh, selectedMed!, b),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      )),
          ),
        ],
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
    child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
  );

  Widget _tdExpiry(String exp) {
    final color = WebExpiryMaster.getStatusColor(exp);
    final status = WebExpiryMaster.getStatus(exp);
    String label = "Safe";
    if (status == ExpiryStatus.expired) label = "Expired";
    if (status == ExpiryStatus.nearExpiry) label = "Near Exp";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(exp, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: color == Colors.green ? const Color(0x3310B981) : (color == Colors.red ? const Color(0x33DC2626) : const Color(0x33F59E0B)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(label, style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, {bool isNum = false, bool isCaps = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}
