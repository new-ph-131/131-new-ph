// FILE: lib/web_live_sync/sub_views/web_accounts/web_voucher_entry_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../web_app_date_logic.dart';
import '../../web_pdf_router_service.dart';
import '../web_billing/quick_add_party_modal.dart';

class WebVoucherEntryView extends StatefulWidget {
  final VoidCallback onBack;
  final String type; // Receipt, Payment, Contra, Expense
  final Voucher? existingVoucher;
  final bool isReadOnly;

  const WebVoucherEntryView({
    super.key,
    required this.onBack,
    required this.type,
    this.existingVoucher,
    this.isReadOnly = false,
  });

  @override
  State<WebVoucherEntryView> createState() => _WebVoucherEntryViewState();
}

class _WebVoucherEntryViewState extends State<WebVoucherEntryView> {
  final amountC = TextEditingController();
  final narrationC = TextEditingController();
  final chequeNoC = TextEditingController();
  final partySearchC = TextEditingController();

  DateTime selectedEntryDate = DateTime.now();
  DateTime selectedChequeDate = DateTime.now();
  Party? selectedParty;
  Party? selectedInternalAccount;
  Party? selectedContraTargetAccount;

  String payMode = "Cash";
  String voucherNo = "Loading...";
  bool isUpdateMode = false;
  bool isSaving = false;

  List<Map<String, dynamic>> pendingBills = [];
  List<String> selectedBillNumbers = [];
  double runningTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  void _initSession() {
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    String typeKey = widget.type.toUpperCase();

    if (widget.existingVoucher != null) {
      isUpdateMode = true;
      final v = widget.existingVoucher!;
      voucherNo = v.voucherNo;
      amountC.text = v.amount.toStringAsFixed(2);
      narrationC.text = v.narration.replaceAll("[CANCELLED] ", "");
      payMode = v.paymentMode;
      selectedEntryDate = v.date;
      selectedChequeDate = v.chequeDate ?? v.date;
      chequeNoC.text = v.chequeNo;
      selectedBillNumbers = List.from(v.linkedBillNumbers);
      runningTotal = v.amount;

      try {
        selectedParty = webPh.parties.firstWhere((p) => p.id == v.partyId || p.name == v.partyName);
      } catch (_) {
        selectedParty = Party(id: v.partyId, name: v.partyName);
      }

      try {
        selectedInternalAccount = webPh.parties.firstWhere((p) => p.name == v.depositedIn);
      } catch (_) {}

      if (selectedParty != null) {
        pendingBills = webPh.getPendingBills(selectedParty!.id, typeKey == "RECEIPT");
      }
    } else {
      selectedEntryDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
      selectedChequeDate = selectedEntryDate;

      String prefix = "RCT-";
      if (typeKey == "PAYMENT") prefix = "PAY-";
      if (typeKey == "CONTRA") prefix = "CNT-";
      if (typeKey == "EXPENSE") prefix = "EXP-";

      voucherNo = webPh.getNextBillNumber(typeKey, prefix, 101);
    }

    final internalAccs = webPh.parties.where((p) => p.group == "Bank Accounts" || p.group == "Cash in Hand").toList();
    if (internalAccs.isNotEmpty && selectedInternalAccount == null) {
      selectedInternalAccount = internalAccs.firstWhere((p) => p.group == "Cash in Hand", orElse: () => internalAccs.first);
    }
    if (internalAccs.length > 1 && selectedContraTargetAccount == null) {
      selectedContraTargetAccount = internalAccs.firstWhere((p) => p.group == "Bank Accounts", orElse: () => internalAccs.last);
    }

    setState(() {});
  }

  @override
  void dispose() {
    amountC.dispose();
    narrationC.dispose();
    chequeNoC.dispose();
    partySearchC.dispose();
    super.dispose();
  }

  void _onPartyChosen(Party party, PharoahWebManager webPh) {
    setState(() {
      selectedParty = party;
      partySearchC.clear();
      selectedBillNumbers.clear();
      runningTotal = 0.0;
      amountC.clear();
      pendingBills = webPh.getPendingBills(party.id, widget.type.toUpperCase() == "RECEIPT");
    });
  }

  void _toggleBill(String bNo, double bAmt, bool isChecked) {
    setState(() {
      if (isChecked) {
        if (!selectedBillNumbers.contains(bNo)) {
          selectedBillNumbers.add(bNo);
          runningTotal += bAmt;
        }
      } else {
        selectedBillNumbers.remove(bNo);
        runningTotal -= bAmt;
      }
      if (runningTotal < 0) runningTotal = 0.0;
      amountC.text = runningTotal > 0 ? runningTotal.toStringAsFixed(2) : "";
    });
  }

  void _selectAllBills() {
    setState(() {
      selectedBillNumbers = pendingBills.map((b) => b['billNo'].toString()).toList();
      runningTotal = pendingBills.fold(0.0, (s, b) => s + (b['amount'] as double));
      amountC.text = runningTotal > 0 ? runningTotal.toStringAsFixed(2) : "";
    });
  }

  void _clearBillSelection() {
    setState(() {
      selectedBillNumbers.clear();
      runningTotal = 0.0;
      amountC.clear();
    });
  }

  double _getTodayCashReceivedForParty(PharoahWebManager webPh, String pId) {
    final now = DateTime.now();
    return webPh.vouchers
        .where((v) =>
            v.partyId == pId &&
            v.paymentMode.toLowerCase() == "cash" &&
            v.type.toUpperCase() == "RECEIPT" &&
            v.status == "Active" &&
            v.date.year == now.year &&
            v.date.month == now.month &&
            v.date.day == now.day)
        .fold(0.0, (s, v) => s + v.amount);
  }

  void _saveVoucher(PharoahWebManager webPh, {bool andPrint = false}) async {
    double amt = double.tryParse(amountC.text) ?? 0.0;
    String typeUp = widget.type.toUpperCase();

    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid voucher amount!"), backgroundColor: Colors.orange),
      );
      return;
    }

    if (typeUp == "CONTRA") {
      if (selectedInternalAccount == null || selectedContraTargetAccount == null || selectedInternalAccount!.id == selectedContraTargetAccount!.id) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Select different Source and Destination accounts for Contra!"), backgroundColor: Colors.orange),
        );
        return;
      }
    } else {
      if (selectedParty == null || selectedInternalAccount == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Select Party and Deposited/Paid From Account!"), backgroundColor: Colors.orange),
        );
        return;
      }
    }

    if (payMode == "Cash" && selectedParty != null && webPh.isCashLimitExceeded(selectedParty!.id, amt)) {
      bool? proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
              SizedBox(width: 10),
              Text("Section 269ST Alert", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            "Total cash transactions with this party exceed ₹2,00,000 today. Proceeding may attract Income Tax scrutiny. Continue?",
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("FORCE PROCEED"),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => isSaving = true);

    String pId = typeUp == "CONTRA" ? selectedContraTargetAccount!.id : selectedParty!.id;
    String pName = typeUp == "CONTRA" ? selectedContraTargetAccount!.name : selectedParty!.name;
    String depIn = selectedInternalAccount!.name;

    final v = Voucher(
      id: isUpdateMode ? widget.existingVoucher!.id : "VCT-WEB-${DateTime.now().millisecondsSinceEpoch}",
      type: typeUp,
      voucherNo: voucherNo,
      date: selectedEntryDate,
      partyId: pId,
      partyName: pName,
      amount: amt,
      paymentMode: payMode,
      depositedIn: depIn,
      chequeNo: chequeNoC.text.trim(),
      chequeDate: payMode == "Bank" ? selectedChequeDate : null,
      narration: narrationC.text.trim(),
      status: "Active",
      linkedBillNumbers: selectedBillNumbers,
    );

    if (isUpdateMode) {
      webPh.vouchers.removeWhere((old) => old.id == v.id);
    }
    webPh.vouchers.add(v);

    await webPh.pushUpdatedDataToCloud();
    setState(() => isSaving = false);

    if (andPrint) {
      final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);
      Party targetParty = selectedParty ?? Party(id: pId, name: pName);
      await WebPdfRouterService.printVoucher(voucher: v, party: targetParty, shop: shopProfile, webPh: webPh);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ $typeUp Voucher $voucherNo Saved & Cloud Synced!"), backgroundColor: Colors.green),
      );
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    Color themeColor = const Color(0xFF10B981);
    String typeUp = widget.type.toUpperCase();
    if (typeUp == "PAYMENT") themeColor = const Color(0xFFDC2626);
    if (typeUp == "CONTRA") themeColor = const Color(0xFFF59E0B);
    if (typeUp == "EXPENSE") themeColor = const Color(0xFFB45309);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK TO ACCOUNTS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              Icon(typeUp == "RECEIPT" ? Icons.add_chart_rounded : (typeUp == "PAYMENT" ? Icons.analytics_rounded : Icons.sync_alt_rounded), color: themeColor, size: 24),
              const SizedBox(width: 10),
              Text(
                "${widget.isReadOnly ? 'VIEW' : (isUpdateMode ? 'MODIFY' : 'NEW')} $typeUp VOUCHER",
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 25),

          // 1000-IQ Responsive Split Layout
          LayoutBuilder(
            builder: (context, constraints) {
              bool isWide = constraints.maxWidth > 950;

              Widget leftForm = _buildLeftVoucherForm(webPh, themeColor, typeUp);
              Widget rightSidecar = _buildRightInteractiveSidecar(webPh, themeColor, typeUp);

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: leftForm),
                    const SizedBox(width: 18),
                    Expanded(flex: 5, child: rightSidecar),
                  ],
                );
              } else {
                return Column(
                  children: [
                    leftForm,
                    const SizedBox(height: 18),
                    rightSidecar,
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 📝 LEFT FORM (VOUCHER TRANSACTION CONTROLS)
  // ===========================================================================
  Widget _buildLeftVoucherForm(PharoahWebManager webPh, Color themeColor, String typeUp) {
    final internalAccounts = webPh.parties.where((p) => p.group == "Bank Accounts" || p.group == "Cash in Hand").toList();
    final expenseHeads = webPh.parties.where((p) => p.group == "Expenses").toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Voucher Number & Entry Date
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("VOUCHER NUMBER", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                      Text(voucherNo, style: TextStyle(color: themeColor, fontSize: 14, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: widget.isReadOnly ? null : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedEntryDate,
                      firstDate: WebAppDateLogic.getFYStart(webPh.financialYear),
                      lastDate: WebAppDateLogic.getFYEnd(webPh.financialYear),
                    );
                    if (picked != null) setState(() => selectedEntryDate = picked);
                  },
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("ENTRY DATE", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                            Text(DateFormat('dd/MM/yyyy').format(selectedEntryDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Party / Account Selection
          if (typeUp == "CONTRA") ...[
            const Text("TRANSFER FROM (SOURCE ACCOUNT) *", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _buildInternalAccountDropdown(internalAccounts, selectedInternalAccount, (v) => setState(() => selectedInternalAccount = v)),
            const SizedBox(height: 12),
            const Text("TRANSFER TO (DESTINATION ACCOUNT) *", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _buildInternalAccountDropdown(internalAccounts, selectedContraTargetAccount, (v) => setState(() => selectedContraTargetAccount = v)),
          ] else if (typeUp == "EXPENSE") ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("EXPENSE CATEGORY / LEDGER *", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                if (!widget.isReadOnly)
                  TextButton.icon(
                    onPressed: () => _openQuickAddParty(webPh, defaultGroup: "Expenses"),
                    icon: const Icon(Icons.add_rounded, size: 14),
                    label: const Text("NEW EXPENSE HEAD", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _buildPartySelectorSection(webPh, expenseHeads, themeColor),
            const SizedBox(height: 14),
            const Text("PAID FROM ACCOUNT (CASH/BANK) *", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _buildInternalAccountDropdown(internalAccounts, selectedInternalAccount, (v) => setState(() => selectedInternalAccount = v)),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(typeUp == "RECEIPT" ? "CUSTOMER / RECEIVED FROM *" : "SUPPLIER / PAID TO *", style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                if (!widget.isReadOnly)
                  TextButton.icon(
                    onPressed: () => _openQuickAddParty(webPh, defaultGroup: typeUp == "RECEIPT" ? "Sundry Debtors" : "Sundry Creditors"),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
                    label: const Text("+ CREATE PARTY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _buildPartySelectorSection(webPh, webPh.parties, themeColor),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("PAYMENT MODE", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'Cash', label: Text('Cash', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                          ButtonSegment(value: 'Bank', label: Text('Bank/Chq', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                        ],
                        selected: {payMode},
                        onSelectionChanged: widget.isReadOnly ? null : (v) => setState(() => payMode = v.first),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(typeUp == "RECEIPT" ? "DEPOSITED IN *" : "PAID FROM *", style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      _buildInternalAccountDropdown(
                        internalAccounts.where((a) => payMode == "Cash" ? a.group == "Cash in Hand" : a.group == "Bank Accounts").toList(),
                        selectedInternalAccount,
                        (v) => setState(() => selectedInternalAccount = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),

          // Cheque Details (if mode is Bank)
          if (payMode == "Bank" || typeUp == "CONTRA") ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: chequeNoC,
                    readOnly: widget.isReadOnly,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      labelText: "CHEQUE / REF TRANSACTION NO",
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: widget.isReadOnly ? null : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedChequeDate,
                        firstDate: WebAppDateLogic.getFYStart(webPh.financialYear),
                        lastDate: WebAppDateLogic.getFYEnd(webPh.financialYear),
                      );
                      if (picked != null) setState(() => selectedChequeDate = picked);
                    },
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("CHQ DATE", style: TextStyle(color: Colors.white54, fontSize: 7.5, fontWeight: FontWeight.bold)),
                              Text(DateFormat('dd/MM/yy').format(selectedChequeDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                            ],
                          ),
                          const Icon(Icons.event_rounded, color: Color(0xFF38BDF8), size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // Amount & Narration
          TextField(
            controller: amountC,
            readOnly: widget.isReadOnly,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: themeColor, fontSize: 24, fontWeight: FontWeight.w900),
            decoration: InputDecoration(
              labelText: "VOUCHER AMOUNT (₹) *",
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.bold),
              prefixIcon: Icon(Icons.currency_rupee_rounded, color: themeColor, size: 20),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: narrationC,
            readOnly: widget.isReadOnly,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              labelText: "NARRATION / REMARKS",
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
              prefixIcon: const Icon(Icons.notes_rounded, color: Colors.white54, size: 18),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons
          if (!widget.isReadOnly)
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      onPressed: isSaving ? null : () => _saveVoucher(webPh, andPrint: false),
                      icon: isSaving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check_circle_rounded, size: 16),
                      label: Text(isSaving ? "SAVING..." : "SAVE & SYNC VOUCHER", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 0.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: themeColor, width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isSaving ? null : () => _saveVoucher(webPh, andPrint: true),
                      icon: const Icon(Icons.print_rounded, size: 16),
                      label: const Text("PRINT A6", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildInternalAccountDropdown(List<Party> list, Party? current, ValueChanged<Party?> onChanged) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Party>(
          value: list.contains(current) ? current : (list.isNotEmpty ? list.first : null),
          isExpanded: true,
          dropdownColor: const Color(0xFF1E293B),
          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
          items: list.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
          onChanged: widget.isReadOnly ? null : onChanged,
        ),
      ),
    );
  }

  Widget _buildPartySelectorSection(PharoahWebManager webPh, List<Party> partyPool, Color themeColor) {
    if (selectedParty != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: themeColor.withValues(alpha: 0.8), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: themeColor.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(Icons.person_rounded, color: themeColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(selectedParty!.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                  Text("${selectedParty!.city} | GST: ${selectedParty!.gst}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
            ),
            if (!widget.isReadOnly)
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                onPressed: () => setState(() {
                  selectedParty = null;
                  selectedBillNumbers.clear();
                  runningTotal = 0.0;
                  amountC.clear();
                }),
              ),
          ],
        ),
      );
    }

    final query = partySearchC.text.trim().toLowerCase();
    final matching = query.isEmpty
        ? <Party>[]
        : partyPool.where((p) => p.name.toLowerCase().contains(query) || p.city.toLowerCase().contains(query)).take(4).toList();

    return Column(
      children: [
        TextField(
          controller: partySearchC,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: "Type name or city to search party...",
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 16),
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (matching.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: matching.length,
              itemBuilder: (ctx, i) {
                final p = matching[i];
                return ListTile(
                  dense: true,
                  title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                  subtitle: Text("${p.city} • ${p.group}", style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
                  onTap: () => _onPartyChosen(p, webPh),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  void _openQuickAddParty(PharoahWebManager webPh, {String defaultGroup = "Sundry Debtors"}) {
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        preFillData: {'group': defaultGroup},
        onPartyCreated: (newParty) => _onPartyChosen(newParty, webPh),
      ),
    );
  }

  // ===========================================================================
  // 📊 RIGHT SIDECAR (INTERACTIVE SETTLEMENT & LIVE FINANCIAL INTELLIGENCE)
  // ===========================================================================
  Widget _buildRightInteractiveSidecar(PharoahWebManager webPh, Color themeColor, String typeUp) {
    if (typeUp == "CONTRA") {
      return _buildContraTransferPreview(webPh);
    }

    if (typeUp == "EXPENSE") {
      return _buildExpenseSidecar(webPh);
    }

    // Default for Receipt & Payment:
    if (selectedParty != null) {
      double bal = webPh.calculatePartyBalance(selectedParty!);
      bool isDr = bal >= 0;
      double todayCash = _getTodayCashReceivedForParty(webPh, selectedParty!.id);
      double cashProgress = (todayCash / 200000).clamp(0.0, 1.0);

      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Party Financial Status
            Row(
              children: [
                const Icon(Icons.account_balance_rounded, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 8),
                const Text("LIVE PARTY FINANCIAL RADAR", style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDr ? const Color(0x3310B981) : const Color(0x33DC2626),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isDr ? "DEBTOR (Dr)" : "CREDITOR (Cr)",
                    style: TextStyle(color: isDr ? Colors.greenAccent : const Color(0xFFF87171), fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("CURRENT LEDGER BALANCE", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text("₹${bal.abs().toStringAsFixed(2)}", style: TextStyle(color: isDr ? Colors.greenAccent : const Color(0xFFF87171), fontSize: 18, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("STATUS", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                      Text(bal == 0 ? "NIL" : (isDr ? "RECEIVABLE" : "PAYABLE"), style: TextStyle(color: isDr ? Colors.greenAccent : const Color(0xFFF87171), fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Section 269ST Cash Tracker Meter
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("SECTION 269ST TODAY CASH METER", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                      Text("₹${todayCash.toStringAsFixed(0)} / ₹2,00,000", style: TextStyle(color: todayCash >= 150000 ? Colors.redAccent : Colors.cyanAccent, fontSize: 9.5, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: cashProgress,
                      backgroundColor: Colors.white12,
                      color: cashProgress > 0.85 ? Colors.redAccent : (cashProgress > 0.5 ? Colors.orangeAccent : Colors.greenAccent),
                      minHeight: 5,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 22),

            // Live In-Screen Settlement Table
            Row(
              children: [
                const Icon(Icons.link_rounded, color: Color(0xFF38BDF8), size: 16),
                const SizedBox(width: 6),
                Text(
                  "SETTLE PENDING BILLS (${pendingBills.length})",
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const Spacer(),
                if (pendingBills.isNotEmpty) ...[
                  InkWell(
                    onTap: _selectAllBills,
                    child: const Text("SELECT ALL", style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _clearBillSelection,
                    child: const Text("CLEAR", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            if (pendingBills.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Text(
                  "No pending unpaid invoices for ${selectedParty!.name}.\nEnter on-account / advance amount on the left.",
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 250),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: pendingBills.length,
                  itemBuilder: (ctx, i) {
                    final b = pendingBills[i];
                    String bNo = b['billNo'].toString();
                    double bAmt = (b['amount'] as num).toDouble();
                    bool isChecked = selectedBillNumbers.contains(bNo);

                    return Container(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5))),
                      child: CheckboxListTile(
                        dense: true,
                        activeColor: const Color(0xFF2563EB),
                        value: isChecked,
                        title: Row(
                          children: [
                            Text("Bill #$bNo", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3)),
                              child: Text("${b['dueDays']}d due", style: const TextStyle(color: Colors.orangeAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                            ),
                            const Spacer(),
                            Text("₹${bAmt.toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 12)),
                          ],
                        ),
                        subtitle: Text("Date: ${DateFormat('dd/MM/yyyy').format(b['date'] as DateTime)}", style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
                        onChanged: (v) => _toggleBill(bNo, bAmt, v == true),
                      ),
                    );
                  },
                ),
              ),

            if (selectedBillNumbers.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0x3310B981), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${selectedBillNumbers.length} Bills Selected", style: const TextStyle(color: Color(0xFF34D399), fontSize: 10.5, fontWeight: FontWeight.bold)),
                    Text("Total: ₹${runningTotal.toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 12.5, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Fallback sidecar when no party is selected
    return _buildAccountLiveRadarSidecar(webPh);
  }

  Widget _buildAccountLiveRadarSidecar(PharoahWebManager webPh) {
    final double totalCash = webPh.parties.where((p) => p.group == "Cash in Hand").fold(0.0, (s, p) => s + p.opBal);
    final bankAccounts = webPh.parties.where((p) => p.group == "Bank Accounts").toList();
    final double totalBanks = bankAccounts.fold(0.0, (s, b) => s + b.opBal);

    final recentVouchers = webPh.vouchers.reversed.take(6).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.radar_rounded, color: Color(0xFF38BDF8), size: 18),
              SizedBox(width: 8),
              Text("INTERNAL ACCOUNTS LIVE BALANCES", style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("CASH IN HAND DRAWER", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text("₹${totalCash.toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.w900)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text("TOTAL BANK DEPOSITS", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text("₹${totalBanks.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 16, fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...bankAccounts.map((b) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("• ${b.name}", style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
                Text("₹${b.opBal.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          )),
          const Divider(color: Colors.white10, height: 22),

          const Row(
            children: [
              Icon(Icons.history_rounded, color: Color(0xFFF59E0B), size: 16),
              SizedBox(width: 6),
              Text("RECENT VOUCHERS AUDIT STREAM", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 8),

          if (recentVouchers.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("No vouchers posted yet.", style: TextStyle(color: Colors.white38, fontSize: 11))))
          else
            ...recentVouchers.map((v) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  Text(v.voucherNo, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(v.partyName, style: const TextStyle(color: Colors.white, fontSize: 11), overflow: TextOverflow.ellipsis)),
                  Text("₹${v.amount.toStringAsFixed(2)}", style: TextStyle(color: v.type == "RECEIPT" ? Colors.greenAccent : const Color(0xFFF87171), fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildContraTransferPreview(PharoahWebManager webPh) {
    double amt = double.tryParse(amountC.text) ?? 0.0;
    double srcBal = selectedInternalAccount?.opBal ?? 0.0;
    double tgtBal = selectedContraTargetAccount?.opBal ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.sync_alt_rounded, color: Color(0xFFF59E0B), size: 20),
              SizedBox(width: 8),
              Text("LIVE CONTRA TRANSFER VISUALIZER", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 14),

          // Source Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0x33DC2626), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("TRANSFER OUT (DEBITED FROM)", style: TextStyle(color: Colors.redAccent, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(selectedInternalAccount?.name ?? "Select Source", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                Text("₹${(srcBal - amt).toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Transfer Arrow
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.black),
                  const SizedBox(width: 4),
                  Text("TRANSFERRING ₹${amt.toStringAsFixed(2)}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Destination Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0x3310B981), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("TRANSFER IN (CREDITED TO)", style: TextStyle(color: Colors.greenAccent, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(selectedContraTargetAccount?.name ?? "Select Destination", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                Text("₹${(tgtBal + amt).toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseSidecar(PharoahWebManager webPh) {
    final now = DateTime.now();
    double todayExpenses = webPh.vouchers
        .where((v) => v.type.toUpperCase() == "EXPENSE" && v.status == "Active" && v.date.year == now.year && v.date.month == now.month && v.date.day == now.day)
        .fold(0.0, (s, v) => s + v.amount);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.money_off_rounded, color: Color(0xFFF59E0B), size: 20),
              SizedBox(width: 8),
              Text("STORE OPERATING EXPENSES RADAR", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("TOTAL EXPENSES POSTED TODAY", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text("₹${todayExpenses.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 18, fontWeight: FontWeight.w900)),
                  ],
                ),
                const Icon(Icons.receipt_long_rounded, color: Colors.white38, size: 28),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 25),

          const Text("RECENT STORE EXPENSES STREAM", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          ...webPh.vouchers.where((v) => v.type.toUpperCase() == "EXPENSE").toList().reversed.take(5).map((e) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
            child: Row(
              children: [
                Text(e.voucherNo, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 9.5, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(child: Text(e.partyName, style: const TextStyle(color: Colors.white, fontSize: 11), overflow: TextOverflow.ellipsis)),
                Text("₹${e.amount.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
