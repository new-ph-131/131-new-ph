// FILE: lib/administration/series_master_view.dart (Replacement Code - FIXED)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../pharoah_manager.dart';
import '../../models.dart';

class SeriesMasterView extends StatefulWidget {
  const SeriesMasterView({super.key});

  @override
  State<SeriesMasterView> createState() => _SeriesMasterViewState();
}

class _SeriesMasterViewState extends State<SeriesMasterView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> types = ["SALE", "PURCHASE", "CHALLAN", "RETURN",  'RECEIPT', 'PAYMENT'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: types.length, vsync: this);
  }

  // --- LOGIC: CHECK IF SERIES IS IN USE ---
  bool _isSeriesInUse(PharoahManager ph, NumberingSeries series) {
    // Basic check: If transactions exist with this prefix, lock the prefix
    List<dynamic> targetList;
    switch (series.type) {
      case "SALE": targetList = ph.sales; break;
      case "PURCHASE": targetList = ph.purchases; break;
      case "CHALLAN": targetList = [...ph.saleChallans, ...ph.purchaseChallans]; break;
      case "RETURN": targetList = [...ph.saleReturns, ...ph.purchaseReturns]; break;
      default: targetList = [];
    }

    return targetList.any((item) {
      String billNo = "";
      try {
        billNo = (series.type == "PURCHASE") ? item.internalNo : item.billNo;
      } catch (e) { billNo = ""; }
      return billNo.startsWith(series.prefix);
    });
  }

  // --- UI: SERIES FORM ---
  void _showSeriesForm({NumberingSeries? existing}) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    bool isLocked = existing != null && _isSeriesInUse(ph, existing);

    final nameC = TextEditingController(text: existing?.name);
    final prefixC = TextEditingController(text: existing?.prefix);
    final startNoC = TextEditingController(text: existing?.startNumber.toString() ?? "1");
    String selType = existing?.type ?? types[_tabController.index];
    bool isDef = existing?.isDefault ?? false;
    bool isAct = existing?.isActive ?? true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(existing == null ? "Add Numbering Series" : "Edit Series Details"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLocked) 
                  Container(
                    padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 15),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                    child: const Text("⚠️ Prefix is LOCKED because bills are already issued.", style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
                  ),
                
                DropdownButtonFormField<String>(
                  value: selType,
                  decoration: const InputDecoration(labelText: "Transaction Type", border: OutlineInputBorder()),
                  items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: isLocked ? null : (v) => setDialogState(() => selType = v!),
                ),
                const SizedBox(height: 15),
                TextField(controller: nameC, decoration: const InputDecoration(labelText: "Series Name", border: OutlineInputBorder())),
                const SizedBox(height: 15),
                TextField(
                  controller: prefixC, 
                  enabled: !isLocked,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: "Prefix (e.g. RET-)", border: OutlineInputBorder())
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: startNoC, 
                  enabled: !isLocked,
                  keyboardType: TextInputType.number, 
                  decoration: const InputDecoration(labelText: "Start From Number", border: OutlineInputBorder())
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  title: const Text("Mark as Default", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  value: isDef, 
                  onChanged: (v) => setDialogState(() => isDef = v)
                ),
                SwitchListTile(
                  title: const Text("Active (In Use)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  value: isAct, 
                  onChanged: (v) => setDialogState(() => isAct = v)
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
            ElevatedButton(
              onPressed: () {
                if (nameC.text.isEmpty || prefixC.text.isEmpty) return;

                final ns = NumberingSeries(
                  id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameC.text.trim(),
                  type: selType,
                  prefix: prefixC.text.trim().toUpperCase(),
                  startNumber: int.tryParse(startNoC.text) ?? 1,
                  isDefault: isDef,
                  isActive: isAct,
                );

                if (existing == null) ph.addNumberingSeries(ns);
                else ph.updateNumberingSeries(ns);
                
                Navigator.pop(c);
              },
              child: const Text("SAVE SERIES"),
            )
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Series Configuration"),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: types.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: types.map((type) => _buildSeriesList(ph, type)).toList(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSeriesForm(),
        backgroundColor: Colors.indigo.shade900,
        label: const Text("ADD NEW SERIES", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildSeriesList(PharoahManager ph, String type) {
    // Properly cast the list from Manager
    final list = ph.getSeriesByType(type);

    if (list.isEmpty) {
      return const Center(child: Text("No custom series for this type."));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: list.length,
      itemBuilder: (c, i) {
        final s = list[i];
        bool isUsed = _isSeriesInUse(ph, s);

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: s.isDefault ? Colors.indigo : Colors.transparent, width: 2)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(15),
            title: Row(
              children: [
                Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (s.isDefault) Container(margin: const EdgeInsets.only(left: 10), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(5)), child: const Text("DEFAULT", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))),
                const Spacer(),
                _statusBadge(s.isActive),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 5),
                Text("Prefix: ${s.prefix} | Start: ${s.startNumber}", style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit_note, color: Colors.blue), onPressed: () => _showSeriesForm(existing: s)),
                if (!isUsed) 
                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () {
                    ph.numberingSeries.removeWhere((x) => x.id == s.id); ph.save();
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusBadge(bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: active ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(5), border: Border.all(color: active ? Colors.green : Colors.red)),
      child: Text(active ? "ACTIVE" : "STOPPED", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: active ? Colors.green.shade900 : Colors.red.shade900)),
    );
  }
}
