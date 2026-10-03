// FILE: lib/web_live_sync/sub_views/web_accounts/web_voucher_entry_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  String payMode = "Cash";
  String voucherNo = "Loading...";
  bool isUpdateMode = false;

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
      amountC.text = v.amount.toString();
      narrationC.text = v.narration.replaceAll("[CANCELLED] ", "");
      payMode = v.paymentMode;
      selectedEntryDate = v.date;
      selectedChequeDate = v.chequeDate ?? v.date;
      chequeNoC.text = v.chequeNo;
      selectedBillNumbers = List.from(v.linkedBillNumbers);
      runningTotal = v.amount;

      try {
        selectedParty = webPh.parties.firstWhere((p) => p.id == v.partyId || p.name == v.partyName);
        selectedInternalAccount = webPh.parties.firstWhere((p) => p.name == v.depositedIn);
        pendingBills = webPh.getPendingBills(selectedParty!.id, typeKey == "RECEIPT");
      } catch (_) {}
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
      selectedInternalAccount = internalAccs.first;
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

  void _openReferenceWizard(PharoahWebManager webPh) {
    if (selectedParty == null || widget.isReadOnly) return;
    pendingBills = webPh.getPendingBills(selectedParty!.id, widget.type.toUpperCase() == "RECEIPT");

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setWizardState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white12)),
            title: Row(
              children: [
                const Icon(Icons.link_rounded, color: Color(0xFF38BDF8), size: 20),
                const SizedBox(width: 10),
                Text("SETTLE BILLS • ${selectedParty!.name}", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 380,
              child: pendingBills.isEmpty
                  ? const Center(child: Text("No pending unpaid bills for this party.", style: TextStyle(color: Colors.white38, fontSize: 12)))
                  : ListView.builder(
                      itemCount: pendingBills.length,
                      itemBuilder: (ctx, i) {
                        final b = pendingBills[i];
                        bool isSel = selectedBillNumbers.contains(b['billNo']);
                        return CheckboxListTile(
                          activeColor: const Color(0xFF2563EB),
                          value: isSel,
                          title: Text("Bill #${b['billNo']} (₹${(b['amount'] as double).toStringAsFixed(2)})", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                          subtitle: Text("Date: ${WebAppDateLogic.format(b['date'])} • Due: ${b['dueDays']} Days ago", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                          onChanged: (v) {
                            setWizardState(() {
                              if (v == true) {
                                selectedBillNumbers.add(b['billNo']);
                                runningTotal += (b['amount'] as double);
                              } else {
                                selectedBillNumbers.remove(b['billNo']);
                                runningTotal -= (b['amount'] as double);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                onPressed: () {
                  setState(() {
                    amountC.text = runningTotal.toStringAsFixed(2);
                  });
                  Navigator.pop(context);
                },
                child: const Text("APPLY SELECTION", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _saveVoucher(PharoahWebManager webPh, {bool andPrint = false}) async {
    double amt = double.tryParse(amountC.text) ?? 0.0;
    if (selectedParty == null || amt <= 0 || selectedInternalAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select Party, Internal Account & valid Amount!"), backgroundColor: Colors.orange),
      );
      return;
    }

    if (payMode == "Cash" && webPh.isCashLimitExceeded(selectedParty!.id, amt)) {
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text("⚠️ Cash Limit Warning", style: TextStyle(color: Colors.orangeAccent)),
          content: const Text("Total cash transaction with this party today exceeds ₹2,00,000 (Income Tax Section 265ST limit). Do you still want to proceed?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent), onPressed: () => Navigator.pop(ctx, true), child: const Text("PROCEED")),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final v = Voucher(
      id: isUpdateMode ? widget.existingVoucher!.id : "VCT-WEB-${DateTime.now().millisecondsSinceEpoch}",
      type: widget.type.toUpperCase(),
      voucherNo: voucherNo,
      date: selectedEntryDate,
      partyId: selectedParty!.id,
      partyName: selectedParty!.name,
      amount: amt,
      paymentMode: payMode,
      depositedIn: selectedInternalAccount!.name,
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

    if (andPrint) {
      final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);
      await WebPdfRouterService.printVoucher(voucher: v, party: selectedParty!, shop: shopProfile, webPh: webPh);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ ${widget.type.toUpperCase()} Voucher $voucherNo Saved Successfully!"), backgroundColor: Colors.green),
      );
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    final internalAccounts = webPh.parties.where((p) => p.group == "Bank Accounts" || p.group == "Cash in Hand").toList();
    
    Color themeColor = const Color(0xFF2563EB);
    String typeUp = widget.type.toUpperCase();
    if (typeUp == "RECEIPT") themeColor = const Color(0xFF10B981);
    if (typeUp == "PAYMENT") themeColor = const Color(0xFFDC2626);
    if (typeUp == "CONTRA") themeColor = const Color(0xFFF59E0B);
    if (typeUp == "EXPENSE") themeColor = const Color(0xFF78350F);

    final matchingParties = partySearchC.text.trim().isEmpty
        ? <Party>[]
        : webPh.parties.where((p) => p.name.toLowerCase().contains(partySearchC.text.trim().toLowerCase())).take(5).toList();

    return Container(
      constraints: const BoxConstraints(maxWidth: 780),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
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
              Icon(typeUp == "RECEIPT" ? Icons.add_chart_rounded : Icons.analytics_rounded, color: themeColor, size: 24),
              const SizedBox(width: 10),
              Text(
                "${widget.isReadOnly ? 'VIEW' : (isUpdateMode ? 'MODIFY' : 'NEW')} $typeUp VOUCHER",
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 25),

          // Header Box: Voucher No & Date
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("VOUCHER NUMBER", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(voucherNo, style: TextStyle(color: themeColor, fontSize: 16, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
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
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("ENTRY DATE", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                              Text(WebAppDateLogic.format(selectedEntryDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
          ),
          const SizedBox(height: 20),

          // Party Selection
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("ACCOUNT / PARTY DETAILS *", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
              if (!widget.isReadOnly)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (c) => QuickAddPartyModal(
                        webPh: webPh,
                        onPartyCreated: (newParty) {
                          setState(() {
                            selectedParty = newParty;
                            pendingBills = webPh.getPendingBills(newParty.id, typeUp == "RECEIPT");
                          });
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
                  label: const Text("+ PARTY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (selectedParty != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: themeColor, width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: themeColor.withValues(alpha: 0.2), shape: BoxShape.circle),
                    child: Icon(Icons.person_rounded, color: themeColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selectedParty!.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                        const SizedBox(height: 3),
                        Text("${selectedParty!.city} | GST: ${selectedParty!.gst} | Group: ${selectedParty!.group}", style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                      ],
                    ),
                  ),
                  if (!widget.isReadOnly)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
                      onPressed: () => setState(() { selectedParty = null; selectedBillNumbers.clear(); }),
                    ),
                ],
              ),
            )
          else ...[
            TextField(
              controller: partySearchC,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
              decoration: InputDecoration(
                hintText: "Type customer or supplier name to search...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                suffixIcon: partySearchC.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                        onPressed: () => setState(() => partySearchC.clear()),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (matchingParties.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x3338BDF8)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: matchingParties.length,
                  itemBuilder: (ctx, idx) {
                    final p = matchingParties[idx];
                    return ListTile(
                      dense: true,
                      title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      subtitle: Text("${p.city} • ${p.group}", style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
                      onTap: () {
                        setState(() {
                          selectedParty = p;
                          partySearchC.clear();
                          pendingBills = webPh.getPendingBills(p.id, typeUp == "RECEIPT");
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ],
          const SizedBox(height: 18),

          // Payment Mode & Internal Account
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("PAYMENT MODE", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Cash', label: Text('Cash', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                        ButtonSegment(value: 'Bank', label: Text('Bank / Cheque', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                      ],
                      selected: {payMode},
                      onSelectionChanged: widget.isReadOnly ? null : (v) => setState(() => payMode = v.first),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("DEPOSITED / PAID FROM ACCOUNT *", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Party>(
                          value: selectedInternalAccount,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          items: internalAccounts.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
                          onChanged: widget.isReadOnly ? null : (v) => setState(() => selectedInternalAccount = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (payMode == "Bank") ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: chequeNoC,
                    readOnly: widget.isReadOnly,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                    decoration: InputDecoration(
                      labelText: "CHEQUE / REF TRANSACTION NO",
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 3,
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
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("CHEQUE DATE", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                              Text(WebAppDateLogic.format(selectedChequeDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                          const Icon(Icons.event_rounded, color: Color(0xFF38BDF8), size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Bill Settlement Trigger (If Customer selected)
          if (selectedParty != null && (typeUp == "RECEIPT" || typeUp == "PAYMENT")) ...[
            InkWell(
              onTap: () => _openReferenceWizard(webPh),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2563EB), width: 1.2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_fix_high_rounded, color: Color(0xFF38BDF8), size: 18),
                    const SizedBox(width: 10),
                    Text(
                      selectedBillNumbers.isEmpty ? "🔗 Adjust / Settle Against Pending Invoices" : "🔗 ${selectedBillNumbers.length} Invoices Adjusted",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 14),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Amount & Narration
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: amountC,
                  readOnly: widget.isReadOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: themeColor, fontSize: 22, fontWeight: FontWeight.w900),
                  decoration: InputDecoration(
                    labelText: "VOUCHER AMOUNT ₹ *",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                    prefixIcon: Icon(Icons.currency_rupee, color: themeColor, size: 18),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 4,
                child: TextField(
                  controller: narrationC,
                  readOnly: widget.isReadOnly,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  decoration: InputDecoration(
                    labelText: "NARRATION / REMARKS",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                    prefixIcon: const Icon(Icons.notes_rounded, color: Colors.white54, size: 18),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),

          if (!widget.isReadOnly)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () => _saveVoucher(webPh, andPrint: false),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text("SAVE & SYNC VOUCHER", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5)),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: themeColor, width: 1.5),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _saveVoucher(webPh, andPrint: true),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text("SAVE & PRINT A6", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
