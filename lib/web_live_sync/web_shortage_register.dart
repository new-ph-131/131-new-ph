// FILE: lib/web_live_sync/web_shortage_register.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'web_models.dart';
import 'pharoah_web_manager.dart';

class WebShortageRegisterView extends StatefulWidget {
  final VoidCallback onBack;

  const WebShortageRegisterView({super.key, required this.onBack});

  @override
  State<WebShortageRegisterView> createState() => _WebShortageRegisterViewState();
}

class _WebShortageRegisterViewState extends State<WebShortageRegisterView> {
  final TextEditingController searchC = TextEditingController();
  String searchQuery = "";
  String? filterCompany;

  @override
  void dispose() {
    searchC.dispose();
    super.dispose();
  }

  void _showManualAddDialog(PharoahWebManager webPh) {
    final qtyC = TextEditingController(text: "1");
    final custC = TextEditingController();
    final medSearchC = TextEditingController();
    Medicine? selectedMed;
    String localMedQuery = "";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredMeds = localMedQuery.isEmpty
              ? <Medicine>[]
              : webPh.medicines
                  .where((m) =>
                      m.name.toLowerCase().contains(localMedQuery.toLowerCase()) ||
                      m.systemId.toLowerCase().contains(localMedQuery.toLowerCase()))
                  .take(6)
                  .toList();

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0x33DC2626),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_shopping_cart_rounded, color: Color(0xFFF87171), size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  "ADD MANUAL SHORTAGE REQUIREMENT",
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (selectedMed == null) ...[
                      TextField(
                        controller: medSearchC,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: "SEARCH PRODUCT *",
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
                          hintText: "Type medicine name (e.g. DOLO, PAN)...",
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFFF87171), size: 18),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        onChanged: (v) => setDialogState(() => localMedQuery = v),
                      ),
                      if (filteredMeds.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0x33F87171)),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredMeds.length,
                            itemBuilder: (ctx, idx) {
                              final m = filteredMeds[idx];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.medication_rounded, color: Color(0xFFF87171), size: 18),
                                title: Text(m.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                subtitle: Text("Pack: ${m.packing} • Current Stock: ${m.stock.toInt()} Qty", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                onTap: () => setDialogState(() => selectedMed = m),
                              );
                            },
                          ),
                        ),
                      ],
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFDC2626)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.medication_rounded, color: Color(0xFFF87171), size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${selectedMed!.name} (${selectedMed!.packing})",
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                                  ),
                                  Text(
                                    "Live Stock: ${selectedMed!.stock.toInt()} Qty • MRP: ₹${selectedMed!.mrp.toStringAsFixed(2)}",
                                    style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                              onPressed: () => setDialogState(() {
                                selectedMed = null;
                                localMedQuery = "";
                                medSearchC.clear();
                              }),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: qtyC,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: "REQUIREMENT QUANTITY *",
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
                          prefixIcon: const Icon(Icons.add_shopping_cart_rounded, color: Color(0xFFF87171), size: 18),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: custC,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: "CUSTOMER DEMAND / PARTY NAME (OPTIONAL)",
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
                          hintText: "e.g. Dr. Verma / Sharma Medicals...",
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                          prefixIcon: const Icon(Icons.person_pin_rounded, color: Colors.white54, size: 18),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ],
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
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: selectedMed == null
                    ? null
                    : () {
                        double req = double.tryParse(qtyC.text) ?? 1.0;
                        if (req <= 0) return;
                        webPh.addManualShortage(
                          med: selectedMed!,
                          qty: req,
                          cust: custC.text.trim(),
                        );
                        Navigator.pop(c);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("✅ Added to Shortage Order List!"), backgroundColor: Colors.green),
                        );
                      },
                child: const Text("ADD TO SHORTAGE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
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

    // Filter Shortages
    final filteredShortages = webPh.shortages.where((s) {
      bool matchesSearch = searchQuery.isEmpty ||
          s.medicineName.toLowerCase().contains(searchQuery.toLowerCase()) ||
          s.companyName.toLowerCase().contains(searchQuery.toLowerCase()) ||
          s.customerName.toLowerCase().contains(searchQuery.toLowerCase());
      bool matchesCompany = filterCompany == null || filterCompany == "ALL" || s.companyName == filterCompany;
      return matchesSearch && matchesCompany;
    }).toList();

    // Unique Companies in Shortage List
    final availableCompanies = webPh.shortages.map((s) => s.companyName).toSet().toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                label: const Text("BACK TO INVENTORY", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.trending_down_rounded, color: Color(0xFFF87171), size: 24),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "SHORTAGE & ORDER REQUIREMENT REGISTER",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  Text(
                    "Intelligent 1.5x monthly sale requirement & customer demand tracker",
                    style: TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: () {
                  webPh.runAutoShortageScan();
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("⚡ Auto-Scan Complete! 45-day stock requirement calculated."),
                      backgroundColor: Color(0xFF2563EB),
                    ),
                  );
                },
                icon: const Icon(Icons.psychology_alt_rounded, size: 18),
                label: const Text("RUN 1.5x AUTO-SCAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: () => _showManualAddDialog(webPh),
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: const Text("+ MANUAL SHORTAGE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 25),

          // Filters Row
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: searchC,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: "Search by Product Name, Brand, or Customer...",
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFFF87171), size: 18),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 16),
                              onPressed: () {
                                searchC.clear();
                                setState(() => searchQuery = "");
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    onChanged: (v) => setState(() => searchQuery = v),
                  ),
                ),
                const SizedBox(width: 14),
                if (availableCompanies.isNotEmpty) ...[
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: filterCompany ?? "ALL",
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                          items: [
                            const DropdownMenuItem(value: "ALL", child: Text("ALL BRANDS / COMPANIES")),
                            ...availableCompanies.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                          ],
                          onChanged: (v) => setState(() => filterCompany = v),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Shortage Data Table (Auto-Adjusting)
          if (filteredShortages.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 60),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, size: 45, color: Color(0xFF10B981)),
                    SizedBox(height: 12),
                    Text(
                      "No shortages found! All inventory stocks are healthy.",
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Click 'RUN 1.5x AUTO-SCAN' above to recalculate 45-day requirements from live sales.",
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final double availableWidth = constraints.maxWidth;
                final double tableWidth = availableWidth > 900 ? availableWidth : 900;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: availableWidth < 900
                            ? const BouncingScrollPhysics()
                            : const NeverScrollableScrollPhysics(),
                        child: SizedBox(
                          width: tableWidth,
                          child: Table(
                            columnWidths: const {
                              0: FixedColumnWidth(60),
                              1: FlexColumnWidth(3.0),
                              2: FlexColumnWidth(2.0),
                              3: FlexColumnWidth(1.4),
                              4: FlexColumnWidth(1.6),
                              5: FlexColumnWidth(2.0),
                              6: FixedColumnWidth(100),
                              7: FixedColumnWidth(60),
                            },
                            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                            children: [
                              TableRow(
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0F172A),
                                  border: Border(bottom: BorderSide(color: Colors.white24, width: 1)),
                                ),
                                children: [
                                  _th("SRC"),
                                  _th("MEDICINE NAME", isLeft: true),
                                  _th("BRAND / COMPANY"),
                                  _th("STOCK", isRight: true),
                                  _th("30D SALE", isRight: true),
                                  _th("CUSTOMER DEMAND"),
                                  _th("ORDER QTY", isRight: true),
                                  _th("ACT"),
                                ],
                              ),
                              for (int i = 0; i < filteredShortages.length; i++) ...[
                                TableRow(
                                  decoration: BoxDecoration(
                                    color: i % 2 == 1 ? const Color(0x0DFFFFFF) : Colors.transparent,
                                    border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
                                  ),
                                  children: [
                                    _tdSourceBadge(filteredShortages[i].source),
                                    _td(filteredShortages[i].medicineName, isLeft: true, isBold: true),
                                    _td(filteredShortages[i].companyName),
                                    _td("${filteredShortages[i].currentStock.toInt()}", isRight: true, color: filteredShortages[i].currentStock > 0 ? Colors.greenAccent : Colors.redAccent),
                                    _td(webPh.calculateAvgMonthlySale(filteredShortages[i].medicineId).toStringAsFixed(1), isRight: true),
                                    _tdCustomerBadge(filteredShortages[i].customerName),
                                    _tdOrderBadge(filteredShortages[i].qtyRequired),
                                    Center(
                                      child: IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                        tooltip: "Remove Shortage",
                                        onPressed: () {
                                          webPh.deleteShortage(filteredShortages[i].id);
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "TOTAL SHORTAGE ITEMS: ${filteredShortages.length}",
                            style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            "TOTAL UNITS TO ORDER: ${filteredShortages.fold(0.0, (sum, s) => sum + s.qtyRequired).toInt()} Qty",
                            style: const TextStyle(color: Color(0xFFF87171), fontSize: 13, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false, bool isRight = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    child: Text(
      t,
      textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center),
      style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
    ),
  );

  Widget _td(String t, {bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    child: Text(
      t,
      textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center),
      style: TextStyle(color: color, fontSize: 11.5, fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
      overflow: TextOverflow.ellipsis,
    ),
  );

  Widget _tdSourceBadge(String src) {
    bool isAuto = src == "Auto";
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isAuto ? const Color(0x332563EB) : const Color(0x33EA580C),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          isAuto ? "AUTO" : "MAN",
          style: TextStyle(
            color: isAuto ? const Color(0xFF60A5FA) : const Color(0xFFFB923C),
            fontSize: 8,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _tdCustomerBadge(String cust) {
    if (cust.trim().isEmpty) return const Center(child: Text("-", style: TextStyle(color: Colors.white24)));
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0x2638BDF8),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x6638BDF8), width: 0.5),
        ),
        child: Text(
          cust,
          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _tdOrderBadge(double qty) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0x33DC2626),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFDC2626), width: 0.8),
          ),
          child: Text(
            "${qty.toInt()} Units",
            style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.w900, fontSize: 11),
          ),
        ),
      ),
    );
  }
}
