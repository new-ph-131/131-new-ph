// FILE: lib/web_live_sync/web_voucher_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'sub_views/web_accounts/web_voucher_entry_view.dart';
import 'sub_views/web_accounts/web_voucher_history_widget.dart';
import 'sub_views/web_accounts/web_daybook_widget.dart';
import 'sub_views/web_accounts/web_bank_book_widget.dart';
import 'web_ledger_view.dart';

class WebVoucherView extends StatefulWidget {
  final VoidCallback onBack;
  final int initialTabIndex;
  final String? initialAction;

  const WebVoucherView({
    super.key,
    required this.onBack,
    this.initialTabIndex = -1,
    this.initialAction,
  });

  @override
  State<WebVoucherView> createState() => _WebVoucherViewState();
}

class _WebVoucherViewState extends State<WebVoucherView> {
  String activeSubView = "HUB"; // HUB, VOUCHER_ENTRY, HISTORY, DAYBOOK, BANK_BOOK, LEDGERS
  String voucherTypeToEdit = "Receipt";
  Voucher? voucherToEdit;
  bool isReadOnlyMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialAction != null) {
      if (widget.initialAction == "GO_RECEIPT") { _openEntry("Receipt"); }
      else if (widget.initialAction == "GO_PAYMENT") { _openEntry("Payment"); }
      else if (widget.initialAction == "GO_CONTRA") { _openEntry("Contra"); }
      else if (widget.initialAction == "GO_EXPENSE") { _openEntry("Expense"); }
      else if (widget.initialAction == "GO_DAYBOOK") { activeSubView = "DAYBOOK"; }
      else if (widget.initialAction == "GO_HISTORY") { activeSubView = "HISTORY"; }
      else if (widget.initialAction == "GO_BANK_BOOK") { activeSubView = "BANK_BOOK"; }
      else if (widget.initialAction == "GO_LEDGERS") { activeSubView = "LEDGERS"; }
    } else if (widget.initialTabIndex == 0) {
      activeSubView = "HISTORY";
    } else if (widget.initialTabIndex == 1) {
      activeSubView = "DAYBOOK";
    } else if (widget.initialTabIndex == 2) {
      activeSubView = "BANK_BOOK";
    }
  }

  void _openEntry(String type, {Voucher? existing, bool isReadOnly = false}) {
    setState(() {
      voucherTypeToEdit = type;
      voucherToEdit = existing;
      isReadOnlyMode = isReadOnly;
      activeSubView = "VOUCHER_ENTRY";
    });
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    // 1. DEDICATED VOUCHER ENTRY (FULL-WIDTH DUAL PANE)
    if (activeSubView == "VOUCHER_ENTRY") {
      return WebVoucherEntryView(
        type: voucherTypeToEdit,
        existingVoucher: voucherToEdit,
        isReadOnly: isReadOnlyMode,
        onBack: () => setState(() {
          activeSubView = "HUB";
          voucherToEdit = null;
          isReadOnlyMode = false;
        }),
      );
    }

    // 2. DEDICATED FULL-WIDTH AUDIT REGISTER
    if (activeSubView == "HISTORY") {
      return _buildFullSubViewWrapper(
        title: "VOUCHER AUDIT REGISTER (HISTORY)",
        icon: Icons.format_list_bulleted_rounded,
        child: WebVoucherHistoryWidget(
          webPh: webPh,
          onEditVoucher: (v, isReadOnly) {
            _openEntry(v.type, existing: v, isReadOnly: isReadOnly);
          },
        ),
      );
    }

    // 3. DEDICATED FULL-WIDTH DAYBOOK STREAM
    if (activeSubView == "DAYBOOK") {
      return _buildFullSubViewWrapper(
        title: "LIVE DAYBOOK STREAM & CASH TALLY",
        icon: Icons.event_note_rounded,
        child: WebDaybookWidget(webPh: webPh),
      );
    }

    // 4. DEDICATED FULL-WIDTH BANK PASSBOOK
    if (activeSubView == "BANK_BOOK") {
      return _buildFullSubViewWrapper(
        title: "BANK PASSBOOK (STATEMENT)",
        icon: Icons.account_balance_rounded,
        child: WebBankBookWidget(webPh: webPh),
      );
    }

    // 5. PARTY LEDGERS
    if (activeSubView == "LEDGERS") {
      return WebLedgerView(onBack: () => setState(() => activeSubView = "HUB"));
    }

    // 6. MAIN HUB SCREEN: CLEAN PREMIUM BUTTONS & MODULES
    final double totalCashInHand = webPh.parties.where((p) => p.group == "Cash in Hand").fold(0.0, (s, p) => s + p.opBal);
    final bankAccounts = webPh.parties.where((p) => p.group == "Bank Accounts").toList();
    final double totalBankBalance = bankAccounts.fold(0.0, (s, b) => s + b.opBal);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
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
                label: const Text("BACK TO DASHBOARD", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF10B981), size: 24),
              const SizedBox(width: 10),
              const Text(
                "CASH & BANK ACCOUNTS HUB",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 25),

          // --- SECTION 1: DAILY VOUCHERS (4 BUTTONS) ---
          const Text(
            "DAILY TRANSACTION VOUCHERS",
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
          const SizedBox(height: 14),

          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = constraints.maxWidth > 950 ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.35,
                children: [
                  _accountButtonCard(
                    title: "Receipt (Cash In)",
                    subtitle: "Customer collection, inflow & bill settlement",
                    badgeText: "Inflow (+)",
                    icon: Icons.add_chart_rounded,
                    color: const Color(0xFF10B981),
                    onTap: () => _openEntry("Receipt"),
                  ),
                  _accountButtonCard(
                    title: "Payment (Cash Out)",
                    subtitle: "Supplier payments, vendor settlement & dues",
                    badgeText: "Outflow (-)",
                    icon: Icons.analytics_rounded,
                    color: const Color(0xFFDC2626),
                    onTap: () => _openEntry("Payment"),
                  ),
                  _accountButtonCard(
                    title: "Contra (Bank/Cash)",
                    subtitle: "Cash deposit to bank or bank cash withdrawal",
                    badgeText: "Transfer",
                    icon: Icons.sync_alt_rounded,
                    color: const Color(0xFFF59E0B),
                    onTap: () => _openEntry("Contra"),
                  ),
                  _accountButtonCard(
                    title: "Store Expenses",
                    subtitle: "Daily shop expenses, rent, salary, tea & tea costs",
                    badgeText: "Expenses",
                    icon: Icons.money_off_rounded,
                    color: const Color(0xFFB45309),
                    onTap: () => _openEntry("Expense"),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),

          // --- SECTION 2: AUDIT, DAYBOOK & PASSBOOK REGISTERS (3 BUTTONS) ---
          const Text(
            "REGISTERS, PASSBOOK & AUDIT",
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
          const SizedBox(height: 14),

          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = constraints.maxWidth > 950 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.45,
                children: [
                  _accountButtonCard(
                    title: "Voucher Audit Register",
                    subtitle: "Searchable table, Modify, Cancel, A6 Print & Excel export",
                    badgeText: "${webPh.vouchers.length} Vouchers",
                    icon: Icons.format_list_bulleted_rounded,
                    color: const Color(0xFF0F766E),
                    onTap: () => setState(() => activeSubView = "HISTORY"),
                  ),
                  _accountButtonCard(
                    title: "Live Daybook Stream",
                    subtitle: "Daily cash & bank flow, sales, purchases & cash tally",
                    badgeText: "Daily Tally",
                    icon: Icons.event_note_rounded,
                    color: const Color(0xFF475569),
                    onTap: () => setState(() => activeSubView = "DAYBOOK"),
                  ),
                  _accountButtonCard(
                    title: "Bank Book (Passbook)",
                    subtitle: "Bank account-wise statement, Dr/Cr & running balance",
                    badgeText: "${bankAccounts.length} Banks",
                    icon: Icons.account_balance_rounded,
                    color: const Color(0xFF0284C7),
                    onTap: () => setState(() => activeSubView = "BANK_BOOK"),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),

          // --- SECTION 3: LIVE DRAWER & INTERNAL ACCOUNTS STATUS STRIP ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(color: Color(0x3310B981), shape: BoxShape.circle),
                      child: const Icon(Icons.payments_rounded, color: Colors.greenAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("CASH IN HAND DRAWER", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                        Text("₹${totalCashInHand.toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(color: Color(0x330284C7), shape: BoxShape.circle),
                      child: const Icon(Icons.account_balance_rounded, color: Color(0xFF38BDF8), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("TOTAL BANK DEPOSITS", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                        Text("₹${totalBankBalance.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 16, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4338CA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => setState(() => activeSubView = "LEDGERS"),
                  icon: const Icon(Icons.people_alt_rounded, size: 16),
                  label: const Text("PARTY LEDGERS ➔", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullSubViewWrapper({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => setState(() => activeSubView = "HUB"),
              icon: const Icon(Icons.arrow_back_rounded, size: 14),
              label: const Text("BACK TO ACCOUNTS", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Icon(icon, color: const Color(0xFF10B981), size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    );
  }

  Widget _accountButtonCard({
    required String title,
    required String subtitle,
    required String badgeText,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(90), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(20),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withAlpha(35), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 22),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withAlpha(90), width: 0.5),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 9.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
