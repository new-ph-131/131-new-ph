// FILE: lib/batch_master_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';

class BatchMasterView extends StatefulWidget {
  const BatchMasterView({super.key});

  @override
  State<BatchMasterView> createState() => _BatchMasterViewState();
}

class _BatchMasterViewState extends State<BatchMasterView> {
  Medicine? selectedMed;
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    
    List<Medicine> filteredMeds = ph.medicines.where((m) => 
      m.name.toLowerCase().contains(searchQuery.toLowerCase()) || 
      m.systemId.toLowerCase().contains(searchQuery.toLowerCase())
    ).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Central Batch Master"),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // --- 1. MEDICINE SELECTOR SECTION ---
          _buildMedicineSearchSection(ph, filteredMeds),

          // --- 2. BATCHES LIST SECTION ---
          Expanded(
            child: selectedMed == null 
              ? _buildEmptyState() 
              : _buildBatchList(ph, selectedMed!),
          ),
        ],
      ),
      // NAYA: Floating Button sirf tab dikhega jab koi Product select ho
      floatingActionButton: selectedMed != null ? FloatingActionButton.extended(
        onPressed: () => _showAddBatchDialog(ph, selectedMed!),
        backgroundColor: Colors.indigo.shade900,
        icon: const Icon(Icons.add_box, color: Colors.white),
        label: const Text("ADD NEW BATCH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ) : null,
    );
  }

  Widget _buildMedicineSearchSection(PharoahManager ph, List<Medicine> filteredMeds) {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("SELECT PRODUCT TO MANAGE BATCHES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1)),
          const SizedBox(height: 10),
          if (selectedMed == null)
            TextField(
              decoration: InputDecoration(
                hintText: "Search by Name or System ID...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true, fillColor: Colors.grey.shade50,
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            )
          else
            ListTile(
              tileColor: Colors.indigo.withOpacity(0.05),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.indigo.shade200)),
              leading: const Icon(Icons.medication, color: Colors.indigo),
              title: Text(selectedMed!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("ID: ${selectedMed!.systemId} | Total Stock: ${selectedMed!.stock}"),
              trailing: IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => setState(() => selectedMed = null)),
            ),
          
          if (selectedMed == null && searchQuery.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filteredMeds.length,
                itemBuilder: (c, i) => ListTile(
                  title: Text(filteredMeds[i].name),
                  subtitle: Text(filteredMeds[i].systemId),
                  onTap: () => setState(() { selectedMed = filteredMeds[i]; searchQuery = ""; }),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBatchList(PharoahManager ph, Medicine med) {
    List<BatchInfo> batches = ph.batchHistory[med.identityKey] ?? [];

    if (batches.isEmpty) {
      return const Center(child: Text("No batches found. Tap '+' to add one manually."));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: batches.length,
      itemBuilder: (c, i) {
        final b = batches[i];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.batch, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.indigo)),
                      Text("Expiry: ${b.exp} | MRP: ₹${b.mrp}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                    _stockBadge(b.qty),
                  ],
                ),
                const Divider(height: 25),
                Row(
                  children: [
                    _actionBtn("ADJUST", Icons.exposure, Colors.orange, () => _showAdjustmentDialog(ph, med, b)),
                    const SizedBox(width: 10),
                    _actionBtn("EDIT INFO", Icons.edit_note, Colors.blue, () => _showEditMetadataDialog(ph, med, b)),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // NAYA FEATURE: ADD BATCH MANUALLY
  // ===========================================================================
  void _showAddBatchDialog(PharoahManager ph, Medicine med) {
    final batchNoC = TextEditingController();
    final expC = TextEditingController();
    final mrpC = TextEditingController(text: med.mrp.toString());
    final rateC = TextEditingController(text: med.purRate.toString());
    final openingQtyC = TextEditingController(text: "0");

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Add Manual Batch for ${med.name}"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: batchNoC, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: "Batch Number", border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: expC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Expiry (MM/YY)", border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: mrpC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "MRP", border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: rateC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Pur. Rate", border: OutlineInputBorder()))),
              ]),
              const SizedBox(height: 12),
              TextField(controller: openingQtyC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Opening Stock Qty", border: OutlineInputBorder(), helperText: "Available stock right now")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              if (batchNoC.text.isEmpty || expC.text.isEmpty) return;
              
              final newBatch = BatchInfo(
                batch: batchNoC.text.toUpperCase().trim(),
                exp: expC.text.trim(),
                packing: med.packing,
                mrp: double.tryParse(mrpC.text) ?? 0,
                rate: double.tryParse(rateC.text) ?? 0,
                openingQty: double.tryParse(openingQtyC.text) ?? 0,
                qty: double.tryParse(openingQtyC.text) ?? 0, // Initial qty
                isShell: false,
              );

              // Update Manager Memory
              if (!ph.batchHistory.containsKey(med.identityKey)) {
                ph.batchHistory[med.identityKey] = [];
              }
              
              // Duplicate Check
              bool exists = ph.batchHistory[med.identityKey]!.any((b) => b.batch == newBatch.batch);
              if (exists) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Batch already exists!"), backgroundColor: Colors.red));
                return;
              }

              ph.batchHistory[med.identityKey]!.add(newBatch);
              ph.save().then((_) => ph.loadAllData()); // Full Save & Sync
              
              Navigator.pop(c);
            },
            child: const Text("SAVE BATCH"),
          )
        ],
      ),
    );
  }

  // --- POPUPS: ADJUST & EDIT (Preserved & Fixed) ---
  void _showAdjustmentDialog(PharoahManager ph, Medicine med, BatchInfo b) {
    final qtyC = TextEditingController();
    String reason = "Stock Correction";
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text("Adjust Stock"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Batch: ${b.batch}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              TextField(controller: qtyC, keyboardType: const TextInputType.numberWithOptions(signed: true), decoration: const InputDecoration(labelText: "Qty Change (+ or -)", border: OutlineInputBorder())),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: reason,
                decoration: const InputDecoration(labelText: "Reason", border: OutlineInputBorder()),
                items: ["Breakage", "Shortage", "Sample", "Stock Correction"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setDialogState(() => reason = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
            ElevatedButton(
              onPressed: () {
                double val = double.tryParse(qtyC.text) ?? 0;
                if (val == 0) return;
                ph.adjustBatchStock(medId: med.identityKey, batchNo: b.batch, adjQty: val, reason: reason);
                Navigator.pop(c);
              },
              child: const Text("UPDATE"),
            )
          ],
        );
      }),
    );
  }

  void _showEditMetadataDialog(PharoahManager ph, Medicine med, BatchInfo b) {
    final expC = TextEditingController(text: b.exp);
    final mrpC = TextEditingController(text: b.mrp.toString());
    final rateC = TextEditingController(text: b.rate.toString());
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Edit Batch Info"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: expC, decoration: const InputDecoration(labelText: "Expiry (MM/YY)", border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: mrpC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "MRP", border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: rateC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Purchase Rate", border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              ph.updateBatchMetadata(medId: med.identityKey, batchNo: b.batch, newExp: expC.text, newMrp: double.tryParse(mrpC.text) ?? 0, newRate: double.tryParse(rateC.text) ?? 0);
              Navigator.pop(c);
            },
            child: const Text("SAVE"),
          )
        ],
      ),
    );
  }

  // --- UI HELPERS ---
  Widget _stockBadge(double qty) {
    bool isNeg = qty < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: isNeg ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: isNeg ? Colors.red.shade200 : Colors.green.shade200)),
      child: Column(children: [
        Text(isNeg ? "SHORT" : "STOCK", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isNeg ? Colors.red : Colors.green)),
        Text(qty.toInt().toString(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isNeg ? Colors.red.shade900 : Colors.green.shade900)),
      ]),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(child: OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 14, color: color), label: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)), style: OutlinedButton.styleFrom(side: BorderSide(color: color.withOpacity(0.5)))));
  }

  Widget _buildEmptyState() {
    return const Center(child: Text("Search a product to manage batches.", style: TextStyle(color: Colors.grey)));
  }
}
