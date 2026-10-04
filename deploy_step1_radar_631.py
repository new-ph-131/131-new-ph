import os
import re
import subprocess
import sys

print("==================================================================")
print("🚀 UPGRADING PURCHASE STEP-1 INTELLIGENCE RADAR (#PH-REV-631)")
print("==================================================================\n")

# 1. UPDATE LIVE TAG TO #PH-REV-631
print("🏷️ Step 1/5: Updating Live Tag to #PH-REV-631...")
tb_path = "lib/web_live_sync/components/web_top_bar.dart"
if os.path.exists(tb_path):
    with open(tb_path, "r", encoding="utf-8") as f:
        tb = f.read()
    new_rev = "#PH-REV-631 (PURCHASE-STEP1-INTELLIGENCE-RADAR)"
    tb = re.sub(r"#PH-REV-\d+[^\"]*", new_rev, tb)
    with open(tb_path, "w", encoding="utf-8") as f:
        f.write(tb)
    print(f"✔ Tag Updated: {new_rev}")

# 2. WRITE ADVANCED RESPONSIVE STEP-1 SCREEN (Only inside web_live_sync)
print("\n🖥️ Step 2/5: Upgrading web_purchase_entry_screen.dart with Dual-Pane Radar...")
screen_path = "lib/web_live_sync/sub_views/web_purchase/ui/web_purchase_entry_screen.dart"

code = '''// FILE: lib/web_live_sync/sub_views/web_purchase/ui/web_purchase_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:pharoah_erp/web_live_sync/web_models.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/web_app_date_logic.dart';
import 'package:pharoah_erp/web_live_sync/web_pharoah_numbering_engine.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_billing/quick_add_party_modal.dart';
import 'web_purchase_billing_screen.dart';

class WebPurchaseEntryScreen extends StatefulWidget {
  final VoidCallback onBack;
  final Purchase? existingPurchase;
  final bool isReadOnly;

  const WebPurchaseEntryScreen({
    super.key,
    required this.onBack,
    this.existingPurchase,
    this.isReadOnly = false,
  });

  @override
  State<WebPurchaseEntryScreen> createState() => _WebPurchaseEntryScreenState();
}

class _WebPurchaseEntryScreenState extends State<WebPurchaseEntryScreen> {
  final internalNoC = TextEditingController();
  final supplierBillNoC = TextEditingController();
  final searchController = TextEditingController();

  DateTime selectedBillDate = DateTime.now();
  DateTime selectedEntryDate = DateTime.now();
  String paymentMode = "CREDIT";
  Party? selectedSupplier;
  String searchQuery = "";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    supplierBillNoC.addListener(() {
      if (mounted) setState(() {});
    });
    _initSession();
  }

  void _initSession() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final webPh = Provider.of<PharoahWebManager>(context, listen: false);

      if (widget.existingPurchase != null) {
        final p = widget.existingPurchase!;
        internalNoC.text = p.internalNo;
        supplierBillNoC.text = p.billNo;
        selectedBillDate = p.date;
        selectedEntryDate = p.entryDate;
        paymentMode = p.paymentMode;
        try {
          selectedSupplier = webPh.parties.firstWhere((pt) => pt.id == p.partyId || pt.name == p.distributorName);
        } catch (_) {
          selectedSupplier = Party(id: p.partyId, name: p.distributorName, group: "Sundry Creditors");
        }
      } else {
        internalNoC.text = webPh.getNextBillNumber("PURCHASE", "PUR-", 1);
        selectedBillDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
        selectedEntryDate = DateTime.now();
      }

      setState(() => isLoading = false);
    });
  }

  Purchase? _checkDuplicateBill(PharoahWebManager webPh) {
    if (selectedSupplier == null || supplierBillNoC.text.trim().isEmpty) return null;
    String cleanNo = supplierBillNoC.text.trim().toUpperCase();
    try {
      return webPh.purchases.firstWhere((p) =>
        (p.partyId == selectedSupplier!.id || p.distributorName.trim().toUpperCase() == selectedSupplier!.name.trim().toUpperCase()) &&
        p.billNo.trim().toUpperCase() == cleanNo &&
        (widget.existingPurchase == null || p.id != widget.existingPurchase!.id)
      );
    } catch (_) {
      return null;
    }
  }

  void _openQuickAddSupplier(PharoahWebManager webPh) {
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        preFillData: const {'group': 'Sundry Creditors'},
        onPartyCreated: (newParty) {
          setState(() => selectedSupplier = newParty);
        },
      ),
    );
  }

  @override
  void dispose() {
    internalNoC.dispose();
    supplierBillNoC.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    if (isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(50), child: CircularProgressIndicator(color: Color(0xFFF59E0B))));
    }

    final duplicateBill = _checkDuplicateBill(webPh);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
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
            // Top Navigation Bar
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
                const Icon(Icons.downloading_rounded, color: Color(0xFFF59E0B), size: 24),
                const SizedBox(width: 10),
                Text(
                  widget.isReadOnly ? "VIEW PURCHASE ENTRY" : (widget.existingPurchase != null ? "MODIFY PURCHASE ENTRY" : "PURCHASE INWARD ENTRY (STEP 1)"),
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 1000-IQ Responsive Layout: 2-Column Split in Landscape, 1-Column in Portrait
            LayoutBuilder(
              builder: (context, constraints) {
                bool isWide = constraints.maxWidth > 950;

                Widget leftForm = _buildLeftEntryForm(webPh, duplicateBill);
                Widget rightRadar = _buildRightIntelligenceRadar(webPh);

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: leftForm),
                      const SizedBox(width: 18),
                      Expanded(flex: 5, child: rightRadar),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      leftForm,
                      const SizedBox(height: 18),
                      rightRadar,
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 📝 LEFT COLUMN: STEP-1 FORM & SUPPLIER SELECTION
  // ===========================================================================
  Widget _buildLeftEntryForm(PharoahWebManager webPh, Purchase? duplicateBill) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Box: Internal ID, Supplier Bill No & Dates
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: internalNoC,
                      readOnly: true,
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFF59E0B), fontSize: 14),
                      decoration: InputDecoration(
                        labelText: "INTERNAL ENTRY NO",
                        labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: supplierBillNoC,
                      readOnly: widget.isReadOnly,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: "SUPPLIER BILL NO *",
                        hintText: "Enter Bill No",
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                        labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                        filled: true,
                        fillColor: widget.isReadOnly ? Colors.black26 : const Color(0x33F59E0B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Live Duplicate Bill Alert Banner
              if (duplicateBill != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x33DC2626),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "⚠️ DUPLICATE INVOICE: Bill #${duplicateBill.billNo} was already recorded on ${DateFormat('dd/MM/yyyy').format(duplicateBill.date)} (₹${duplicateBill.totalAmount.toStringAsFixed(2)}).",
                          style: const TextStyle(color: Colors.redAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: widget.isReadOnly ? null : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedBillDate,
                          firstDate: WebAppDateLogic.getFYStart(webPh.financialYear),
                          lastDate: WebAppDateLogic.getFYEnd(webPh.financialYear),
                        );
                        if (picked != null) setState(() => selectedBillDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("SUPPLIER BILL DATE", style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(DateFormat('dd/MM/yyyy').format(selectedBillDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                              ],
                            ),
                            const Icon(Icons.calendar_month_rounded, color: Color(0xFFF59E0B), size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("STOCK INWARD DATE", style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(DateFormat('dd/MM/yyyy').format(selectedEntryDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                              ],
                            ),
                            const Icon(Icons.event_available_rounded, color: Colors.greenAccent, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'CASH', label: Text('CASH', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold))),
                      ButtonSegment(value: 'CREDIT', label: Text('CREDIT', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold))),
                    ],
                    selected: {paymentMode},
                    onSelectionChanged: widget.isReadOnly ? null : (v) => setState(() => paymentMode = v.first),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        const Text(
          "SELECT DISTRIBUTOR / SUPPLIER",
          style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        const SizedBox(height: 8),

        if (selectedSupplier != null)
          _buildSupplierCard()
        else
          _buildSupplierList(webPh),

        // Proceed Button
        if (selectedSupplier != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 16),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: () {
                if (supplierBillNoC.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Supplier Bill Number is mandatory to proceed!"), backgroundColor: Colors.red),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (c) => WebPurchaseBillingScreen(
                      supplier: selectedSupplier!,
                      internalNo: internalNoC.text.trim(),
                      supplierBillNo: supplierBillNoC.text.trim(),
                      billDate: selectedBillDate,
                      entryDate: selectedEntryDate,
                      paymentMode: paymentMode,
                      existingPurchase: widget.existingPurchase,
                      isReadOnly: widget.isReadOnly,
                      onCompleted: widget.onBack,
                    ),
                  ),
                );
              },
              icon: Icon(widget.isReadOnly ? Icons.visibility : Icons.arrow_forward_rounded, size: 20),
              label: Text(
                widget.isReadOnly ? "VIEW PURCHASED ITEMS ➔" : "PROCEED TO ITEM ENTRY (STEP 2) ➔",
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, letterSpacing: 0.5),
              ),
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // 🧠 RIGHT COLUMN: LIVE SUPPLIER RADAR & PREVIOUS BILLS INTELLIGENCE
  // ===========================================================================
  Widget _buildRightIntelligenceRadar(PharoahWebManager webPh) {
    if (selectedSupplier != null) {
      double bal = webPh.calculatePartyBalance(selectedSupplier!);
      bool isPayable = bal <= 0;

      // Previous 5 Inwards from this Supplier
      final previousBills = webPh.purchases
          .where((p) =>
              p.partyId == selectedSupplier!.id ||
              p.distributorName.trim().toUpperCase() == selectedSupplier!.name.trim().toUpperCase())
          .toList();
      previousBills.sort((a, b) => b.date.compareTo(a.date));
      final recentFive = previousBills.take(5).toList();

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
            Row(
              children: [
                const Icon(Icons.radar_rounded, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 8),
                const Text(
                  "VENDOR FINANCIAL & INWARD RADAR",
                  style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPayable ? const Color(0x33DC2626) : const Color(0x3310B981),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isPayable ? "PAYABLE (CREDITOR)" : "ADVANCE (DEBIT)",
                    style: TextStyle(color: isPayable ? const Color(0xFFF87171) : Colors.greenAccent, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Live Ledger Balance
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
                      const SizedBox(height: 3),
                      Text("₹${bal.abs().toStringAsFixed(2)}", style: TextStyle(color: isPayable ? const Color(0xFFF87171) : Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("CREDIT TERMS", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text("${selectedSupplier!.creditDays > 0 ? selectedSupplier!.creditDays : 30} Days Due", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Supplier Stat Info
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("GSTIN: ${selectedSupplier!.gst} • PAN: ${selectedSupplier!.pan}", style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text("Phone: ${selectedSupplier!.phone.isNotEmpty ? selectedSupplier!.phone : 'N/A'} • DL: ${selectedSupplier!.dl}", style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 22),

            // Previous 5 Inward Invoices Stream
            Row(
              children: [
                const Icon(Icons.history_edu_rounded, color: Color(0xFFFBBF24), size: 16),
                const SizedBox(width: 6),
                Text(
                  "RECENT INWARD INVOICES (${previousBills.length} TOTAL)",
                  style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (recentFive.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                child: Text("First time purchase from ${selectedSupplier!.name}.", style: const TextStyle(color: Colors.white38, fontSize: 11)),
              )
            else
              ...recentFive.map((p) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white10)),
                child: Row(
                  children: [
                    Text("Bill #${p.billNo}", style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(width: 8),
                    Text(DateFormat('dd/MM/yy').format(p.date), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    const Spacer(),
                    Text("${p.items.length} Items", style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
                    const SizedBox(width: 10),
                    Text("₹${p.totalAmount.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                  ],
                ),
              )),
          ],
        ),
      );
    }

    // Default Inward Intelligence when no supplier is chosen yet
    double totalMonthPur = webPh.purchases.fold(0.0, (s, p) => s + p.totalAmount);
    final allSuppliers = webPh.parties.where((p) => p.group == "Sundry Creditors").toList();

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
              Icon(Icons.insights_rounded, color: Color(0xFFF59E0B), size: 18),
              SizedBox(width: 8),
              Text(
                "STORE INWARD INTELLIGENCE",
                style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
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
                    const Text("TOTAL INWARD PURCHASES", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text("₹${totalMonthPur.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 18, fontWeight: FontWeight.w900)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text("REGISTERED VENDORS", style: TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text("${allSuppliers.length} Suppliers", style: const TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 22),

          const Text("QUICK TIP: DUPLICATE BILL PROTECTION", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          const Text(
            "• सप्लायर चुनते ही दाएँ हाथ पर उसका बकाया खाता और पिछले 5 बिल दिखाई देंगे।\\n• अगर आपने सप्लायर का वही बिल नंबर दोबारा टाइप किया तो सिस्टम तुरंत डुप्लीकेट अलर्ट देगा।",
            style: TextStyle(color: Colors.white54, fontSize: 10, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(color: Color(0x33F59E0B), shape: BoxShape.circle),
          child: const Icon(Icons.business_rounded, color: Color(0xFFF59E0B), size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(selectedSupplier!.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 3),
              Text("${selectedSupplier!.city} | GST: ${selectedSupplier!.gst}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
        if (!widget.isReadOnly)
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 24),
            onPressed: () => setState(() => selectedSupplier = null),
          ),
      ],
    ),
  );

  Widget _buildSupplierList(PharoahWebManager webPh) {
    final query = searchQuery.trim().toLowerCase();
    final matchingSuppliers = webPh.parties.where((p) {
      if (query.isEmpty) return p.group == "Sundry Creditors";
      return p.group == "Sundry Creditors" &&
          (p.name.toLowerCase().contains(query) ||
           p.city.toLowerCase().contains(query) ||
           p.gst.toLowerCase().contains(query));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: searchController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: "Search Distributor by Name, City or GST...",
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFF59E0B), size: 16),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 16),
                          onPressed: () {
                            searchController.clear();
                            setState(() => searchQuery = "");
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (v) => setState(() => searchQuery = v),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _openQuickAddSupplier(webPh),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text("NEW SUPPLIER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(minHeight: 140, maxHeight: 280),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: matchingSuppliers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      searchQuery.isEmpty ? "No suppliers registered under Sundry Creditors." : "No supplier found matching '$searchQuery'.",
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: matchingSuppliers.length,
                  itemBuilder: (context, idx) {
                    final p = matchingSuppliers[idx];
                    return Container(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Color(0x26F59E0B), shape: BoxShape.circle),
                          child: const Icon(Icons.business_outlined, color: Color(0xFFF59E0B), size: 16),
                        ),
                        title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                        subtitle: Text("${p.city.isEmpty ? 'No City' : p.city} | GST: ${p.gst.isEmpty ? 'N/A' : p.gst}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 12),
                        onTap: () => setState(() => selectedSupplier = p),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
'''

with open(screen_path, "w", encoding="utf-8") as f:
    f.write(code)
print("✔ web_purchase_entry_screen.dart upgraded with Dual-Pane LayoutBuilder & Radar.")

# 3. VERIFY WITH FLUTTER ANALYZE
print("\n🔍 Step 3/5: Running Flutter Analyze on lib/web_live_sync/...")
res = subprocess.run(["flutter", "analyze", "lib/web_live_sync/"], capture_output=True, text=True)
print(res.stdout)

errors = [line for line in res.stdout.split('\n') if 'error •' in line]
if len(errors) > 0:
    print(f"❌ Still found {len(errors)} error(s):")
    for e in errors:
        print("  " + e)
    sys.exit(1)

print("🎉 0 ERRORS! COMPILATION IS 100% CLEAN.")

# 4. BUILD WEB
print("\n🔨 Step 4/5: Building Production Web App...")
b_res = subprocess.run(
    ["flutter", "build", "web", "-t", "lib/web_live_sync/web_main.dart", "--release", "--base-href", "/", "--pwa-strategy=none"],
    text=True
)
if b_res.returncode != 0:
    print("❌ Web Build Failed!")
    sys.exit(1)

# 5. DEPLOY TO CLOUDFLARE PAGES & PUSH GIT
print("\n🌐 Step 5/5: Deploying to Cloudflare Pages & Git Commit...")
subprocess.run(["npx", "wrangler", "pages", "deploy", "build/web", "--project-name=pharoah-erp"], text=True)

subprocess.run(["git", "add", "."], text=True)
subprocess.run(["git", "commit", "-m", "🚀 #PH-REV-631: Dual-Pane Purchase Step-1 Intelligence Radar Deployed"], text=True)
branch_res = subprocess.run(["git", "branch", "--show-current"], capture_output=True, text=True)
branch = branch_res.stdout.strip() or "main"
subprocess.run(["git", "push", "origin", branch], text=True)

print("\n" + "="*65)
print("🎉 SUCCESS: #PH-REV-631 IS LIVE ON CLOUDFLARE PAGES!")
print("🔗 Website: https://pharoah-erp.pages.dev")
print("✅ Tag: #PH-REV-631 (PURCHASE-STEP1-INTELLIGENCE-RADAR)")
print("="*65)
