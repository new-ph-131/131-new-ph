// FILE: lib/product_master.dart (UPDATED VERSION)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'logic/pharoah_numbering_engine.dart';

class ProductMasterView extends StatefulWidget {
  final bool isSelectionMode; 
  final Map<String, dynamic>? preFillData; // P2P data carrier

  const ProductMasterView({
    super.key, 
    this.isSelectionMode = false, 
    this.preFillData
  });

  @override State<ProductMasterView> createState() => _ProductMasterViewState();
}

class _ProductMasterViewState extends State<ProductMasterView> {
  String searchQuery = "";
  final List<String> drugForms = ["TAB", "CAP", "SYP", "INJ", "IV", "PCS", "EXT", "OINT", "DROP"];
  final List<String> storageOptions = ["Room Temp", "Refrigerated (2-8°C)", "Cool Place"];

  @override
  void initState() {
    super.initState();
    if (widget.preFillData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showProductForm();
      });
    }
  }

  // --- 🛡️ NAYA: DELETION PROTECTION LOGIC ---
  void _confirmDelete(PharoahManager ph, Medicine med) {
    // 1. Check Usage from Manager
    bool inUse = ph.isProductInUse(med.id);

    if (inUse) {
      // Restricted Alert
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(children: [Icon(Icons.lock, color: Colors.red), SizedBox(width: 10), Text("Delete Restricted")]),
          content: Text("Cannot delete '${med.name}' because it is linked to existing Sale or Purchase records in this year."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("CLOSE")),
          ],
        ),
      );
      return;
    }

    // 2. Clear to Delete Dialog
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Product?"),
        content: Text("Are you sure you want to remove '${med.name}' permanently?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ph.medicines.removeWhere((m) => m.id == med.id);
              ph.save();
              Navigator.pop(c);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Item Deleted!")));
            }, 
            child: const Text("YES, DELETE", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 🛠️ THE CORE FORM: AUTO-FILL & MAPPING LOGIC
  // ===========================================================================
  void _showProductForm({Medicine? med}) async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    if (ph.activeCompany == null) return;

    final pf = widget.preFillData;

    final nameC = TextEditingController(text: med?.name ?? pf?['name']?.toString().toUpperCase());
    final packC = TextEditingController(text: med?.packing ?? pf?['pack']?.toString().toUpperCase());
    final hsnC = TextEditingController(text: med?.hsnCode ?? pf?['hsn']?.toString());
    final gstC = TextEditingController(text: med?.gst.toString() ?? pf?['gstPer']?.toString() ?? "12");
    final rackC = TextEditingController(text: med?.rackNo);
    final reorderC = TextEditingController(text: med?.reorderLevel.toString() ?? "0");

    final mrpC = TextEditingController(text: med?.mrp.toString() ?? pf?['mrp']?.toString() ?? "0");
    final purRateC = TextEditingController(text: med?.purRate.toString() ?? pf?['purRateInFile']?.toString() ?? "0");
    final rateAC = TextEditingController(text: med?.rateA.toString() ?? pf?['saleRateInFile']?.toString() ?? "0");

    String sysIdDisplay = med?.systemId ?? "Generating...";
    if (med == null) {
      sysIdDisplay = await PharoahNumberingEngine.getNextNumber(
        type: "PRODUCT", 
        companyID: ph.activeCompany!.id, 
        prefix: "PH-", 
        startFrom: 10001, 
        currentList: ph.medicines,
      );
    }

    String selForm = med?.drugForm ?? pf?['form']?.toString().toUpperCase() ?? "TAB";
    bool naco = med?.isNarcotic ?? (pf?['isNaco'] == true);
    bool schH1 = med?.isScheduleH1 ?? (pf?['isH1'] == true);

    String? companyId = med?.companyId;
    String? saltId = med?.saltId;
    String companyName = "Tap to Select Company";
    String saltName = "Tap to Select Salt";

    if (pf != null && med == null) {
       if (pf['mfg'] != null) {
         try {
           final found = ph.companies.firstWhere((c) => c.name.toUpperCase() == pf['mfg'].toString().toUpperCase());
           companyId = found.id; companyName = found.name;
         } catch(e) { companyName = pf['mfg'].toString().toUpperCase(); }
       }
       if (pf['salt'] != null) {
         try {
           final found = ph.salts.firstWhere((s) => s.name.toUpperCase() == pf['salt'].toString().toUpperCase());
           saltId = found.id; saltName = found.name;
         } catch(e) { saltName = pf['salt'].toString().toUpperCase(); }
       }
    } else if (med != null) {
       try {
         if(companyId != null) companyName = ph.companies.firstWhere((c) => c.id == companyId).name;
         if(saltId != null) saltName = ph.salts.firstWhere((s) => s.id == saltId).name;
       } catch(e) {}
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(med == null ? "Register New Product" : "Edit Product Details"),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _infoBanner("SYSTEM ID: $sysIdDisplay", Colors.indigo),
                  _sectionHeader("PRIMARY DETAILS"),
                  _input(nameC, "Product Name *", Icons.medication),
                  Row(children: [
                    Expanded(child: _input(packC, "Packing *", Icons.inventory)),
                    const SizedBox(width: 10),
                    Expanded(child: DropdownButtonFormField<String>(
                      value: drugForms.contains(selForm) ? selForm : "TAB",
                      decoration: const InputDecoration(labelText: "Form", border: OutlineInputBorder()),
                      items: drugForms.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                      onChanged: (v) => setDialogState(() => selForm = v!),
                    )),
                  ]),
                  const SizedBox(height: 15),
                  _searchableBox(label: "Company / Brand", value: companyName, icon: Icons.business, onTap: () => _showSearchablePicker(title: "Company", items: ph.companies, onSelected: (val) => setDialogState(() { companyId = val.id; companyName = val.name; }), onQuickAdd: () => _quickAddCompany(ph))),
                  const SizedBox(height: 15),
                  _searchableBox(label: "Salt / Composition", value: saltName, icon: Icons.science, onTap: () => _showSearchablePicker(title: "Salt", items: ph.salts, onSelected: (val) => setDialogState(() { saltId = val.id; saltName = val.name; }), onQuickAdd: () => _quickAddSalt(ph))),
                  
                  _sectionHeader("COMPLIANCE & TAX"),
                  Row(children: [
                    Expanded(child: SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text("Narcotic", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), value: naco, onChanged: (v) => setDialogState(() => naco = v))),
                    Expanded(child: SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text("Sch. H1", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), value: schH1, onChanged: (v) => setDialogState(() => schH1 = v))),
                  ]),
                  Row(children: [
                    Expanded(child: _input(hsnC, "HSN Code", Icons.tag)),
                    const SizedBox(width: 10),
                    Expanded(child: _input(gstC, "GST %", Icons.percent, isNum: true)),
                  ]),
                  
                  _sectionHeader("PRICING (LATEST)"),
                  Row(children: [
                    Expanded(child: _input(mrpC, "MRP", Icons.currency_rupee, isNum: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _input(purRateC, "Pur. Rate", Icons.shopping_cart, isNum: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _input(rateAC, "Sale Rate", Icons.sell, isNum: true)),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
              onPressed: () {
                if(nameC.text.isEmpty || packC.text.isEmpty) return;

                if (companyId == null && companyName != "Tap to Select Company") {
                  companyId = ph.getOrCreateCompany(companyName);
                }
                if (saltId == null && saltName != "Tap to Select Salt") {
                  saltId = ph.getOrCreateSalt(saltName);
                }

                final newItem = Medicine(
                  id: med?.id ?? DateTime.now().toString(),
                  systemId: sysIdDisplay, 
                  name: nameC.text.trim().toUpperCase(),
                  packing: packC.text.trim().toUpperCase(),
                  companyId: companyId ?? "",
                  saltId: saltId ?? "",
                  hsnCode: hsnC.text.isEmpty ? "3004" : hsnC.text.toUpperCase(),
                  gst: double.tryParse(gstC.text) ?? 12.0,
                  mrp: double.tryParse(mrpC.text) ?? 0.0,
                  purRate: double.tryParse(purRateC.text) ?? 0.0,
                  rateA: double.tryParse(rateAC.text) ?? 0.0,
                  drugForm: selForm,
                  isNarcotic: naco,
                  isScheduleH1: schH1,
                  stock: med?.stock ?? 0.0,
                  rackNo: rackC.text.toUpperCase(),
                );

                if(med == null) ph.addMedicine(newItem);
                else { int i = ph.medicines.indexWhere((x)=>x.id==med.id); ph.medicines[i] = newItem; ph.save(); }
                
                Navigator.pop(c);
                if (widget.isSelectionMode) Navigator.pop(context, newItem);
              }, 
              child: const Text("SAVE TO MASTER")
            )
          ],
        );
      }),
    );
  }

  @override Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final list = ph.medicines.where((m) => m.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(title: const Text("Product Master"), backgroundColor: Colors.purple, foregroundColor: Colors.white),
      body: Column(children: [
        Container(padding: const EdgeInsets.all(15), color: Colors.purple.shade50, child: TextField(
          decoration: InputDecoration(hintText: "Search Product...", prefixIcon: const Icon(Icons.search, color: Colors.purple), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)), 
          onChanged: (v) => setState(() => searchQuery = v)
        )),
        Expanded(child: ListView.builder(itemCount: list.length, itemBuilder: (c, i) {
            final m = list[i];
            return Card(elevation: 1, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), child: ListTile(
                leading: CircleAvatar(backgroundColor: Colors.purple.shade50, child: Text(m.systemId.replaceAll("PH-", ""), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.purple))),
                title: Text("${m.name} (${m.packing})", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Stock: ${m.stock} | MRP: ₹${m.mrp}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit_note, color: Colors.blue), onPressed: () => _showProductForm(med: m)),
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _confirmDelete(ph, m)),
                  ],
                ),
            ));
        }))
      ]),
      floatingActionButton: FloatingActionButton(onPressed: () => _showProductForm(), backgroundColor: Colors.purple, foregroundColor: Colors.white, child: const Icon(Icons.add)),
    );
  }

  Widget _infoBanner(String t, Color c) => Container(width: double.infinity, padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 15), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.2))), child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: c, fontSize: 12)));
  Widget _sectionHeader(String t) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Align(alignment: Alignment.centerLeft, child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1))));
  
  Widget _input(TextEditingController ctrl, String l, IconData i, {bool isNum = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12), 
    child: TextField(
      controller: ctrl, 
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text, 
      textCapitalization: TextCapitalization.characters, 
      decoration: InputDecoration(labelText: l, prefixIcon: Icon(i, size: 18), border: const OutlineInputBorder(), isDense: true)
    )
  );

  Widget _searchableBox({required String label, required String value, required IconData icon, required VoidCallback onTap}) => InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(5)), child: Row(children: [Icon(icon, color: Colors.grey, size: 18), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)), Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)])), const Icon(Icons.arrow_drop_down)])));

  void _showSearchablePicker({required String title, required List<dynamic> items, required Function(dynamic) onSelected, required VoidCallback onQuickAdd}) {
    showDialog(context: context, builder: (context) {
        String localSearch = "";
        return StatefulBuilder(builder: (context, setPickerState) {
          final filtered = items.where((item) => item.name.toLowerCase().contains(localSearch.toLowerCase())).toList();
          return AlertDialog(title: Text("Select $title"), content: SizedBox(width: double.maxFinite, child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(autofocus: true, decoration: const InputDecoration(hintText: "Search...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()), onChanged: (v) => setPickerState(() => localSearch = v)),
                  const SizedBox(height: 10),
                  Flexible(child: ListView.builder(shrinkWrap: true, itemCount: filtered.length, itemBuilder: (c, i) => ListTile(title: Text(filtered[i].name), onTap: () { onSelected(filtered[i]); Navigator.pop(context); }))),
                  const Divider(),
                  TextButton.icon(onPressed: () { Navigator.pop(context); onQuickAdd(); }, icon: const Icon(Icons.add), label: Text("ADD NEW ${title.toUpperCase()}"))
          ])));
        });
    });
  }

  void _quickAddCompany(PharoahManager ph) async {
    final cC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Quick Add Company"), content: TextField(controller: cC, decoration: const InputDecoration(labelText: "Company Name"), textCapitalization: TextCapitalization.characters), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")), ElevatedButton(onPressed: () { if(cC.text.isNotEmpty) { ph.addCompany(Company(id: DateTime.now().toString(), name: cC.text.toUpperCase())); Navigator.pop(c); } }, child: const Text("ADD"))]));
  }

  void _quickAddSalt(PharoahManager ph) async {
    final sC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Quick Add Salt"), content: TextField(controller: sC, decoration: const InputDecoration(labelText: "Salt Name"), textCapitalization: TextCapitalization.characters), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")), ElevatedButton(onPressed: () { if(sC.text.isNotEmpty) { ph.addSalt(Salt(id: DateTime.now().toString(), name: sC.text.toUpperCase())); Navigator.pop(c); } }, child: const Text("ADD"))]));
  }
}
