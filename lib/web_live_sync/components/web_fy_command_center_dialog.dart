// FILE: lib/web_live_sync/components/web_fy_command_center_dialog.dart
// Revision: #PH-REV-803 (APP-STYLE-3-TAB-FY-CONTROL-PANEL-AND-SAFE-CASCADE-SWITCHER)

import 'dart:convert';
import 'package:flutter/material.dart';
import '../pharoah_web_manager.dart';
import '../web_app_date_logic.dart';

class WebFyCommandCenterDialog extends StatefulWidget {
  final PharoahWebManager webPh;

  const WebFyCommandCenterDialog({
    super.key,
    required this.webPh,
  });

  static void show(BuildContext context, PharoahWebManager webPh) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WebFyCommandCenterDialog(webPh: webPh),
    );
  }

  @override
  State<WebFyCommandCenterDialog> createState() => _WebFyCommandCenterDialogState();
}

class _WebFyCommandCenterDialogState extends State<WebFyCommandCenterDialog> {
  int _activeTab = 0; // 0 = Switch FY Workspace, 1 = Carry-Forward & Maintenance, 2 = Start New FY

  bool _isSwitchingFy = false;
  String _switchingTargetFy = "";
  String _switchingStepText = "";

  bool _isRunningMaintenance = false;
  double _maintenanceProgress = 0.0;
  String _maintenanceStatus = "";
  List<String> _maintenanceReport = [];

  late TextEditingController _newFyCtrl;
  bool _skipZeroStock = false;
  bool _skipExpired = false;
  bool _isCreatingFy = false;

  @override
  void initState() {
    super.initState();
    final List<String> sortedFys = WebAppDateLogic.sortFYList(
      widget.webPh.availableFinancialYears.isNotEmpty
          ? widget.webPh.availableFinancialYears
          : [widget.webPh.financialYear],
    );
    final String latestFy = sortedFys.last;
    _newFyCtrl = TextEditingController(text: WebAppDateLogic.getNextFYString(latestFy));
  }

  @override
  void dispose() {
    _newFyCtrl.dispose();
    super.dispose();
  }

  ({int salesCount, int purcCount, int partiesCount}) _getYearStats(String fy) {
    if (fy == widget.webPh.financialYear) {
      return (
        salesCount: widget.webPh.sales.where((s) => s.isDeleted != 1).length,
        purcCount: widget.webPh.purchases.where((p) => p.isDeleted != 1).length,
        partiesCount: widget.webPh.parties.length,
      );
    }
    final files = widget.webPh.fyVault[fy];
    if (files == null) return (salesCount: 0, purcCount: 0, partiesCount: 0);
    int countJsonList(String key) {
      try {
        final raw = files[key];
        if (raw == null || raw.trim().isEmpty) return 0;
        final dec = jsonDecode(raw);
        if (dec is List) {
          return dec.where((e) => e is Map && (e['isDeleted'] ?? e['is_deleted'] ?? 0) != 1).length;
        }
      } catch (_) {}
      return 0;
    }

    return (
      salesCount: countJsonList('sales.json'),
      purcCount: countJsonList('purc.json'),
      partiesCount: countJsonList('parts.json'),
    );
  }

  int _getSourceYearPendingChallansCount(String sourceFy) {
    if (sourceFy == widget.webPh.financialYear) {
      return widget.webPh.saleChallans.where((c) => c.isDeleted != 1 && c.status == "Pending").length;
    }
    final files = widget.webPh.fyVault[sourceFy];
    if (files == null || !files.containsKey('s_challan.json')) return 0;
    try {
      final dec = jsonDecode(files['s_challan.json']!);
      if (dec is List) {
        return dec
            .where((c) =>
                c is Map &&
                (c['isDeleted'] ?? c['is_deleted'] ?? 0) != 1 &&
                (c['status'] ?? '') == 'Pending')
            .length;
      }
    } catch (_) {}
    return 0;
  }

  Future<void> _handleSwitchFy(String targetFy) async {
    if (targetFy == widget.webPh.financialYear || _isSwitchingFy) return;
    final String fromFy = widget.webPh.financialYear;
    final bool leavingBackYear = widget.webPh.isBackYearActive;

    setState(() {
      _isSwitchingFy = true;
      _switchingTargetFy = targetFy;
      _switchingStepText = leavingBackYear
          ? "Cascading closing balances & batch stock from $fromFy..."
          : "Saving $fromFy snapshot & loading $targetFy workspace...";
    });

    await Future.delayed(const Duration(milliseconds: 120));
    await widget.webPh.switchWebFinancialYear(targetFy);

    if (!mounted) return;
    setState(() {
      _isSwitchingFy = false;
    });
    Navigator.pop(context);
    final List<String> sortedFys = WebAppDateLogic.sortFYList(
      widget.webPh.availableFinancialYears.isNotEmpty
          ? widget.webPh.availableFinancialYears
          : [widget.webPh.financialYear],
    );
    final bool isLatest = targetFy == sortedFys.last;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isLatest
              ? "🟢 Active Workspace Switched to Current Financial Year: $targetFy (All Carry-Forward Balances Synced)"
              : "🟠 Entered Back-Year Audit Workspace: $targetFy (01 Apr ${targetFy.split('-').first} – 31 Mar 20${targetFy.split('-').last})",
        ),
        backgroundColor: isLatest ? const Color(0xFF059669) : const Color(0xFFD97706),
      ),
    );
  }

  Future<void> _handleRunMaintenance() async {
    setState(() {
      _isRunningMaintenance = true;
      _maintenanceProgress = 0.05;
      _maintenanceStatus = "Starting Multi-Year Carry-Forward & Database Doctor...";
      _maintenanceReport = [];
    });

    final report = await widget.webPh.runWebFileMaintenance(
      onProgress: (p, s) {
        if (mounted) {
          setState(() {
            _maintenanceProgress = p;
            _maintenanceStatus = s;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _isRunningMaintenance = false;
      _maintenanceReport = report;
    });
  }

  Future<void> _handleCreateNewFy() async {
    final String targetFy = _newFyCtrl.text.trim();
    if (targetFy.isEmpty || !targetFy.contains("-")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a valid Financial Year format (e.g. 2027-28)"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isCreatingFy = true);
    final bool ok = await widget.webPh.startNewFinancialYearOnWeb(
      targetFy,
      filterZeroStock: _skipZeroStock,
      filterExpired: _skipExpired,
    );
    if (!mounted) return;
    setState(() => _isCreatingFy = false);

    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "🎉 New Financial Year $targetFy Created! Opening Balances, Batch Stock & Pending Challans carried forward to Cloud & App.",
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  Widget _buildTabButton({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
  }) {
    final bool isSelected = _activeTab == index;
    return Expanded(
      child: InkWell(
        onTap: (_isSwitchingFy || _isRunningMaintenance || _isCreatingFy)
            ? null
            : () => setState(() => _activeTab = index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? accentColor.withOpacity(0.16) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? accentColor : Colors.white12,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? accentColor : Colors.white54, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? accentColor : Colors.white38,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> years = WebAppDateLogic.sortFYList(
      widget.webPh.availableFinancialYears.isNotEmpty
          ? widget.webPh.availableFinancialYears
          : [widget.webPh.financialYear],
    );
    final String latestFy = years.last;
    final int pendingChallansCount = _getSourceYearPendingChallansCount(latestFy);

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF334155), width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 740),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header (Matches Mobile App CompanyControlPanelView)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.account_balance_rounded, color: Color(0xFF38BDF8), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              "COMPANY CONTROL PANEL & FY HUB",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: widget.webPh.isBackYearActive
                                    ? const Color(0xFFF59E0B).withOpacity(0.2)
                                    : const Color(0xFF10B981).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "ACTIVE: ${widget.webPh.financialYear}",
                                style: TextStyle(
                                  color: widget.webPh.isBackYearActive
                                      ? const Color(0xFFFBBF24)
                                      : const Color(0xFF34D399),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          "App-Grade Financial Year Switcher, Multi-Year Carry-Forward Cascade & New Year Wizard",
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: (_isSwitchingFy || _isRunningMaintenance || _isCreatingFy)
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 3-Tab App Control Panel Bar
              Row(
                children: [
                  _buildTabButton(
                    index: 0,
                    icon: Icons.login_rounded,
                    title: "1. Switch FY",
                    subtitle: "Login to Work",
                    accentColor: const Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 8),
                  _buildTabButton(
                    index: 1,
                    icon: Icons.sync_alt_rounded,
                    title: "2. Sync Balances",
                    subtitle: "Cascade & Doctor",
                    accentColor: const Color(0xFFA78BFA),
                  ),
                  const SizedBox(width: 8),
                  _buildTabButton(
                    index: 2,
                    icon: Icons.rocket_launch_rounded,
                    title: "3. New FY Year",
                    subtitle: "Carry Forward",
                    accentColor: const Color(0xFF10B981),
                  ),
                ],
              ),

              const SizedBox(height: 14),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 14),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isSwitchingFy)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                          ),
                          child: Column(
                            children: [
                              const CircularProgressIndicator(color: Color(0xFF38BDF8)),
                              const SizedBox(height: 14),
                              Text(
                                "Switching Workspace to FY $_switchingTargetFy...",
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _switchingStepText,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                              ),
                            ],
                          ),
                        )
                      else if (_activeTab == 0) ...[
                        // TAB 0: SWITCH FINANCIAL YEAR WORKSPACE (App Login-to-Work Style)
                        if (widget.webPh.isBackYearActive)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.45)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, color: Color(0xFFFBBF24), size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "You are currently in Back Year (${widget.webPh.financialYear}). Any Sale/Purchase edits or deletions made here are automatically cascaded across ${years.join(' → ')} when you switch back to $latestFy.",
                                    style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 11, height: 1.35),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Text(
                          "SELECT FINANCIAL YEAR WORKSPACE (चयनित वित्तीय वर्ष में प्रवेश करें)",
                          style: TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...years.reversed.map((fy) {
                          final bool isSelected = fy == widget.webPh.financialYear;
                          final bool isLatest = fy == latestFy;
                          final stats = _getYearStats(fy);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? (isLatest ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                                    : Colors.white12,
                                width: isSelected ? 1.6 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? Icons.radio_button_checked : Icons.folder_copy_rounded,
                                  color: isSelected
                                      ? (isLatest ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                                      : Colors.white38,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            "FY $fy",
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isLatest
                                                  ? const Color(0xFF10B981).withOpacity(0.18)
                                                  : const Color(0xFFF59E0B).withOpacity(0.18),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isLatest ? "CURRENT YEAR" : "BACK YEAR (AUDIT)",
                                              style: TextStyle(
                                                color: isLatest ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Period: 01 Apr ${fy.split('-').first} to 31 Mar 20${fy.split('-').last}  •  Sales: ${stats.salesCount}  •  Purchases: ${stats.purcCount}  •  Parties: ${stats.partiesCount}",
                                        style: const TextStyle(color: Colors.white60, fontSize: 10.5),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      "ACTIVE WORKSPACE",
                                      style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  )
                                else
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isLatest ? const Color(0xFF059669) : const Color(0xFF2563EB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _handleSwitchFy(fy),
                                    icon: const Icon(Icons.login_rounded, size: 15),
                                    label: Text(
                                      isLatest ? "Enter Current FY" : "Open Back FY",
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ] else if (_activeTab == 1) ...[
                        // TAB 1: CARRY-FORWARD BALANCE SYNC & FILE MAINTENANCE (Matches App DataSyncView)
                        const Text(
                          "MULTI-YEAR CARRY-FORWARD & DATABASE DOCTOR (बैलेंस और स्टॉक सिंक)",
                          style: TextStyle(
                            color: Color(0xFFA78BFA),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.account_tree_rounded, color: Color(0xFFA78BFA), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Active Multi-Year Chain: ${years.join('  →  ')}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "Agar aapne pichhle kisi bhi Financial Year (1 ya 2+ saal peeche) me Sale/Purchase bill modify, delete ya recreate kiya hai, to ye tool sabhi saalon ke Closing Party Balances, Bank Balances aur Batch Closing Stock ko step-by-step agle saal ke Opening Balance aur Opening Stock me 100% sync karke Cloud + Mobile App par update kar deta hai.",
                                style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.45),
                              ),
                              const SizedBox(height: 14),
                              if (_isRunningMaintenance) ...[
                                LinearProgressIndicator(
                                  value: _maintenanceProgress,
                                  backgroundColor: Colors.white10,
                                  color: const Color(0xFF8B5CF6),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _maintenanceStatus,
                                  style: const TextStyle(
                                    color: Color(0xFFC4B5FD),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ] else
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF8B5CF6),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: _handleRunMaintenance,
                                    icon: const Icon(Icons.build_circle_rounded, size: 18),
                                    label: const Text(
                                      "SYNC OPENING BALANCES & REBUILD MULTI-YEAR STOCK NOW",
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                ),
                              if (_maintenanceReport.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF064E3B).withOpacity(0.45),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "✓ MULTI-YEAR CARRY-FORWARD & MAINTENANCE COMPLETE:",
                                        style: TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      ..._maintenanceReport.map(
                                        (line) => Padding(
                                          padding: const EdgeInsets.only(bottom: 3),
                                          child: Text(
                                            line,
                                            style: const TextStyle(color: Colors.white, fontSize: 11),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ] else if (_activeTab == 2) ...[
                        // TAB 2: START NEW FINANCIAL YEAR WIZARD
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.rocket_launch_rounded, color: Color(0xFF10B981), size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    "START NEW FINANCIAL YEAR (Source: FY $latestFy)",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Creates a 100% fresh Financial Year (Sales, Purchases, Vouchers, Returns & GST Sessions reset to 0; Bill Series reset to #1) and automatically carries forward Party Closing Balances, Bank Balances, Batch Closing Stock & Pending Challans from the latest year.",
                                style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.4),
                              ),
                              if (pendingChallansCount > 0) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                                  ),
                                  child: Text(
                                    "Note: $pendingChallansCount Pending Sale Challan(s) found in FY $latestFy — they will be automatically carried forward to the new year.",
                                    style: const TextStyle(
                                      color: Color(0xFFFBBF24),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextField(
                                controller: _newFyCtrl,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  labelText: "Target New Financial Year (e.g. 2027-28)",
                                  labelStyle: const TextStyle(color: Colors.white60, fontSize: 11),
                                  filled: true,
                                  fillColor: const Color(0xFF0F172A),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                              const SizedBox(height: 8),
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: _skipZeroStock,
                                activeColor: const Color(0xFF10B981),
                                title: const Text(
                                  "Remove Zero-Stock Batches (0 स्टॉक वाले बैच हटाएं)",
                                  style: TextStyle(color: Colors.white70, fontSize: 11.5),
                                ),
                                onChanged: (v) => setState(() => _skipZeroStock = v ?? false),
                              ),
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: _skipExpired,
                                activeColor: const Color(0xFF10B981),
                                title: const Text(
                                  "Remove Expired Batches (एक्सपायर्ड बैच हटाएं)",
                                  style: TextStyle(color: Colors.white70, fontSize: 11.5),
                                ),
                                onChanged: (v) => setState(() => _skipExpired = v ?? false),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: _isCreatingFy ? null : _handleCreateNewFy,
                                  icon: _isCreatingFy
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                        )
                                      : const Icon(Icons.check_circle_rounded, size: 18),
                                  label: Text(
                                    _isCreatingFy
                                        ? "INITIALIZING NEW FINANCIAL YEAR..."
                                        : "CREATE & SWITCH TO NEW FINANCIAL YEAR",
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
