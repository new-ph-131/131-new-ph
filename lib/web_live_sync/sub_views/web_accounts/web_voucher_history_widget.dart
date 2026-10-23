// FILE: lib/web_live_sync/sub_views/web_accounts/web_voucher_history_widget.dart
// Revision: #PH-REV-755 (ENTERPRISE-WEB-VOUCHER-AUDIT-HISTORY-HUB)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../pharoah_web_manager.dart';
import '../../web_models.dart';
import '../../web_app_date_logic.dart';
import '../../pdf/web_pdf_router_service.dart';
import 'services/web_accounts_excel_service.dart';

class WebVoucherHistoryWidget extends StatefulWidget {
  final PharoahWebManager webPh;
  final Function(Voucher, bool) onEditVoucher;

  const WebVoucherHistoryWidget({
    super.key,
    required this.webPh,
    required this.onEditVoucher,
  });

  @override
  State<WebVoucherHistoryWidget> createState() => _WebVoucherHistoryWidgetState();
}

class _WebVoucherHistoryWidgetState extends State<WebVoucherHistoryWidget> {
  String searchQuery = "";
  String typeFilter = "ALL"; // ALL, RECEIPT, PAYMENT, CONTRA, EXPENSE
  String modeFilter = "ALL"; // ALL, Cash, Bank
  String statusFilter = "ALL"; // ALL, ACTIVE, CANCELLED
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  bool _isInit = false;
  bool showAllDates = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      toDate = WebAppDateLogic.getSmartDate(widget.webPh.financialYear);
      fromDate = toDate.subtract(const Duration(days: 30));
      DateTime fyStart = WebAppDateLogic.getFYStart(widget.webPh.financialYear);
      if (fromDate.isBefore(fyStart)) fromDate = fyStart;
      _isInit = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime startDay = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final DateTime endDay = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    List<Voucher> allVouchers = List.from(widget.webPh.vouchers)
        .where((v) => v.isDeleted != 1 && v.status != "Deleted")
        .toList();
    allVouchers.sort((a, b) {
      int cmp = b.date.compareTo(a.date);
      if (cmp != 0) return cmp;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    final filtered = allVouchers.where((v) {
      bool dateMatch = showAllDates || (!v.date.isBefore(startDay) && !v.date.isAfter(endDay));
      bool matchesType = typeFilter == "ALL" || v.type.toUpperCase() == typeFilter;
      bool matchesMode = modeFilter == "ALL" || v.paymentMode.toLowerCase() == modeFilter.toLowerCase();
      bool isCancelled = v.status.toUpperCase() == "CANCELLED";
      bool matchesStatus = statusFilter == "ALL" ||
          (statusFilter == "ACTIVE" && !isCancelled) ||
          (statusFilter == "CANCELLED" && isCancelled);

      String q = searchQuery.toLowerCase().trim();
      bool searchMatch = q.isEmpty ||
          v.partyName.toLowerCase().contains(q) ||
          v.voucherNo.toLowerCase().contains(q) ||
          v.depositedIn.toLowerCase().contains(q) ||
          v.chequeNo.toLowerCase().contains(q) ||
          v.narration.toLowerCase().contains(q);

      return dateMatch && matchesType && matchesMode && matchesStatus && searchMatch;
    }).toList();

    double totalRec = filtered
        .where((v) => v.type.toUpperCase() == "RECEIPT" && v.status == "Active")
        .fold(0.0, (s, v) => s + v.amount);
    double totalPay = filtered
        .where((v) => (v.type.toUpperCase() == "PAYMENT" || v.type.toUpperCase() == "EXPENSE") && v.status == "Active")
        .fold(0.0, (s, v) => s + v.amount);
    int cancelledCount = filtered.where((v) => v.status == "Cancelled").length;

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
                    hintText: "Search Party, Voucher No, Bank, Cheque, Narration...",
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

          // Secondary Sub-filter tabs (Type, Mode & Audit Status)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterTag("ALL TYPES", typeFilter == "ALL", () => setState(() => typeFilter = "ALL")),
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
                const SizedBox(width: 14),
                Container(height: 16, width: 1, color: Colors.white24),
                const SizedBox(width: 14),
                _filterTag("ALL STATUS", statusFilter == "ALL", () => setState(() => statusFilter = "ALL")),
                const SizedBox(width: 6),
                _filterTag("ACTIVE", statusFilter == "ACTIVE", () => setState(() => statusFilter = "ACTIVE"), color: const Color(0xFF059669)),
                const SizedBox(width: 6),
                _filterTag("CANCELLED ($cancelledCount)", statusFilter == "CANCELLED", () => setState(() => statusFilter = "CANCELLED"), color: const Color(0xFFD97706)),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 20),

          // Master Vouchers Audit Table
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              child: const Text("No vouchers found matching filters.", style: TextStyle(color: Colors.white38, fontSize: 12)),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final double tableWidth = constraints.maxWidth > 1060 ? constraints.maxWidth : 1060;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Table(
                      columnWidths: const {
                        0: FixedColumnWidth(82),
                        1: FixedColumnWidth(95),
                        2: FlexColumnWidth(2.8),
                        3: FlexColumnWidth(1.8),
                        4: FixedColumnWidth(76),
                        5: FixedColumnWidth(68),
                        6: FixedColumnWidth(88),
                        7: FixedColumnWidth(105),
                        8: FixedColumnWidth(275),
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
                            _th("PARTY / ACCOUNT & ALLOCATIONS", isLeft: true),
                            _th("INTERNAL ACC", isLeft: true),
                            _th("TYPE"),
                            _th("MODE"),
                            _th("STATUS"),
                            _th("AMOUNT", isRight: true),
                            _th("AUDIT ACTIONS (SEPARATED)"),
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
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("TOTAL ENTRIES: ${filtered.length}", style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                    if (cancelledCount > 0) ...[
                      const SizedBox(width: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD97706).withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                        ),
                        child: Text(
                          "CANCELLED: $cancelledCount",
                          style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("ACTIVE RECEIVED: ₹${totalRec.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF34D399), fontSize: 11.5, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 20),
                    Text("ACTIVE PAID: ₹${totalPay.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFF87171), fontSize: 11.5, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 20),
                    Text(
                      "NET FLOW: ₹${(totalRec - totalPay).toStringAsFixed(2)}",
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11.5, fontWeight: FontWeight.w900),
                    ),
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
        color: isCan ? const Color(0x1AF59E0B) : (index % 2 == 1 ? const Color(0x0DFFFFFF) : Colors.transparent),
        border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      children: [
        _td(DateFormat('dd/MM/yy').format(v.date)),
        _td(v.voucherNo, isBold: true, color: isCan ? const Color(0xFFFBBF24) : Colors.white),
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
              if (v.chequeInstruments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    "Agst: " + v.chequeInstruments.map((inst) {
                      String bNo = inst['billNo']?.toString() ?? '';
                      double amt = (inst['amount'] as num?)?.toDouble() ?? 0.0;
                      String bank = inst['bankName']?.toString() ?? '';
                      String chq = inst['chequeNo']?.toString() ?? '';
                      return "$bNo (₹${amt.toStringAsFixed(2)})${bank.isNotEmpty ? ' [$bank' : ''}${chq.isNotEmpty ? ' Chq:$chq' : ''}${bank.isNotEmpty ? ']' : ''}";
                    }).join(", "),
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else if (v.billAllocations.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    "Agst: " + v.billAllocations.entries.map((e) => "${e.key} (₹${e.value.toStringAsFixed(2)})").join(", "),
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else if (v.linkedBillNumbers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    "Agst: " + v.linkedBillNumbers.join(", "),
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9),
                    overflow: TextOverflow.ellipsis,
                  ),
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
        _tdStatusBadge(isCan),
        _td(
          "₹${v.amount.toStringAsFixed(2)}",
          isRight: true,
          isBold: true,
          color: isCan ? Colors.white38 : (isRec ? Colors.greenAccent : const Color(0xFFF87171)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. PRINT BUTTON
              _actionPillBtn(
                icon: Icons.print_rounded,
                label: "PRINT",
                color: const Color(0xFF38BDF8),
                tooltip: "Print A6 Voucher",
                onTap: () {
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
              const SizedBox(width: 5),

              // 2. EDIT / MODIFY BUTTON
              _actionPillBtn(
                icon: Icons.edit_note_rounded,
                label: "EDIT",
                color: const Color(0xFF10B981),
                tooltip: "Modify Voucher",
                onTap: () => widget.onEditVoucher(v, false),
              ),
              const SizedBox(width: 6),
              Container(width: 1, height: 18, color: Colors.white12),
              const SizedBox(width: 6),

              // 3. SEPARATE CANCEL BUTTON (Amber/Orange — Reverses ledger impact, keeps audit trail)
              if (!isCan)
                _actionPillBtn(
                  icon: Icons.block_rounded,
                  label: "CANCEL",
                  color: const Color(0xFFF59E0B),
                  tooltip: "Cancel Voucher (Keep Audit Trail)",
                  onTap: () => _confirmCancel(v),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    "VOIDED",
                    style: TextStyle(color: Colors.white38, fontSize: 8.5, fontWeight: FontWeight.w800),
                  ),
                ),

              const SizedBox(width: 6),
              Container(width: 1, height: 18, color: Colors.white12),
              const SizedBox(width: 6),

              // 4. SEPARATE DELETE BUTTON (Crimson Red — Permanently removes record)
              _actionPillBtn(
                icon: Icons.delete_forever_rounded,
                label: "DELETE",
                color: const Color(0xFFEF4444),
                tooltip: "Delete Voucher Permanently",
                onTap: () => _confirmDelete(v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionPillBtn({
    required IconData icon,
    required String label,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12.5, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tdStatusBadge(bool isCan) {
    final Color c = isCan ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: c.withOpacity(0.15),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: c.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isCan ? Icons.block_rounded : Icons.check_circle_rounded, size: 10, color: c),
            const SizedBox(width: 3),
            Text(
              isCan ? "CANCELLED" : "ACTIVE",
              style: TextStyle(color: c, fontSize: 8.5, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmCancel(Voucher v) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: const Color(0xFFF59E0B).withOpacity(0.4)),
        ),
        title: Row(
          children: const [
            Icon(Icons.block_rounded, color: Color(0xFFF59E0B), size: 20),
            SizedBox(width: 8),
            Text("Cancel Voucher (Keep Audit Trail)?", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "Cancel voucher '${v.voucherNo}' (${v.partyName} — ₹${v.amount.toStringAsFixed(2)})?\n\n"
          "• Reverses its impact on Party Ledger, Day Book, and Bank/Cash balances immediately.\n"
          "• Un-settles linked bills so they become pending again.\n"
          "• Keeps the Cancelled entry visible in Audit History and syncs to Mobile App immediately.",
          style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("BACK", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(c);
              widget.webPh.cancelVoucher(v.id);
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("🚫 Voucher ${v.voucherNo} marked CANCELLED & synced with App!"),
                    backgroundColor: const Color(0xFFD97706),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.block_rounded, size: 15),
            label: const Text("YES, CANCEL VOUCHER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: const Color(0xFFEF4444).withOpacity(0.4)),
        ),
        title: Row(
          children: const [
            Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 20),
            SizedBox(width: 8),
            Text("Delete Voucher Permanently?", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "Permanently delete voucher '${v.voucherNo}' (${v.partyName} — ₹${v.amount.toStringAsFixed(2)})?\n\n"
          "• Completely removes this voucher from Web and Mobile App.\n"
          "• Reverses all bill settlements and ledger balances immediately.",
          style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("BACK", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(c);
              widget.webPh.deleteVoucher(v.id);
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("🗑️ Voucher ${v.voucherNo} permanently deleted & synced with App!"),
                    backgroundColor: const Color(0xFFDC2626),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.delete_forever_rounded, size: 15),
            label: const Text("PERMANENTLY DELETE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
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
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today, size: 12, color: Color(0xFF38BDF8)),
            const SizedBox(width: 6),
            Text("$label: ${DateFormat('dd/MM/yy').format(dt)}", style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _th(String text, {bool isLeft = false, bool isRight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Text(
        text,
        textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center),
        style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _td(String text, {bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white70}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Text(
        text,
        textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center),
        style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _tdTypeBadge(String type) {
    Color c = const Color(0xFF10B981);
    String tUp = type.toUpperCase();
    if (tUp == "PAYMENT") c = const Color(0xFFDC2626);
    if (tUp == "CONTRA") c = const Color(0xFFF59E0B);
    if (tUp == "EXPENSE") c = const Color(0xFFB45309);

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.withOpacity(0.4)),
        ),
        child: Text(tUp, style: TextStyle(color: c, fontSize: 8.5, fontWeight: FontWeight.w900)),
      ),
    );
  }
}
