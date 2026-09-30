import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'pharoah_manager.dart';
import 'models.dart';

class ImportVerificationView extends StatefulWidget {
  final List<List<dynamic>> csvData;
  final String importType; 
  final bool isOtherFormat;

  const ImportVerificationView({
    super.key, 
    required this.csvData, 
    required this.importType, 
    this.isOtherFormat = false
  });

  @override State<ImportVerificationView> createState() => _ImportVerificationViewState();
}

class _ImportVerificationViewState extends State<ImportVerificationView> {
  Map<String, List<List<dynamic>>> groupedBills = {};
  List<String> billNumbers = [];
  bool isShowingOverview = true;

  String? activeBillKey;
  int wizardStep = 0;
  final billNoC = TextEditingController();
  DateTime selectedDate = DateTime.now();
  final pNameC = TextEditingController();
  final pGstC = TextEditingController();
  final pStateC = TextEditingController();
  bool isNewParty = false;
  List<Map<String, dynamic>> itemsToImport = [];

  @override
  void initState() {
    super.initState();
    _groupCsvData();
  }

  void _groupCsvData() {
    groupedBills.clear();
    for (int i = 1; i < widget.csvData.length; i++) {
      var row = widget.csvData[i];
      if (row.length < 18) continue;
      String bNo = row[1].toString().trim();
      if (!groupedBills.containsKey(bNo)) {
        groupedBills[bNo] = [];
      }
      groupedBills[bNo]!.add(row);
    }
    billNumbers = groupedBills.keys.toList();
  }

  void _startSingleBillWizard(String bNo) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    var rows = groupedBills[bNo]!;
    var firstRow = rows[0];

    setState(() {
      activeBillKey = bNo;
      wizardStep = 0;
      isShowingOverview = false;
      billNoC.text = bNo;
      try { selectedDate = DateFormat('dd/MM/yyyy').parse(firstRow[0].toString()); } 
      catch (e) { selectedDate = DateTime.now(); }

      String extractedParty = firstRow[2].toString().toUpperCase().trim();
      Party? existing;
      try { existing = ph.parties.firstWhere((p) => p.name.toUpperCase() == extractedParty); } 
      catch (e) { existing = null; }

      if (existing == null) {
        isNewParty = true;
        pNameC.text = extractedParty;
        pGstC.text = firstRow[3].toString();
        pStateC.text = firstRow[4].toString();
      } else {
        isNewParty = false;
        pNameC.text = existing.name;
        pGstC.text = existing.gst;
        pStateC.text = existing.state;
      }

      itemsToImport.clear();
      for (var r in rows) {
        itemsToImport.add({
          'name': r[5].toString().toUpperCase(),
          'pack': r[7].toString(),
          'batch': r[8].toString().toUpperCase(),
          'exp': r[9].toString(),
          'hsn': r[10].toString(),
          'qty': double.tryParse(r[11].toString()) ?? 0,
          'free': double.tryParse(r[12].toString()) ?? 0,
          'mrp': double.tryParse(r[13].toString()) ?? 0,
          'rate': double.tryParse(r[14].toString()) ?? 0,
          'gst': double.tryParse(r[16].toString().replaceAll("%", "")) ?? 12,
          'total': double.tryParse(r[17].toString()) ?? 0,
          'exists': ph.medicines.any((m) => m.name.toUpperCase() == r[5].toString().toUpperCase()),
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: Text(isShowingOverview ? "Import Overview" : "Verifying: $activeBillKey"),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
      ),
      body: isShowingOverview ? _buildOverview() : _buildWizard(),
    );
  }

  Widget _buildOverview() {
    final ph = Provider.of<PharoahManager>(context);
    return Column(children: [
        Container(padding: const EdgeInsets.all(15), color: Colors.indigo.shade50, child: Row(children: [const Icon(Icons.info_outline), const SizedBox(width: 10), Text("Found ${billNumbers.length} Bills in CSV.", style: const TextStyle(fontWeight: FontWeight.bold))])),
        Expanded(child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: billNumbers.length, itemBuilder: (c, i) {
              String bNo = billNumbers[i];
              var rows = groupedBills[bNo]!;
              double total = rows.fold(0, (sum, r) => sum + (double.tryParse(r[17].toString()) ?? 0));
              bool alreadyExists = widget.importType == "SALE" ? ph.sales.any((s) => s.billNo == bNo) : ph.purchases.any((p) => p.billNo == bNo);
              return Card(child: ListTile(title: Text(bNo, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text("Party: ${rows[0][2]}\nItems: ${rows.length} | ₹${total.toStringAsFixed(2)}"), trailing: ElevatedButton(onPressed: alreadyExists ? null : () => _startSingleBillWizard(bNo), child: Text(alreadyExists ? "EXISTS" : "VERIFY"))));
            })),
      ]);
  }

  Widget _buildWizard() {
    return Column(children: [
        Container(padding: const EdgeInsets.symmetric(vertical: 20), color: Colors.white, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [_stepCircle(1, "Header", wizardStep >= 0), _stepLine(wizardStep >= 1), _stepCircle(2, "Party", wizardStep >= 1), _stepLine(wizardStep >= 2), _stepCircle(3, "Items", wizardStep >= 2)])),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: wizardStep == 0 ? _stepHeader() : (wizardStep == 1 ? _stepParty() : _stepItems()))),
        Container(
          padding: const EdgeInsets.all(20), 
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]), 
          child: Row(children: [
            if (wizardStep > 0) OutlinedButton(onPressed: () => setState(() => wizardStep--), child: const Text("BACK")), 
            const Spacer(), 
            ElevatedButton(onPressed: () { if (wizardStep < 2) setState(() => wizardStep++); else _finishAndSaveBill(); }, child: Text(wizardStep == 2 ? "FINISH & SAVE" : "NEXT STEP"))
          ])
        ),
      ]);
  }

  Widget _stepHeader() => Column(children: [const Icon(Icons.receipt_long, size: 60, color: Colors.indigo), const SizedBox(height: 20), TextField(controller: billNoC, decoration: const InputDecoration(labelText: "Bill Number", border: OutlineInputBorder())), const SizedBox(height: 15), ListTile(tileColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.black12)), title: Text("Date: ${DateFormat('dd/MM/yyyy').format(selectedDate)}"), trailing: const Icon(Icons.calendar_month), onTap: () async { DateTime? p = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (p != null) setState(() => selectedDate = p); })]);
  Widget _stepParty() => Column(children: [Icon(isNewParty ? Icons.person_add : Icons.how_to_reg, size: 60, color: isNewParty ? Colors.orange : Colors.green), const SizedBox(height: 20), TextField(controller: pNameC, decoration: const InputDecoration(labelText: "Party Name", border: OutlineInputBorder())), const SizedBox(height: 15), TextField(controller: pGstC, decoration: const InputDecoration(labelText: "GSTIN", border: OutlineInputBorder())), const SizedBox(height: 15), TextField(controller: pStateC, decoration: const InputDecoration(labelText: "State", border: OutlineInputBorder()))]);
  Widget _stepItems() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Item Mapping", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), ...itemsToImport.map((it) => Card(child: ListTile(dense: true, title: Text(it['name']), subtitle: Text("Batch: ${it['batch']} | Qty: ${it['qty']}"), trailing: Icon(it['exists'] ? Icons.check_circle : Icons.add_circle, color: it['exists'] ? Colors.green : Colors.orange))))]);

  void _finishAndSaveBill() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    Party targetParty;
    if (isNewParty) {
      targetParty = Party(id: DateTime.now().toString(), name: pNameC.text.toUpperCase(), gst: pGstC.text.toUpperCase(), state: pStateC.text);
      ph.parties.add(targetParty);
    } else {
      targetParty = ph.parties.firstWhere((p) => p.name.toUpperCase() == pNameC.text.toUpperCase());
    }

    if (widget.importType == "SALE") {
      List<BillItem> bItems = [];
      for (var it in itemsToImport) {
        Medicine m = _getOrCreateMed(ph, it);
        bItems.add(BillItem(id: DateTime.now().toString(), srNo: bItems.length + 1, medicineID: m.id, name: m.name, packing: m.packing, batch: it['batch'], exp: it['exp'], hsn: it['hsn'], mrp: it['mrp'], qty: it['qty'], freeQty: it['free'], rate: it['rate'], gstRate: it['gst'], total: it['total']));
      }
      ph.finalizeSale(billNo: billNoC.text, date: selectedDate, party: targetParty, items: bItems, total: bItems.fold(0, (s, i) => s + i.total), mode: "CREDIT");
    } else {
      List<PurchaseItem> pItems = [];
      for (var it in itemsToImport) {
        Medicine m = _getOrCreateMed(ph, it);
        pItems.add(PurchaseItem(id: DateTime.now().toString(), srNo: pItems.length + 1, medicineID: m.id, name: m.name, packing: m.packing, batch: it['batch'], exp: it['exp'], hsn: it['hsn'], mrp: it['mrp'], qty: it['qty'], freeQty: it['free'], purchaseRate: it['rate'], gstRate: it['gst'], total: it['total']));
      }
      ph.finalizePurchase(internalNo: "IMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}", billNo: billNoC.text, date: selectedDate, entryDate: DateTime.now(), party: targetParty, items: pItems, total: pItems.fold(0, (s, i) => s + i.total), mode: "CREDIT");
    }
    await ph.save();
    setState(() { _groupCsvData(); isShowingOverview = true; });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Import Successful!"), backgroundColor: Colors.green));
  }

  Medicine _getOrCreateMed(PharoahManager ph, Map<String, dynamic> it) {
    try { return ph.medicines.firstWhere((m) => m.name.toUpperCase() == it['name']); } catch (e) {
      Medicine n = Medicine(id: DateTime.now().toString(), name: it['name'], packing: it['pack'], mrp: it['mrp'], rateA: it['rate'] * 1.1, rateB: it['rate'] * 1.05, rateC: it['rate'], stock: 0.0, purRate: it['rate'], gst: it['gst'], hsnCode: it['hsn']);
      ph.medicines.add(n);
      return n;
    }
  }

  Widget _stepCircle(int n, String l, bool a) => Column(children: [CircleAvatar(radius: 12, backgroundColor: a ? Colors.indigo : Colors.grey.shade300, child: Text("$n", style: const TextStyle(fontSize: 10, color: Colors.white))), const SizedBox(height: 4), Text(l, style: TextStyle(fontSize: 10, fontWeight: a ? FontWeight.bold : FontWeight.normal))]);
  Widget _stepLine(bool a) => Container(width: 40, height: 2, color: a ? Colors.indigo : Colors.grey.shade300, margin: const EdgeInsets.only(bottom: 15, left: 5, right: 5));
}
