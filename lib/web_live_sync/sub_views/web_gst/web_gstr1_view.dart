// FILE: lib/web_live_sync/sub_views/web_gst/web_gstr1_view.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../../compliance/gst_offline_engine/gst_offline_export_service.dart';

class WebGstr1View extends StatefulWidget {
  final PharoahWebManager webPh;
  final VoidCallback onBack;

  const WebGstr1View({super.key, required this.webPh, required this.onBack});

  @override
  State<WebGstr1View> createState() => _WebGstr1ViewState();
}

class _WebGstr1ViewState extends State<WebGstr1View> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final now = DateTime.now();
      toDate = DateTime(now.year, now.month, now.day);
      fromDate = DateTime(now.year, now.month, 1);
      _isInit = true;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  CompanyProfile _getShopProfile() {
    return CompanyProfile.fromMap(widget.webPh.companyProfile);
  }

  @override
  Widget build(BuildContext context) {
    final fDate = _dateOnly(fromDate);
    final tDate = _dateOnly(toDate);

    final periodSales = widget.webPh.sales.where((s) {
      final d = _dateOnly(s.date);
      return !d.isBefore(fDate) && !d.isAfter(tDate);
    }).toList();

    final activeSales = periodSales.where((s) => s.status == "Active").toList();

    final b2b = activeSales.where((s) => s.partyGstin.trim().length == 15).toList();
    final b2c = activeSales.where((s) => s.partyGstin.trim().length != 15).toList();

    double totalTaxable = 0.0;
    double totalTax = 0.0;
    double grandTotal = 0.0;

    for (var s in activeSales) {
      double t = s.items.fold(0.0, (sum, i) => sum + (i.cgst + i.sgst + i.igst));
      totalTax += t;
      totalTaxable += (s.totalAmount - t);
      grandTotal += s.totalAmount;
    }

    final Map<String, Map<String, dynamic>> hsnSummary = {};
    for (var s in activeSales) {
      for (var it in s.items) {
        String cleanHsn = it.hsn.trim().replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanHsn.isEmpty) cleanHsn = "3004";
        double t = it.cgst + it.sgst + it.igst;
        double tx = it.total - t;
        if (hsnSummary.containsKey(cleanHsn)) {
          hsnSummary[cleanHsn]!['qty'] += (it.qty + it.freeQty);
          hsnSummary[cleanHsn]!['taxable'] += tx;
          hsnSummary[cleanHsn]!['tax'] += t;
          hsnSummary[cleanHsn]!['total'] += it.total;
        } else {
          hsnSummary[cleanHsn] = {
            'qty': (it.qty + it.freeQty),
            'taxable': tx,
            'tax': t,
            'total': it.total,
          };
        }
      }
    }

    final shopProfile = _getShopProfile();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // HEADER ROW
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFF10B981).withAlpha(30), shape: BoxShape.circle),
                    child: const Icon(Icons.assignment_outlined, color: Color(0xFF10B981), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text("GSTR-1 OUTWARD SUPPLIES & OFF-LINE ENGINE", style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ],
              ),
              Row(
                children: [
                  _dateChip("FROM", fromDate, (d) => setState(() => fromDate = d)),
                  const SizedBox(width: 8),
                  _dateChip("TO", toDate, (d) => setState(() => toDate = d)),
                ],
              )
            ],
          ),
          const SizedBox(height: 14),

          // SUMMARY METRICS STRIP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metric("TOTAL INVOICES", "${activeSales.length}"),
                _metric("B2B INVOICES", "${b2b.length}", color: const Color(0xFF38BDF8)),
                _metric("B2C INVOICES", "${b2c.length}", color: const Color(0xFFA78BFA)),
                _metric("TAXABLE VALUE", "₹${totalTaxable.toStringAsFixed(2)}"),
                _metric("TOTAL TAX", "₹${totalTax.toStringAsFixed(2)}", color: Colors.orangeAccent),
                _metric("INVOICE VALUE", "₹${grandTotal.toStringAsFixed(2)}", color: Colors.greenAccent),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // TAB BAR & ACTION BUTTONS ROW
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFF10B981),
                    labelColor: const Color(0xFF34D399),
                    unselectedLabelColor: Colors.white54,
                    tabs: [
                      Tab(text: "B2B (${b2b.length})"),
                      Tab(text: "B2C (${b2c.length})"),
                      Tab(text: "HSN SUMMARY (${hsnSummary.length})"),
                      Tab(text: "DOCUMENTS (${periodSales.length})"),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              
              // ⚡ BUTTON 1: GOVT OFFLINE JSON
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: activeSales.isEmpty ? null : () {
                  GstOfflineExportService.exportGstr1Json(
                    context: context,
                    sales: widget.webPh.sales,
                    returns: widget.webPh.saleReturns,
                    parties: widget.webPh.parties,
                    shop: shopProfile,
                    fromDate: fromDate,
                    toDate: toDate,
                  );
                },
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: const Text("GOVT JSON (OFFLINE)", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
              ),
              const SizedBox(width: 8),

              // 🔍 BUTTON 2: PRE-UPLOAD AUDIT
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: activeSales.isEmpty ? null : () {
                  GstOfflineExportService.showAuditModal(
                    context: context,
                    sales: widget.webPh.sales,
                    returns: widget.webPh.saleReturns,
                    parties: widget.webPh.parties,
                    shop: shopProfile,
                    fromDate: fromDate,
                    toDate: toDate,
                  );
                },
                icon: const Icon(Icons.fact_check_rounded, size: 15),
                label: const Text("AUDIT CHECK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              const SizedBox(width: 8),

              // 📂 BUTTON 3: GOVT CSV PACK
              PopupMenuButton<String>(
                tooltip: "Export GST Offline CSVs",
                onSelected: (sec) {
                  GstOfflineExportService.exportCsvSection(
                    context: context,
                    section: sec,
                    sales: widget.webPh.sales,
                    parties: widget.webPh.parties,
                    shop: shopProfile,
                    fromDate: fromDate,
                    toDate: toDate,
                  );
                },
                itemBuilder: (c) => [
                  const PopupMenuItem(value: "B2B", child: Text("Export B2B CSV (v2.2)")),
                  const PopupMenuItem(value: "B2CS", child: Text("Export B2CS CSV (v2.2)")),
                  const PopupMenuItem(value: "HSN", child: Text("Export HSN CSV (Table 12)")),
                  const PopupMenuItem(value: "DOCS", child: Text("Export Docs CSV (Table 13)")),
                ],
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.table_chart_rounded, size: 15, color: Colors.white),
                      SizedBox(width: 6),
                      Text("CSV PACK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                      Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // TAB VIEWS
          SizedBox(
            height: 480,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSalesTable(b2b, true),
                _buildSalesTable(b2c, false),
                _buildHsnTable(hsnSummary),
                _buildDocsTable(periodSales),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String title, String val, {Color color = Colors.white}) => Column(
    children: [
      Text(title, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
      const SizedBox(height: 3),
      Text(val, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
    ],
  );

  Widget _buildSalesTable(List<Sale> list, bool isB2b) {
    if (list.isEmpty) {
      return Center(child: Text("No ${isB2b ? 'B2B (Registered)' : 'B2C (Consumer)'} sales in selected period.", style: const TextStyle(color: Colors.white38)));
    }
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(85),
          1: FixedColumnWidth(100),
          2: FlexColumnWidth(3),
          3: FixedColumnWidth(130),
          4: FixedColumnWidth(100),
          5: FixedColumnWidth(90),
          6: FixedColumnWidth(110),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFF0F172A), border: Border(bottom: BorderSide(color: Colors.white24))),
            children: [
              _th("DATE"), _th("INVOICE NO"), _th("PARTY NAME", isLeft: true),
              _th(isB2b ? "GSTIN" : "STATE"), _th("TAXABLE ₹", isRight: true),
              _th("TAX ₹", isRight: true), _th("TOTAL ₹", isRight: true),
            ],
          ),
          for (var s in list) _buildSaleRow(s, isB2b),
        ],
      ),
    );
  }

  Widget _buildHsnTable(Map<String, Map<String, dynamic>> map) {
    if (map.isEmpty) return const Center(child: Text("No HSN data found.", style: TextStyle(color: Colors.white38)));
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(120),
          1: FixedColumnWidth(100),
          2: FlexColumnWidth(2),
          3: FlexColumnWidth(2),
          4: FlexColumnWidth(2),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFF0F172A), border: Border(bottom: BorderSide(color: Colors.white24))),
            children: [_th("HSN CODE", isLeft: true), _th("TOTAL QTY", isRight: true), _th("TAXABLE VALUE", isRight: true), _th("TOTAL TAX", isRight: true), _th("TOTAL VALUE", isRight: true)],
          ),
          for (var entry in map.entries)
            TableRow(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
              children: [
                _td(entry.key, isLeft: true, isBold: true, color: const Color(0xFF38BDF8)),
                _td("${entry.value['qty'].toInt()} Units", isRight: true),
                _td("₹${(entry.value['taxable'] as double).toStringAsFixed(2)}", isRight: true),
                _td("₹${(entry.value['tax'] as double).toStringAsFixed(2)}", isRight: true, color: Colors.orangeAccent),
                _td("₹${(entry.value['total'] as double).toStringAsFixed(2)}", isRight: true, isBold: true, color: Colors.greenAccent),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDocsTable(List<Sale> all) {
    int total = all.length;
    int cancelled = all.where((s) => s.status == "Cancelled").length;
    int active = total - cancelled;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("DOCUMENT SUMMARY (TABLE 13)", style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w900, fontSize: 13)),
            const Divider(color: Colors.white12, height: 25),
            _statRow("Total Invoices Issued", "$total", Colors.white),
            _statRow("Active / Valid Invoices", "$active", Colors.greenAccent),
            _statRow("Cancelled Invoices", "$cancelled", Colors.redAccent),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String val, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)), Text(val, style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w900))]),
  );

  Widget _dateChip(String label, DateTime dt, Function(DateTime) onPick) {
    return InkWell(
      onTap: () async {
        final p = await showDatePicker(context: context, initialDate: dt, firstDate: DateTime(2020), lastDate: DateTime(2035));
        if (p != null) onPick(p);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
        child: Text("$label: ${DateFormat('dd/MM/yy').format(dt)}", style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false, bool isRight = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
  );

  TableRow _buildSaleRow(Sale s, bool isB2b) {
    double tax = s.items.fold(0.0, (sum, i) => sum + (i.cgst + i.sgst + i.igst));
    double taxable = s.totalAmount - tax;
    return TableRow(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
      children: [
        _td(DateFormat('dd/MM/yy').format(s.date)),
        _td(s.billNo, isBold: true),
        _td(s.partyName, isLeft: true),
        _td(isB2b ? s.partyGstin : s.partyState),
        _td("₹${taxable.toStringAsFixed(2)}", isRight: true),
        _td("₹${tax.toStringAsFixed(2)}", isRight: true, color: Colors.orangeAccent),
        _td("₹${s.totalAmount.toStringAsFixed(2)}", isRight: true, isBold: true, color: Colors.greenAccent),
      ],
    );
  }
}
