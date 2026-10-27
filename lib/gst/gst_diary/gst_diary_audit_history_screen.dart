// FILE: lib/gst/gst_diary/gst_diary_audit_history_screen.dart
// Revision: #PH-REV-786 (DEDICATED-GST-AUDIT-HISTORY-AND-MODIFICATION-SCREEN)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models.dart';
import 'gst_diary_models.dart';

class GstDiaryAuditHistoryScreen extends StatefulWidget {
  final List<GstDiarySession> sessions;
  final List<Sale> allSales;
  final List<Purchase> allPurchases;
  final List<Party> allParties;
  final void Function(GstDiarySession updatedSession) onUpdateSession;
  final void Function(String sessionId) onDeleteSession;
  final VoidCallback onBack;
  final String? initialSelectedSessionId;
  final void Function(GstDiarySession session)? onLoadToWorkbench;

  const GstDiaryAuditHistoryScreen({
    super.key,
    required this.sessions,
    required this.allSales,
    required this.allPurchases,
    required this.allParties,
    required this.onUpdateSession,
    required this.onDeleteSession,
    required this.onBack,
    this.initialSelectedSessionId,
    this.onLoadToWorkbench,
  });

  @override
  State<GstDiaryAuditHistoryScreen> createState() => _GstDiaryAuditHistoryScreenState();
}

class _GstDiaryAuditHistoryScreenState extends State<GstDiaryAuditHistoryScreen> {
  final DateFormat _df = DateFormat('dd/MM/yyyy');
  final DateFormat _isoDf = DateFormat('yyyy-MM-dd');
  final TextEditingController _sessionSearchCtrl = TextEditingController();
  final TextEditingController _billSearchCtrl = TextEditingController();

  String? _selectedSessionId;
  String _sessionSearchQuery = "";
  String _billSearchQuery = "";
  String _billTypeFilter = "ALL"; // "ALL", "PURCHASE", "SALE", "TICKED"

  // Modification State
  bool _isEditing = false;
  late TextEditingController _editTitleCtrl;
  late TextEditingController _editRemarksCtrl;
  String _editStatus = "DEDUCTED";
  DateTime _editFromDate = DateTime.now();
  DateTime _editToDate = DateTime.now();
  Set<String> _editTickedBillIds = {};

  static const TextStyle _thStyle = TextStyle(
    color: Color(0xFF94A3B8),
    fontSize: 11,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.4,
  );

  @override
  void initState() {
    super.initState();
    _editTitleCtrl = TextEditingController();
    _editRemarksCtrl = TextEditingController();
    if (widget.initialSelectedSessionId != null &&
        widget.sessions.any((s) => s.id == widget.initialSelectedSessionId)) {
      _selectedSessionId = widget.initialSelectedSessionId;
    } else if (widget.sessions.isNotEmpty) {
      _selectedSessionId = widget.sessions.first.id;
    }
  }

  @override
  void didUpdateWidget(covariant GstDiaryAuditHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedSessionId != null &&
        !widget.sessions.any((s) => s.id == _selectedSessionId)) {
      _selectedSessionId = widget.sessions.isNotEmpty ? widget.sessions.first.id : null;
      _isEditing = false;
    } else if (_selectedSessionId == null && widget.sessions.isNotEmpty) {
      _selectedSessionId = widget.sessions.first.id;
    }
  }

  @override
  void dispose() {
    _sessionSearchCtrl.dispose();
    _billSearchCtrl.dispose();
    _editTitleCtrl.dispose();
    _editRemarksCtrl.dispose();
    super.dispose();
  }

  GstDiarySession? get _activeSession {
    if (_selectedSessionId == null) return null;
    try {
      return widget.sessions.firstWhere((s) => s.id == _selectedSessionId);
    } catch (_) {
      return widget.sessions.isNotEmpty ? widget.sessions.first : null;
    }
  }

  DateTime _parseDateSafe(String raw, DateTime fallback) {
    if (raw.trim().isEmpty) return fallback;
    try {
      return DateTime.parse(raw.trim());
    } catch (_) {
      try {
        return _df.parse(raw.trim());
      } catch (_) {
        return fallback;
      }
    }
  }

  void _startEditingSession(GstDiarySession sess) {
    final now = DateTime.now();
    final fDate = _parseDateSafe(sess.fromDate, DateTime(now.year, now.month, 1));
    final tDate = _parseDateSafe(sess.toDate, DateTime(now.year, now.month + 1, 0));
    setState(() {
      _selectedSessionId = sess.id;
      _isEditing = true;
      _editTitleCtrl.text = sess.title;
      _editRemarksCtrl.text = sess.remarks;
      _editStatus = sess.status;
      _editFromDate = fDate;
      _editToDate = tDate;
      _editTickedBillIds = Set<String>.from(sess.includedBillIds);
      _billTypeFilter = "ALL";
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _billTypeFilter = "ALL";
    });
  }

  Future<void> _pickEditDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(start: _editFromDate, end: _editToDate),
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
        _editFromDate = picked.start;
        _editToDate = picked.end;
      });
    }
  }

  Map<String, String> get _partyGstLookup {
    final map = <String, String>{};
    for (final pt in widget.allParties) {
      if (pt.id.isNotEmpty) map[pt.id] = pt.gst;
      if (pt.name.isNotEmpty) map[pt.name.trim().toLowerCase()] = pt.gst;
    }
    return map;
  }

  bool _isDateInRange(DateTime d, DateTime from, DateTime to) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  /// Resolves exact bill rows for a session (either strictly the session's included bills,
  /// or in Modify Mode all candidate bills from the period + already-included bills)
  List<GstBillDifferenceRow> _resolveSessionBills(GstDiarySession sess, {required bool includeCandidates}) {
    final gstLookup = _partyGstLookup;
    final Set<String> sessionSet = sess.includedBillIds.toSet();

    // Bills locked by OTHER sessions
    final Map<String, GstDiarySession> otherLockedMap = {};
    for (final other in widget.sessions) {
      if (other.id == sess.id || other.isDeleted == 1) continue;
      if (other.status == 'DEDUCTED' || other.status == 'SETTLED') {
        for (final bId in other.includedBillIds) {
          otherLockedMap[bId] = other;
        }
      }
    }

    final List<GstBillDifferenceRow> rows = [];

    for (final p in widget.allPurchases) {
      if (p.isDeleted == 1 || p.gstStatus == 'Cancelled' || p.gstStatus == 'Deleted') continue;
      if (p.id.startsWith('SESS_') || p.id == 'APP_CONFIG_MASTER') continue;
      if (p.billNo.trim().isEmpty && p.internalNo.trim().isEmpty) continue;
      if (p.items.isEmpty && p.totalAmount <= 0) continue;

      final bool inThisSession = sessionSet.contains(p.id) || _editTickedBillIds.contains(p.id);
      if (!includeCandidates && !sessionSet.contains(p.id)) continue;
      if (includeCandidates && !inThisSession && !_isDateInRange(p.date, _editFromDate, _editToDate)) {
        continue;
      }

      double taxable = 0.0;
      double gst = 0.0;
      for (final it in p.items) {
        final t = it.purchaseRate * it.qty;
        taxable += t;
        gst += (t * (it.gstRate / 100));
      }
      final purGstin = gstLookup[p.partyId] ?? gstLookup[p.distributorName.trim().toLowerCase()] ?? '';
      final otherSess = otherLockedMap[p.id];

      rows.add(GstBillDifferenceRow(
        billId: p.id,
        billNo: p.billNo.isNotEmpty ? p.billNo : p.internalNo,
        date: _df.format(p.date),
        partyName: p.distributorName,
        partyGstin: purGstin,
        voucherType: 'PURCHASE',
        taxableAmount: taxable,
        gstAmount: gst,
        netBillAmount: p.totalAmount,
        isDeducted: otherSess != null,
        deductedSessionName: otherSess?.title ?? '',
        deductedSessionId: otherSess?.id ?? '',
      ));
    }

    for (final s in widget.allSales) {
      if (s.isDeleted == 1 || s.status == 'Cancelled' || s.status == 'Deleted') continue;
      if (s.id.startsWith('SESS_') || s.id == 'APP_CONFIG_MASTER') continue;
      if (s.billNo.trim().isEmpty) continue;
      if (s.items.isEmpty && s.totalAmount <= 0) continue;

      final bool inThisSession = sessionSet.contains(s.id) || _editTickedBillIds.contains(s.id);
      if (!includeCandidates && !sessionSet.contains(s.id)) continue;
      if (includeCandidates && !inThisSession && !_isDateInRange(s.date, _editFromDate, _editToDate)) {
        continue;
      }

      double taxable = 0.0;
      double gst = 0.0;
      for (final it in s.items) {
        taxable += (it.rate * it.qty) - it.discountRupees;
        gst += (it.cgst + it.sgst + it.igst);
      }
      final sGstin = s.partyGstin.isNotEmpty
          ? s.partyGstin
          : (gstLookup[s.partyId] ?? gstLookup[s.partyName.trim().toLowerCase()] ?? '');
      final otherSess = otherLockedMap[s.id];

      rows.add(GstBillDifferenceRow(
        billId: s.id,
        billNo: s.billNo,
        date: _df.format(s.date),
        partyName: s.partyName,
        partyGstin: sGstin,
        voucherType: 'SALE',
        taxableAmount: taxable,
        gstAmount: gst,
        netBillAmount: s.totalAmount,
        isDeducted: otherSess != null,
        deductedSessionName: otherSess?.title ?? '',
        deductedSessionId: otherSess?.id ?? '',
      ));
    }

    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows;
  }

  void _saveModifiedSession(GstDiarySession original) {
    final candidateRows = _resolveSessionBills(original, includeCandidates: true);
    final selectedRows = candidateRows.where((r) => _editTickedBillIds.contains(r.billId)).toList();

    double purTaxable = 0.0;
    double purItc = 0.0;
    double salTaxable = 0.0;
    double salOutput = 0.0;
    final Set<String> purPartyNames = {};
    final Set<String> salPartyNames = {};

    for (final r in selectedRows) {
      if (r.voucherType == 'PURCHASE') {
        purTaxable += r.taxableAmount;
        purItc += r.gstAmount;
        if (r.partyName.trim().isNotEmpty) purPartyNames.add(r.partyName.trim());
      } else {
        salTaxable += r.taxableAmount;
        salOutput += r.gstAmount;
        if (r.partyName.trim().isNotEmpty) salPartyNames.add(r.partyName.trim());
      }
    }

    final double netPayable = salOutput - purItc;
    final updated = GstDiarySession(
      id: original.id,
      title: _editTitleCtrl.text.trim().isNotEmpty ? _editTitleCtrl.text.trim() : original.title,
      createdAt: original.createdAt,
      fromDate: _isoDf.format(_editFromDate),
      toDate: _isoDf.format(_editToDate),
      purchasePartyIds: original.purchasePartyIds,
      salePartyIds: original.salePartyIds,
      purchasePartyNames: purPartyNames.toList(),
      salePartyNames: salPartyNames.toList(),
      includedBillIds: selectedRows.map((r) => r.billId).toList(),
      totalPurchaseTaxable: purTaxable,
      totalPurchaseItc: purItc,
      totalSaleTaxable: salTaxable,
      totalSaleOutputGst: salOutput,
      netGstPayable: netPayable,
      deductedAmount: netPayable,
      totalBillsCount: selectedRows.length,
      status: _editStatus,
      remarks: _editRemarksCtrl.text.trim(),
      createdBy: original.createdBy,
      version: original.version + 1,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      isDeleted: 0,
    );

    widget.onUpdateSession(updated);
    setState(() {
      _isEditing = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "✓ Session '${updated.title}' updated (${updated.totalBillsCount} bills) & synced across App and Web!",
        ),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  void _confirmDeleteSession(GstDiarySession sess) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          "Delete Settlement Session?",
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Are you sure you want to delete '${sess.title}'? All ${sess.includedBillIds.length} bills in this session will be unlocked (OPEN) across App and Web.",
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDeleteSession(sess.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("🗑️ Session '${sess.title}' deleted and unlocked across App & Web."),
                  backgroundColor: const Color(0xFFEF4444),
                ),
              );
            },
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text("Delete Session"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredSessions = widget.sessions.where((s) {
      if (s.isDeleted == 1) return false;
      if (_sessionSearchQuery.isEmpty) return true;
      final q = _sessionSearchQuery.toLowerCase();
      if (s.title.toLowerCase().contains(q) ||
          s.fromDate.toLowerCase().contains(q) ||
          s.toDate.toLowerCase().contains(q) ||
          s.remarks.toLowerCase().contains(q) ||
          s.purchasePartyNames.any((p) => p.toLowerCase().contains(q)) ||
          s.salePartyNames.any((p) => p.toLowerCase().contains(q))) {
        return true;
      }
      // Also check if any billNo in this session matches search
      final bills = _resolveSessionBills(s, includeCandidates: false);
      return bills.any((b) =>
          b.billNo.toLowerCase().contains(q) || b.partyName.toLowerCase().contains(q));
    }).toList();

    final activeSess = _activeSession;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenW = constraints.maxWidth;
        final bool isWide = screenW >= 920;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: screenW < 600 ? 8 : 14,
            vertical: 10,
          ),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            padding: EdgeInsets.all(screenW < 600 ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TOP DEDICATED AUDIT SCREEN HEADER
                _buildTopBar(filteredSessions),
                const SizedBox(height: 14),

                if (widget.sessions.isEmpty)
                  _buildEmptySessionsState()
                else if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Sessions List (32% width)
                      Expanded(
                        flex: 32,
                        child: _buildSessionsListPanel(filteredSessions, activeSess),
                      ),
                      const SizedBox(width: 14),
                      // Right: Selected Session Detail & Live Editor (68% width)
                      Expanded(
                        flex: 68,
                        child: activeSess != null
                            ? _buildSessionDetailAndEditor(activeSess)
                            : _buildEmptySessionsState(),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSessionsListPanel(filteredSessions, activeSess, isCompact: true),
                      const SizedBox(height: 14),
                      if (activeSess != null) _buildSessionDetailAndEditor(activeSess),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(List<GstDiarySession> sessions) {
    int totalLockedBills = 0;
    double totalAdjustedNet = 0.0;
    for (final s in widget.sessions) {
      if (s.isDeleted == 1) continue;
      if (s.status == 'DEDUCTED' || s.status == 'SETTLED') {
        totalLockedBills += s.includedBillIds.length;
        totalAdjustedNet += s.netGstPayable;
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.35)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: widget.onBack,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        "BACK TO GST DIARY",
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history_edu_rounded, color: Color(0xFF8B5CF6), size: 22),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "GST AUDIT & BILL ADJUSTMENT HISTORY",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Text(
                    "${widget.sessions.length} Recorded Sessions · $totalLockedBills Adjusted Bills · Net Adjusted: ₹${totalAdjustedNet.toStringAsFixed(2)}",
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(
            width: 260,
            height: 36,
            child: TextField(
              controller: _sessionSearchCtrl,
              onChanged: (v) => setState(() => _sessionSearchQuery = v.trim()),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: "Search session, bill no, party...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySessionsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, color: Colors.white24, size: 52),
          const SizedBox(height: 12),
          const Text(
            "No GST Settlement Sessions Recorded Yet",
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            "Tick your Purchase & Sale bills in the GST Diary Workbench and click 'CREATE SESSION' to lock & track adjustments here.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
            ),
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text("Go to GST Diary Workbench"),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsListPanel(
    List<GstDiarySession> sessions,
    GstDiarySession? activeSess, {
    bool isCompact = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.folder_special_rounded, color: Color(0xFF10B981), size: 17),
                  SizedBox(width: 8),
                  Text(
                    "RECORDED SESSIONS",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "${sessions.length} Sessions",
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: isCompact ? 240 : 580),
            child: sessions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: Text("No matching sessions found.", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final s = sessions[idx];
                      final bool isSelected = activeSess?.id == s.id;
                      final Color statusColor = s.status == 'SETTLED'
                          ? const Color(0xFF10B981)
                          : (s.status == 'DEDUCTED' ? const Color(0xFFF59E0B) : Colors.blueGrey);
                      final String createdStr = DateFormat('dd MMM yyyy, hh:mm a')
                          .format(DateTime.fromMillisecondsSinceEpoch(s.createdAt));

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedSessionId = s.id;
                            _isEditing = false;
                            _billTypeFilter = "ALL";
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF8B5CF6).withOpacity(0.16)
                                : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF8B5CF6) : Colors.white10,
                              width: isSelected ? 1.5 : 1.0,
                            ),
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
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: statusColor),
                                    ),
                                    child: Text(
                                      s.status,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                "Period: ${s.fromDate} → ${s.toDate} · ${s.includedBillIds.length} Bills",
                                style: const TextStyle(color: Colors.white60, fontSize: 10.5),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                "Saved: $createdStr · v${s.version}",
                                style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "ITC: ₹${s.totalPurchaseItc.toStringAsFixed(2)}",
                                    style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 10.5, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    "Sale: ₹${s.totalSaleOutputGst.toStringAsFixed(2)}",
                                    style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10.5, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    "Net: ₹${s.netGstPayable.toStringAsFixed(2)}",
                                    style: TextStyle(
                                      color: s.netGstPayable > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionDetailAndEditor(GstDiarySession sess) {
    final allRows = _resolveSessionBills(sess, includeCandidates: _isEditing);

    // Compute live preview stats when in Modify Mode vs View Mode
    double purTaxable = sess.totalPurchaseTaxable;
    double purItc = sess.totalPurchaseItc;
    double salTaxable = sess.totalSaleTaxable;
    double salOutput = sess.totalSaleOutputGst;
    int purCount = 0;
    int salCount = 0;

    if (_isEditing) {
      purTaxable = 0.0;
      purItc = 0.0;
      salTaxable = 0.0;
      salOutput = 0.0;
      for (final r in allRows) {
        if (_editTickedBillIds.contains(r.billId)) {
          if (r.voucherType == 'PURCHASE') {
            purTaxable += r.taxableAmount;
            purItc += r.gstAmount;
            purCount++;
          } else {
            salTaxable += r.taxableAmount;
            salOutput += r.gstAmount;
            salCount++;
          }
        }
      }
    } else {
      for (final r in allRows) {
        if (r.voucherType == 'PURCHASE') {
          purCount++;
        } else {
          salCount++;
        }
      }
    }

    final double netPayable = _isEditing ? (salOutput - purItc) : sess.netGstPayable;
    final bool isPayable = netPayable > 0;

    // Filter displayed bills by type and search query
    final visibleBills = allRows.where((r) {
      if (_billTypeFilter == "PURCHASE" && r.voucherType != "PURCHASE") return false;
      if (_billTypeFilter == "SALE" && r.voucherType != "SALE") return false;
      if (_billTypeFilter == "TICKED" && !_editTickedBillIds.contains(r.billId)) return false;
      if (_billSearchQuery.isNotEmpty) {
        final q = _billSearchQuery.toLowerCase();
        return r.billNo.toLowerCase().contains(q) ||
            r.partyName.toLowerCase().contains(q) ||
            r.partyGstin.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    final Color statusColor = sess.status == 'SETTLED'
        ? const Color(0xFF10B981)
        : (sess.status == 'DEDUCTED' ? const Color(0xFFF59E0B) : Colors.blueGrey);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isEditing ? const Color(0xFF8B5CF6) : Colors.white12,
          width: _isEditing ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Session Header & Action Toolbar
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(
                          _isEditing ? "MODIFYING SESSION" : sess.status,
                          style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Text(
                          sess.title,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Period: ${sess.fromDate} to ${sess.toDate} · Created by ${sess.createdBy} · Sync Version v${sess.version}",
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  if (sess.remarks.isNotEmpty && !_isEditing) ...[
                    const SizedBox(height: 4),
                    Text(
                      "Remarks: ${sess.remarks}",
                      style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!_isEditing) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _startEditingSession(sess),
                      icon: const Icon(Icons.edit_note_rounded, size: 17),
                      label: const Text(
                        "MODIFY SESSION / BILLS",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (widget.onLoadToWorkbench != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF06B6D4),
                          side: const BorderSide(color: Color(0xFF06B6D4)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => widget.onLoadToWorkbench!(sess),
                        icon: const Icon(Icons.sync_rounded, size: 15),
                        label: const Text("Load In Workbench", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    if (sess.status != 'SETTLED')
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(color: Color(0xFF10B981)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          widget.onUpdateSession(sess.copyWith(status: 'SETTLED'));
                        },
                        icon: const Icon(Icons.verified_rounded, size: 15),
                        label: const Text("Mark Settled", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    if (sess.status != 'OPEN')
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF59E0B),
                          side: const BorderSide(color: Color(0xFFF59E0B)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          widget.onUpdateSession(sess.copyWith(status: 'OPEN'));
                        },
                        icon: const Icon(Icons.lock_open_rounded, size: 15),
                        label: const Text("Unlock Bills", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      )
                    else
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF59E0B),
                          side: const BorderSide(color: Color(0xFFF59E0B)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          widget.onUpdateSession(sess.copyWith(status: 'DEDUCTED'));
                        },
                        icon: const Icon(Icons.lock_rounded, size: 15),
                        label: const Text("Lock Bills", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    IconButton(
                      tooltip: "Delete Session",
                      onPressed: () => _confirmDeleteSession(sess),
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                    ),
                  ] else ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onPressed: _cancelEditing,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text("Cancel", style: TextStyle(fontSize: 11)),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onPressed: () => _saveModifiedSession(sess),
                      icon: const Icon(Icons.save_rounded, size: 17),
                      label: const Text(
                        "SAVE & SYNC CHANGES (APP + WEB)",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 2. If in Modify Mode, show Editable Session Metadata Form
          if (_isEditing) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune_rounded, color: Color(0xFF8B5CF6), size: 16),
                      SizedBox(width: 6),
                      Text(
                        "EDIT SESSION DETAILS & TICK/UNTICK BILLS BELOW",
                        style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _editTitleCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            labelText: "Session Title",
                            labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _editRemarksCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            labelText: "Audit Remarks / Note",
                            labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _pickEditDateRange,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.date_range_rounded, color: Color(0xFF8B5CF6), size: 15),
                              const SizedBox(width: 6),
                              Text(
                                "${_df.format(_editFromDate)} - ${_df.format(_editToDate)}",
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _editStatus,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            items: const [
                              DropdownMenuItem(value: "DEDUCTED", child: Text("Status: DEDUCTED (Locked)")),
                              DropdownMenuItem(value: "SETTLED", child: Text("Status: SETTLED (Final)")),
                              DropdownMenuItem(value: "OPEN", child: Text("Status: OPEN (Unlocked)")),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _editStatus = v);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 3. Financial Summary Strip for Session (Live Recalculated in Modify Mode)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _miniMetricCard(
                "PURCHASE ITC (INPUT)",
                "₹${purItc.toStringAsFixed(2)}",
                "Taxable: ₹${purTaxable.toStringAsFixed(2)} · $purCount Bills",
                const Color(0xFF06B6D4),
              ),
              _miniMetricCard(
                "SALE GST (OUTPUT)",
                "₹${salOutput.toStringAsFixed(2)}",
                "Taxable: ₹${salTaxable.toStringAsFixed(2)} · $salCount Bills",
                const Color(0xFFF59E0B),
              ),
              _miniMetricCard(
                isPayable ? "NET GST PAYABLE" : "NET ITC SURPLUS",
                "₹${netPayable.abs().toStringAsFixed(2)}",
                _isEditing ? "Live Recalculated from Ticked Bills" : "Adjusted in Session",
                isPayable ? const Color(0xFFEF4444) : const Color(0xFF10B981),
              ),
              _miniMetricCard(
                "ADJUSTED VOUCHERS",
                "${purCount + salCount} Bills",
                "$purCount Purchase · $salCount Sale",
                const Color(0xFF8B5CF6),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 4. Filter & Search Toolbar for Session Bills
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _filterChipBtn("ALL", _isEditing ? "All Candidate Bills (${allRows.length})" : "All Adjusted Bills (${allRows.length})"),
                    if (_isEditing)
                      _filterChipBtn("TICKED", "Ticked in Session (${_editTickedBillIds.length})"),
                    _filterChipBtn("PURCHASE", "Purchase ($purCount)"),
                    _filterChipBtn("SALE", "Sale ($salCount)"),
                    if (_isEditing) ...[
                      InkWell(
                        onTap: () {
                          setState(() {
                            for (final r in visibleBills) {
                              if (!r.isDeducted) _editTickedBillIds.add(r.billId);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "Select All",
                            style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          setState(() => _editTickedBillIds.clear());
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "Clear All",
                            style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(
                  width: 200,
                  height: 32,
                  child: TextField(
                    controller: _billSearchCtrl,
                    onChanged: (v) => setState(() => _billSearchQuery = v.trim()),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    decoration: InputDecoration(
                      hintText: "Search bill or party...",
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                      prefixIcon: const Icon(Icons.search, size: 14, color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 5. Bills Table (View Mode OR Tick-Mark Modification Mode)
          Container(
            height: 360,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: visibleBills.isEmpty
                ? const Center(
                    child: Text(
                      "No bills match the current filter in this session.",
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  )
                : _buildSessionBillsTable(visibleBills),
          ),
        ],
      ),
    );
  }

  Widget _miniMetricCard(String title, String value, String sub, Color color) {
    return Container(
      width: 195,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 9.5), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _filterChipBtn(String key, String label) {
    final bool active = _billTypeFilter == key;
    return InkWell(
      onTap: () => setState(() => _billTypeFilter = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF8B5CF6) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontSize: 10.5,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSessionBillsTable(List<GstBillDifferenceRow> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double minTableWidth = 660.0;
        final bool needHScroll = constraints.maxWidth < minTableWidth;

        Widget table = Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
              ),
              child: Row(
                children: [
                  if (_isEditing)
                    const SizedBox(width: 34, child: Text("✓", style: _thStyle)),
                  const Expanded(flex: 2, child: Text("BILL NO", style: _thStyle)),
                  const Expanded(flex: 2, child: Text("DATE", style: _thStyle)),
                  const Expanded(flex: 3, child: Text("PARTY NAME", style: _thStyle)),
                  const Expanded(flex: 2, child: Text("TYPE", style: _thStyle)),
                  const Expanded(flex: 2, child: Text("TAXABLE (₹)", textAlign: TextAlign.right, style: _thStyle)),
                  const Expanded(flex: 2, child: Text("GST (₹)", textAlign: TextAlign.right, style: _thStyle)),
                  const Expanded(flex: 2, child: Text("BILL TOTAL (₹)", textAlign: TextAlign.right, style: _thStyle)),
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
                  final bool isPur = r.voucherType == "PURCHASE";
                  final bool isTicked = !_isEditing || _editTickedBillIds.contains(r.billId);

                  return InkWell(
                    onTap: _isEditing
                        ? () {
                            setState(() {
                              if (_editTickedBillIds.contains(r.billId)) {
                                _editTickedBillIds.remove(r.billId);
                              } else {
                                _editTickedBillIds.add(r.billId);
                              }
                            });
                          }
                        : null,
                    child: Opacity(
                      opacity: isTicked ? 1.0 : 0.45,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        color: isTicked
                            ? (idx % 2 == 0 ? Colors.transparent : Colors.white.withOpacity(0.02))
                            : Colors.black12,
                        child: Row(
                          children: [
                            if (_isEditing)
                              SizedBox(
                                width: 34,
                                height: 24,
                                child: Checkbox(
                                  value: isTicked,
                                  activeColor: isPur ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B),
                                  side: const BorderSide(color: Colors.white38, width: 1.4),
                                  onChanged: (_) {
                                    setState(() {
                                      if (_editTickedBillIds.contains(r.billId)) {
                                        _editTickedBillIds.remove(r.billId);
                                      } else {
                                        _editTickedBillIds.add(r.billId);
                                      }
                                    });
                                  },
                                ),
                              ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                r.billNo,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(r.date, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                            ),
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
                            Expanded(
                              flex: 2,
                              child: Text(
                                r.taxableAmount.toStringAsFixed(2),
                                textAlign: TextAlign.right,
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ),
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
                              child: Text(
                                r.netBillAmount.toStringAsFixed(2),
                                textAlign: TextAlign.right,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
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
              child: table,
            ),
          );
        }
        return table;
      },
    );
  }
}
