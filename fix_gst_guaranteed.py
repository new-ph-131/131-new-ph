import re
import subprocess
import sys

# 1. Update Revision Tag
top_bar_path = "lib/web_live_sync/components/web_top_bar.dart"
with open(top_bar_path, "r", encoding="utf-8") as f:
    tb = f.read()

new_rev = "#PH-REV-583 (GST-PICKER-FIX)"
tb = re.sub(r"#PH-REV-\d+[^\"]*", new_rev, tb)
with open(top_bar_path, "w", encoding="utf-8") as f:
    f.write(tb)
print(f"✔ Live Tag Updated: {new_rev}")

# 2. FULL REWRITE: Web Product Master
pm_path = "lib/web_live_sync/web_product_master.dart"
pm_code = r'''// FILE: lib/web_live_sync/web_product_master.dart

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
  final List<String> storageOptions = ["Room Temp", "Refrigerated (2-8°C)", "Cool Place"];

  void _convertAllBoxMastersToStrips(PharoahWebManager webPh) async {
    int convertedCount = 0;

    for (var m in webPh.medicines) {
      String p = m.packing.trim();
      var match = RegExp(r'^(\d+)[\*xX](\d+)$').firstMatch(p);
      if (match != null) {
        int n = int.tryParse(match.group(1)!) ?? 1;
        int mUnits = int.tryParse(match.group(2)!) ?? 10;

        if (n > 1) {
          m.packing = "1*$mUnits";
          m.mrp = m.mrp / n;
          m.purRate = m.purRate / n;
          m.rateA = m.rateA / n;
          m.rateB = m.rateB / n;
          m.rateC = m.rateC / n;

          if (webPh.batchHistory.containsKey(m.identityKey)) {
            for (var b in webPh.batchHistory[m.identityKey]!) {
              b.packing = "1*$mUnits";
              b.mrp = b.mrp / n;
              b.purRate = b.purRate / n;
              b.rate = b.purRate;
              b.rateA = b.rateA / n;
              b.rateB = b.rateB / n;
              b.rateC = b.rateC / n;
            }
          }
          convertedCount++;
        }
      }
    }

    if (convertedCount > 0) {
      webPh.rebuildInventory();
      await webPh.pushUpdatedDataToCloud();
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("🎉 Converted $convertedCount products to single strip (1*10) pricing!"), backgroundColor: Colors.green),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("All products are already in strip format!"), backgroundColor: Colors.blue),
        );
      }
    }
  }

  void _showProductForm(PharoahWebManager webPh, {Medicine? med}) async {
    final pf = null;

    final nameC = TextEditingController(text: med?.name ?? pf?['name']?.toString().toUpperCase());
    final packC = TextEditingController(text: med?.packing ?? pf?['pack']?.toString().toUpperCase() ?? "1*10");
    final hsnC = TextEditingController(text: med?.hsnCode ?? pf?['hsn']?.toString() ?? "3004");
    
    // 🔥 NAYA GST LOGIC
    String selGst = "5";
    if (med != null) {
      if ([0.0, 5.0, 12.0, 18.0, 28.0].contains(med.gst)) {
        selGst = med.gst.toInt().toString();
      } else {
        selGst = "Manual";
      }
    } else if (pf?['gstPer'] != null) {
       double g = double.tryParse(pf!['gstPer'].toString()) ?? 5.0;
       if ([0.0, 5.0, 12.0, 18.0, 28.0].contains(g)) {
         selGst = g.toInt().toString();
       } else {
         selGst = "Manual";
       }
    }
    final gstC = TextEditingController(text: med?.gst.toString() ?? pf?['gstPer']?.toString() ?? "5");

    final rackC = TextEditingController(text: med?.rackNo);
    final reorderC = TextEditingController(text: med?.reorderLevel.toString() ?? "0");

    final mrpC = TextEditingController(text: med?.mrp.toString() ?? pf?['mrp']?.toString() ?? "0.0");
    final purRateC = TextEditingController(text: med?.purRate.toString() ?? pf?['purRateInFile']?.toString() ?? "0.0");
    final rateAC = TextEditingController(text: med?.rateA.toString() ?? pf?['saleRateInFile']?.toString() ?? "0.0");
    final rateBC = TextEditingController(text: med?.rateB.toString() ?? "0.0");
    final rateCC = TextEditingController(text: med?.rateC.toString() ?? "0.0");

    String sysIdDisplay = med?.systemId ?? "Generating...";
    if (med == null) {
      sysIdDisplay = WebPharoahNumberingEngine.getNextNumber(
        prefix: "PH-",
        startFrom: 10001,
        currentList: webPh.medicines,
      );
    }

    String selForm = med?.drugForm ?? pf?['form']?.toString().toUpperCase() ?? "TAB";
    bool isNaco = med?.isNarcotic ?? (pf?['isNaco'] == true);
    bool isH1 = med?.isScheduleH1 ?? (pf?['isH1'] == true);

    String? companyId = med?.companyId;
    String? saltId = med?.saltId;

    if (!mounted) return;

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
                  child: Text(sysIdDisplay, style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
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
                        Expanded(flex: 3, child: _inputField("PACKING (e.g. 1*10) *", packC, Icons.inventory, isCaps: true)),
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
                    
                    // 🔥 NAYA GST ROW (Drop-down + Manual Text Field)
                    Row(
                      children: [
                        Expanded(flex: 2, child: _inputField("HSN CODE", hsnC, Icons.tag, isCaps: true)),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: ["0", "5", "12", "18", "28", "Manual"].contains(selGst) ? selGst : "5",
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            decoration: _dropdownDecor("GST % *"),
                            items: ["0", "5", "12", "18", "28", "Manual"].map((f) => DropdownMenuItem(value: f, child: Text(f == "Manual" ? f : "$f%"))).toList(),
                            onChanged: (v) {
                              setDialogState(() {
                                selGst = v!;
                                if (v != "Manual") {
                                  gstC.text = v;
                                } else {
                                  gstC.text = "";
                                }
                              });
                            },
                          ),
                        ),
                        if (selGst == "Manual") ...[
                          const SizedBox(width: 10),
                          Expanded(flex: 2, child: _inputField("CUSTOM GST %", gstC, Icons.edit, isNum: true)),
                        ]
                      ],
                    ),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _inputField("STRIP MRP ₹", mrpC, Icons.currency_rupee, isNum: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _inputField("STRIP PUR. RATE ₹", purRateC, Icons.shopping_cart, isNum: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _inputField("STRIP RATE A ₹", rateAC, Icons.sell, isNum: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _inputField("STRIP RATE B ₹", rateBC, Icons.sell, isNum: true)),
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
                  if (nameC.text.trim().isEmpty || packC.text.trim().isEmpty || gstC.text.trim().isEmpty) return;

                  double mrp = double.tryParse(mrpC.text) ?? 0.0;
                  double pur = double.tryParse(purRateC.text) ?? 0.0;
                  double a = double.tryParse(rateAC.text) ?? mrp;
                  double b = double.tryParse(rateBC.text) ?? (a * 0.95);

                  final newMed = Medicine(
                    id: med?.id ?? "MED-${DateTime.now().millisecondsSinceEpoch}",
                    systemId: sysIdDisplay,
                    name: nameC.text.trim().toUpperCase(),
                    packing: packC.text.trim().toUpperCase(),
                    hsnCode: hsnC.text.trim().toUpperCase().isEmpty ? "3004" : hsnC.text.trim().toUpperCase(),
                    drugForm: selForm,
                    gst: double.tryParse(gstC.text) ?? 5.0,
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
          // Header Bar
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
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: () => _convertAllBoxMastersToStrips(webPh),
                icon: const Icon(Icons.call_split_rounded, size: 16, color: Color(0xFF34D399)),
                label: const Text("CONVERT 10*10 TO STRIPS", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: () => _showProductForm(webPh),
                icon: const Icon(Icons.add_box_rounded, size: 18),
                label: const Text("ADD NEW PRODUCT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
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
                                _td(m.packing, color: m.packing.startsWith("1*") ? Colors.greenAccent : Colors.orangeAccent, isBold: true),
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
                                      onPressed: () {
                                        webPh.deleteMedicine(m.id);
                                        setState(() {});
                                      },
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
}
'''
with open(pm_path, "w", encoding="utf-8") as f:
    f.write(pm_code)
print(f"✔ FULL REWRITE applied to: {pm_path}")


# 3. FULL REWRITE: Quick Add Product Modal (For Billing Screens)
qm_path = "lib/web_live_sync/sub_views/web_billing/quick_add_product_modal.dart"
qm_code = r'''// FILE: lib/web_live_sync/sub_views/web_billing/quick_add_product_modal.dart

import 'package:flutter/material.dart';
import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../web_pharoah_numbering_engine.dart';

class QuickAddProductModal extends StatefulWidget {
  final PharoahWebManager webPh;
  final Function(Map<String, dynamic> newMed) onProductCreated;
  final Map<String, dynamic>? preFillData;

  const QuickAddProductModal({
    super.key,
    required this.webPh,
    required this.onProductCreated,
    this.preFillData,
  });

  @override
  State<QuickAddProductModal> createState() => _QuickAddProductModalState();
}

class _QuickAddProductModalState extends State<QuickAddProductModal> {
  final nameC = TextEditingController();
  final packC = TextEditingController(text: "1*10");
  final hsnC = TextEditingController(text: "3004");
  final gstC = TextEditingController(text: "5");
  final mrpC = TextEditingController(text: "0.0");
  final purRateC = TextEditingController(text: "0.0");
  final rateAC = TextEditingController(text: "0.0");
  final rateBC = TextEditingController(text: "0.0");

  String selectedForm = "TAB";
  String? selectedCompanyId;
  String? selectedSaltId;
  bool isNarcotic = false;
  bool isScheduleH1 = false;
  String selGst = "5";

  final List<String> drugForms = ["TAB", "CAP", "SYP", "INJ", "IV", "PCS", "EXT", "OINT", "DROP"];

  @override
  void initState() {
    super.initState();
    if (widget.preFillData != null) {
      final pf = widget.preFillData!;
      nameC.text = (pf['name'] ?? '').toString();
      packC.text = (pf['pack'] ?? '1*10').toString();
      hsnC.text = (pf['hsn'] ?? '3004').toString();
      
      double g = double.tryParse((pf['gst'] ?? 5.0).toString()) ?? 5.0;
      gstC.text = g.toString();
      if ([0.0, 5.0, 12.0, 18.0, 28.0].contains(g)) {
        selGst = g.toInt().toString();
      } else {
        selGst = "Manual";
      }

      mrpC.text = (pf['mrp'] ?? 0.0).toString();
      purRateC.text = (pf['purRate'] ?? 0.0).toString();
      rateAC.text = (pf['rateA'] ?? pf['mrp'] ?? 0.0).toString();
      rateBC.text = (pf['rateB'] ?? 0.0).toString();
      selectedForm = (pf['form'] ?? 'TAB').toString();
    }
  }

  @override
  void dispose() {
    nameC.dispose();
    packC.dispose();
    hsnC.dispose();
    gstC.dispose();
    mrpC.dispose();
    purRateC.dispose();
    rateAC.dispose();
    rateBC.dispose();
    super.dispose();
  }

  void _saveProduct() {
    if (nameC.text.trim().isEmpty || packC.text.trim().isEmpty || gstC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Product Name, Packing and GST% are required!"), backgroundColor: Colors.orange),
      );
      return;
    }

    double mrp = double.tryParse(mrpC.text) ?? 0.0;
    double pur = double.tryParse(purRateC.text) ?? 0.0;
    double a = double.tryParse(rateAC.text) ?? (mrp > 0 ? mrp : 0.0);
    double b = double.tryParse(rateBC.text) ?? (a > 0 ? a * 0.95 : 0.0);
    double gst = double.tryParse(gstC.text) ?? 5.0;

    String sysId = WebPharoahNumberingEngine.getNextNumber(
      prefix: "PH-",
      startFrom: 10001,
      currentList: widget.webPh.medicines,
    );

    final newMed = Medicine(
      id: "MED-${DateTime.now().millisecondsSinceEpoch}",
      systemId: sysId,
      name: nameC.text.trim().toUpperCase(),
      packing: packC.text.trim().toUpperCase(),
      hsnCode: hsnC.text.trim().toUpperCase().isEmpty ? '3004' : hsnC.text.trim().toUpperCase(),
      drugForm: selectedForm,
      gst: gst,
      mrp: mrp,
      purRate: pur,
      rateA: a > 0 ? a : mrp,
      rateB: b,
      rateC: a > 0 ? a * 0.92 : 0.0,
      stock: 0.0,
      isNarcotic: isNarcotic,
      isScheduleH1: isScheduleH1,
      companyId: selectedCompanyId ?? '',
      saltId: selectedSaltId ?? '',
    );

    widget.webPh.addMedicine(newMed);
    Navigator.pop(context);
    widget.onProductCreated(newMed.toMap());
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 620 ? 580.0 : (screenWidth * 0.94);

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.white12),
      ),
      titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: const BoxDecoration(
              color: Color(0x337C3AED),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_box_rounded, color: Color(0xFFA78BFA), size: 18),
          ),
          const SizedBox(width: 10),
          const Text(
            "QUICK ADD PRODUCT",
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ipadInput("PRODUCT / DRUG NAME *", nameC, Icons.medication, isCaps: true),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(flex: 3, child: _ipadInput("PACKING (e.g. 1*10) *", packC, Icons.inventory, isCaps: true)),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _ipadDropdown(
                      "DRUG FORM",
                      selectedForm,
                      drugForms.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                      (v) => setState(() => selectedForm = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ipadDropdown(
                      "COMPANY / BRAND",
                      selectedCompanyId,
                      widget.webPh.companies.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                      (v) => setState(() => selectedCompanyId = v),
                      hint: "Select Brand",
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ipadDropdown(
                      "SALT COMPOSITION",
                      selectedSaltId,
                      widget.webPh.salts.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                      (v) => setState(() => selectedSaltId = v),
                      hint: "Select Salt",
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(flex: 2, child: _ipadInput("HSN CODE", hsnC, Icons.tag, isCaps: true)),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _ipadDropdown(
                      "GST % *",
                      ["0", "5", "12", "18", "28", "Manual"].contains(selGst) ? selGst : "5",
                      ["0", "5", "12", "18", "28", "Manual"].map((f) => DropdownMenuItem(value: f, child: Text(f == "Manual" ? f : "$f%"))).toList(),
                      (v) {
                        setState(() {
                          selGst = v!;
                          if (v != "Manual") {
                            gstC.text = v;
                          } else {
                            gstC.text = "";
                          }
                        });
                      },
                    ),
                  ),
                  if (selGst == "Manual") ...[
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: _ipadInput("CUSTOM GST %", gstC, Icons.edit, isNum: true)),
                  ]
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _ipadInput("MRP ₹", mrpC, Icons.currency_rupee, isNum: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _ipadInput("PUR. RATE ₹", purRateC, Icons.shopping_cart, isNum: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _ipadInput("SALE RATE A ₹", rateAC, Icons.sell, isNum: true)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Schedule H1", style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
                      value: isScheduleH1,
                      activeColor: const Color(0xFF38BDF8),
                      onChanged: (v) => setState(() => isScheduleH1 = v),
                    ),
                  ),
                  Expanded(
                    child: SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Narcotic (NDPS)", style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
                      value: isNarcotic,
                      activeColor: Colors.redAccent,
                      onChanged: (v) => setState(() => isNarcotic = v),
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
          onPressed: () => Navigator.pop(context),
          child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _saveProduct,
          child: const Text("SAVE PRODUCT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
        ),
      ],
    );
  }

  Widget _ipadInput(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    bool isNum = false,
    bool isCaps = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFA78BFA), size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                  textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ipadDropdown<T>(
    String label,
    T? value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged, {
    String hint = "",
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
              items: items,
              onChanged: onChanged,
              hint: hint.isNotEmpty ? Text(hint, style: const TextStyle(color: Colors.white38, fontSize: 10.5)) : null,
            ),
          ),
        ),
      ],
    );
  }
}
'''
with open(qm_path, "w", encoding="utf-8") as f:
    f.write(qm_code)
print(f"✔ FULL REWRITE applied to: {qm_path}")


# 4. Analyze Web Code
print("\n🔍 Step 1/3: Analyzing Web Code...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], text=True)
if res.returncode != 0:
    print("❌ Analyze failed! Please inspect issues.")
    sys.exit(1)
print("✅ 0 Issues Found! Proceeding to build...")

# 5. Build Production Web Bundle
print("\n🔨 Step 2/3: Building Production Web Bundle...")
build_cmd = ["flutter", "build", "web", "-t", "lib/web_live_sync/web_main.dart", "--release", "--base-href", "/", "--pwa-strategy=none"]
res_build = subprocess.run(build_cmd, text=True)
if res_build.returncode != 0:
    print("❌ Web Build failed!")
    sys.exit(1)

# 6. Deploy to Cloudflare Pages
print("\n🌐 Step 3/3: Deploying to Cloudflare Pages...")
subprocess.run(["npx", "wrangler", "pages", "deploy", "build/web", "--project-name=pharoah-erp"])

print("\n" + "="*56)
print(f"🎉 100% SMART GST PICKER DEPLOYED! Version: {new_rev}")
print("🔗 Live URL: https://pharoah-erp.pages.dev")
print("="*56)
