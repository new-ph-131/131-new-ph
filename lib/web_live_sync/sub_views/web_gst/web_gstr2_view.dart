// FILE: lib/web_live_sync/sub_views/web_gst/web_gstr2_view.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../../compliance/gst_offline_engine/gst_offline_export_service.dart';

class WebGstr2View extends StatefulWidget {
  final PharoahWebManager webPh;
  final VoidCallback onBack;

  const WebGstr2View({super.key, required this.webPh, required this.onBack});

  @override
  State<WebGstr2View> createState() => _WebGstr2ViewState();
}

class _WebGstr2ViewState extends State<WebGstr2View> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

    final purchases = widget.webPh.purchases.where((p) {
      final d = _dateOnly(p.date);
      return !d.isBefore(fDate) && !d.isAfter(tDate);
    }).toList();

    final purchaseReturns = widget.webPh.purchaseReturns.where((pr) {
      final d = _dateOnly(pr.date);
      return !d.isBefore(fDate) && !d.isAfter(tDate);
    }).toList();

    double totalTaxable = 0.0;
    double totalItc = 0.0;
    double totalGrand = 0.0;

    for (var p in purchases) {
      double t = p.items.fold(0.0, (s, i) => s + (i.purchaseRate * i.qty));
      totalTaxable += t;
      totalItc += (p.totalAmount - t);
      totalGrand += p.totalAmount;
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
                    decoration: BoxDecoration(color: const Color(0xFFF59E0B).withAlpha(30), shape: BoxShape.circle),
                    child: const Icon(Icons.shopping_cart_checkout_rounded, color: Color(0xFFF59E0B), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text("GSTR-2 INWARD SUPPLIES & ITC ENGINE", style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
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

          // SUMMARY STRIP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metric("INWARD BILLS", "${purchases.length}"),
                _metric("DEBIT NOTES", "${purchaseReturns.length}", color: Colors.orangeAccent),
                _metric("TAXABLE PURCHASES", "₹${totalTaxable.toStringAsFixed(2)}"),
                _metric("ELIGIBLE INPUT TAX (ITC)", "₹${totalItc.toStringAsFixed(2)}", color: Colors.greenAccent),
                _metric("TOTAL INWARD VALUE", "₹${totalGrand.toStringAsFixed(2)}", color: const Color(0xFF38BDF8)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // TABS & ACTIONS
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFFF59E0B),
                    labelColor: const Color(0xFFFBBF24),
                    unselectedLabelColor: Colors.white54,
                    tabs: [
                      Tab(text: "INWARD PURCHASES (${purchases.length})"),
                      Tab(text: "DEBIT NOTES / RETURNS (${purchaseReturns.length})"),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // EXPORT INWARD CSV BUTTON
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: purchases.isEmpty ? null : () {
                  GstOfflineExportService.exportCsvSection(
                    context: context,
                    section: "GSTR2_INWARD",
                    purchases: purchases,
                    parties: widget.webPh.parties,
                    shop: shopProfile,
                    fromDate: fromDate,
                    toDate: toDate,
                  );
                },
                icon: const Icon(Icons.file_download_rounded, size: 16),
                label: const Text("EXPORT INWARD CSV", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              const SizedBox(width: 8),

              // EXPORT DEBIT NOTES CSV BUTTON
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: purchaseReturns.isEmpty ? null : () {
                  GstOfflineExportService.exportCsvSection(
                    context: context,
                    section: "GSTR2_DEBIT",
                    purchaseReturns: purchaseReturns,
                    parties: widget.webPh.parties,
                    shop: shopProfile,
                    fromDate: fromDate,
                    toDate: toDate,
                  );
                },
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: const Text("DEBIT NOTES CSV", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
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
                _buildPurchasesTable(purchases),
                _buildDebitNotesTable(purchaseReturns),
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

  Widget _buildPurchasesTable(List<Purchase> list) {
    if (list.isEmpty) {
      return const Center(child: Text("No inward purchase bills found in date range.", style: TextStyle(color: Colors.white38)));
    }
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(85),
          1: FixedColumnWidth(110),
          2: FlexColumnWidth(3),
          3: FixedColumnWidth(120),
          4: FixedColumnWidth(120),
          5: FixedColumnWidth(130),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFF0F172A), border: Border(bottom: BorderSide(color: Colors.white24))),
            children: [
              _th("DATE"), _th("BILL NO"), _th("SUPPLIER NAME", isLeft: true),
              _th("TAXABLE ₹", isRight: true), _th("ITC TAX ₹", isRight: true), _th("TOTAL ₹", isRight: true),
            ],
          ),
          for (var p in list) _buildPurchaseRow(p),
        ],
      ),
    );
  }

  Widget _buildDebitNotesTable(List<PurchaseReturn> list) {
    if (list.isEmpty) {
      return const Center(child: Text("No purchase returns / debit notes in date range.", style: TextStyle(color: Colors.white38)));
    }
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(85),
          1: FixedColumnWidth(110),
          2: FlexColumnWidth(3),
          3: FixedColumnWidth(120),
          4: FixedColumnWidth(130),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFF0F172A), border: Border(bottom: BorderSide(color: Colors.white24))),
            children: [
              _th("DATE"), _th("NOTE NO"), _th("SUPPLIER NAME", isLeft: true),
              _th("RETURN TYPE"), _th("TOTAL ₹", isRight: true),
            ],
          ),
          for (var pr in list)
            TableRow(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
              children: [
                _td(DateFormat('dd/MM/yy').format(pr.date)),
                _td(pr.billNo, isBold: true),
                _td(pr.partyName, isLeft: true),
                _td(pr.returnType, color: Colors.orangeAccent),
                _td("₹${pr.totalAmount.toStringAsFixed(2)}", isRight: true, isBold: true, color: Colors.greenAccent),
              ],
            ),
        ],
      ),
    );
  }

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

  TableRow _buildPurchaseRow(Purchase p) {
    double tRow = p.items.fold(0.0, (s, i) => s + (i.purchaseRate * i.qty));
    double itc = p.totalAmount - tRow;
    return TableRow(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
      children: [
        _td(DateFormat('dd/MM/yy').format(p.date)),
        _td(p.billNo, isBold: true),
        _td(p.distributorName, isLeft: true),
        _td("₹${tRow.toStringAsFixed(2)}", isRight: true),
        _td("₹${itc.toStringAsFixed(2)}", isRight: true, color: Colors.greenAccent),
        _td("₹${p.totalAmount.toStringAsFixed(2)}", isRight: true, isBold: true),
      ],
    );
  }
}
