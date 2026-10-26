// FILE: lib/web_live_sync/sub_views/web_gst/web_gst_diary_view.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_saver/file_saver.dart';

import '../../pharoah_web_manager.dart';
import '../../../models.dart';
import '../../../gst/gst_diary/gst_diary_models.dart';
import '../../../gst/gst_diary/gst_diary_calculator.dart';

class WebGstDiaryView extends StatefulWidget {
  final PharoahWebManager webPh;
  final VoidCallback onBack;

  const WebGstDiaryView({
    super.key,
    required this.webPh,
    required this.onBack,
  });

  @override
  State<WebGstDiaryView> createState() => _WebGstDiaryViewState();
}

class _WebGstDiaryViewState extends State<WebGstDiaryView> with SingleTickerProviderStateMixin {
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
    // Default to current month
    fromDate = DateTime(now.year, now.month, 1);
    toDate = DateTime(now.year, now.month + 1, 0);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setDatePreset(String preset) {
    final now = DateTime.now();
    setState(() {
      if (preset == "THIS_MONTH") {
        fromDate = DateTime(now.year, now.month, 1);
        toDate = DateTime(now.year, now.month + 1, 0);
      } else if (preset == "LAST_MONTH") {
        fromDate = DateTime(now.year, now.month - 1, 1);
        toDate = DateTime(now.year, now.month, 0);
      } else if (preset == "THIS_QUARTER") {
        int currentQ = ((now.month - 1) / 3).floor();
        fromDate = DateTime(now.year, currentQ * 3 + 1, 1);
        toDate = DateTime(now.year, currentQ * 3 + 4, 0);
      } else if (preset == "LAST_QUARTER") {
        int lastQ = ((now.month - 1) / 3).floor() - 1;
        int yr = now.year;
        if (lastQ < 0) {
          lastQ = 3;
          yr -= 1;
        }
        fromDate = DateTime(yr, lastQ * 3 + 1, 1);
        toDate = DateTime(yr, lastQ * 3 + 4, 0);
      }
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(start: fromDate, end: toDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF8B5CF6),
              surface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        fromDate = picked.start;
        toDate = picked.end;
      });
    }
  }

  void _openPartyFilterDialog({required bool isPurchase}) {
    showDialog(
      context: context,
      builder: (ctx) {
        final List<String> allParties = isPurchase
            ? widget.webPh.purchases
                .map((p) => p.distributorName.trim())
                .where((n) => n.isNotEmpty)
                .toSet()
                .toList()
            : widget.webPh.parties
                .map((p) => p.id.trim())
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList();

        final Set<String> tempSelected = Set.from(
          isPurchase ? selectedPurchasePartyIds : selectedSalePartyIds,
        );

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    isPurchase ? Icons.storefront_rounded : Icons.people_alt_rounded,
                    color: isPurchase ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isPurchase ? "SELECT PURCHASE SUPPLIERS" : "SELECT SALE CUSTOMERS",
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                height: 400,
                child: Column(
                  children: [
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setDialogState(() => tempSelected.addAll(allParties));
                          },
                          child: const Text("Select All", style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setDialogState(() => tempSelected.clear());
                          },
                          child: const Text("Clear All", style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ),
                        const Spacer(),
                        Text(
                          "${tempSelected.isEmpty ? 'All Parties Selected' : '${tempSelected.length} Selected'}",
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
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
                              : (widget.webPh.parties.firstWhere(
                                      (p) => p.id == partyKey,
                                      orElse: () => Party(id: partyKey, name: partyKey, group: ''),
                                    ).name);
                          final isChecked = tempSelected.contains(partyKey);
                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            activeColor: const Color(0xFF8B5CF6),
                            title: Text(
                              displayName,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                            value: isChecked,
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  tempSelected.add(partyKey);
                                } else {
                                  tempSelected.remove(partyKey);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      if (isPurchase) {
                        selectedPurchasePartyIds.clear();
                        selectedPurchasePartyIds.addAll(tempSelected);
                      } else {
                        selectedSalePartyIds.clear();
                        selectedSalePartyIds.addAll(tempSelected);
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text("APPLY FILTER"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateSessionModal(GstDiaryCalculationResult result) {
    final titleCtrl = TextEditingController(
      text: "${DateFormat('MMM yyyy').format(fromDate)} GST Settlement",
    );
    final remarkCtrl = TextEditingController(
      text: "Reconciled with Purchase & Sale registers. Net tax calculated.",
    );
    final deductedAmountCtrl = TextEditingController(
      text: (result.netGstPayable > 0 ? result.netGstPayable : 0.0).toStringAsFixed(2),
    );
    String status = "DEDUCTED";

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.bookmark_add_rounded, color: Color(0xFF10B981), size: 22),
                  SizedBox(width: 10),
                  Text(
                    "CREATE GST SETTLEMENT SESSION",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Session Title / Label", style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Deducted Amount (₹)", style: TextStyle(color: Colors.white70, fontSize: 11)),
                              const SizedBox(height: 5),
                              TextField(
                                controller: deductedAmountCtrl,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.black26,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Status", style: TextStyle(color: Colors.white70, fontSize: 11)),
                              const SizedBox(height: 5),
                              DropdownButtonFormField<String>(
                                value: status,
                                dropdownColor: const Color(0xFF0F172A),
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.black26,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                items: const [
                                  DropdownMenuItem(value: "DEDUCTED", child: Text("DEDUCTED")),
                                  DropdownMenuItem(value: "SETTLED", child: Text("SETTLED")),
                                  DropdownMenuItem(value: "OPEN", child: Text("OPEN")),
                                ],
                                onChanged: (val) {
                                  if (val != null) setDialogState(() => status = val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text("Settlement Remarks / Bank Challan Info", style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: remarkCtrl,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "e.g. Paid via Bank Challan #CH-9921 or adjusted against ITC ledger",
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final newSession = GstDiarySession(
                      id: "gst_sess_${DateTime.now().millisecondsSinceEpoch}",
                      title: titleCtrl.text.trim().isNotEmpty
                          ? titleCtrl.text.trim()
                          : "GST Session",
                      createdAt: DateTime.now().millisecondsSinceEpoch,
                      fromDate: _isoDf.format(fromDate),
                      toDate: _isoDf.format(toDate),
                      purchasePartyIds: selectedPurchasePartyIds.toList(),
                      salePartyIds: selectedSalePartyIds.toList(),
                      totalPurchaseItc: result.totalPurchaseItc,
                      totalSaleOutputGst: result.totalSaleOutputGst,
                      netGstPayable: result.netGstPayable,
                      deductedAmount: double.tryParse(deductedAmountCtrl.text) ?? result.netGstPayable,
                      status: status,
                      remarks: remarkCtrl.text.trim(),
                    );

                    setState(() {
                      widget.webPh.gstDiarySessions.insert(0, newSession);
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF10B981),
                        content: Text("✅ GST Session '${newSession.title}' created successfully!"),
                      ),
                    );
                  },
                  child: const Text("SAVE SESSION"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditRemarkModal(GstDiarySession session) {
    final remarkCtrl = TextEditingController(text: session.remarks);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            "EDIT REMARKS: ${session.title}",
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: remarkCtrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  final idx = widget.webPh.gstDiarySessions.indexWhere((s) => s.id == session.id);
                  if (idx != -1) {
                    widget.webPh.gstDiarySessions[idx] = session.copyWith(
                      remarks: remarkCtrl.text.trim(),
                    );
                  }
                });
                Navigator.pop(ctx);
              },
              child: const Text("UPDATE REMARK"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportCsv(GstDiaryCalculationResult result) async {
    final StringBuffer sb = StringBuffer();
    sb.writeln("=== PHAROAH ERP GST DIARY AUDIT EXPORT ===");
    sb.writeln("Period: ${_df.format(fromDate)} to ${_df.format(toDate)}");
    sb.writeln("Total Output GST: ₹${result.totalSaleOutputGst.toStringAsFixed(2)}");
    sb.writeln("Total Purchase ITC: ₹${result.totalPurchaseItc.toStringAsFixed(2)}");
    sb.writeln("Net Tax Payable: ₹${result.netGstPayable.toStringAsFixed(2)}");
    sb.writeln("");

    if (activeTab == "PRODUCT") {
      sb.writeln("Product Name,Packing,HSN,Purchased Qty,Purchase GST (ITC),Avg Pur GST/Unit,Sold Qty,Sale GST (Output),Avg Sale GST/Unit,Eligible ITC,GST Difference (Payable)");
      for (var r in result.productRows) {
        sb.writeln('"${r.productName}","${r.packing}","${r.hsn}",${r.purchaseQty},${r.purchaseGst.toStringAsFixed(2)},${r.avgPurchaseGstPerUnit.toStringAsFixed(2)},${r.saleQty},${r.saleGst.toStringAsFixed(2)},${r.avgSaleGstPerUnit.toStringAsFixed(2)},${r.eligibleItcForSoldUnits.toStringAsFixed(2)},${r.gstDifference.toStringAsFixed(2)}');
      }
    } else if (activeTab == "PARTY") {
      sb.writeln("Party Name,GSTIN,Type,Total Bills,Taxable Amount,CGST,SGST,IGST,Total GST");
      for (var p in result.partyRows) {
        sb.writeln('"${p.partyName}","${p.gstin}","${p.type}",${p.totalBills},${p.taxableAmount.toStringAsFixed(2)},${p.cgst.toStringAsFixed(2)},${p.sgst.toStringAsFixed(2)},${p.igst.toStringAsFixed(2)},${p.totalGst.toStringAsFixed(2)}');
      }
    } else {
      sb.writeln("Bill No,Date,Party Name,GSTIN,Voucher Type,Taxable Amount,GST Amount,Net Bill Amount");
      for (var b in result.billRows) {
        sb.writeln('"${b.billNo}","${b.date}","${b.partyName}","${b.partyGstin}","${b.voucherType}",${b.taxableAmount.toStringAsFixed(2)},${b.gstAmount.toStringAsFixed(2)},${b.netBillAmount.toStringAsFixed(2)}');
      }
    }

    final bytes = Uint8List.fromList(utf8.encode(sb.toString()));
    final name = "gst_diary_${_isoDf.format(fromDate)}_${_isoDf.format(toDate)}";
    await FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      ext: "csv",
      mimeType: MimeType.csv,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0F766E),
          content: Text("✅ CSV Exported successfully: $name.csv"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final calcResult = GstDiaryCalculator.compute(
      sales: widget.webPh.sales,
      purchases: widget.webPh.purchases,
      parties: widget.webPh.parties,
      fromDate: fromDate,
      toDate: toDate,
      selectedPurchasePartyIds: selectedPurchasePartyIds,
      selectedSalePartyIds: selectedSalePartyIds,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TOP BAR
          _buildHeaderBar(calcResult),
          const SizedBox(height: 18),

          // 2. CONTROLS BAR (Date Presets, Multi-Party Selectors, Tab Segmented Control)
          _buildControlsBar(calcResult),
          const SizedBox(height: 18),

          // 3. MAIN SPLIT CONTENT (Grid on left + Session Drawer on right)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Workbench Grid (74%)
                Expanded(
                  flex: 74,
                  child: Column(
                    children: [
                      // Spreadsheet Table View
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: _buildGridContent(calcResult),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Sticky Bottom Summary Bar
                      _buildBottomSummaryBar(calcResult),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Right Sessions Sidebar (26%)
                Expanded(
                  flex: 26,
                  child: _buildSessionsSidebar(calcResult),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBar(GstDiaryCalculationResult result) {
    return Row(
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white12,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text("BACK TO GST HUB", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFF8B5CF6).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.menu_book_rounded, color: Color(0xFF8B5CF6), size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "GST DIARY & TAX DIFFERENCE RECONCILIATION",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
            const SizedBox(height: 2),
            Text(
              "Period: ${_df.format(fromDate)} - ${_df.format(toDate)} · Multi-party & Weighted Average ITC Matching",
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        const Spacer(),
        // ACTION 1: CREATE SESSION
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _showCreateSessionModal(result),
          icon: const Icon(Icons.add_task_rounded, size: 16),
          label: const Text("CREATE SESSION", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
        ),
        const SizedBox(width: 10),
        // ACTION 2: EXPORT CSV
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _exportCsv(result),
          icon: const Icon(Icons.download_rounded, size: 16),
          label: const Text("EXPORT CSV", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      ],
    );
  }

  Widget _buildControlsBar(GstDiaryCalculationResult result) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          // Segmented Tabs: PRODUCT / PARTY / BILL
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _tabBtn("PRODUCT", "Product-wise", Icons.inventory_2_outlined),
                _tabBtn("PARTY", "Party-wise", Icons.people_outline_rounded),
                _tabBtn("BILL", "Bill-wise", Icons.receipt_long_rounded),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Date Presets
          _datePresetChip("This Month", "THIS_MONTH"),
          const SizedBox(width: 6),
          _datePresetChip("Last Month", "LAST_MONTH"),
          const SizedBox(width: 6),
          _datePresetChip("This Quarter", "THIS_QUARTER"),
          const SizedBox(width: 12),

          // Custom Date Range Button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _pickDateRange,
            icon: const Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFF8B5CF6)),
            label: Text(
              "${_df.format(fromDate)} - ${_df.format(toDate)}",
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 14),

          // Purchase Party Filter Button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: selectedPurchasePartyIds.isNotEmpty ? const Color(0xFF06B6D4) : Colors.white70,
              side: BorderSide(
                color: selectedPurchasePartyIds.isNotEmpty ? const Color(0xFF06B6D4) : Colors.white24,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _openPartyFilterDialog(isPurchase: true),
            icon: const Icon(Icons.storefront_rounded, size: 13),
            label: Text(
              selectedPurchasePartyIds.isEmpty
                  ? "All Suppliers"
                  : "${selectedPurchasePartyIds.length} Suppliers",
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),

          // Sale Party Filter Button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: selectedSalePartyIds.isNotEmpty ? const Color(0xFFF59E0B) : Colors.white70,
              side: BorderSide(
                color: selectedSalePartyIds.isNotEmpty ? const Color(0xFFF59E0B) : Colors.white24,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _openPartyFilterDialog(isPurchase: false),
            icon: const Icon(Icons.people_alt_rounded, size: 13),
            label: Text(
              selectedSalePartyIds.isEmpty
                  ? "All Customers"
                  : "${selectedSalePartyIds.length} Customers",
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const Spacer(),

          // Search Box
          SizedBox(
            width: 200,
            height: 34,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => searchQuery = v.trim().toLowerCase()),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: "Search rows...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon: const Icon(Icons.search_rounded, size: 15, color: Colors.white54),
                contentPadding: EdgeInsets.zero,
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String tabKey, String label, IconData icon) {
    final isSel = activeTab == tabKey;
    return InkWell(
      onTap: () => setState(() => activeTab = tabKey),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF8B5CF6) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: isSel ? Colors.white : Colors.white60),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSel ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _datePresetChip(String label, String preset) {
    return InkWell(
      onTap: () => _setDatePreset(preset),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white10),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildGridContent(GstDiaryCalculationResult result) {
    if (activeTab == "PRODUCT") {
      final rows = result.productRows.where((r) {
        if (searchQuery.isEmpty) return true;
        return r.productName.toLowerCase().contains(searchQuery) ||
            r.packing.toLowerCase().contains(searchQuery) ||
            r.hsn.toLowerCase().contains(searchQuery);
      }).toList();

      if (rows.isEmpty) {
        return const Center(
          child: Text(
            "No product transactions found for the selected dates and party filters.",
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
              headingRowHeight: 40,
              dataRowHeight: 40,
              columnSpacing: 18,
              horizontalMargin: 16,
              columns: const [
                DataColumn(label: Text("PRODUCT NAME", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
                DataColumn(label: Text("PACK", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
                DataColumn(numeric: true, label: Text("PUR QTY", style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.bold))),
                DataColumn(numeric: true, label: Text("PUR ITC (₹)", style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.bold))),
                DataColumn(numeric: true, label: Text("AVG ITC/U", style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.bold))),
                DataColumn(numeric: true, label: Text("SALE QTY", style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold))),
                DataColumn(numeric: true, label: Text("SALE GST (₹)", style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold))),
                DataColumn(numeric: true, label: Text("AVG SALE/U", style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold))),
                DataColumn(numeric: true, label: Text("ELIGIBLE ITC (₹)", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
                DataColumn(numeric: true, label: Text("GST DIFF (₹)", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900))),
              ],
              rows: rows.map((r) {
                final isPayable = r.gstDifference >= 0;
                return DataRow(
                  color: MaterialStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(MaterialState.hovered)) {
                      return Colors.white.withOpacity(0.04);
                    }
                    return null;
                  }),
                  cells: [
                    DataCell(Text(r.productName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                    DataCell(Text(r.packing, style: const TextStyle(color: Colors.white60, fontSize: 11))),
                    DataCell(Text(r.purchaseQty.toStringAsFixed(0), style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'))),
                    DataCell(Text(r.purchaseGst.toStringAsFixed(2), style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 12, fontFamily: 'monospace'))),
                    DataCell(Text(r.avgPurchaseGstPerUnit.toStringAsFixed(2), style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace'))),
                    DataCell(Text(r.saleQty.toStringAsFixed(0), style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'))),
                    DataCell(Text(r.saleGst.toStringAsFixed(2), style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontFamily: 'monospace'))),
                    DataCell(Text(r.avgSaleGstPerUnit.toStringAsFixed(2), style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace'))),
                    DataCell(Text(r.eligibleItcForSoldUnits.toStringAsFixed(2), style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'))),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isPayable ? Colors.red.withOpacity(0.15) : Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "${isPayable ? '+' : ''}${r.gstDifference.toStringAsFixed(2)}",
                          style: TextStyle(
                            color: isPayable ? Colors.redAccent : Colors.greenAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      );
    } else if (activeTab == "PARTY") {
      final rows = result.partyRows.where((p) {
        if (searchQuery.isEmpty) return true;
        return p.partyName.toLowerCase().contains(searchQuery) ||
            p.gstin.toLowerCase().contains(searchQuery);
      }).toList();

      if (rows.isEmpty) {
        return const Center(
          child: Text("No party GST records match filters.", style: TextStyle(color: Colors.white38, fontSize: 13)),
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
            headingRowHeight: 40,
            dataRowHeight: 40,
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text("PARTY NAME", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(label: Text("GSTIN", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(label: Text("TYPE", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(numeric: true, label: Text("BILLS", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(numeric: true, label: Text("TAXABLE (₹)", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(numeric: true, label: Text("TOTAL GST (₹)", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
            ],
            rows: rows.map((p) {
              final isPur = p.type == "PURCHASE_SUPPLIER";
              return DataRow(
                cells: [
                  DataCell(Text(p.partyName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                  DataCell(Text(p.gstin.isNotEmpty ? p.gstin : "URP", style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace'))),
                  DataCell(
                    Text(
                      isPur ? "Supplier (ITC)" : "Customer (Output)",
                      style: TextStyle(
                        color: isPur ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  DataCell(Text("${p.totalBills}", style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'))),
                  DataCell(Text(p.taxableAmount.toStringAsFixed(2), style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'))),
                  DataCell(
                    Text(
                      p.totalGst.toStringAsFixed(2),
                      style: TextStyle(
                        color: isPur ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      );
    } else {
      // BILL-WISE
      final rows = result.billRows.where((b) {
        if (searchQuery.isEmpty) return true;
        return b.billNo.toLowerCase().contains(searchQuery) ||
            b.partyName.toLowerCase().contains(searchQuery);
      }).toList();

      if (rows.isEmpty) {
        return const Center(
          child: Text("No bill vouchers match filters.", style: TextStyle(color: Colors.white38, fontSize: 13)),
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
            headingRowHeight: 40,
            dataRowHeight: 40,
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text("BILL NO", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(label: Text("DATE", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(label: Text("PARTY NAME", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(label: Text("VOUCHER TYPE", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(numeric: true, label: Text("TAXABLE (₹)", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(numeric: true, label: Text("GST (₹)", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
              DataColumn(numeric: true, label: Text("TOTAL BILL (₹)", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
            ],
            rows: rows.map((b) {
              final isPur = b.voucherType == "PURCHASE";
              return DataRow(
                cells: [
                  DataCell(Text(b.billNo, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
                  DataCell(Text(b.date, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                  DataCell(Text(b.partyName, style: const TextStyle(color: Colors.white, fontSize: 12))),
                  DataCell(
                    Text(
                      isPur ? "PURCHASE" : "SALE",
                      style: TextStyle(
                        color: isPur ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  DataCell(Text(b.taxableAmount.toStringAsFixed(2), style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'))),
                  DataCell(Text(b.gstAmount.toStringAsFixed(2), style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'))),
                  DataCell(Text(b.netBillAmount.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
                ],
              );
            }).toList(),
          ),
        ),
      );
    }
  }

  Widget _buildBottomSummaryBar(GstDiaryCalculationResult result) {
    final bool isPayable = result.netGstPayable > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _summaryMetric("TOTAL PURCHASE ITC (INPUT)", "₹${result.totalPurchaseItc.toStringAsFixed(2)}", const Color(0xFF06B6D4)),
          const Text("—", style: TextStyle(color: Colors.white24, fontSize: 18)),
          _summaryMetric("TOTAL SALE GST (OUTPUT)", "₹${result.totalSaleOutputGst.toStringAsFixed(2)}", const Color(0xFFF59E0B)),
          const Text("=", style: TextStyle(color: Colors.white24, fontSize: 18)),
          _summaryMetric(
            isPayable ? "NET GST PAYABLE (TAX DUE)" : "SURPLUS ITC CARRY FORWARD",
            "₹${result.netGstPayable.abs().toStringAsFixed(2)}",
            isPayable ? Colors.redAccent : Colors.greenAccent,
            isBold: true,
          ),
        ],
      ),
    );
  }

  Widget _summaryMetric(String label, String value, Color color, {bool isBold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildSessionsSidebar(GstDiaryCalculationResult result) {
    final sessions = widget.webPh.gstDiarySessions;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_edu_rounded, color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              const Text(
                "SETTLEMENT SESSIONS",
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "${sessions.length}",
                  style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),

          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bookmark_outline_rounded, color: Colors.white.withOpacity(0.2), size: 36),
                          const SizedBox(height: 8),
                          const Text(
                            "No sessions created yet.",
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Calculate net payable and click 'CREATE SESSION' above to save deductions.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white30, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, idx) {
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
                              style: const TextStyle(color: Colors.white54, fontSize: 10),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Deducted:", style: TextStyle(color: Colors.white60, fontSize: 11)),
                                Text(
                                  "₹${s.deductedAmount.toStringAsFixed(2)}",
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                            if (s.remarks.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "Remark: ${s.remarks}",
                                  style: const TextStyle(color: Colors.white70, fontSize: 10, fontStyle: FontStyle.italic),
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                InkWell(
                                  onTap: () => _showEditRemarkModal(s),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_note_rounded, size: 14, color: Color(0xFF8B5CF6)),
                                        SizedBox(width: 4),
                                        Text("Edit Remark", style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      widget.webPh.gstDiarySessions.removeWhere((x) => x.id == s.id);
                                    });
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Icon(Icons.delete_outline_rounded, size: 14, color: Colors.redAccent),
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
  }
}
