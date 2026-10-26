// FILE: lib/gst/gst_diary/gst_diary_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../pharoah_manager.dart';
import '../../models.dart';
import 'gst_diary_models.dart';
import 'gst_diary_calculator.dart';

class GstDiaryView extends StatefulWidget {
  const GstDiaryView({super.key});

  @override
  State<GstDiaryView> createState() => _GstDiaryViewState();
}

class _GstDiaryViewState extends State<GstDiaryView> with SingleTickerProviderStateMixin {
  late DateTime fromDate;
  late DateTime toDate;
  final DateFormat _df = DateFormat('dd/MM/yyyy');
  final DateFormat _isoDf = DateFormat('yyyy-MM-dd');

  String activeTab = "PRODUCT"; // "PRODUCT", "PARTY", "BILL"
  String searchQuery = "";

  final Set<String> selectedPurchasePartyIds = {};
  final Set<String> selectedSalePartyIds = {};

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    fromDate = DateTime(now.year, now.month, 1);
    toDate = DateTime(now.year, now.month + 1, 0);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(start: fromDate, end: toDate),
    );
    if (picked != null) {
      setState(() {
        fromDate = picked.start;
        toDate = picked.end;
      });
    }
  }

  void _showPartyFilterSheet(PharoahManager ph, {required bool isPurchase}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final List<String> allParties = isPurchase
            ? ph.purchases
                .map((p) => p.distributorName.trim())
                .where((n) => n.isNotEmpty)
                .toSet()
                .toList()
            : ph.parties
                .map((p) => p.id.trim())
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList();

        final Set<String> temp = Set.from(
          isPurchase ? selectedPurchasePartyIds : selectedSalePartyIds,
        );

        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        isPurchase ? Icons.storefront_rounded : Icons.people_alt_rounded,
                        color: isPurchase ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isPurchase ? "SELECT SUPPLIERS" : "SELECT CUSTOMERS",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setSheetState(() => temp.addAll(allParties)),
                        child: const Text("Select All", style: TextStyle(color: Color(0xFF8B5CF6))),
                      ),
                      TextButton(
                        onPressed: () => setSheetState(() => temp.clear()),
                        child: const Text("Clear All", style: TextStyle(color: Colors.white54)),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: allParties.length,
                      itemBuilder: (c, idx) {
                        final partyKey = allParties[idx];
                        final displayName = isPurchase
                            ? partyKey
                            : (ph.parties.firstWhere(
                                (p) => p.id == partyKey,
                                orElse: () => Party(id: partyKey, name: partyKey, group: ''),
                              ).name);
                        final isChecked = temp.contains(partyKey);
                        return CheckboxListTile(
                          dense: true,
                          activeColor: const Color(0xFF8B5CF6),
                          title: Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          value: isChecked,
                          onChanged: (val) {
                            setSheetState(() {
                              if (val == true) {
                                temp.add(partyKey);
                              } else {
                                temp.remove(partyKey);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        setState(() {
                          if (isPurchase) {
                            selectedPurchasePartyIds.clear();
                            selectedPurchasePartyIds.addAll(temp);
                          } else {
                            selectedSalePartyIds.clear();
                            selectedSalePartyIds.addAll(temp);
                          }
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text("APPLY FILTER", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showSessionsSheet(PharoahManager ph, GstDiaryCalculationResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final sessions = ph.gstDiarySessions;
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history_edu_rounded, color: Color(0xFF10B981), size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        "GST SETTLEMENT SESSIONS",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        _showCreateSessionDialog(ph, result, onCreated: () {
                          setSheetState(() {});
                          setState(() {});
                        });
                      },
                      icon: const Icon(Icons.add_task_rounded, size: 16),
                      label: const Text("CREATE NEW SESSION NOW", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12),
                  Expanded(
                    child: sessions.isEmpty
                        ? const Center(
                            child: Text(
                              "No sessions created yet.",
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            itemCount: sessions.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (c, idx) {
                              final s = sessions[idx];
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            s.title,
                                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: s.status == "DEDUCTED"
                                                ? const Color(0xFF10B981).withOpacity(0.2)
                                                : const Color(0xFFF59E0B).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            s.status,
                                            style: TextStyle(
                                              color: s.status == "DEDUCTED" ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Period: ${s.fromDate} to ${s.toDate}",
                                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "Deducted: ₹${s.deductedAmount.toStringAsFixed(2)}",
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                    ),
                                    if (s.remarks.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        "Remark: ${s.remarks}",
                                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        InkWell(
                                          onTap: () {
                                            setSheetState(() {
                                              ph.deleteGstDiarySession(s.id);
                                            });
                                            setState(() {});
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            child: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showCreateSessionDialog(PharoahManager ph, GstDiaryCalculationResult result, {required VoidCallback onCreated}) {
    final titleCtrl = TextEditingController(
      text: "${DateFormat('MMM yyyy').format(fromDate)} GST Settlement",
    );
    final remarkCtrl = TextEditingController(
      text: "Net tax settled & deducted",
    );
    final deductedAmountCtrl = TextEditingController(
      text: (result.netGstPayable > 0 ? result.netGstPayable : 0.0).toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("CREATE SESSION", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Title", style: TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 4),
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(filled: true, fillColor: Colors.black26),
                ),
                const SizedBox(height: 10),
                const Text("Deducted Amount (₹)", style: TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 4),
                TextField(
                  controller: deductedAmountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(filled: true, fillColor: Colors.black26),
                ),
                const SizedBox(height: 10),
                const Text("Remark", style: TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 4),
                TextField(
                  controller: remarkCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: "Challan / Bank remarks",
                    hintStyle: TextStyle(color: Colors.white30, fontSize: 11),
                    filled: true,
                    fillColor: Colors.black26,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              onPressed: () {
                final s = GstDiarySession(
                  id: "gst_sess_${DateTime.now().millisecondsSinceEpoch}",
                  title: titleCtrl.text.trim().isNotEmpty ? titleCtrl.text.trim() : "GST Session",
                  createdAt: DateTime.now().millisecondsSinceEpoch,
                  fromDate: _isoDf.format(fromDate),
                  toDate: _isoDf.format(toDate),
                  purchasePartyIds: selectedPurchasePartyIds.toList(),
                  salePartyIds: selectedSalePartyIds.toList(),
                  totalPurchaseItc: result.totalPurchaseItc,
                  totalSaleOutputGst: result.totalSaleOutputGst,
                  netGstPayable: result.netGstPayable,
                  deductedAmount: double.tryParse(deductedAmountCtrl.text) ?? result.netGstPayable,
                  includedBillIds: result.billRows.map((b) => b.billId).toList(),
                  totalBillsCount: result.billRows.length,
                  status: "DEDUCTED",
                  remarks: remarkCtrl.text.trim(),
                );
                ph.createGstDiarySession(s);
                Navigator.pop(dialogCtx);
                onCreated();
              },
              child: const Text("SAVE"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final calcResult = GstDiaryCalculator.compute(
      sales: ph.sales,
      purchases: ph.purchases,
      parties: ph.parties,
      fromDate: fromDate,
      toDate: toDate,
      selectedPurchasePartyIds: selectedPurchasePartyIds,
      selectedSalePartyIds: selectedSalePartyIds,
      existingSessions: ph.gstDiarySessions,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("GST Diary", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: "Filter Parties",
            onPressed: () => _showPartyFilterSheet(ph, isPurchase: true),
            icon: const Icon(Icons.filter_alt_rounded, size: 20),
          ),
          IconButton(
            tooltip: "Settlement Sessions",
            onPressed: () => _showSessionsSheet(ph, calcResult),
            icon: const Icon(Icons.history_edu_rounded, color: Color(0xFF10B981), size: 22),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter & Date Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDateRange,
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF8B5CF6)),
                        const SizedBox(width: 6),
                        Text(
                          "${_df.format(fromDate)} - ${_df.format(toDate)}",
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                // Tabs
                Row(
                  children: [
                    _tabChip("PRODUCT", "Products"),
                    const SizedBox(width: 4),
                    _tabChip("PARTY", "Parties"),
                    const SizedBox(width: 4),
                    _tabChip("BILL", "Bills"),
                  ],
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => searchQuery = v.trim().toLowerCase()),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: "Search rows...",
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Colors.white54),
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),

          // Main List Content
          Expanded(
            child: _buildMobileContent(calcResult),
          ),

          // Bottom Summary Strip
          _buildMobileBottomSummary(calcResult, () => _showSessionsSheet(ph, calcResult)),
        ],
      ),
    );
  }

  Widget _tabChip(String key, String label) {
    final isSel = activeTab == key;
    return InkWell(
      onTap: () => setState(() => activeTab = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF8B5CF6) : Colors.white10,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSel ? Colors.white : Colors.white70,
            fontSize: 10,
            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildMobileContent(GstDiaryCalculationResult result) {
    if (activeTab == "PRODUCT") {
      final rows = result.productRows.where((r) {
        if (searchQuery.isEmpty) return true;
        return r.productName.toLowerCase().contains(searchQuery);
      }).toList();

      if (rows.isEmpty) {
        return const Center(child: Text("No product records found", style: TextStyle(color: Colors.white38)));
      }

      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, idx) {
          final r = rows[idx];
          final isPayable = r.gstDifference >= 0;
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        r.productName,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      "${isPayable ? '+' : ''}₹${r.gstDifference.toStringAsFixed(2)}",
                      style: TextStyle(
                        color: isPayable ? Colors.redAccent : Colors.greenAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Pur: ${r.purchaseQty.toInt()}u · ITC: ₹${r.purchaseGst.toStringAsFixed(1)}", style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 11)),
                    Text("Sale: ${r.saleQty.toInt()}u · GST: ₹${r.saleGst.toStringAsFixed(1)}", style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
                  ],
                ),
              ],
            ),
          );
        },
      );
    } else if (activeTab == "PARTY") {
      final rows = result.partyRows.where((p) {
        if (searchQuery.isEmpty) return true;
        return p.partyName.toLowerCase().contains(searchQuery);
      }).toList();

      if (rows.isEmpty) {
        return const Center(child: Text("No party records found", style: TextStyle(color: Colors.white38)));
      }

      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, idx) {
          final p = rows[idx];
          final isPur = p.type == "PURCHASE_SUPPLIER";
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.partyName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text(isPur ? "Supplier (ITC)" : "Customer (Output)", style: TextStyle(color: isPur ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("₹${p.totalGst.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                    Text("${p.totalBills} Bills", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ),
              ],
            ),
          );
        },
      );
    } else {
      final rows = result.billRows.where((b) {
        if (searchQuery.isEmpty) return true;
        return b.billNo.toLowerCase().contains(searchQuery) || b.partyName.toLowerCase().contains(searchQuery);
      }).toList();

      if (rows.isEmpty) {
        return const Center(child: Text("No bill records found", style: TextStyle(color: Colors.white38)));
      }

      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, idx) {
          final b = rows[idx];
          final isPur = b.voucherType == "PURCHASE";
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(b.billNo, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                          const SizedBox(width: 6),
                          Text(isPur ? "PURCHASE" : "SALE", style: TextStyle(color: isPur ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(b.partyName, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("GST: ₹${b.gstAmount.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                    Text("Total: ₹${b.netBillAmount.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Widget _buildMobileBottomSummary(GstDiaryCalculationResult result, VoidCallback onSessions) {
    final isPayable = result.netGstPayable > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPayable ? "NET GST PAYABLE" : "SURPLUS ITC",
                style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                "₹${result.netGstPayable.abs().toStringAsFixed(2)}",
                style: TextStyle(
                  color: isPayable ? Colors.redAccent : Colors.greenAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: onSessions,
            icon: const Icon(Icons.history_edu_rounded, size: 16),
            label: const Text("SESSIONS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
