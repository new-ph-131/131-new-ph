// FILE: lib/web_live_sync/sub_views/web_accounts/web_voucher_history_widget.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../web_app_date_logic.dart';
import '../../web_pdf_router_service.dart';
import 'web_accounts_excel_service.dart';

class WebVoucherHistoryWidget extends StatefulWidget {
  final PharoahWebManager webPh;
  final Function(Voucher voucher, bool isReadOnly) onEditVoucher;

  const WebVoucherHistoryWidget({
    super.key,
    required this.webPh,
    required this.onEditVoucher,
  });

  @override
  State<WebVoucherHistoryWidget> createState() => _WebVoucherHistoryWidgetState();
}

class _WebVoucherHistoryWidgetState extends State<WebVoucherHistoryWidget> {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  String searchQuery = "";
  String typeFilter = "ALL"; // ALL, RECEIPT, PAYMENT, CONTRA, EXPENSE
  String modeFilter = "ALL"; // ALL, Cash, Bank
  bool showAllDates = false;
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final now = DateTime.now();
      toDate = DateTime(now.year, now.month, now.day);
      DateTime thirtyDaysAgo = toDate.subtract(const Duration(days: 30));
      DateTime fyStart = WebAppDateLogic.getFYStart(widget.webPh.financialYear);
      fromDate = thirtyDaysAgo.isBefore(fyStart) ? fyStart : thirtyDaysAgo;
      _isInit = true;
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  @override
  Widget build(BuildContext context) {
    final fDateOnly = _dateOnly(fromDate);
    final tDateOnly = _dateOnly(toDate);

    List<Voucher> allVouchers = List.from(widget.webPh.vouchers);
    allVouchers.sort((a, b) => b.date.compareTo(a.date));

    final filtered = allVouchers.where((v) {
      final vDateOnly = _dateOnly(v.date);
      bool dateMatch = showAllDates || (!vDateOnly.isBefore(fDateOnly) && !vDateOnly.isAfter(tDateOnly));

      bool matchesType = true;
      if (typeFilter != "ALL") {
        matchesType = v.type.toUpperCase() == typeFilter;
      }

      bool matchesMode = true;
      if (modeFilter != "ALL") {
        matchesMode = v.paymentMode.toLowerCase() == modeFilter.toLowerCase();
      }

      String q = searchQuery.trim().toLowerCase();
      bool searchMatch = q.isEmpty ||
          v.partyName.toLowerCase().contains(q) ||
          v.voucherNo.toLowerCase().contains(q) ||
          v.depositedIn.toLowerCase().contains(q) ||
          v.chequeNo.toLowerCase().contains(q) ||
          v.narration.toLowerCase().contains(q);

      return dateMatch && matchesType && matchesMode && searchMatch;
    }).toList();

    double totalRec = filtered.where((v) => v.type.toUpperCase() == "RECEIPT" && v.status == "Active").fold(0.0, (s, v) => s + v.amount);
    double totalPay = filtered.where((v) => (v.type.toUpperCase() == "PAYMENT" || v.type.toUpperCase() == "EXPENSE") && v.status == "Active").fold(0.0, (s, v) => s + v.amount);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter & Export Controls Bar
          Row(
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: "Search Party, Voucher No, Bank, Cheque...",
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 16),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
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
              const SizedBox(width: 8),
              _dateChip("FROM", fromDate, (d) => setState(() => fromDate = d)),
              const SizedBox(width: 6),
              _dateChip("TO", toDate, (d) => setState(() => toDate = d)),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: showAllDates ? const Color(0xFF10B981) : Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: () => setState(() => showAllDates = !showAllDates),
                icon: Icon(showAllDates ? Icons.visibility_rounded : Icons.all_inclusive_rounded, size: 14),
                label: Text(showAllDates ? "30 DAYS" : "ALL DATES", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: filtered.isEmpty
                    ? null
                    : () => WebAccountsExcelService.exportVouchersCsv(filtered, widget.webPh.companyName),
                icon: const Icon(Icons.file_download_rounded, size: 15),
                label: const Text("EXCEL", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Secondary Sub-filter tabs (Type & Mode)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterTag("ALL", typeFilter == "ALL", () => setState(() => typeFilter = "ALL")),
                const SizedBox(width: 6),
                _filterTag("RECEIPTS", typeFilter == "RECEIPT", () => setState(() => typeFilter = "RECEIPT"), color: const Color(0xFF10B981)),
                const SizedBox(width: 6),
                _filterTag("PAYMENTS", typeFilter == "PAYMENT", () => setState(() => typeFilter = "PAYMENT"), color: const Color(0xFFDC2626)),
                const SizedBox(width: 6),
                _filterTag("CONTRA", typeFilter == "CONTRA", () => setState(() => typeFilter = "CONTRA"), color: const Color(0xFFF59E0B)),
                const SizedBox(width: 6),
                _filterTag("EXPENSES", typeFilter == "EXPENSE", () => setState(() => typeFilter = "EXPENSE"), color: const Color(0xFFB45309)),
                const SizedBox(width: 14),
                Container(height: 16, width: 1, color: Colors.white24),
                const SizedBox(width: 14),
                _filterTag("ALL MODES", modeFilter == "ALL", () => setState(() => modeFilter = "ALL")),
                const SizedBox(width: 6),
                _filterTag("CASH ONLY", modeFilter == "Cash", () => setState(() => modeFilter = "Cash")),
                const SizedBox(width: 6),
                _filterTag("BANK ONLY", modeFilter == "Bank", () => setState(() => modeFilter = "Bank")),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 20),

          // Master Vouchers Table
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              child: const Text("No vouchers found matching filters.", style: TextStyle(color: Colors.white38, fontSize: 12)),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final double tableWidth = constraints.maxWidth > 860 ? constraints.maxWidth : 860;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Table(
                      columnWidths: const {
                        0: FixedColumnWidth(85),
                        1: FixedColumnWidth(95),
                        2: FlexColumnWidth(3.0),
                        3: FlexColumnWidth(2.0),
                        4: FixedColumnWidth(75),
                        5: FixedColumnWidth(75),
                        6: FixedColumnWidth(100),
                        7: FixedColumnWidth(130),
                      },
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(
                            color: Color(0xFF0F172A),
                            border: Border(bottom: BorderSide(color: Colors.white24, width: 1)),
                          ),
                          children: [
                            _th("DATE"),
                            _th("VOUCHER NO"),
                            _th("PARTY / ACCOUNT", isLeft: true),
                            _th("INTERNAL ACC", isLeft: true),
                            _th("TYPE"),
                            _th("MODE"),
                            _th("AMOUNT", isRight: true),
                            _th("ACTIONS"),
                          ],
                        ),
                        for (int i = 0; i < filtered.length; i++) ...[
                          _buildVoucherRow(filtered[i], i),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 12),

          // Summary Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("TOTAL ENTRIES: ${filtered.length}", style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Text("TOTAL RECEIVED: ₹${totalRec.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF34D399), fontSize: 11.5, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 20),
                    Text("TOTAL PAID: ₹${totalPay.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFF87171), fontSize: 11.5, fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildVoucherRow(Voucher v, int index) {
    bool isRec = v.type.toUpperCase() == "RECEIPT";
    bool isCan = v.status == "Cancelled";

    return TableRow(
      decoration: BoxDecoration(
        color: isCan ? const Color(0x1ADC2626) : (index % 2 == 1 ? const Color(0x0DFFFFFF) : Colors.transparent),
        border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      children: [
        _td(DateFormat('dd/MM/yy').format(v.date)),
        _td(v.voucherNo, isBold: true, color: isCan ? Colors.redAccent : Colors.white),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                v.partyName,
                style: TextStyle(
                  color: isCan ? Colors.white54 : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                  decoration: isCan ? TextDecoration.lineThrough : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (v.narration.isNotEmpty)
                Text(
                  v.narration,
                  style: const TextStyle(color: Colors.white38, fontSize: 9.5, fontStyle: FontStyle.italic),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        _td(v.depositedIn, isLeft: true),
        _tdTypeBadge(v.type),
        _td(v.paymentMode),
        _td(
          "₹${v.amount.toStringAsFixed(2)}",
          isRight: true,
          isBold: true,
          color: isCan ? Colors.white38 : (isRec ? Colors.greenAccent : const Color(0xFFF87171)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.print_rounded, size: 16, color: Color(0xFF38BDF8)),
              tooltip: "Print A6 Voucher",
              onPressed: () {
                Party? p;
                try {
                  p = widget.webPh.parties.firstWhere((pt) => pt.id == v.partyId || pt.name == v.partyName);
                } catch (_) {
                  p = Party(id: v.partyId, name: v.partyName);
                }
                final shopProfile = CompanyProfile.fromMap(widget.webPh.companyProfile);
                WebPdfRouterService.printVoucher(voucher: v, party: p, shop: shopProfile, webPh: widget.webPh);
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit_note_rounded, size: 18, color: Colors.orangeAccent),
              tooltip: "Modify Voucher",
              onPressed: () => widget.onEditVoucher(v, false),
            ),
            if (!isCan)
              IconButton(
                icon: const Icon(Icons.block_rounded, size: 16, color: Colors.redAccent),
                tooltip: "Cancel Voucher",
                onPressed: () => _confirmCancel(v),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.white38),
              tooltip: "Delete Permanently",
              onPressed: () => _confirmDelete(v),
            ),
          ],
        ),
      ],
    );
  }

  void _confirmCancel(Voucher v) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Cancel Voucher?", style: TextStyle(color: Colors.white, fontSize: 14)),
        content: Text("Are you sure you want to cancel voucher '${v.voucherNo}'? This will mark it cancelled in the ledger.", style: const TextStyle(color: Colors.white70, fontSize: 11)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("NO")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              widget.webPh.cancelVoucher(v.id);
              Navigator.pop(c);
              setState(() {});
            },
            child: const Text("YES, CANCEL"),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Voucher v) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Delete Voucher Permanently?", style: TextStyle(color: Colors.white, fontSize: 14)),
        content: Text("Are you sure you want to permanently delete '${v.voucherNo}' from records?", style: const TextStyle(color: Colors.white70, fontSize: 11)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              widget.webPh.deleteVoucher(v.id);
              Navigator.pop(c);
              setState(() {});
            },
            child: const Text("DELETE"),
          ),
        ],
      ),
    );
  }

  Widget _filterTag(String label, bool isSelected, VoidCallback onTap, {Color? color}) {
    Color activeC = color ?? const Color(0xFF2563EB);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeC : Colors.black26,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? activeC : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontSize: 9.5, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _dateChip(String label, DateTime dt, Function(DateTime) onPick) {
    return InkWell(
      onTap: () async {
        final p = await showDatePicker(
          context: context,
          initialDate: dt,
          firstDate: WebAppDateLogic.getFYStart(widget.webPh.financialYear),
          lastDate: WebAppDateLogic.getFYEnd(widget.webPh.financialYear),
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

  Widget _tdTypeBadge(String type) {
    Color bg = const Color(0x332563EB);
    Color fg = Colors.blueAccent;

    if (type.toUpperCase() == "RECEIPT") { bg = const Color(0x3310B981); fg = Colors.greenAccent; }
    if (type.toUpperCase() == "PAYMENT") { bg = const Color(0x33DC2626); fg = const Color(0xFFF87171); }
    if (type.toUpperCase() == "CONTRA") { bg = const Color(0x33F59E0B); fg = const Color(0xFFFBBF24); }
    if (type.toUpperCase() == "EXPENSE") { bg = const Color(0x33B45309); fg = Colors.orangeAccent; }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(type.toUpperCase(), style: TextStyle(color: fg, fontSize: 8, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
