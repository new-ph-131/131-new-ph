// FILE: lib/web_live_sync/components/web_fy_command_center_dialog.dart
// Revision: #PH-REV-787 (MARG-STYLE-WEB-FY-SWITCHER-NEW-FY-AND-FILE-MAINTENANCE)

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
      builder: (_) => WebFyCommandCenterDialog(webPh: webPh),
    );
  }

  @override
  State<WebFyCommandCenterDialog> createState() => _WebFyCommandCenterDialogState();
}

class _WebFyCommandCenterDialogState extends State<WebFyCommandCenterDialog> {
  bool _isRunningMaintenance = false;
  double _maintenanceProgress = 0.0;
  String _maintenanceStatus = "";
  List<String> _maintenanceReport = [];

  bool _showNewFyForm = false;
  late TextEditingController _newFyCtrl;
  bool _skipZeroStock = false;
  bool _skipExpired = false;
  bool _isCreatingFy = false;

  @override
  void initState() {
    super.initState();
    final String latestFy = widget.webPh.availableFinancialYears.isNotEmpty
        ? widget.webPh.availableFinancialYears.last
        : widget.webPh.financialYear;
    _newFyCtrl = TextEditingController(text: WebAppDateLogic.getNextFYString(latestFy));
  }

  @override
  void dispose() {
    _newFyCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSwitchFy(String targetFy) async {
    if (targetFy == widget.webPh.financialYear) return;
    await widget.webPh.switchWebFinancialYear(targetFy);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          targetFy == widget.webPh.availableFinancialYears.last
              ? "🟢 Switched to Current Financial Year: $targetFy"
              : "🟠 Switched to Back Year Audit Mode: $targetFy (Auto-Cascade Active)",
        ),
        backgroundColor: targetFy == widget.webPh.availableFinancialYears.last
            ? const Color(0xFF059669)
            : const Color(0xFFD97706),
      ),
    );
  }

  Future<void> _handleRunMaintenance() async {
    setState(() {
      _isRunningMaintenance = true;
      _maintenanceProgress = 0.05;
      _maintenanceStatus = "Starting Multi-Year Database Doctor...";
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
          content: Text("🎉 New Financial Year $targetFy Created! Fresh registers & carried balances synced to Cloud & App."),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> years = widget.webPh.availableFinancialYears.isNotEmpty
        ? widget.webPh.availableFinancialYears
        : [widget.webPh.financialYear];
    final String latestFy = years.last;
    final int pendingChallansCount =
        widget.webPh.saleChallans.where((c) => c.isDeleted != 1 && c.status == "Pending").length;

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF334155), width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "FINANCIAL YEAR & MAINTENANCE HUB",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Marg-Grade Multi-Year Switcher, Back-Year Auto-Cascade & File Maintenance",
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
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
                      // 1. FINANCIAL YEAR SWITCHER LIST
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "1. AVAILABLE FINANCIAL YEARS (चयनित वर्ष बदलें)",
                            style: TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => _showNewFyForm = !_showNewFyForm),
                            icon: Icon(
                              _showNewFyForm ? Icons.remove_circle_outline : Icons.add_circle_outline,
                              size: 15,
                              color: const Color(0xFF10B981),
                            ),
                            label: Text(
                              _showNewFyForm ? "Hide New FY Setup" : "+ Start New Financial Year",
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      ...years.reversed.map((fy) {
                        final bool isSelected = fy == widget.webPh.financialYear;
                        final bool isLatest = fy == latestFy;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0B1120),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? (isLatest ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                                  : Colors.white12,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                color: isSelected
                                    ? (isLatest ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                                    : Colors.white38,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
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
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (isLatest ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                                                .withOpacity(0.16),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(
                                            isLatest ? "CURRENT WORKING YEAR" : "BACK YEAR (HISTORICAL)",
                                            style: TextStyle(
                                              color: isLatest ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      "01 Apr ${fy.split('-').first} to 31 Mar 20${fy.split('-').last}",
                                      style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    "ACTIVE NOW",
                                    style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                )
                              else
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () => _handleSwitchFy(fy),
                                  child: const Text("Switch Year", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                        );
                      }),

                      // 2. NEW FINANCIAL YEAR CREATION FORM (Expandable)
                      if (_showNewFyForm) ...[
                        const SizedBox(height: 12),
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
                              const Row(
                                children: [
                                  Icon(Icons.rocket_launch_rounded, color: Color(0xFF10B981), size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    "START NEW FINANCIAL YEAR (नया वित्तीय वर्ष शुरू करें)",
                                    style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Creates a 100% fresh year (Sales, Purchases, Vouchers, Returns & GST Sessions reset to 0; Bill Series reset to #1) and carries forward Party Opening Balances, Bank Balances, Batch Opening Stock & Pending Challans.",
                                style: TextStyle(color: Colors.white60, fontSize: 11),
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
                                    "Note: $pendingChallansCount Pending Sale Challan(s) found — they will be automatically carried forward to the new year.",
                                    style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 10.5, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextField(
                                controller: _newFyCtrl,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  labelText: "Target Financial Year (e.g. 2027-28)",
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
                                    _isCreatingFy ? "INITIALIZING NEW YEAR..." : "CREATE & SWITCH TO NEW FINANCIAL YEAR",
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      const Divider(color: Colors.white12, height: 1),
                      const SizedBox(height: 16),

                      // 3. FILE MAINTENANCE & MULTI-YEAR CASCADE DOCTOR
                      const Text(
                        "2. FILE MAINTENANCE & MULTI-YEAR CASCADE (फाइल मेंटेनेंस और बैलेंस रिपेयर)",
                        style: TextStyle(
                          color: Color(0xFFA78BFA),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Agar aapne Back Year me koi bill change kiya hai ya stock/party balance verify karna chahte hain, to File Maintenance chalayein. Ye pichle saal se lekar current saal tak saare Opening Balances (incl. Sale/Purchase Returns) aur Batch Stocks ko dubara calculate karke App + Cloud me sync kar deta hai.",
                              style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            if (_isRunningMaintenance) ...[
                              LinearProgressIndicator(
                                value: _maintenanceProgress,
                                backgroundColor: Colors.white10,
                                color: const Color(0xFF8B5CF6),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _maintenanceStatus,
                                style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ] else
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF8B5CF6),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: _handleRunMaintenance,
                                  icon: const Icon(Icons.build_circle_rounded, size: 18),
                                  label: const Text(
                                    "RUN FILE MAINTENANCE & MULTI-YEAR CASCADE NOW",
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            if (_maintenanceReport.isNotEmpty) ...[
                              const SizedBox(height: 12),
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
                                      "✓ FILE MAINTENANCE & CASCADE COMPLETE:",
                                      style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w900),
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
