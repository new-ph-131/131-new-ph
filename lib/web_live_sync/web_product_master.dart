// FILE: lib/web_live_sync/web_product_master.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_pharoah_numbering_engine.dart';

class WebProductMasterView extends StatefulWidget {
  final VoidCallback onBack;

  const WebProductMasterView({super.key, required this.onBack});

  @override
  State<WebProductMasterView> createState() => _WebProductMasterViewState();
}

class _WebProductMasterViewState extends State<WebProductMasterView> {
  String searchQuery = "";
  final List<String> drugForms = ["TAB", "CAP", "SYP", "INJ", "IV", "PCS", "EXT", "OINT", "DROP"];

  void _showProductForm(PharoahWebManager webPh, {Medicine? med}) {
    final nameC = TextEditingController(text: med?.name);
    final packC = TextEditingController(text: med?.packing ?? "10 TAB");
    final hsnC = TextEditingController(text: med?.hsnCode ?? "3004");
    final gstC = TextEditingController(text: med?.gst.toString() ?? "12");
    final rackC = TextEditingController(text: med?.rackNo);
    final reorderC = TextEditingController(text: med?.reorderLevel.toString() ?? "0");

    final mrpC = TextEditingController(text: med?.mrp.toString() ?? "0.0");
    final purRateC = TextEditingController(text: med?.purRate.toString() ?? "0.0");
    final rateAC = TextEditingController(text: med?.rateA.toString() ?? "0.0");
    final rateBC = TextEditingController(text: med?.rateB.toString() ?? "0.0");
    final rateCC = TextEditingController(text: med?.rateC.toString() ?? "0.0");

    String sysId = med?.systemId ?? "";
    if (sysId.isEmpty) {
      sysId = WebPharoahNumberingEngine.getNextNumber(
        prefix: "PH-",
        startFrom: 10001,
        currentList: webPh.medicines,
      );
    }

    String selForm = med?.drugForm ?? "TAB";
    bool isNaco = med?.isNarcotic ?? false;
    bool isH1 = med?.isScheduleH1 ?? false;

    String? companyId = med?.companyId;
    String? saltId = med?.saltId;
    String companyName = companyId != null && companyId.isNotEmpty
        ? webPh.companies.firstWhere((c) => c.id == companyId, orElse: () => Company(id: "", name: "")).name
        : "Select Company Brand";
    String saltName = saltId != null && saltId.isNotEmpty
        ? webPh.salts.firstWhere((s) => s.id == saltId, orElse: () => Salt(id: "", name: "")).name
        : "Select Salt Composition";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.white12),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0x337C3AED),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.medication_rounded, color: Color(0xFFA78BFA), size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  med == null ? "ADD NEW PRODUCT" : "EDIT PRODUCT DETAILS",
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
                  child: Text(sysId, style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _inputField("PRODUCT NAME *", nameC, Icons.medication, isCaps: true),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(flex: 3, child: _inputField("PACKING *", packC, Icons.inventory, isCaps: true)),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: drugForms.contains(selForm) ? selForm : "TAB",
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            decoration: _dropdownDecor("DRUG FORM"),
                            items: drugForms.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                            onChanged: (v) => setDialogState(() => selForm = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _inputField("HSN CODE", hsnC, Icons.tag, isCaps: true)),
                        const SizedBox(width: 10),
                        Expanded(child: _inputField("GST %", gstC, Icons.percent, isNum: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _pickerBox("COMPANY / BRAND", companyName, Icons.business, () {
                      _showSearchModal("Select Company", webPh.companies.map((c) => c.name).toList(), (selected) {
                        setDialogState(() {
                          companyName = selected;
                          companyId = webPh.getOrCreateCompany(selected);
                        });
                      });
                    }),
                    const SizedBox(height: 12),
                    _pickerBox("SALT COMPOSITION", saltName, Icons.science, () {
                      _showSearchModal("Select Salt", webPh.salts.map((s) => s.name).toList(), (selected) {
                        setDialogState(() {
                          saltName = selected;
                          saltId = webPh.getOrCreateSalt(selected);
                        });
                      });
                    }),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _inputField("MRP ₹", mrpC, Icons.currency_rupee, isNum: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _inputField("PUR. RATE ₹", purRateC, Icons.shopping_cart, isNum: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _inputField("RATE A ₹", rateAC, Icons.sell, isNum: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _inputField("RATE B ₹", rateBC, Icons.sell, isNum: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _inputField("RACK NO", rackC, Icons.grid_3x3, isCaps: true)),
                        const SizedBox(width: 10),
                        Expanded(child: _inputField("MIN. REORDER QTY", reorderC, Icons.warning_amber, isNum: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text("Schedule H1", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                            value: isH1,
                            activeColor: const Color(0xFF38BDF8),
                            onChanged: (v) => setDialogState(() => isH1 = v),
                          ),
                        ),
                        Expanded(
                          child: SwitchListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text("Narcotic (NDPS)", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                            value: isNaco,
                            activeColor: Colors.redAccent,
                            onChanged: (v) => setDialogState(() => isNaco = v),
                          ),
                        ),
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
                  if (nameC.text.trim().isEmpty || packC.text.trim().isEmpty) return;

                  double mrp = double.tryParse(mrpC.text) ?? 0.0;
                  double pur = double.tryParse(purRateC.text) ?? 0.0;
                  double a = double.tryParse(rateAC.text) ?? mrp;
                  double b = double.tryParse(rateBC.text) ?? (a * 0.95);

                  final newMed = Medicine(
                    id: med?.id ?? "MED-${DateTime.now().millisecondsSinceEpoch}",
                    systemId: sysId,
                    name: nameC.text.trim().toUpperCase(),
                    packing: packC.text.trim().toUpperCase(),
                    hsnCode: hsnC.text.trim().toUpperCase().isEmpty ? "3004" : hsnC.text.trim().toUpperCase(),
                    drugForm: selForm,
                    gst: double.tryParse(gstC.text) ?? 12.0,
                    mrp: mrp,
                    purRate: pur,
                    rateA: a,
                    rateB: b,
                    rateC: double.tryParse(rateCC.text) ?? (a * 0.92),
                    stock: med?.stock ?? 0.0,
                    isNarcotic: isNaco,
                    isScheduleH1: isH1,
                    companyId: companyId ?? "",
                    saltId: saltId ?? "",
                    rackNo: rackC.text.trim().toUpperCase(),
                    reorderLevel: double.tryParse(reorderC.text) ?? 0.0,
                  );

                  if (med == null) {
                    webPh.addMedicine(newMed);
                  } else {
                    webPh.updateMedicine(newMed);
                  }

                  Navigator.pop(c);
                },
                child: const Text("SAVE PRODUCT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSearchModal(String title, List<String> list, Function(String) onSelect) {
    String query = "";
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final filtered = list.where((item) => item.toLowerCase().contains(query.toLowerCase())).toList();
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 380,
              height: 350,
              child: Column(
                children: [
                  TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: "Type to search...",
                      hintStyle: TextStyle(color: Colors.white38),
                      prefixIcon: Icon(Icons.search, color: Colors.cyanAccent, size: 18),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                    ),
                    onChanged: (v) => setModalState(() => query = v),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, idx) {
                        return ListTile(
                          dense: true,
                          title: Text(filtered[idx], style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          onTap: () {
                            onSelect(filtered[idx]);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final filteredList = webPh.medicines.where((m) =>
        m.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
        m.systemId.toLowerCase().contains(searchQuery.toLowerCase()) ||
        m.hsnCode.toLowerCase().contains(searchQuery.toLowerCase())).toList();

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
              const Icon(Icons.medication_rounded, color: Color(0xFFA78BFA), size: 22),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "ITEM / PRODUCT MASTER",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  Text(
                    "${webPh.medicines.length} Total Catalog Items",
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () => _showProductForm(webPh),
                icon: const Icon(Icons.add_box_rounded, size: 18),
                label: const Text("ADD NEW PRODUCT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 25),

          Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: const InputDecoration(
                hintText: "Search Product by Name, Packing, HSN or System ID...",
                hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon: Icon(Icons.search, color: Color(0xFFA78BFA), size: 18),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: filteredList.isEmpty
                ? const Center(
                    child: Text("No products found matching search query.", style: TextStyle(color: Colors.white38)),
                  )
                : SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 800),
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(90),
                          1: FlexColumnWidth(3),
                          2: FixedColumnWidth(90),
                          3: FixedColumnWidth(80),
                          4: FixedColumnWidth(80),
                          5: FixedColumnWidth(80),
                          6: FixedColumnWidth(80),
                          7: FixedColumnWidth(90),
                          8: FixedColumnWidth(90),
                        },
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                            children: [
                              _th("ID"),
                              _th("PRODUCT NAME", isLeft: true),
                              _th("PACK"),
                              _th("FORM"),
                              _th("MRP"),
                              _th("RATE A"),
                              _th("GST%"),
                              _th("STOCK"),
                              _th("ACTIONS"),
                            ],
                          ),
                          for (final m in filteredList)
                            TableRow(
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                              children: [
                                _td(m.systemId, isBold: true, color: Colors.cyanAccent),
                                _td(m.name, isLeft: true, isBold: true),
                                _td(m.packing),
                                _td(m.drugForm),
                                _td("₹${m.mrp.toStringAsFixed(2)}"),
                                _td("₹${m.rateA.toStringAsFixed(2)}"),
                                _td("${m.gst.toInt()}%"),
                                _td("${m.stock.toInt()} Qty", isBold: true, color: m.stock > 0 ? Colors.greenAccent : Colors.redAccent),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF38BDF8)),
                                      tooltip: "Edit Product",
                                      onPressed: () => _showProductForm(webPh, med: m),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                      tooltip: "Delete Product",
                                      onPressed: () => _confirmDelete(webPh, m),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
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

  Widget _inputField(String label, TextEditingController ctrl, IconData icon, {bool isNum = false, bool isCaps = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold),
        prefixIcon: Icon(icon, color: const Color(0xFFA78BFA), size: 16),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  InputDecoration _dropdownDecor(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold),
      filled: true,
      fillColor: Colors.black26,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  Widget _pickerBox(String label, String value, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFA78BFA), size: 16),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_drop_down, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(PharoahWebManager webPh, Medicine m) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Delete Product?", style: TextStyle(color: Colors.white, fontSize: 14)),
        content: Text("Are you sure you want to remove '${m.name}' from catalog?", style: const TextStyle(color: Colors.white70, fontSize: 11)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              webPh.deleteMedicine(m.id);
              Navigator.pop(ctx);
            },
            child: const Text("DELETE"),
          ),
        ],
      ),
    );
  }
}
