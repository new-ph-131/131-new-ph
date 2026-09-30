// FILE: lib/web_live_sync/web_voucher_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'web_pharoah_numbering_engine.dart';

class WebVoucherView extends StatefulWidget {
  final VoidCallback onBack;
  final int initialTabIndex;

  const WebVoucherView({
    super.key,
    required this.onBack,
    this.initialTabIndex = 0,
  });

  @override
  State<WebVoucherView> createState() => _WebVoucherViewState();
}

class _WebVoucherViewState extends State<WebVoucherView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Receipt Form State
  final rctNumberC = TextEditingController();
  final rctAmountC = TextEditingController();
  final rctNarrationC = TextEditingController();
  final rctChequeNoC = TextEditingController();
  Party? rctSelectedCustomer;
  Party? rctInternalAccount;
  String rctPayMode = "Cash";

  // Payment Form State
  final payNumberC = TextEditingController();
  final payAmountC = TextEditingController();
  final payNarrationC = TextEditingController();
  final payChequeNoC = TextEditingController();
  Party? paySelectedSupplier;
  Party? payInternalAccount;
  String payPayMode = "Cash";

  String registerSearch = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex);
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);

    rctNumberC.text = WebPharoahNumberingEngine.getNextNumber(
      prefix: "RCT-",
      startFrom: 101,
      currentList: webPh.vouchers,
    );

    payNumberC.text = WebPharoahNumberingEngine.getNextNumber(
      prefix: "PAY-",
      startFrom: 101,
      currentList: webPh.vouchers,
    );

    final internalAccs = webPh.parties.where((p) => p.group == "Cash in Hand" || p.group == "Bank Accounts").toList();
    if (internalAccs.isNotEmpty) {
      rctInternalAccount = internalAccs.first;
      payInternalAccount = internalAccs.first;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    rctNumberC.dispose();
    rctAmountC.dispose();
    rctNarrationC.dispose();
    rctChequeNoC.dispose();
    payNumberC.dispose();
    payAmountC.dispose();
    payNarrationC.dispose();
    payChequeNoC.dispose();
    super.dispose();
  }

  // ===========================================================================
  // 1. SAVE RECEIPT VOUCHER
  // ===========================================================================
  void _saveReceipt(PharoahWebManager webPh) {
    double amt = double.tryParse(rctAmountC.text) ?? 0.0;
    if (rctSelectedCustomer == null || amt <= 0 || rctInternalAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select Customer, Internal Account & valid Amount!"), backgroundColor: Colors.orange),
      );
      return;
    }

    final newVoucher = Voucher(
      id: "VCT-WEB-${DateTime.now().millisecondsSinceEpoch}",
      type: "Receipt",
      voucherNo: rctNumberC.text.trim(),
      date: DateTime.now(),
      partyId: rctSelectedCustomer!.id,
      partyName: rctSelectedCustomer!.name,
      amount: amt,
      paymentMode: rctPayMode,
      depositedIn: rctInternalAccount!.name,
      chequeNo: rctChequeNoC.text.trim(),
      narration: rctNarrationC.text.trim(),
      status: "Active",
    );

    webPh.vouchers.add(newVoucher);
    // Adjust party balance
    rctSelectedCustomer!.opBal -= amt;
    webPh.updateParty(rctSelectedCustomer!);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✅ Receipt Voucher ${rctNumberC.text} Saved!"), backgroundColor: Colors.green),
    );

    widget.onBack();
  }

  // ===========================================================================
  // 2. SAVE PAYMENT VOUCHER
  // ===========================================================================
  void _savePayment(PharoahWebManager webPh) {
    double amt = double.tryParse(payAmountC.text) ?? 0.0;
    if (paySelectedSupplier == null || amt <= 0 || payInternalAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select Supplier, Internal Account & valid Amount!"), backgroundColor: Colors.orange),
      );
      return;
    }

    final newVoucher = Voucher(
      id: "PAY-WEB-${DateTime.now().millisecondsSinceEpoch}",
      type: "Payment",
      voucherNo: payNumberC.text.trim(),
      date: DateTime.now(),
      partyId: paySelectedSupplier!.id,
      partyName: paySelectedSupplier!.name,
      amount: amt,
      paymentMode: payPayMode,
      depositedIn: payInternalAccount!.name,
      chequeNo: payChequeNoC.text.trim(),
      narration: payNarrationC.text.trim(),
      status: "Active",
    );

    webPh.vouchers.add(newVoucher);
    // Adjust party balance
    paySelectedSupplier!.opBal += amt;
    webPh.updateParty(paySelectedSupplier!);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✅ Payment Voucher ${payNumberC.text} Saved!"), backgroundColor: Colors.green),
    );

    widget.onBack();
  }

  // ===========================================================================
  // 3. MAIN UI
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
                label: const Text("BACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF10B981), size: 22),
              const SizedBox(width: 10),
              const Text(
                "CASH & BANK VOUCHERS HUB",
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 15),

          // Tabs Switcher
          Container(
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF10B981),
              labelColor: const Color(0xFF34D399),
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(text: "RECEIPT (CASH IN)", icon: Icon(Icons.add_chart_rounded, size: 16)),
                Tab(text: "PAYMENT (CASH OUT)", icon: Icon(Icons.analytics_rounded, size: 16)),
                Tab(text: "DAYBOOK REGISTER", icon: Icon(Icons.event_note_rounded, size: 16)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildReceiptTab(webPh),
                _buildPaymentTab(webPh),
                _buildDaybookTab(webPh),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptTab(PharoahWebManager webPh) {
    final internalAccounts = webPh.parties.where((p) => p.group == "Cash in Hand" || p.group == "Bank Accounts").toList();

    return Center(
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x3310B981))),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("RECORD PAYMENT INFLOW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(rctNumberC.text, style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w900, fontSize: 13)),
                ],
              ),
              const Divider(color: Colors.white10, height: 20),
              Autocomplete<Party>(
                displayStringForOption: (p) => "${p.name} (Balance: ₹${p.opBal.toStringAsFixed(0)})",
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return const Iterable.empty();
                  return webPh.parties.where((p) => p.group == "Sundry Debtors" && p.name.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                },
                onSelected: (p) => setState(() => rctSelectedCustomer = p),
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: "RECEIVED FROM (CUSTOMER) *",
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 9),
                      prefixIcon: Icon(Icons.person, color: Color(0xFF38BDF8), size: 18),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _input("AMOUNT RECEIVED ₹ *", rctAmountC, isNum: true, isHighlight: true)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<Party>(
                      value: rctInternalAccount,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        labelText: "DEPOSITED INTO ACCOUNT *",
                        labelStyle: TextStyle(color: Colors.white54, fontSize: 9),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(),
                      ),
                      items: internalAccounts.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
                      onChanged: (v) => setState(() => rctInternalAccount = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Cash', label: Text('Cash', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                        ButtonSegment(value: 'Bank', label: Text('Bank Transfer / UPI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      ],
                      selected: {rctPayMode},
                      onSelectionChanged: (v) => setState(() => rctPayMode = v.first),
                    ),
                  ),
                  if (rctPayMode == "Bank") ...[
                    const SizedBox(width: 12),
                    Expanded(child: _input("CHEQUE / REF NO", rctChequeNoC, isCaps: true)),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              _input("REMARKS / NARRATION", rctNarrationC),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _saveReceipt(webPh),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text("FINALIZE & SAVE RECEIPT", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentTab(PharoahWebManager webPh) {
    final internalAccounts = webPh.parties.where((p) => p.group == "Cash in Hand" || p.group == "Bank Accounts").toList();

    return Center(
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x33DC2626))),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("RECORD PAYMENT OUTFLOW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(payNumberC.text, style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.w900, fontSize: 13)),
                ],
              ),
              const Divider(color: Colors.white10, height: 20),
              Autocomplete<Party>(
                displayStringForOption: (p) => "${p.name} (Balance: ₹${p.opBal.toStringAsFixed(0)})",
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return const Iterable.empty();
                  return webPh.parties.where((p) =>
                      (p.group == "Sundry Creditors" || p.group == "Expenses") &&
                      p.name.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                },
                onSelected: (p) => setState(() => paySelectedSupplier = p),
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: "PAID TO (SUPPLIER / EXPENSE) *",
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 9),
                      prefixIcon: Icon(Icons.business, color: Color(0xFFF59E0B), size: 18),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _input("AMOUNT PAID ₹ *", payAmountC, isNum: true, isHighlight: true)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<Party>(
                      value: payInternalAccount,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        labelText: "PAID FROM ACCOUNT *",
                        labelStyle: TextStyle(color: Colors.white54, fontSize: 9),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(),
                      ),
                      items: internalAccounts.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
                      onChanged: (v) => setState(() => payInternalAccount = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Cash', label: Text('Cash', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                        ButtonSegment(value: 'Bank', label: Text('Bank Transfer / Cheque', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      ],
                      selected: {payPayMode},
                      onSelectionChanged: (v) => setState(() => payPayMode = v.first),
                    ),
                  ),
                  if (payPayMode == "Bank") ...[
                    const SizedBox(width: 12),
                    Expanded(child: _input("CHEQUE / REF NO", payChequeNoC, isCaps: true)),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              _input("REMARKS / NARRATION", payNarrationC),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _savePayment(webPh),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text("FINALIZE & SAVE PAYMENT", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDaybookTab(PharoahWebManager webPh) {
    List<Voucher> list = List.from(webPh.vouchers);
    list.sort((a, b) => b.date.compareTo(a.date));

    final filtered = list.where((v) =>
        v.partyName.toLowerCase().contains(registerSearch.toLowerCase()) ||
        v.voucherNo.toLowerCase().contains(registerSearch.toLowerCase()) ||
        v.depositedIn.toLowerCase().contains(registerSearch.toLowerCase())).toList();

    double totalIn = list.where((v) => v.type == "Receipt" && v.status == "Active").fold(0.0, (s, v) => s + v.amount);
    double totalOut = list.where((v) => v.type == "Payment" && v.status == "Active").fold(0.0, (s, v) => s + v.amount);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 38,
                decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: "Search in Daybook / Vouchers Register...",
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                    prefixIcon: Icon(Icons.search, color: Color(0xFF10B981), size: 16),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) => setState(() => registerSearch = v),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Text("TOTAL IN: ₹${totalIn.toStringAsFixed(0)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w900)),
            const SizedBox(width: 15),
            Text("TOTAL OUT: ₹${totalOut.toStringAsFixed(0)}", style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text("No voucher records found.", style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (c, i) {
                    final v = filtered[i];
                    bool isReceipt = v.type == "Receipt";
                    Color color = isReceipt ? const Color(0xFF10B981) : const Color(0xFFDC2626);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isReceipt ? const Color(0x3310B981) : const Color(0x33DC2626),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(isReceipt ? "REC" : "PAY",
                              style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(v.partyName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        subtitle: Text("ID: ${v.voucherNo} • ${WebAppDateLogic.format(v.date)} • Mode: ${v.paymentMode} (${v.depositedIn})",
                            style: const TextStyle(color: Colors.white38, fontSize: 10)),
                        trailing: Text(
                          "${isReceipt ? '+' : '-'} ₹${v.amount.toStringAsFixed(2)}",
                          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _input(String label, TextEditingController ctrl, {bool isNum = false, bool isCaps = false, bool isHighlight = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold),
        filled: true,
        fillColor: isHighlight ? const Color(0x3310B981) : Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}
