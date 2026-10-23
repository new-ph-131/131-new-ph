// FILE: lib/payment_receipt_history.dart
// Revision: #PH-REV-755 (MOBILE-VOUCHER-AUDIT-HISTORY-1TAP-SYNC)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'pharoah_date_controller.dart';
import 'app_date_logic.dart';
import 'accounting_views.dart';
import 'pdf/pdf_router_service.dart';
import 'pdf/history_report_pdf.dart';
import 'logic/history_excel_service.dart';

class PaymentReceiptHistory extends StatefulWidget {
  const PaymentReceiptHistory({super.key});

  @override
  State<PaymentReceiptHistory> createState() => _PaymentReceiptHistoryState();
}

class _PaymentReceiptHistoryState extends State<PaymentReceiptHistory> {
  String searchQuery = "";
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  String viewMode = "All";
  Party? selectedParty;
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final ph = Provider.of<PharoahManager>(context, listen: false);
      // FY Locked Smart Date Initialization
      toDate = AppDateLogic.getSmartDate(ph.currentFY);
      fromDate = toDate.subtract(const Duration(days: 30));
      DateTime fyStart = AppDateLogic.getFYStart(ph.currentFY);
      if (fromDate.isBefore(fyStart)) fromDate = fyStart;
      _isInit = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    final DateTime startDay = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final DateTime endDay = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    // --- ADVANCED UNIVERSAL FILTER LOGIC ---
    final filteredList = ph.vouchers.reversed.where((v) {
      if (v.isDeleted == 1 || v.status == "Deleted") return false;

      // 1. Date Range Filter (Inclusive of full startDay and endDay)
      bool matchesDate = !v.date.isBefore(startDay) && !v.date.isAfter(endDay);

      // 2. Multi-parameter Search (Party Name, Voucher No, Bank, or Cheque)
      final q = searchQuery.toLowerCase().trim();
      bool matchesSearch = q.isEmpty ||
          v.partyName.toLowerCase().contains(q) ||
          v.voucherNo.toLowerCase().contains(q) ||
          v.depositedIn.toLowerCase().contains(q) ||
          v.chequeNo.toLowerCase().contains(q);

      // 3. View Mode Check
      bool matchesParty = viewMode == "All" || (selectedParty != null && v.partyId == selectedParty!.id);

      return matchesDate && matchesSearch && matchesParty;
    }).toList();

    // Summary Analytics (Only Active Vouchers, Case-Insensitive Type Match)
    double totalReceived = filteredList
        .where((v) => v.type.toUpperCase() == "RECEIPT" && v.status == "Active")
        .fold(0.0, (s, v) => s + v.amount);
    double totalPaid = filteredList
        .where((v) => (v.type.toUpperCase() == "PAYMENT" || v.type.toUpperCase() == "EXPENSE") && v.status == "Active")
        .fold(0.0, (s, v) => s + v.amount);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text("History & Audit Hub", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          // 📊 EXCEL EXPORT
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => HistoryExcelService.export(filteredList, ph.activeCompany!.name),
            tooltip: "Export Excel Statement",
          ),
          // 📄 PDF STATEMENT
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () {
              double opFlow = ph.vouchers
                  .where((v) => v.isDeleted != 1 && v.date.isBefore(startDay) && v.status == "Active")
                  .fold(0.0, (sum, v) => sum + (v.type.toUpperCase() == "RECEIPT" ? v.amount : -v.amount));

              HistoryReportPdf.generate(
                list: filteredList,
                fDate: fromDate,
                tDate: toDate,
                shop: ph.activeCompany!,
                openingFlow: opFlow,
              );
            },
            tooltip: "Export PDF Ledger",
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterHeader(ph),
          _buildSummaryRibbon(totalReceived, totalPaid),
          Expanded(
            child: filteredList.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredList.length,
                    itemBuilder: (c, i) => _buildVoucherCard(filteredList[i], ph),
                  ),
          ),
          _buildSystemFooter(ph.currentFY),
        ],
      ),
    );
  }

  // ===========================================================================
  // UI COMPONENTS
  // ===========================================================================

  Widget _buildFilterHeader(PharoahManager ph) {
    return Container(
      padding: const EdgeInsets.all(15),
      color: const Color(0xFF1A237E),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => setState(() => searchQuery = v),
              decoration: InputDecoration(
                hintText: "Search Party, Voucher ID, Bank, or Cheque...",
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _buildViewToggle(ph),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _dateTile("FROM", fromDate, (d) => setState(() => fromDate = d), ph.currentFY),
          const Icon(Icons.swap_horiz_rounded, color: Colors.white24, size: 20),
          _dateTile("TO", toDate, (d) => setState(() => toDate = d), ph.currentFY),
        ]),
      ]),
    );
  }

  Widget _buildSummaryRibbon(double rec, double paid) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _sumStat("TOTAL RECEIVED", rec, Colors.green.shade700),
        _sumStat("TOTAL PAID", paid, Colors.red.shade700),
        _sumStat("NET FLOW", rec - paid, Colors.indigo.shade900),
      ]),
    );
  }

  Widget _buildVoucherCard(Voucher v, PharoahManager ph) {
    bool isReceipt = v.type.toUpperCase() == "RECEIPT";
    bool isCancelled = v.status == "Cancelled";
    Color themeColor = isReceipt ? Colors.green.shade700 : Colors.red.shade700;

    return Card(
      key: ValueKey("${v.id}_${v.version}_${v.status}"),
      elevation: isCancelled ? 0 : 1.5,
      margin: const EdgeInsets.only(bottom: 10),
      color: isCancelled ? Colors.amber.withOpacity(0.04) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: isCancelled ? Colors.amber.shade300 : Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _showActionHub(v, ph),
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _dateCircle(v.date, themeColor, isCancelled),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.partyName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          decoration: isCancelled ? TextDecoration.lineThrough : null,
                          color: isCancelled ? Colors.grey.shade600 : Colors.black87,
                        ),
                      ),
                      Text(
                        "${isReceipt ? 'INTO' : 'FROM'}: ${v.depositedIn.toUpperCase()}",
                        style: TextStyle(
                          fontSize: 10,
                          color: isCancelled ? Colors.grey : Colors.indigo.shade900,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        "${v.voucherNo} | ${v.paymentMode}",
                        style: const TextStyle(fontSize: 9.5, color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                      if (v.chequeInstruments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            "Agst: " +
                                v.chequeInstruments.map((inst) {
                                  String bNo = inst['billNo']?.toString() ?? '';
                                  double amt = (inst['amount'] as num?)?.toDouble() ?? 0.0;
                                  String bank = inst['bankName']?.toString() ?? '';
                                  String chq = inst['chequeNo']?.toString() ?? '';
                                  return "$bNo (₹${amt.toStringAsFixed(0)})${bank.isNotEmpty ? ' [$bank' : ''}${chq.isNotEmpty ? ' Chq:$chq' : ''}${bank.isNotEmpty ? ']' : ''}";
                                }).join(", "),
                            style: TextStyle(fontSize: 9, color: Colors.indigo.shade700, fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else if (v.billAllocations.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            "Agst: " +
                                v.billAllocations.entries
                                    .map((e) => "${e.key} (₹${e.value.toStringAsFixed(0)})")
                                    .join(", "),
                            style: TextStyle(fontSize: 9, color: Colors.indigo.shade700, fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "₹${v.amount.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: isCancelled ? Colors.grey : Colors.black87,
                        decoration: isCancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _statusTag(v.type, themeColor, isCancelled),
                  ],
                ),
              ]),
              const Divider(height: 16),
              // Separated Quick Action Strip (1-Tap View, Modify, Print, Cancel & Delete)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _cardQuickBtn(
                    icon: Icons.visibility_outlined,
                    label: "VIEW",
                    color: Colors.blue.shade700,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => VoucherEntryView(type: v.type, existingVoucher: v, isReadOnly: true),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  _cardQuickBtn(
                    icon: Icons.edit_note_rounded,
                    label: "EDIT",
                    color: Colors.teal.shade700,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => VoucherEntryView(type: v.type, existingVoucher: v),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  _cardQuickBtn(
                    icon: Icons.print_rounded,
                    label: "PRINT",
                    color: Colors.indigo.shade700,
                    onTap: () {
                      final party = ph.parties.firstWhere(
                        (p) => p.id == v.partyId,
                        orElse: () => Party(id: '0', name: v.partyName),
                      );
                      PdfRouterService.printVoucher(voucher: v, party: party, ph: ph);
                    },
                  ),
                  const Spacer(),
                  // Separate CANCEL button
                  if (!isCancelled)
                    _cardQuickBtn(
                      icon: Icons.block_flipped,
                      label: "CANCEL",
                      color: Colors.deepOrange.shade700,
                      onTap: () => _confirmCancel(v, ph),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Text(
                        "VOIDED",
                        style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.amber.shade900),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 16, color: Colors.grey.shade300),
                  const SizedBox(width: 8),
                  // Separate DELETE button
                  _cardQuickBtn(
                    icon: Icons.delete_forever_rounded,
                    label: "DELETE",
                    color: Colors.red.shade700,
                    onTap: () => _confirmDelete(v, ph),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardQuickBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // THE 5-WAY ACTION HUB (FULL CONTROL)
  // ===========================================================================
  void _showActionHub(Voucher v, PharoahManager ph) {
    final bool isCancelled = v.status == "Cancelled";
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (c) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            height: 5,
            width: 40,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
          ),
          const SizedBox(height: 20),
          Text(v.partyName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 4),
          Text("${v.voucherNo} • ₹${v.amount.toStringAsFixed(2)}", style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const Divider(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            // 1. VIEW (Read Only Mode)
            _hubBtn(Icons.visibility_outlined, "VIEW", Colors.blue, () {
              Navigator.pop(c);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) => VoucherEntryView(type: v.type, existingVoucher: v, isReadOnly: true),
                ),
              );
            }),
            // 2. MODIFY (Everything Editable)
            _hubBtn(Icons.edit_note_rounded, "MODIFY", Colors.orange, () {
              Navigator.pop(c);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (c) => VoucherEntryView(type: v.type, existingVoucher: v)),
              );
            }),
            // 3. PRINT (The 1/4 A4 Portrait Design)
            _hubBtn(Icons.print_rounded, "PRINT", Colors.teal, () {
              Navigator.pop(c);
              final party = ph.parties.firstWhere(
                (p) => p.id == v.partyId,
                orElse: () => Party(id: '0', name: v.partyName),
              );
              PdfRouterService.printVoucher(voucher: v, party: party, ph: ph);
            }),
          ]),
          const SizedBox(height: 25),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            // 4. CANCEL (Status Change + Log)
            if (!isCancelled)
              _hubBtn(Icons.block_flipped, "CANCEL", Colors.deepOrange, () {
                Navigator.pop(c);
                _confirmCancel(v, ph);
              }),
            // 5. DELETE (Permanent Removal)
            _hubBtn(Icons.delete_forever_rounded, "DELETE", Colors.red, () {
              Navigator.pop(c);
              _confirmDelete(v, ph);
            }),
          ]),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  void _confirmCancel(Voucher v, PharoahManager ph) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.block_flipped, color: Colors.deepOrange),
            SizedBox(width: 8),
            Expanded(child: Text("Cancel Voucher?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text(
          "Mark voucher '${v.voucherNo}' (₹${v.amount.toStringAsFixed(2)}) as Cancelled?\n\n"
          "• Reverses Party Ledger & Bank/Cash balance impact immediately.\n"
          "• Un-settles linked bills.\n"
          "• Syncs immediately with Web Portal.",
          style: const TextStyle(fontSize: 12.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("BACK")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(c);
              await ph.cancelVoucher(v.id);
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("🚫 Voucher ${v.voucherNo} Cancelled & Synced!"),
                    backgroundColor: Colors.deepOrange,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text("YES, CANCEL"),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Voucher v, PharoahManager ph) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text("Delete Voucher Permanently?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text(
          "Permanently remove voucher '${v.voucherNo}' (₹${v.amount.toStringAsFixed(2)})?\n\n"
          "• Removes record permanently from App and Web Portal.\n"
          "• Reverses all ledger & bill settlements immediately.",
          style: const TextStyle(fontSize: 12.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("BACK")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(c);
              await ph.deleteVoucher(v.id);
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("🗑️ Voucher ${v.voucherNo} Permanently Deleted & Synced!"),
                    backgroundColor: Colors.red.shade700,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text("DELETE PERMANENTLY"),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HELPERS & STYLES
  // ===========================================================================

  Widget _buildViewToggle(PharoahManager ph) {
    return InkWell(
      onTap: () => _openPartyFilterSheet(ph),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.orange.shade800, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Text(viewMode == "All" ? "ALL" : "FILTERED", style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
          const Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
        ]),
      ),
    );
  }

  void _openPartyFilterSheet(PharoahManager ph) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Text("FILTER BY PARTY NAME", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ListTile(
            leading: const Icon(Icons.all_inclusive),
            title: const Text("Show Full History"),
            onTap: () {
              setState(() {
                viewMode = "All";
                selectedParty = null;
              });
              Navigator.pop(c);
            },
          ),
          const Divider(),
          Expanded(
            child: ListView(
              children: ph.parties
                  .map((p) => ListTile(
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(p.city),
                        onTap: () {
                          setState(() {
                            viewMode = "Party Wise";
                            selectedParty = p;
                          });
                          Navigator.pop(c);
                        },
                      ))
                  .toList(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _dateTile(String l, DateTime d, Function(DateTime) onPick, String fy) => InkWell(
        onTap: () async {
          DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: fy, initialDate: d);
          if (p != null) onPick(p);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: Text("$l: ${DateFormat('dd/MM/yy').format(d)}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      );

  Widget _sumStat(String l, double v, Color c) => Column(children: [
        Text(l, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
        Text("₹${v.toStringAsFixed(0)}", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c)),
      ]);

  Widget _dateCircle(DateTime d, Color c, bool can) => Container(
        width: 45,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: can ? Colors.amber.shade100 : c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text(DateFormat('dd').format(d), style: TextStyle(fontWeight: FontWeight.bold, color: can ? Colors.amber.shade900 : c, fontSize: 16)),
          Text(DateFormat('MMM').format(d).toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: can ? Colors.amber.shade900 : c)),
        ]),
      );

  Widget _statusTag(String t, Color c, bool can) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: can ? Colors.amber.shade100 : c,
          borderRadius: BorderRadius.circular(6),
          border: can ? Border.all(color: Colors.amber.shade400) : null,
        ),
        child: Text(
          can ? "CANCELLED" : t.toUpperCase(),
          style: TextStyle(color: can ? Colors.amber.shade900 : Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
        ),
      );

  Widget _hubBtn(IconData i, String l, Color c, VoidCallback t) => InkWell(
        onTap: t,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(i, color: c, size: 24),
          ),
          const SizedBox(height: 6),
          Text(l, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: c)),
        ]),
      );

  Widget _buildEmptyState() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.history_toggle_off_rounded, size: 70, color: Colors.grey.shade300),
          const Text("No transactions found in this period.", style: TextStyle(color: Colors.grey, fontSize: 13)),
        ]),
      );

  Widget _buildSystemFooter(String fy) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        color: Colors.white,
        child: Text(
          "Live Financial Feed Locked to FY: $fy",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      );
}
