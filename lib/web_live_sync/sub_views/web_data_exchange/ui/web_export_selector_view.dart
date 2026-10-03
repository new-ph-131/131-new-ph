// FILE: lib/web_live_sync/sub_views/web_data_exchange/ui/web_export_selector_view.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_saver/file_saver.dart';
import '../../../web_models.dart';
import '../../../pharoah_web_manager.dart';
import '../../../web_app_date_logic.dart';
import '../engine/web_csv_engine.dart';

class WebExportSelectorView extends StatefulWidget {
  final String exportType; // "SALE" or "PURCHASE"
  final bool maskPurchaseRate;
  final VoidCallback onBack;

  const WebExportSelectorView({
    super.key,
    required this.exportType,
    this.maskPurchaseRate = false,
    required this.onBack,
  });

  @override
  State<WebExportSelectorView> createState() => _WebExportSelectorViewState();
}

class _WebExportSelectorViewState extends State<WebExportSelectorView> {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  String searchQuery = "";
  List<String> selectedBillIds = [];
  bool isExporting = false;
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final now = DateTime.now();
      toDate = DateTime(now.year, now.month, now.day);
      fromDate = toDate.subtract(const Duration(days: 30));
      _isInit = true;
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  void _trigger39CsvExport(List<dynamic> selectedBills, PharoahWebManager webPh) async {
    if (selectedBills.isEmpty) return;

    setState(() => isExporting = true);

    final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);
    String csvString = "";

    if (widget.exportType == "SALE") {
      csvString = WebCsvEngine.convertSalesTo39Csv(
        sales: selectedBills.cast<Sale>(),
        shop: shopProfile,
        allMeds: webPh.medicines,
        allComps: webPh.companies,
        allSalts: webPh.salts,
        allParties: webPh.parties,
        maskPurchaseRate: widget.maskPurchaseRate,
      );
    } else {
      csvString = WebCsvEngine.convertPurchasesTo39Csv(
        purchases: selectedBills.cast<Purchase>(),
        shop: shopProfile,
        allMeds: webPh.medicines,
        allComps: webPh.companies,
        allSalts: webPh.salts,
        allParties: webPh.parties,
      );
    }

    Uint8List bytes = Uint8List.fromList(utf8.encode(csvString));
    String modeTag = widget.maskPurchaseRate ? "C2V_MASKED" : "C2C_FULL";
    String fileName = "${widget.exportType}_39COL_${modeTag}_${DateFormat('ddMMMyy_HHmm').format(DateTime.now())}";

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      ext: "csv",
      mimeType: MimeType.csv,
    );

    setState(() => isExporting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ Exported ${selectedBills.length} bills into 39-Col CSV ($fileName.csv)!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final bool isSale = widget.exportType == "SALE";
    final fDate = _dateOnly(fromDate);
    final tDate = _dateOnly(toDate);

    List<dynamic> sourceList = isSale ? webPh.sales : webPh.purchases;
    if (isSale) {
      sourceList = sourceList.where((s) => (s as Sale).status == "Active").toList();
    }
    sourceList = sourceList.reversed.toList();

    final filteredList = sourceList.where((item) {
      DateTime dt = isSale ? (item as Sale).date : (item as Purchase).date;
      final d = _dateOnly(dt);
      bool dateMatch = !d.isBefore(fDate) && !d.isAfter(tDate);

      String pName = isSale ? (item as Sale).partyName : (item as Purchase).distributorName;
      String billNo = isSale ? (item as Sale).billNo : (item as Purchase).billNo;
      String q = searchQuery.trim().toLowerCase();
      bool searchMatch = q.isEmpty || pName.toLowerCase().contains(q) || billNo.toLowerCase().contains(q);

      return dateMatch && searchMatch;
    }).toList();

    bool allSelected = filteredList.isNotEmpty && filteredList.every((b) {
      String id = isSale ? (b as Sale).id : (b as Purchase).id;
      return selectedBillIds.contains(id);
    });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                label: const Text("BACK TO DATA HUB", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              Icon(isSale ? Icons.file_upload_rounded : Icons.inventory_2_outlined, color: const Color(0xFF38BDF8), size: 24),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "EXPORT ${widget.exportType} (39-COLUMN UNIVERSAL CSV)",
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  Text(
                    widget.maskPurchaseRate
                        ? "C2V Mode: Purchase rates are masked to 0.0 for external trade privacy"
                        : "C2C Mode: Full data sync with actual purchase & sale rates",
                    style: TextStyle(
                      color: widget.maskPurchaseRate ? const Color(0xFFFBBF24) : Colors.greenAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 25),

          // Filters Bar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: "Search by Party Name or Bill No...",
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 16),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 16),
                              onPressed: () => setState(() => searchQuery = ""),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onChanged: (v) => setState(() => searchQuery = v),
                  ),
                ),
                const SizedBox(width: 10),
                _dateChip("FROM", fromDate, (d) => setState(() => fromDate = d), webPh.financialYear),
                const SizedBox(width: 8),
                _dateChip("TO", toDate, (d) => setState(() => toDate = d), webPh.financialYear),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: filteredList.isEmpty
                      ? null
                      : () {
                          setState(() {
                            if (allSelected) {
                              selectedBillIds.clear();
                            } else {
                              selectedBillIds = filteredList.map((b) => isSale ? (b as Sale).id : (b as Purchase).id).toList();
                            }
                          });
                        },
                  icon: Icon(allSelected ? Icons.deselect_rounded : Icons.select_all_rounded, size: 16, color: const Color(0xFF38BDF8)),
                  label: Text(
                    allSelected ? "UNSELECT ALL" : "SELECT ALL",
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Invoices Table
          Expanded(
            child: filteredList.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(40),
                    alignment: Alignment.center,
                    child: Text("No ${widget.exportType} records found matching date or search query.", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: SingleChildScrollView(
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(50),
                          1: FixedColumnWidth(90),
                          2: FixedColumnWidth(110),
                          3: FlexColumnWidth(3.0),
                          4: FixedColumnWidth(80),
                          5: FixedColumnWidth(75),
                          6: FixedColumnWidth(110),
                        },
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(color: Color(0xFF0F172A), border: Border(bottom: BorderSide(color: Colors.white24))),
                            children: [
                              const Center(child: Icon(Icons.check_box_outline_blank, color: Colors.white54, size: 16)),
                              _th("DATE"),
                              _th("BILL NO"),
                              _th("PARTY / FIRM NAME", isLeft: true),
                              _th("MODE"),
                              _th("ITEMS", isRight: true),
                              _th("TOTAL AMOUNT", isRight: true),
                            ],
                          ),
                          for (int i = 0; i < filteredList.length; i++)
                            _buildTableRow(filteredList[i], i, isSale),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 14),

          // Bottom Action Dock
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "SELECTED FOR EXPORT: ${selectedBillIds.length} BILLS",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: selectedBillIds.isEmpty || isExporting
                        ? null
                        : () {
                            final chosen = filteredList.where((b) {
                              String id = isSale ? (b as Sale).id : (b as Purchase).id;
                              return selectedBillIds.contains(id);
                            }).toList();
                            _trigger39CsvExport(chosen, webPh);
                          },
                    icon: isExporting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.file_download_rounded, size: 18),
                    label: Text(
                      isExporting ? "EXPORTING..." : "EXPORT SELECTED TO 39-COL CSV",
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildTableRow(dynamic item, int i, bool isSale) {
    String id = isSale ? (item as Sale).id : (item as Purchase).id;
    DateTime dt = isSale ? (item as Sale).date : (item as Purchase).date;
    String bNo = isSale ? (item as Sale).billNo : (item as Purchase).billNo;
    String pName = isSale ? (item as Sale).partyName : (item as Purchase).distributorName;
    String mode = isSale ? (item as Sale).paymentMode : (item as Purchase).paymentMode;
    int itemCount = isSale ? (item as Sale).items.length : (item as Purchase).items.length;
    double total = isSale ? (item as Sale).totalAmount : (item as Purchase).totalAmount;
    bool isChecked = selectedBillIds.contains(id);

    return TableRow(
      decoration: BoxDecoration(
        color: isChecked ? const Color(0x2638BDF8) : (i % 2 == 1 ? const Color(0x0DFFFFFF) : Colors.transparent),
        border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      children: [
        Center(
          child: Checkbox(
            value: isChecked,
            activeColor: const Color(0xFF38BDF8),
            onChanged: (v) {
              setState(() {
                v == true ? selectedBillIds.add(id) : selectedBillIds.remove(id);
              });
            },
          ),
        ),
        _td(DateFormat('dd/MM/yy').format(dt)),
        _td(bNo, isBold: true, color: const Color(0xFF38BDF8)),
        _td(pName, isLeft: true),
        _td(mode),
        _td("$itemCount", isRight: true),
        _td("₹${total.toStringAsFixed(2)}", isRight: true, isBold: true, color: Colors.greenAccent),
      ],
    );
  }

  Widget _dateChip(String label, DateTime dt, Function(DateTime) onPick, String fy) {
    return InkWell(
      onTap: () async {
        final p = await showDatePicker(
          context: context,
          initialDate: dt,
          firstDate: WebAppDateLogic.getFYStart(fy),
          lastDate: WebAppDateLogic.getFYEnd(fy),
        );
        if (p != null) onPick(p);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
        child: Row(
          children: [
            Text("$label: ${DateFormat('dd/MM/yy').format(dt)}", style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF38BDF8)),
          ],
        ),
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false, bool isRight = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
  );
}
