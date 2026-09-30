// FILE: lib/export_selector_view.dart

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'csv_engine.dart';

class ExportSelectorView extends StatefulWidget {
  final String exportType; 
  final bool maskPurchaseRate; 

  const ExportSelectorView({super.key, required this.exportType, this.maskPurchaseRate = false});

  @override State<ExportSelectorView> createState() => _ExportSelectorViewState();
}

class _ExportSelectorViewState extends State<ExportSelectorView> {
  String partySearch = "";
  List<String> selectedIds = [];
  Party? targetParty;

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    List<dynamic> source = widget.exportType == "SALE" ? ph.sales : ph.purchases;
    if (widget.exportType == "SALE") source = source.where((s) => s.status == "Active").toList();
    source = source.reversed.toList();

    List<dynamic> filtered = source.where((b) {
      String pName = widget.exportType == "SALE" ? (b as Sale).partyName : (b as Purchase).distributorName;
      return targetParty == null || pName == targetParty!.name;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(title: Text("${widget.exportType} EXPORT"), backgroundColor: Colors.indigo.shade800, foregroundColor: Colors.white),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.all(15), color: Colors.white,
          child: targetParty == null 
            ? TextField(decoration: const InputDecoration(hintText: "Search Party Name...", prefixIcon: Icon(Icons.person_search), border: OutlineInputBorder()), onChanged: (v) => setState(() => partySearch = v))
            : ListTile(tileColor: Colors.indigo.shade50, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), leading: const Icon(Icons.person, color: Colors.indigo), title: Text(targetParty!.name, style: const TextStyle(fontWeight: FontWeight.bold)), trailing: IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() { targetParty = null; selectedIds.clear(); }))),
        ),
        Expanded(child: ListView.builder(itemCount: filtered.length, itemBuilder: (c, i) {
          final b = filtered[i];
          final isSel = selectedIds.contains(b.id);
          return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: CheckboxListTile(activeColor: Colors.indigo, value: isSel, title: Text(widget.exportType == "SALE" ? (b as Sale).partyName : (b as Purchase).distributorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), subtitle: Text("Invoice: ${b.billNo} | ₹${b.totalAmount.toStringAsFixed(0)}"), onChanged: (v) => setState(() => v! ? selectedIds.add(b.id) : selectedIds.remove(b.id))));
        })),
      ]),
      bottomNavigationBar: selectedIds.isEmpty ? null : Container(
        padding: const EdgeInsets.all(20), color: Colors.white,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55)), 
          onPressed: () => _startExport(filtered, ph), 
          icon: const Icon(Icons.download), label: const Text("EXPORT SELECTED", style: TextStyle(fontWeight: FontWeight.bold))),
      ),
    );
  }

  void _startExport(List<dynamic> all, PharoahManager ph) async {
    List<dynamic> sel = all.where((b) => selectedIds.contains(b.id)).toList();
    String csv = "";

    if (widget.exportType == "SALE") {
      csv = CsvEngine.convertSalesToCsv(sales: sel.cast<Sale>(), shop: ph.activeCompany!, allMeds: ph.medicines, allComps: ph.companies, allSalts: ph.salts, allParties: ph.parties, maskPurchaseRate: widget.maskPurchaseRate);
    } else {
      // FIXED CALL: Aligned with new 5-parameter signature
      csv = CsvEngine.convertPurchasesToCsv(
        purchases: sel.cast<Purchase>(), 
        shop: ph.activeCompany!, 
        allMeds: ph.medicines, 
        allComps: ph.companies, 
        allSalts: ph.salts, 
        allParties: ph.parties
      );
    }

    Uint8List bytes = Uint8List.fromList(utf8.encode(csv));
    await FileSaver.instance.saveAs(name: "${widget.exportType}_EXPORT", bytes: bytes, ext: "csv", mimeType: MimeType.csv);
  }
}
