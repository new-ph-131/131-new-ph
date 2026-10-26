// FILE: lib/web_live_sync/sub_views/web_gst/web_gst_diary_view.dart
import 'dart:convert';
import 'dart:math' as math;
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
  String deductionFilter = "ALL"; // "ALL", "PENDING", "DEDUCTED"
  String activePeriodLabel = "This Month";

  final Set<String> selectedPurchasePartyIds = {};
  final Set<String> selectedSalePartyIds = {};
  final TextEditingController _searchCtrl = TextEditingController();

  int get activeFyStartYear {
    final now = DateTime.now();
    return now.month >= 4 ? now.year : now.year - 1;
  }

  String get activeFyLabel => "FY $activeFyStartYear-${(activeFyStartYear + 1).toString().substring(2)}";

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    fromDate = DateTime(now.year, now.month, 1);
    toDate = DateTime(now.year, now.month + 1, 0);
    activePeriodLabel = DateFormat('MMMM yyyy').format(now);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setDateRange(DateTime start, DateTime end, String label) {
    setState(() {
      fromDate = start;
      toDate = end;
      activePeriodLabel = label;
    });
  }

  void _openFyPeriodPicker() {
    final fyYear = activeFyStartYear;
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 580,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded, color: Color(0xFF8B5CF6), size: 22),
                        const SizedBox(width: 10),
                        Text(
                          "SELECT PERIOD ($activeFyLabel)",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 16),

                // QUARTERS SECTION
                const Text(
                  "FINANCIAL YEAR QUARTERS",
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _periodOptionButton(
                        ctx,
                        "Q1 (Apr - Jun)",
                        DateTime(fyYear, 4, 1),
                        DateTime(fyYear, 6, 30),
                        "Q1 Apr-Jun $fyYear",
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _periodOptionButton(
                        ctx,
                        "Q2 (Jul - Sep)",
                        DateTime(fyYear, 7, 1),
                        DateTime(fyYear, 9, 30),
                        "Q2 Jul-Sep $fyYear",
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _periodOptionButton(
                        ctx,
                        "Q3 (Oct - Dec)",
                        DateTime(fyYear, 10, 1),
                        DateTime(fyYear, 12, 31),
                        "Q3 Oct-Dec $fyYear",
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _periodOptionButton(
                        ctx,
                        "Q4 (Jan - Mar)",
                        DateTime(fyYear + 1, 1, 1),
                        DateTime(fyYear + 1, 3, 31),
                        "Q4 Jan-Mar ${fyYear + 1}",
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // 12 MONTHS SECTION
                const Text(
                  "MONTH-WISE AUDIT (ALL 12 MONTHS)",
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _monthButton(ctx, "April", fyYear, 4),
                    _monthButton(ctx, "May", fyYear, 5),
                    _monthButton(ctx, "June", fyYear, 6),
                    _monthButton(ctx, "July", fyYear, 7),
                    _monthButton(ctx, "August", fyYear, 8),
                    _monthButton(ctx, "September", fyYear, 9),
                    _monthButton(ctx, "October", fyYear, 10),
                    _monthButton(ctx, "November", fyYear, 11),
                    _monthButton(ctx, "December", fyYear, 12),
                    _monthButton(ctx, "January", fyYear + 1, 1),
                    _monthButton(ctx, "February", fyYear + 1, 2),
                    _monthButton(ctx, "March", fyYear + 1, 3),
                  ],
                ),

                const SizedBox(height: 20),

                // PRESETS & CUSTOM RANGE
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                          ),
                          onPressed: () {
                            final now = DateTime.now();
                            _setDateRange(
                              DateTime(now.year, now.month, 1),
                              DateTime(now.year, now.month + 1, 0),
                              "This Month",
                            );
                            Navigator.pop(ctx);
                          },
                          child: const Text("This Month"),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                          ),
                          onPressed: () {
                            final now = DateTime.now();
                            _setDateRange(
                              DateTime(now.year, now.month - 1, 1),
                              DateTime(now.year, now.month, 0),
                              "Last Month",
                            );
                            Navigator.pop(ctx);
                          },
                          child: const Text("Last Month"),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF10B981),
                            side: const BorderSide(color: Color(0xFF10B981)),
                          ),
                          onPressed: () {
                            _setDateRange(
                              DateTime(fyYear, 4, 1),
                              DateTime(fyYear + 1, 3, 31),
                              "Full $activeFyLabel",
                            );
                            Navigator.pop(ctx);
                          },
                          child: Text("Full $activeFyLabel"),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _pickDateRange();
                      },
                      icon: const Icon(Icons.date_range_rounded, size: 16),
                      label: const Text("Custom Range"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _periodOptionButton(
    BuildContext ctx,
    String label,
    DateTime start,
    DateTime end,
    String displayLabel,
  ) {
    final bool isSelected = fromDate == start && toDate == end;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: isSelected ? Colors.white : Colors.white70,
        backgroundColor: isSelected ? const Color(0xFF8B5CF6) : Colors.transparent,
        side: BorderSide(color: isSelected ? const Color(0xFF8B5CF6) : Colors.white24),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () {
        _setDateRange(start, end, displayLabel);
        Navigator.pop(ctx);
      },
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _monthButton(BuildContext ctx, String monthName, int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    final isSelected = fromDate == start && toDate == end;
    return SizedBox(
      width: 120,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: isSelected ? Colors.white : Colors.white70,
          backgroundColor: isSelected ? const Color(0xFF06B6D4) : Colors.transparent,
          side: BorderSide(color: isSelected ? const Color(0xFF06B6D4) : Colors.white24),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () {
          _setDateRange(start, end, "$monthName $year");
          Navigator.pop(ctx);
        },
        child: Text(
          "$monthName '$year".substring(0, monthName.length > 5 ? 6 : monthName.length),
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
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
      _setDateRange(
        picked.start,
        picked.end,
        "${_df.format(picked.start)} - ${_df.format(picked.end)}",
      );
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
                .toList();

        final Set<String> tempSelected = Set.from(
          isPurchase ? selectedPurchasePartyIds : selectedSalePartyIds,
        );
        String partySearch = "";

        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = allParties.where((idOrName) {
              final disp = isPurchase
                  ? idOrName
                  : (widget.webPh.parties
                          .firstWhere((p) => p.id == idOrName, orElse: () => Party(id: idOrName, name: idOrName))
                          .name);
              return disp.toLowerCase().contains(partySearch.toLowerCase());
            }).toList();

            return Dialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 480,
                height: 540,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isPurchase ? "SELECT SUPPLIERS (PURCHASE)" : "SELECT CUSTOMERS (SALE)",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (v) => setModalState(() => partySearch = v),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "Search party name...",
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              tempSelected.clear();
                              tempSelected.addAll(allParties);
                            });
                          },
                          child: const Text("Select All", style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: () {
                            setModalState(() => tempSelected.clear());
                          },
                          child: const Text("Clear All", style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                        ),
                        const Spacer(),
                        Text(
                          "${tempSelected.length} selected",
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, idx) {
                          final item = filtered[idx];
                          final bool isChecked = tempSelected.contains(item);
                          final displayName = isPurchase
                              ? item
                              : (widget.webPh.parties
                                      .firstWhere((p) => p.id == item, orElse: () => Party(id: item, name: item))
                                      .name);

                          return CheckboxListTile(
                            dense: true,
                            value: isChecked,
                            activeColor: isPurchase ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B),
                            title: Text(
                              displayName,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                            onChanged: (val) {
                              setModalState(() {
                                if (val == true) {
                                  tempSelected.add(item);
                                } else {
                                  tempSelected.remove(item);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                          child: const Text("Cancel"),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isPurchase ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B),
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
                          child: const Text("Apply Filter"),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openCreateSessionModal(GstDiaryCalculationResult result) {
    final titleCtrl = TextEditingController(
      text: "${activePeriodLabel.isNotEmpty ? activePeriodLabel : 'GST Settlement'} (${_df.format(fromDate)} to ${_df.format(toDate)})",
    );
    final remarksCtrl = TextEditingController();
    String selectedStatus = 'DEDUCTED';

    final includedBillIds = result.billRows.map((b) => b.billId).toList();
    final purParties = result.partyRows
        .where((p) => p.type == 'PURCHASE_SUPPLIER')
        .map((p) => p.partyName)
        .toList();
    final salParties = result.partyRows
        .where((p) => p.type == 'SALE_CUSTOMER')
        .map((p) => p.partyName)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.lock_clock_rounded, color: Color(0xFF10B981), size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "CREATE GST SETTLEMENT SESSION",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                "Snapshot and lock vouchers with deduction tracking",
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 16),

                    // Auto-lock summary box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Period Range:", style: TextStyle(color: Colors.white70, fontSize: 12)),
                              Text(
                                "${_df.format(fromDate)} - ${_df.format(toDate)}",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Vouchers to Tag / Lock:", style: TextStyle(color: Colors.white70, fontSize: 12)),
                              Text(
                                "${includedBillIds.length} bills (${result.totalPurchaseBills} Pur, ${result.totalSaleBills} Sal)",
                                style: const TextStyle(color: Color(0xFF06B6D4), fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Net Payable Amount:", style: TextStyle(color: Colors.white70, fontSize: 12)),
                              Text(
                                "₹${result.netGstPayable.toStringAsFixed(2)}",
                                style: TextStyle(
                                  color: result.netGstPayable > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Text("Session Title / Identifier", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),

                    const SizedBox(height: 14),
                    const Text("Status Tag", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _statusChoiceChip("DEDUCTED", "DEDUCTED (Input Adjusted)", selectedStatus, (s) {
                          setDialogState(() => selectedStatus = s);
                        }),
                        const SizedBox(width: 8),
                        _statusChoiceChip("SETTLED", "SETTLED (Paid/Filed)", selectedStatus, (s) {
                          setDialogState(() => selectedStatus = s);
                        }),
                      ],
                    ),

                    const SizedBox(height: 14),
                    const Text("Deduction / Challan Remarks", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: remarksCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: "e.g. Challan CIN #12345678, Bank Ref, Paid on 20 Oct",
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),

                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                          child: const Text("Cancel"),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                          onPressed: () {
                            final session = GstDiarySession(
                              id: "SESS_${DateTime.now().millisecondsSinceEpoch}",
                              title: titleCtrl.text.trim().isNotEmpty
                                  ? titleCtrl.text.trim()
                                  : "GST Settlement",
                              createdAt: DateTime.now().millisecondsSinceEpoch,
                              fromDate: _isoDf.format(fromDate),
                              toDate: _isoDf.format(toDate),
                              purchasePartyIds: selectedPurchasePartyIds.toList(),
                              salePartyIds: selectedSalePartyIds.toList(),
                              purchasePartyNames: purParties,
                              salePartyNames: salParties,
                              includedBillIds: includedBillIds,
                              totalPurchaseTaxable: result.totalPurchaseTaxable,
                              totalPurchaseItc: result.totalPurchaseItc,
                              totalSaleTaxable: result.totalSaleTaxable,
                              totalSaleOutputGst: result.totalSaleOutputGst,
                              netGstPayable: result.netGstPayable,
                              deductedAmount: result.netGstPayable,
                              totalBillsCount: includedBillIds.length,
                              status: selectedStatus,
                              remarks: remarksCtrl.text.trim(),
                              createdBy: "Admin",
                            );
                            widget.webPh.createGstDiarySession(session);
                            Navigator.pop(dialogCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Session '${session.title}' created & ${includedBillIds.length} vouchers locked!"),
                                backgroundColor: const Color(0xFF10B981),
                              ),
                            );
                            setState(() {});
                          },
                          icon: const Icon(Icons.check_circle_rounded, size: 18),
                          label: const Text("Save & Lock"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _statusChoiceChip(String val, String label, String current, Function(String) onSelect) {
    final bool active = current == val;
    final color = val == 'DEDUCTED' ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    return InkWell(
      onTap: () => onSelect(val),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.2) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? color : Colors.white12),
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 15,
              color: active ? color : Colors.white54,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSessionAuditHistoryModal() {
    final sessions = widget.webPh.gstDiarySessions;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: math.min(screenW - 24, 780),
            height: math.min(screenH - 48, 620),
            padding: EdgeInsets.all(screenW < 600 ? 14 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.history_edu_rounded, color: Color(0xFF8B5CF6), size: 24),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "GST SETTLEMENT AUDIT & HISTORY",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              "${sessions.length} historical deduction sessions recorded",
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 12),

                Expanded(
                  child: sessions.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inventory_2_outlined, color: Colors.white24, size: 48),
                              SizedBox(height: 12),
                              Text(
                                "No settlement sessions created yet.",
                                style: TextStyle(color: Colors.white54, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: sessions.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, idx) {
                            final sess = sessions[idx];
                            return _buildAuditSessionCard(ctx, sess);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAuditSessionCard(BuildContext ctx, GstDiarySession sess) {
    final bool isDeducted = sess.status == 'DEDUCTED';
    final statusColor = isDeducted ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(sess.createdAt),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sess.title,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Created: $dateStr · By: ${sess.createdBy}",
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  sess.status,
                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Financials Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _metricItem("Period Range", "${sess.fromDate} to ${sess.toDate}", Colors.white70),
                _metricItem("Vouchers Locked", "${sess.totalBillsCount} bills", const Color(0xFF06B6D4)),
                _metricItem("Total ITC (Pur)", "₹${sess.totalPurchaseItc.toStringAsFixed(2)}", const Color(0xFF10B981)),
                _metricItem("Output GST (Sal)", "₹${sess.totalSaleOutputGst.toStringAsFixed(2)}", const Color(0xFFF59E0B)),
                _metricItem("Net Deducted", "₹${sess.deductedAmount.toStringAsFixed(2)}", statusColor),
              ],
            ),
          ),
          if (sess.remarks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.comment_outlined, size: 13, color: Colors.white38),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Remark: ${sess.remarks}",
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8B5CF6),
                  side: const BorderSide(color: Color(0xFF8B5CF6)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                onPressed: () {
                  // Apply historical session snapshot to screen
                  try {
                    final pStart = DateTime.tryParse(sess.fromDate) ?? fromDate;
                    final pEnd = DateTime.tryParse(sess.toDate) ?? toDate;
                    setState(() {
                      fromDate = pStart;
                      toDate = pEnd;
                      activePeriodLabel = sess.title;
                      selectedPurchasePartyIds.clear();
                      selectedPurchasePartyIds.addAll(sess.purchasePartyIds);
                      selectedSalePartyIds.clear();
                      selectedSalePartyIds.addAll(sess.salePartyIds);
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Applied filters for '${sess.title}' onto the workbench!"),
                        backgroundColor: const Color(0xFF8B5CF6),
                      ),
                    );
                  } catch (_) {}
                },
                icon: const Icon(Icons.sync_rounded, size: 14),
                label: const Text("Apply To Screen (लोड करें)", style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                tooltip: "Delete Session",
                onPressed: () {
                  widget.webPh.deleteGstDiarySession(sess.id);
                  Navigator.pop(ctx);
                  _openSessionAuditHistoryModal();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricItem(String title, String val, Color valColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(color: valColor, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _exportCsv(GstDiaryCalculationResult result) async {
    final StringBuffer csv = StringBuffer();
    if (activeTab == "PRODUCT") {
      csv.writeln("Product,Packing,HSN,Purchase Qty,Purchase Taxable,Purchase GST,Avg Pur GST/Unit,Sale Qty,Sale Taxable,Sale GST,Avg Sal GST/Unit,Eligible ITC,GST Difference");
      for (var r in result.productRows) {
        csv.writeln('"${r.productName}","${r.packing}","${r.hsn}",${r.purchaseQty},${r.purchaseTaxable.toStringAsFixed(2)},${r.purchaseGst.toStringAsFixed(2)},${r.avgPurchaseGstPerUnit.toStringAsFixed(2)},${r.saleQty},${r.saleTaxable.toStringAsFixed(2)},${r.saleGst.toStringAsFixed(2)},${r.avgSaleGstPerUnit.toStringAsFixed(2)},${r.eligibleItcForSoldUnits.toStringAsFixed(2)},${r.gstDifference.toStringAsFixed(2)}');
      }
    } else if (activeTab == "PARTY") {
      csv.writeln("Party Name,GSTIN,Voucher Group,Total Invoices,Taxable,CGST,SGST,IGST,Total GST");
      for (var r in result.partyRows) {
        csv.writeln('"${r.partyName}","${r.gstin}","${r.type}",${r.totalBills},${r.taxableAmount.toStringAsFixed(2)},${r.cgst.toStringAsFixed(2)},${r.sgst.toStringAsFixed(2)},${r.igst.toStringAsFixed(2)},${r.totalGst.toStringAsFixed(2)}');
      }
    } else {
      csv.writeln("Bill No,Date,Party,GSTIN,Voucher Type,Taxable,GST Amount,Net Bill Amount,Status,Session");
      for (var r in result.billRows) {
        csv.writeln('"${r.billNo}","${r.date}","${r.partyName}","${r.partyGstin}","${r.voucherType}",${r.taxableAmount.toStringAsFixed(2)},${r.gstAmount.toStringAsFixed(2)},${r.netBillAmount.toStringAsFixed(2)},"${r.isDeducted ? 'DEDUCTED' : 'OPEN'}","${r.deductedSessionName}"');
      }
    }

    final bytes = Uint8List.fromList(utf8.encode(csv.toString()));
    await FileSaver.instance.saveFile(
      name: "GST_Diary_${activeTab}_${_isoDf.format(DateTime.now())}.csv",
      bytes: bytes,
      ext: "csv",
      mimeType: MimeType.csv,
    );
  }

  int _getFilteredRowCount(GstDiaryCalculationResult result) {
    if (activeTab == "PRODUCT") {
      return result.productRows.where((r) {
        if (searchQuery.isEmpty) return true;
        return r.productName.toLowerCase().contains(searchQuery) ||
            r.packing.toLowerCase().contains(searchQuery) ||
            r.hsn.toLowerCase().contains(searchQuery);
      }).length;
    } else if (activeTab == "PARTY") {
      return result.partyRows.where((r) {
        if (searchQuery.isEmpty) return true;
        return r.partyName.toLowerCase().contains(searchQuery) ||
            r.gstin.toLowerCase().contains(searchQuery);
      }).length;
    } else {
      return result.billRows.where((r) {
        if (searchQuery.isEmpty) return true;
        return r.billNo.toLowerCase().contains(searchQuery) ||
            r.partyName.toLowerCase().contains(searchQuery) ||
            r.partyGstin.toLowerCase().contains(searchQuery);
      }).length;
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
      existingSessions: widget.webPh.gstDiarySessions,
      deductionFilter: deductionFilter,
    );

    final int filteredRows = _getFilteredRowCount(calcResult);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenWidth = constraints.maxWidth;
        final double screenHeight = MediaQuery.of(context).size.height;
        // Wide landscape mode (Desktop / iPad Landscape >= 980px)
        final bool isWide = screenWidth >= 980;
        // Tablet Portrait mode (600px .. 979px)
        final bool isTabletPortrait = screenWidth >= 600 && screenWidth < 980;

        // Smart auto-fitting table height based on actual row count:
        // Eliminates the giant empty dark-blue void when there are only 1-3 rows,
        // keeping Net Payable Summary Bar and Audit & History immediately visible!
        final double naturalRowsHeight = filteredRows == 0
            ? 170.0
            : (54.0 + (filteredRows * 48.0));

        final double portraitTableHeight = naturalRowsHeight.clamp(165.0, 360.0);
        final double wideTableHeight = naturalRowsHeight.clamp(280.0, (screenHeight - 330).clamp(360.0, 560.0));
        final double widePanelHeight = (wideTableHeight + 66.0).clamp(360.0, 640.0);

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth < 600 ? 8 : 14,
            vertical: 10,
          ),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            padding: EdgeInsets.all(screenWidth < 600 ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. TOP RESPONSIVE HEADER BAR
                _buildHeaderBar(calcResult, screenWidth),
                const SizedBox(height: 12),

                // 2. EXECUTIVE 4-CARD TOP KPI STRIP (AUTO-ADAPTIVE: 4x1 ON TABLET/DESKTOP, 2x2 ON MOBILE)
                _buildTopExecutiveKpiStrip(calcResult, screenWidth),
                const SizedBox(height: 12),

                // 3. RESPONSIVE CONTROLS & FILTER BAR
                _buildControlsBar(calcResult),
                const SizedBox(height: 12),

                // 4. 100% AUTOMATIC WORKBENCH (NO MANUAL SWITCH NEEDED!)
                if (isWide) ...[
                  // LANDSCAPE / DESKTOP: Auto Side-by-Side (70% Left Table+Summary | 30% Right Audit+Sessions)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 70,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: wideTableHeight,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: _buildGridContent(calcResult),
                            ),
                            const SizedBox(height: 10),
                            _buildBottomSummaryBar(calcResult),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 30,
                        child: _buildRightSidePanel(
                          calcResult,
                          height: widePanelHeight,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // PORTRAIT TABLET & MOBILE: Auto-Fitted Table + Immediate Net Payable Bar + Auto Audit & Sessions Panel
                  Container(
                    height: portraitTableHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: _buildGridContent(calcResult),
                  ),
                  const SizedBox(height: 10),

                  // Net Payable Bottom Summary Bar (Directly under table - Always visible!)
                  _buildBottomSummaryBar(calcResult),
                  const SizedBox(height: 12),

                  // Auto Audit & History + Settlement Sessions (Side-by-Side on Tablet Portrait, Stacked on Mobile)
                  _buildAutoPortraitAuditAndSessions(calcResult, isTabletPortrait),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Automatically renders Audit & History and Settlement Sessions on the same screen
  /// in Portrait Tablet (2-column side-by-side) and Mobile (stacked) without any manual switch.
  Widget _buildAutoPortraitAuditAndSessions(GstDiaryCalculationResult result, bool isTabletPortrait) {
    final sessions = widget.webPh.gstDiarySessions;
    final net = result.netGstPayable;
    final isPayable = net > 0;

    final Widget auditBox = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_edu_rounded, color: Color(0xFF8B5CF6), size: 17),
                  SizedBox(width: 8),
                  Text(
                    "AUDIT & HISTORY",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${sessions.length} recorded",
                  style: const TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPayable ? "NET GST PAYABLE" : "NET SURPLUS ITC",
                      style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "₹${net.abs().toStringAsFixed(2)}",
                      style: TextStyle(
                        color: isPayable ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      "BILLS STATUS",
                      style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${result.totalDeductedBills} Locked · ${result.totalPendingBills} Pending",
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _openSessionAuditHistoryModal,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.5)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_rounded, size: 15, color: Color(0xFF8B5CF6)),
                  SizedBox(width: 6),
                  Text(
                    "View History Details (इतिहास देखें)",
                    style: TextStyle(
                      color: Color(0xFF8B5CF6),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final Widget sessionsBox = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.bookmark_added_rounded, color: Color(0xFF10B981), size: 16),
                  SizedBox(width: 6),
                  Text(
                    "SETTLEMENT SESSIONS",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _openCreateSessionModal(result),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                  ),
                  child: const Text(
                    "+ Snapshot Session",
                    style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),
          _buildSessionListView(sessions, shrinkWrap: true),
        ],
      ),
    );

    if (isTabletPortrait) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 44, child: auditBox),
          const SizedBox(width: 12),
          Expanded(flex: 56, child: sessionsBox),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        auditBox,
        const SizedBox(height: 12),
        sessionsBox,
      ],
    );
  }

  Widget _buildHeaderBar(GstDiaryCalculationResult result, double screenWidth) {
    final sessions = widget.webPh.gstDiarySessions;

    return Container(
      width: double.infinity,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: widget.onBack,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 16),
                      SizedBox(width: 6),
                      Text("BACK TO GST HUB", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_stories_rounded, color: Color(0xFF8B5CF6), size: 18),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "GST DIARY & TAX DIFFERENCE RECONCILIATION",
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                  ),
                  Text(
                    "Active Period: $activePeriodLabel (${_df.format(fromDate)} - ${_df.format(toDate)}) · Multi-Party & Weighted-Avg ITC",
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8B5CF6),
                  side: const BorderSide(color: Color(0xFF8B5CF6)),
                  backgroundColor: const Color(0xFF8B5CF6).withOpacity(0.1),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _openSessionAuditHistoryModal,
                icon: const Icon(Icons.history_edu_rounded, size: 15),
                label: Text(
                  "AUDIT & HISTORY (${sessions.length})",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _openCreateSessionModal(result),
                icon: const Icon(Icons.add_task_rounded, size: 15),
                label: const Text("CREATE SESSION", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _exportCsv(result),
                icon: const Icon(Icons.download_rounded, size: 15),
                label: const Text("EXPORT CSV", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopExecutiveKpiStrip(GstDiaryCalculationResult result, double screenWidth) {
    final net = result.netGstPayable;
    final isPayable = net > 0;
    final sessions = widget.webPh.gstDiarySessions;

    final itcCard = _kpiCard(
      title: "PURCHASE ITC (INPUT)",
      amount: "₹${result.totalPurchaseItc.toStringAsFixed(2)}",
      badgeText: "ITC CREDIT",
      subtitle: "Eligible Input Tax Credit",
      color: const Color(0xFF06B6D4),
      icon: Icons.input_rounded,
    );

    final saleGstCard = _kpiCard(
      title: "SALE GST (OUTPUT)",
      amount: "₹${result.totalSaleOutputGst.toStringAsFixed(2)}",
      badgeText: "OUTPUT TAX",
      subtitle: "Tax Collected on Sales",
      color: const Color(0xFFF59E0B),
      icon: Icons.output_rounded,
    );

    final netCard = _kpiCard(
      title: isPayable ? "NET GST PAYABLE (DUE)" : "NET SURPLUS CREDIT",
      amount: "₹${net.abs().toStringAsFixed(2)}",
      badgeText: isPayable ? "TAX DUE" : "SURPLUS",
      subtitle: isPayable ? "Net Tax Payable (शुद्ध देय कर)" : "Carry Forward (अधिशेष क्रेडिट)",
      color: isPayable ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      icon: isPayable ? Icons.account_balance_wallet_rounded : Icons.savings_rounded,
      isHero: true,
    );

    final auditCard = _kpiCard(
      title: "AUDIT & SESSIONS",
      amount: "${result.totalDeductedBills} Locked · ${result.totalPendingBills} Open",
      badgeText: "${sessions.length} SESSIONS",
      subtitle: "Tap to open Audit History",
      color: const Color(0xFF8B5CF6),
      icon: Icons.history_edu_rounded,
      onTap: _openSessionAuditHistoryModal,
    );

    // On Desktop & Tablet Portrait (>= 740px), show all 4 cards in a single compact row!
    if (screenWidth >= 740) {
      return Row(
        children: [
          Expanded(child: itcCard),
          const SizedBox(width: 8),
          Expanded(child: saleGstCard),
          const SizedBox(width: 8),
          Expanded(child: netCard),
          const SizedBox(width: 8),
          Expanded(child: auditCard),
        ],
      );
    }

    // On Mobile (< 740px), show compact 2x2 grid so all 4 cards are visible at a glance!
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: itcCard),
            const SizedBox(width: 8),
            Expanded(child: saleGstCard),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: netCard),
            const SizedBox(width: 8),
            Expanded(child: auditCard),
          ],
        ),
      ],
    );
  }

  Widget _kpiCard({
    required String title,
    required String amount,
    required String badgeText,
    required String subtitle,
    required Color color,
    required IconData icon,
    bool isHero = false,
    VoidCallback? onTap,
  }) {
    Widget card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHero ? color.withOpacity(0.65) : color.withOpacity(0.25),
          width: isHero ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: color,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            amount,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 9.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: card,
      );
    }
    return card;
  }

  Widget _buildControlsBar(GstDiaryCalculationResult result) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // Segmented Tabs
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tabBtn("PRODUCT", "Product-wise", Icons.inventory_2_outlined),
                _tabBtn("PARTY", "Party-wise", Icons.people_outline_rounded),
                _tabBtn("BILL", "Bill-wise", Icons.receipt_long_rounded),
              ],
            ),
          ),

          // FY Period Dropdown Button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF8B5CF6).withOpacity(0.12),
              side: const BorderSide(color: Color(0xFF8B5CF6)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _openFyPeriodPicker,
            icon: const Icon(Icons.calendar_month_rounded, size: 14, color: Color(0xFF8B5CF6)),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  activePeriodLabel,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Colors.white70),
              ],
            ),
          ),

          // Date Range Details
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.date_range_rounded, size: 13, color: Colors.white54),
                  const SizedBox(width: 6),
                  Text(
                    "${_df.format(fromDate)} - ${_df.format(toDate)}",
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),

          // Suppliers Filter
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
              selectedPurchasePartyIds.isEmpty ? "All Suppliers" : "${selectedPurchasePartyIds.length} Suppliers",
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),

          // Customers Filter
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
            icon: const Icon(Icons.groups_rounded, size: 13),
            label: Text(
              selectedSalePartyIds.isEmpty ? "All Customers" : "${selectedSalePartyIds.length} Customers",
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),

          // Deduction Filter Toggle (All / Pending / Deducted)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: deductionFilter,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(fontSize: 11, color: Colors.white),
                icon: const Icon(Icons.filter_alt_outlined, size: 14, color: Colors.white54),
                items: const [
                  DropdownMenuItem(value: "ALL", child: Text("Status: All Vouchers")),
                  DropdownMenuItem(value: "PENDING", child: Text("Status: Pending Only")),
                  DropdownMenuItem(value: "DEDUCTED", child: Text("Status: Deducted Only")),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => deductionFilter = val);
                },
              ),
            ),
          ),

          // Search Box (adaptive width)
          SizedBox(
            width: 170,
            height: 34,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => searchQuery = v.trim().toLowerCase()),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: "Search rows...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon: const Icon(Icons.search, size: 15, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String key, String label, IconData icon) {
    final bool active = activeTab == key;
    return InkWell(
      onTap: () => setState(() => activeTab = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF8B5CF6) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: active ? Colors.white : Colors.white60),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white60,
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
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
        return _emptyState("No products found for the selected period & party filters.");
      }

      return _buildProductTable(rows);
    } else if (activeTab == "PARTY") {
      final rows = result.partyRows.where((r) {
        if (searchQuery.isEmpty) return true;
        return r.partyName.toLowerCase().contains(searchQuery) ||
            r.gstin.toLowerCase().contains(searchQuery);
      }).toList();

      if (rows.isEmpty) {
        return _emptyState("No party records found for the selected filters.");
      }

      return _buildPartyTable(rows);
    } else {
      final rows = result.billRows.where((r) {
        if (searchQuery.isEmpty) return true;
        return r.billNo.toLowerCase().contains(searchQuery) ||
            r.partyName.toLowerCase().contains(searchQuery) ||
            r.partyGstin.toLowerCase().contains(searchQuery);
      }).toList();

      if (rows.isEmpty) {
        return _emptyState("No bills found for the selected filters.");
      }

      return _buildBillTable(rows);
    }
  }

  Widget _buildProductTable(List<GstProductDifferenceRow> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double minTableWidth = 650.0;
        final bool needHScroll = constraints.maxWidth < minTableWidth;
        
        Widget tableWidget = Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: const Row(
                children: [
                  Expanded(flex: 3, child: Text("PRODUCT NAME", style: _thStyle)),
                  Expanded(flex: 1, child: Text("PACK", style: _thStyle)),
                  Expanded(flex: 1, child: Text("PUR QTY", textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.bold))),
                  Expanded(flex: 1, child: Text("PUR ITC (₹)", textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.bold))),
                  Expanded(flex: 1, child: Text("AVG ITC/U", textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.bold))),
                  Expanded(flex: 1, child: Text("SALE QTY", textAlign: TextAlign.right, style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold))),
                  Expanded(flex: 1, child: Text("SALE GST (₹)", textAlign: TextAlign.right, style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold))),
                  Expanded(flex: 1, child: Text("AVG SALE/U", textAlign: TextAlign.right, style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold))),
                  Expanded(flex: 1, child: Text("ELIGIBLE ITC (₹)", textAlign: TextAlign.right, style: _thStyle)),
                  Expanded(flex: 1, child: Text("GST DIFF (₹)", textAlign: TextAlign.right, style: _thStyle)),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            // Rows
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, idx) {
                  final r = rows[idx];
                  final diffColor = r.gstDifference >= 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    color: idx % 2 == 0 ? Colors.transparent : Colors.white.withOpacity(0.015),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            r.productName,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(flex: 1, child: Text(r.packing, style: const TextStyle(color: Colors.white54, fontSize: 11), overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 1, child: Text(r.purchaseQty.toStringAsFixed(0), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                        Expanded(flex: 1, child: Text(r.purchaseGst.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.w600))),
                        Expanded(flex: 1, child: Text(r.avgPurchaseGstPerUnit.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontSize: 11))),
                        Expanded(flex: 1, child: Text(r.saleQty.toStringAsFixed(0), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                        Expanded(flex: 1, child: Text(r.saleGst.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.w600))),
                        Expanded(flex: 1, child: Text(r.avgSaleGstPerUnit.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontSize: 11))),
                        Expanded(flex: 1, child: Text(r.eligibleItcForSoldUnits.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                        Expanded(
                          flex: 1,
                          child: Text(
                            "${r.gstDifference >= 0 ? "+" : ""}${r.gstDifference.toStringAsFixed(2)}",
                            textAlign: TextAlign.right,
                            style: TextStyle(color: diffColor, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );

        if (needHScroll) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: minTableWidth,
              height: constraints.maxHeight,
              child: tableWidget,
            ),
          );
        }
        return tableWidget;
      },
    );
  }

  Widget _buildPartyTable(List<GstPartyDifferenceRow> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double minTableWidth = 620.0;
        final bool needHScroll = constraints.maxWidth < minTableWidth;
        
        Widget tableWidget = Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: const Row(
                children: [
                  Expanded(flex: 3, child: Text("PARTY NAME", style: _thStyle)),
                  Expanded(flex: 2, child: Text("GSTIN", style: _thStyle)),
                  Expanded(flex: 2, child: Text("TYPE", style: _thStyle)),
                  Expanded(flex: 1, child: Text("BILLS", textAlign: TextAlign.right, style: _thStyle)),
                  Expanded(flex: 2, child: Text("TAXABLE (₹)", textAlign: TextAlign.right, style: _thStyle)),
                  Expanded(flex: 2, child: Text("TOTAL GST (₹)", textAlign: TextAlign.right, style: _thStyle)),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, idx) {
                  final r = rows[idx];
                  final isSupplier = r.type == "PURCHASE_SUPPLIER";
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    color: idx % 2 == 0 ? Colors.transparent : Colors.white.withOpacity(0.015),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            r.partyName,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            r.gstin.isNotEmpty ? r.gstin : "UNREGISTERED",
                            style: TextStyle(color: r.gstin.isNotEmpty ? Colors.white70 : Colors.white38, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            isSupplier ? "Supplier (ITC)" : "Customer (Output)",
                            style: TextStyle(
                              color: isSupplier ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(flex: 1, child: Text("${r.totalBills}", textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                        Expanded(flex: 2, child: Text(r.taxableAmount.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                        Expanded(
                          flex: 2,
                          child: Text(
                            r.totalGst.toStringAsFixed(2),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: isSupplier ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );

        if (needHScroll) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: minTableWidth,
              height: constraints.maxHeight,
              child: tableWidget,
            ),
          );
        }
        return tableWidget;
      },
    );
  }

  Widget _buildBillTable(List<GstBillDifferenceRow> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double minTableWidth = 650.0;
        final bool needHScroll = constraints.maxWidth < minTableWidth;
        
        Widget tableWidget = Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: const Row(
                children: [
                  Expanded(flex: 2, child: Text("BILL NO", style: _thStyle)),
                  Expanded(flex: 2, child: Text("DATE", style: _thStyle)),
                  Expanded(flex: 3, child: Text("PARTY NAME", style: _thStyle)),
                  Expanded(flex: 2, child: Text("TYPE", style: _thStyle)),
                  Expanded(flex: 2, child: Text("TAXABLE (₹)", textAlign: TextAlign.right, style: _thStyle)),
                  Expanded(flex: 2, child: Text("GST (₹)", textAlign: TextAlign.right, style: _thStyle)),
                  Expanded(flex: 2, child: Text("STATUS", textAlign: TextAlign.center, style: _thStyle)),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, idx) {
                  final r = rows[idx];
                  final isPur = r.voucherType == "PURCHASE";
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    color: idx % 2 == 0 ? Colors.transparent : Colors.white.withOpacity(0.015),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            r.billNo,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(flex: 2, child: Text(r.date, style: const TextStyle(color: Colors.white54, fontSize: 11))),
                        Expanded(
                          flex: 3,
                          child: Text(
                            r.partyName,
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            isPur ? "PURCHASE" : "SALE",
                            style: TextStyle(
                              color: isPur ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(flex: 2, child: Text(r.taxableAmount.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                        Expanded(
                          flex: 2,
                          child: Text(
                            r.gstAmount.toStringAsFixed(2),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: isPur ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Center(
                            child: r.isDeducted
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFF10B981)),
                                    ),
                                    child: const Text(
                                      "DEDUCTED",
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: const Text(
                                      "OPEN",
                                      style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );

        if (needHScroll) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: minTableWidth,
              height: constraints.maxHeight,
              child: tableWidget,
            ),
          );
        }
        return tableWidget;
      },
    );
  }

  Widget _buildBottomSummaryBar(GstDiaryCalculationResult result) {
    final net = result.netGstPayable;
    final isPayable = net > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 620;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _summaryBlock("PUR ITC", "₹${result.totalPurchaseItc.toStringAsFixed(2)}", const Color(0xFF06B6D4)),
                    _summaryBlock("SALE GST", "₹${result.totalSaleOutputGst.toStringAsFixed(2)}", const Color(0xFFF59E0B)),
                    _summaryBlock(isPayable ? "NET DUE" : "SURPLUS", "₹${net.abs().toStringAsFixed(2)}", isPayable ? const Color(0xFFEF4444) : const Color(0xFF10B981)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Locked: ${result.totalDeductedBills} · Pending: ${result.totalPendingBills}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                    InkWell(
                      onTap: _openSessionAuditHistoryModal,
                      child: const Text("Audit History Details →", style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _summaryBlock(
                        "TOTAL PURCHASE ITC (INPUT)",
                        "₹${result.totalPurchaseItc.toStringAsFixed(2)}",
                        const Color(0xFF06B6D4),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text("—", style: TextStyle(color: Colors.white24, fontSize: 18)),
                      ),
                      _summaryBlock(
                        "TOTAL SALE GST (OUTPUT)",
                        "₹${result.totalSaleOutputGst.toStringAsFixed(2)}",
                        const Color(0xFFF59E0B),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text("=", style: TextStyle(color: Colors.white24, fontSize: 18)),
                      ),
                      _summaryBlock(
                        isPayable ? "NET GST PAYABLE (TAX DUE)" : "NET SURPLUS CREDIT (CARRY FWD)",
                        "₹${net.abs().toStringAsFixed(2)}",
                        isPayable ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "Locked: ${result.totalDeductedBills} · Pending: ${result.totalPendingBills}",
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _openSessionAuditHistoryModal,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_edu_rounded, size: 12, color: Color(0xFF8B5CF6)),
                          SizedBox(width: 4),
                          Text("History", style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryBlock(String title, String val, Color valColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(color: valColor, fontSize: 14, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildRightSidePanel(GstDiaryCalculationResult result, {double? height}) {
    final sessions = widget.webPh.gstDiarySessions;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
      children: [
        // 1. TOP HISTORY & AUDIT BOX
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.history_edu_rounded, color: Color(0xFF8B5CF6), size: 16),
                      SizedBox(width: 8),
                      Text(
                        "AUDIT & HISTORY",
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${sessions.length} recorded",
                      style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _openSessionAuditHistoryModal,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.visibility_rounded, size: 14, color: Color(0xFF8B5CF6)),
                      SizedBox(width: 6),
                      Text(
                        "View History Details (इतिहास देखें)",
                        style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),

        // 2. ACTIVE SETTLEMENT SESSIONS HEADER
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.bookmark_added_rounded, color: Color(0xFF10B981), size: 15),
                  SizedBox(width: 6),
                  Text(
                    "SETTLEMENT SESSIONS",
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Text(
                "${sessions.length}",
                style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),

        // 3. SESSION STREAM
        if (height != null)
          Expanded(
            child: _buildSessionListView(sessions),
          )
        else
          _buildSessionListView(sessions, shrinkWrap: true),
      ],
    );

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: content,
    );
  }

  Widget _buildSessionListView(List<GstDiarySession> sessions, {bool shrinkWrap = false}) {
    if (sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, color: Colors.white.withOpacity(0.2), size: 36),
              const SizedBox(height: 8),
              const Text(
                "No sessions created yet.",
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                "Click 'CREATE SESSION' above to snapshot current calculations.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(10),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final s = sessions[idx];
        return _buildSessionSideCard(s);
      },
    );
  }

  Widget _buildSessionSideCard(GstDiarySession s) {
    final bool isDeducted = s.status == 'DEDUCTED';
    final statusColor = isDeducted ? const Color(0xFFF59E0B) : const Color(0xFF10B981);

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  s.title,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor, width: 0.8),
                ),
                child: Text(
                  s.status,
                  style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "${s.fromDate} - ${s.toDate} · ${s.totalBillsCount} bills",
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Deducted ₹:", style: TextStyle(color: Colors.white54, fontSize: 10)),
              Text(
                "₹${s.deductedAmount.toStringAsFixed(2)}",
                style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          if (s.remarks.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              "Note: ${s.remarks}",
              style: const TextStyle(color: Colors.white60, fontSize: 10, fontStyle: FontStyle.italic),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            Text(msg, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  static const TextStyle _thStyle = TextStyle(
    color: Colors.white70,
    fontSize: 11,
    fontWeight: FontWeight.bold,
  );
}
