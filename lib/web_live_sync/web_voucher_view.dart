// FILE: lib/web_live_sync/web_voucher_view.dart

import 'package:flutter/material.dart';
import 'sub_views/web_accounts/web_voucher_entry_view.dart';

class WebVoucherView extends StatefulWidget {
  final VoidCallback onBack;
  final int initialTabIndex;
  final String? initialAction; // "RECEIPT", "PAYMENT", "CONTRA", "EXPENSE", "DAYBOOK"

  const WebVoucherView({
    super.key,
    required this.onBack,
    this.initialTabIndex = 0,
    this.initialAction,
  });

  @override
  State<WebVoucherView> createState() => _WebVoucherViewState();
}

class _WebVoucherViewState extends State<WebVoucherView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String activeSubView = "HUB"; // HUB, VOUCHER_ENTRY, DAYBOOK

  String voucherTypeToEdit = "Receipt";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex);
    if (widget.initialAction != null) {
      if (widget.initialAction == "GO_RECEIPT") { voucherTypeToEdit = "Receipt"; activeSubView = "VOUCHER_ENTRY"; }
      else if (widget.initialAction == "GO_PAYMENT") { voucherTypeToEdit = "Payment"; activeSubView = "VOUCHER_ENTRY"; }
      else if (widget.initialAction == "GO_CONTRA") { voucherTypeToEdit = "Contra"; activeSubView = "VOUCHER_ENTRY"; }
      else if (widget.initialAction == "GO_EXPENSE") { voucherTypeToEdit = "Expense"; activeSubView = "VOUCHER_ENTRY"; }
      else if (widget.initialAction == "GO_DAYBOOK") { activeSubView = "DAYBOOK"; }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // webPh not needed here

    if (activeSubView == "VOUCHER_ENTRY") {
      return WebVoucherEntryView(
        type: voucherTypeToEdit,
        onBack: () => setState(() => activeSubView = "HUB"),
      );
    }

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
          const Text(
            "PRIMARY ACCOUNT MODULES",
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
          const SizedBox(height: 16),

          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = constraints.maxWidth > 950 ? 4 : (constraints.maxWidth > 650 ? 2 : 1);

              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.25,
                children: [
                  _accountCard(
                    title: "Receipt (Cash In)",
                    subtitle: "Customer Inflow & Collections",
                    icon: Icons.add_chart_rounded,
                    color: Colors.green,
                    onTap: () => setState(() { voucherTypeToEdit = "Receipt"; activeSubView = "VOUCHER_ENTRY"; }),
                  ),
                  _accountCard(
                    title: "Payment (Cash Out)",
                    subtitle: "Supplier & Vendor Payments",
                    icon: Icons.analytics_rounded,
                    color: Colors.red,
                    onTap: () => setState(() { voucherTypeToEdit = "Payment"; activeSubView = "VOUCHER_ENTRY"; }),
                  ),
                  _accountCard(
                    title: "Contra (Bank)",
                    subtitle: "Bank deposit & cash withdrawal",
                    icon: Icons.sync_alt_rounded,
                    color: Colors.orange,
                    onTap: () => setState(() { voucherTypeToEdit = "Contra"; activeSubView = "VOUCHER_ENTRY"; }),
                  ),
                  _accountCard(
                    title: "Expenses",
                    subtitle: "Operating store expenses",
                    icon: Icons.money_off_rounded,
                    color: Colors.brown,
                    onTap: () => setState(() { voucherTypeToEdit = "Expense"; activeSubView = "VOUCHER_ENTRY"; }),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _accountCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(100), width: 1.2),
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
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withAlpha(35), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 22),
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
