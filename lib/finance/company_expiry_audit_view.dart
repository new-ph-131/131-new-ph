import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../../pdf/statements/expiry_audit_pdf.dart';

class CompanyExpiryAuditView extends StatefulWidget {
  const CompanyExpiryAuditView({super.key});
  @override State<CompanyExpiryAuditView> createState() => _CompanyExpiryAuditViewState();
}

class _CompanyExpiryAuditViewState extends State<CompanyExpiryAuditView> {
  Company? selectedCompany;
  String viewMode = "STOCK"; 
  int monthsHorizon = 3; 
  String companySearch = "";

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    List<Map<String, dynamic>> auditData = [];
    if (selectedCompany != null) auditData = _calculateExpiryData(ph);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F5),
      appBar: AppBar(
        title: Text(selectedCompany == null ? "Expiry Audit" : selectedCompany!.name),
        backgroundColor: Colors.red.shade900,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf), 
            onPressed: () async {
              if (selectedCompany == null) return;
              await ExpiryAuditPdf.generate(
                shop: ph.activeCompany!,
                selectedCompany: selectedCompany!,
                auditData: auditData,
                horizon: monthsHorizon,
                viewMode: viewMode,
              );
            }
          )
        ],
      ),
      body: Column(children: [
        _buildTopSelectionHeader(ph),
        if (selectedCompany != null) _buildModeToggle(),
        Expanded(
          child: selectedCompany == null ? _buildCompanyPicker(ph) : _buildAuditList(auditData, ph),
        ),
      ]),
    );
  }

  List<Map<String, dynamic>> _calculateExpiryData(PharoahManager ph) {
    List<Map<String, dynamic>> results = [];
    DateTime threshold = DateTime.now().add(Duration(days: monthsHorizon * 30));
    final companyMeds = ph.medicines.where((m) => m.companyId == selectedCompany!.id).toList();

    for (var med in companyMeds) {
      final batches = ph.batchHistory[med.identityKey] ?? [];
      for (var b in batches) {
        if (b.qty <= 0) continue;
        DateTime? expDate;
        try { expDate = DateFormat('MM/yy').parse(b.exp); } catch (e) { continue; }
        if (expDate.isBefore(threshold)) {
          Map<String, dynamic> entry = {'med': med, 'batch': b, 'status': expDate.isBefore(DateTime.now()) ? "EXPIRED" : "NEAR", 'val': b.qty * med.purRate};
          if (viewMode == "PARTY") {
            try {
              final lastPur = ph.purchases.lastWhere((p) => p.items.any((it) => it.medicineID == med.id && it.batch == b.batch));
              entry['supplier'] = lastPur.distributorName;
              entry['billNo'] = lastPur.billNo;
            } catch (e) { entry['supplier'] = "Unknown"; }
          }
          results.add(entry);
        }
      }
    }
    return results;
  }

  Widget _buildTopSelectionHeader(PharoahManager ph) => Container(
    padding: const EdgeInsets.all(15), color: Colors.red.shade900,
    child: Row(children: [
      Expanded(child: _simpleDropdown([3, 6, 12], (v) => setState(() => monthsHorizon = v!), "${monthsHorizon} Mo")),
      const SizedBox(width: 15),
      Expanded(child: _simpleDropdown(["STOCK", "PARTY"], (v) => setState(() => viewMode = v!), viewMode)),
    ]),
  );

  Widget _buildCompanyPicker(PharoahManager ph) {
    final list = ph.companies.where((c) => c.name.toLowerCase().contains(companySearch.toLowerCase())).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.all(15), child: TextField(decoration: const InputDecoration(hintText: "Search Brand...", border: OutlineInputBorder()), onChanged: (v) => setState(() => companySearch = v))),
      Expanded(child: ListView.builder(itemCount: list.length, itemBuilder: (c, i) => ListTile(title: Text(list[i].name), onTap: () => setState(() => selectedCompany = list[i]))))
    ]);
  }

  Widget _buildAuditList(List<Map<String, dynamic>> data, PharoahManager ph) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: data.length,
      itemBuilder: (c, i) {
        final row = data[i];
        return Card(
          child: ListTile(
            title: Text(row['med'].name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Batch: ${row['batch'].batch} | Exp: ${row['batch'].exp}"),
            trailing: Text(row['status'], style: TextStyle(color: row['status'] == "EXPIRED" ? Colors.red : Colors.orange, fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  Widget _buildModeToggle() => ListTile(tileColor: Colors.white, title: Text("Selected: ${selectedCompany!.name}"), trailing: TextButton(onPressed: () => setState(() => selectedCompany = null), child: const Text("CHANGE")));
  Widget _simpleDropdown(List<dynamic> items, Function(dynamic) onChange, String val) => Container(height: 35, padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(5)), child: DropdownButtonHideUnderline(child: DropdownButton<dynamic>(dropdownColor: Colors.red.shade900, style: const TextStyle(color: Colors.white), isExpanded: true, value: items.contains(val) ? val : items.first, items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.toString()))).toList(), onChanged: onChange)));
  Widget _dropdownLabel(String t) => Text(t, style: const TextStyle(color: Colors.white70, fontSize: 9));
  Widget _badge(String t, Color c) => Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: c), child: Text(t));
  Widget _info(String l, String v, {bool isBold = false}) => Text("$l: $v");
}
