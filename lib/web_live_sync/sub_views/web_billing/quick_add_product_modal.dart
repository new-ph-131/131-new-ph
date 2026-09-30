// FILE: lib/web_live_sync/sub_views/web_billing/quick_add_product_modal.dart

import 'package:flutter/material.dart';
import '../../web_models.dart';
import '../../pharoah_web_manager.dart';

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
  final packC = TextEditingController(text: "10 TAB");
  final hsnC = TextEditingController(text: "3004");
  final gstC = TextEditingController(text: "12");
  final mrpC = TextEditingController(text: "0.0");
  final purRateC = TextEditingController(text: "0.0");
  final rateAC = TextEditingController(text: "0.0");
  final rateBC = TextEditingController(text: "0.0");

  String selectedForm = "TAB";
  String? selectedCompanyId;
  String? selectedSaltId;
  bool isNarcotic = false;
  bool isScheduleH1 = false;

  final List<String> drugForms = ["TAB", "CAP", "SYP", "INJ", "IV", "PCS", "EXT", "OINT", "DROP"];

  @override
  void initState() {
    super.initState();
    if (widget.preFillData != null) {
      final pf = widget.preFillData!;
      nameC.text = (pf['name'] ?? '').toString();
      packC.text = (pf['pack'] ?? '10 TAB').toString();
      hsnC.text = (pf['hsn'] ?? '3004').toString();
      gstC.text = (pf['gst'] ?? 12).toString();
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
    if (nameC.text.trim().isEmpty || packC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Product Name and Packing are required!"), backgroundColor: Colors.orange),
      );
      return;
    }

    double mrp = double.tryParse(mrpC.text) ?? 0.0;
    double pur = double.tryParse(purRateC.text) ?? 0.0;
    double a = double.tryParse(rateAC.text) ?? (mrp > 0 ? mrp : 0.0);
    double b = double.tryParse(rateBC.text) ?? (a > 0 ? a * 0.95 : 0.0);
    double gst = double.tryParse(gstC.text) ?? 12.0;

    String sysId = "PH-W-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";

    final newMed = Medicine(
      id: sysId,
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
                  Expanded(flex: 3, child: _ipadInput("PACKING *", packC, Icons.inventory, isCaps: true)),
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
                  Expanded(child: _ipadInput("HSN CODE", hsnC, Icons.tag, isCaps: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _ipadInput("GST %", gstC, Icons.percent, isNum: true)),
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
