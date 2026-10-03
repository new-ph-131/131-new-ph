// FILE: lib/web_live_sync/sub_views/web_gst/web_gst_hub.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../pharoah_web_manager.dart';
import 'web_gstr1_view.dart';
import 'web_gstr3b_view.dart';
import 'web_gstr2_view.dart';
import 'web_gst_recon_view.dart';
import 'web_eway_bill_view.dart';

class WebGstHub extends StatefulWidget {
  final VoidCallback onBack;
  final String? initialAction;

  const WebGstHub({super.key, required this.onBack, this.initialAction});

  @override
  State<WebGstHub> createState() => _WebGstHubState();
}

class _WebGstHubState extends State<WebGstHub> {
  late String activeSubView; // "HUB", "GSTR1", "GSTR3B", "GSTR2", "RECON", "EWAY"

  @override
  void initState() {
    super.initState();
    if (widget.initialAction == "GO_GST_1") {
      activeSubView = "GSTR1";
    } else if (widget.initialAction == "GO_GST_3B") {
      activeSubView = "GSTR3B";
    } else if (widget.initialAction == "GO_GST_2") {
      activeSubView = "GSTR2";
    } else if (widget.initialAction == "GO_GST_RECON") {
      activeSubView = "RECON";
    } else if (widget.initialAction == "GO_EWAY") {
      activeSubView = "EWAY";
    } else {
      activeSubView = "HUB";
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    // Sub-view Router
    if (activeSubView == "GSTR1") {
      return _wrapSubView("GSTR-1 (SALES REGISTER & HSN SUMMARY)", Icons.assignment_outlined, WebGstr1View(webPh: webPh, onBack: () => setState(() => activeSubView = "HUB")));
    }
    if (activeSubView == "GSTR3B") {
      return _wrapSubView("GSTR-3B (MONTHLY TAX LIABILITY COMPUTATION)", Icons.summarize_outlined, WebGstr3bView(webPh: webPh, onBack: () => setState(() => activeSubView = "HUB")));
    }
    if (activeSubView == "GSTR2") {
      return _wrapSubView("GSTR-2 (PURCHASE INWARD & ITC REGISTER)", Icons.shopping_cart_checkout_rounded, WebGstr2View(webPh: webPh, onBack: () => setState(() => activeSubView = "HUB")));
    }
    if (activeSubView == "RECON") {
      return _wrapSubView("PORTAL RECONCILIATION (2A / 2B ITC MATCHER)", Icons.fact_check_outlined, WebGstReconView(webPh: webPh, onBack: () => setState(() => activeSubView = "HUB")));
    }
    if (activeSubView == "EWAY") {
      return _wrapSubView("E-WAY BILL & TRANSPORT MANAGEMENT", Icons.local_shipping_outlined, WebEwayBillView(webPh: webPh, onBack: () => setState(() => activeSubView = "HUB")));
    }

    // MAIN GST BUTTONS HUB
    double totalOutputGst = 0.0;
    for (var s in webPh.sales.where((s) => s.status == "Active")) {
      for (var it in s.items) {
        totalOutputGst += (it.cgst + it.sgst + it.igst);
      }
    }

    double totalInputItc = 0.0;
    for (var p in webPh.purchases) {
      double t = p.items.fold(0.0, (s, i) => s + (i.purchaseRate * i.qty));
      totalInputItc += (p.totalAmount - t);
    }
    double netTaxLiability = totalOutputGst - totalInputItc;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK TO DASHBOARD", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 24),
              const SizedBox(width: 10),
              const Text("GST COMPLIANCE & RETURNS HUB", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 25),

          const Text("PRIMARY GST MODULES", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 14),

          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = constraints.maxWidth > 950 ? 5 : (constraints.maxWidth > 650 ? 3 : 2);
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.25,
                children: [
                  _gstBtn(
                    title: "GSTR-1",
                    subtitle: "B2B, B2C & HSN Summary",
                    badgeText: "Outward",
                    icon: Icons.assignment_outlined,
                    color: const Color(0xFF10B981),
                    onTap: () => setState(() => activeSubView = "GSTR1"),
                  ),
                  _gstBtn(
                    title: "GSTR-3B",
                    subtitle: "Monthly Tax Computation",
                    badgeText: "Summary",
                    icon: Icons.summarize_outlined,
                    color: const Color(0xFF2563EB),
                    onTap: () => setState(() => activeSubView = "GSTR3B"),
                  ),
                  _gstBtn(
                    title: "GSTR-2",
                    subtitle: "Inward Purchase Register & ITC",
                    badgeText: "ITC Check",
                    icon: Icons.shopping_cart_checkout_rounded,
                    color: const Color(0xFFF59E0B),
                    onTap: () => setState(() => activeSubView = "GSTR2"),
                  ),
                  _gstBtn(
                    title: "Portal Match",
                    subtitle: "2A / 2B Reconciliation Switch",
                    badgeText: "Recon",
                    icon: Icons.fact_check_outlined,
                    color: const Color(0xFF0D9488),
                    onTap: () => setState(() => activeSubView = "RECON"),
                  ),
                  _gstBtn(
                    title: "E-Way Bill",
                    subtitle: ">= ₹50,000 & Govt JSON Download",
                    badgeText: "E-Way",
                    icon: Icons.local_shipping_outlined,
                    color: const Color(0xFF6366F1),
                    onTap: () => setState(() => activeSubView = "EWAY"),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),

          // LIVE GST TAX STATUS STRIP
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
                _metricCol("OUTPUT TAX LIABILITY (SALES)", "₹${totalOutputGst.toStringAsFixed(2)}", Colors.orangeAccent),
                _metricCol("INPUT TAX CREDIT (PURCHASES)", "₹${totalInputItc.toStringAsFixed(2)}", Colors.greenAccent),
                _metricCol(
                  netTaxLiability > 0 ? "NET CASH PAYABLE" : "SURPLUS ITC CARRY-FORWARD",
                  "₹${netTaxLiability.abs().toStringAsFixed(2)}",
                  netTaxLiability > 0 ? Colors.redAccent : Colors.greenAccent,
                  isBold: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCol(String l, String v, Color c, {bool isBold = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(v, style: TextStyle(color: c, fontSize: isBold ? 17 : 14, fontWeight: FontWeight.w900)),
    ],
  );

  Widget _wrapSubView(String title, IconData icon, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white),
              onPressed: () => setState(() => activeSubView = "HUB"),
              icon: const Icon(Icons.arrow_back_rounded, size: 14),
              label: const Text("BACK TO GST HUB", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Icon(icon, color: const Color(0xFF10B981), size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    );
  }

  Widget _gstBtn({
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
          boxShadow: [BoxShadow(color: color.withAlpha(20), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withAlpha(35), shape: BoxShape.circle), child: Icon(icon, color: color, size: 22)),
                Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5), decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(6)), child: Text(badgeText, style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.bold))),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 9.5), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
