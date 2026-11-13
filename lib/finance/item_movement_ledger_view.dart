import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../../pdf/statements/item_ledger_pdf.dart';

class ItemMovementLedgerView extends StatefulWidget {
  const ItemMovementLedgerView({super.key});
  @override State<ItemMovementLedgerView> createState() => _ItemMovementLedgerViewState();
}

class _ItemMovementLedgerViewState extends State<ItemMovementLedgerView> {
  Medicine? selectedMed;
  String medSearch = "";

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    List<Map<String, dynamic>> movement = [];
    if (selectedMed != null) movement = _calculateMovement(ph);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(selectedMed == null ? "Item Ledger" : selectedMed!.name),
        backgroundColor: Colors.blue.shade900,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf), 
            onPressed: () async {
              if (selectedMed == null) return;
              await ItemLedgerPdf.generate(
                shop: ph.activeCompany!,
                med: selectedMed!,
                movementData: movement.reversed.toList(),
              );
            }
          )
        ],
      ),
      body: Column(children: [
        _buildMedicineSelector(ph),
        if (selectedMed != null) _buildProductQuickStats(),
        Expanded(child: selectedMed == null ? _buildInitialState(ph) : _buildMovementTimeline(movement)),
      ]),
    );
  }

  List<Map<String, dynamic>> _calculateMovement(PharoahManager ph) {
    bool matchesMed(String mId) =>
        mId == selectedMed!.id ||
        (selectedMed!.identityKey.isNotEmpty && mId == selectedMed!.identityKey);

    List<Map<String, dynamic>> history = [];
    for (var p in ph.purchases.where((p) => p.isDeleted != 1)) {
      for (var it in p.items.where((it) => matchesMed(it.medicineID))) {
        history.add({'date': p.date, 'type': 'PURCHASE', 'party': p.distributorName, 'in': it.qty + it.freeQty, 'out': 0.0, 'batch': it.batch, 'ref': p.billNo});
      }
    }
    for (var s in ph.sales.where((s) => s.isDeleted != 1 && (s.status.isEmpty || s.status == "Active"))) {
      for (var it in s.items.where((it) => matchesMed(it.medicineID))) {
        history.add({'date': s.date, 'type': 'SALE', 'party': s.partyName, 'in': 0.0, 'out': it.qty + it.freeQty, 'batch': it.batch, 'ref': s.billNo});
      }
    }
    for (var r in ph.saleReturns.where((r) => r.isDeleted != 1 && (r.status.isEmpty || r.status == "Active"))) {
      for (var it in r.items.where((it) => matchesMed(it.medicineID) && !it.isBreakage)) {
        history.add({'date': r.date, 'type': 'SALE RETURN', 'party': r.partyName, 'in': it.qty + it.freeQty, 'out': 0.0, 'batch': it.batch, 'ref': r.billNo});
      }
    }
    for (var r in ph.purchaseReturns.where((r) => r.isDeleted != 1 && (r.status.isEmpty || r.status == "Active"))) {
      for (var it in r.items.where((it) => matchesMed(it.medicineID))) {
        history.add({'date': r.date, 'type': 'PURCHASE RETURN', 'party': r.distributorName, 'in': 0.0, 'out': it.qty + it.freeQty, 'batch': it.batch, 'ref': r.billNo});
      }
    }
    history.sort((a, b) => a['date'].compareTo(b['date']));
    final batches = ph.batchHistory[selectedMed!.identityKey] ?? [];
    double runningStock = batches.fold(0.0, (sum, b) => sum + b.openingQty + b.adjustmentQty);
    for (var entry in history) {
      runningStock += (entry['in'] - entry['out']);
      entry['bal'] = runningStock;
    }
    return history.reversed.toList();
  }

  Widget _buildMedicineSelector(PharoahManager ph) => Container(
    padding: const EdgeInsets.all(15), color: Colors.white,
    child: selectedMed == null 
      ? TextField(decoration: const InputDecoration(hintText: "Search Product...", prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => medSearch = v))
      : ListTile(tileColor: Colors.blue.shade50, title: Text(selectedMed!.name), trailing: IconButton(icon: const Icon(Icons.cancel), onPressed: () => setState(() => selectedMed = null))),
  );

  Widget _buildProductQuickStats() => Container(
    padding: const EdgeInsets.all(10), color: Colors.blue.shade900,
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      _quickStat("STOCK", "${formatQty(selectedMed!.stock)}"),
      _quickStat("MRP", "₹${selectedMed!.mrp}"),
    ]),
  );

  Widget _buildMovementTimeline(List<Map<String, dynamic>> data) => ListView.builder(
    itemCount: data.length,
    itemBuilder: (c, i) => ListTile(
      title: Text(data[i]['party']),
      subtitle: Text("${data[i]['type']} | Bal: ${data[i]['bal']}"),
      trailing: Text("${data[i]['in'] > 0 ? '+' : '-'}${data[i]['in'] > 0 ? data[i]['in'] : data[i]['out']}"),
    ),
  );

  Widget _buildInitialState(PharoahManager ph) {
    final list = ph.medicines.where((m) => m.name.toLowerCase().contains(medSearch.toLowerCase())).toList();
    return ListView.builder(itemCount: list.length, itemBuilder: (c, i) => ListTile(title: Text(list[i].name), onTap: () => setState(() => selectedMed = list[i])));
  }

  Widget _quickStat(String l, String v) => Column(children: [Text(l, style: const TextStyle(color: Colors.white70, fontSize: 8)), Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]);
}
