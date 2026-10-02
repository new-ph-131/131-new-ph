// FILE: lib/web_live_sync/sub_views/web_challans/web_challan_hub.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'web_sale_challan_view.dart';
import 'web_purchase_challan_view.dart';
import '../../web_challan_view.dart';
import '../../web_challan_stitcher_wizard.dart';
import '../../pharoah_web_manager.dart';

class WebChallanHub extends StatefulWidget {
  final VoidCallback onBack;
  final String? initialAction;

  const WebChallanHub({
    super.key,
    required this.onBack,
    this.initialAction,
  });

  @override
  State<WebChallanHub> createState() => _WebChallanHubState();
}

class _WebChallanHubState extends State<WebChallanHub> {
  late String activeSubView;

  @override
  void initState() {
    super.initState();
    if (widget.initialAction == "GO_CHALLAN_SALE") {
      activeSubView = "SALE_CHALLAN_ENTRY";
    } else if (widget.initialAction == "GO_CHALLAN_PUR") {
      activeSubView = "PURCHASE_CHALLAN_ENTRY";
    } else if (widget.initialAction == "GO_CHALLAN_SALE_REG") {
      activeSubView = "SALE_REG";
    } else if (widget.initialAction == "GO_CHALLAN_PUR_REG") {
      activeSubView = "PUR_REG";
    } else if (widget.initialAction == "GO_STITCHER") {
      activeSubView = "STITCHER";
    } else {
      activeSubView = "HUB";
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    if (activeSubView == "SALE_CHALLAN_ENTRY") {
      return WebSaleChallanView(
        onBack: () => setState(() => activeSubView = "HUB"),
      );
    }
    if (activeSubView == "PURCHASE_CHALLAN_ENTRY") {
      return WebPurchaseChallanView(
        onBack: () => setState(() => activeSubView = "HUB"),
      );
    }
    if (activeSubView == "SALE_REG") {
      return WebChallanView(
        onBack: () => setState(() => activeSubView = "HUB"),
        initialTabIndex: 2,
      );
    }
    if (activeSubView == "PUR_REG") {
      return WebChallanView(
        onBack: () => setState(() => activeSubView = "HUB"),
        initialTabIndex: 3,
      );
    }
    if (activeSubView == "STITCHER") {
      return WebChallanStitcherWizard(
        onBack: () => setState(() => activeSubView = "HUB"),
      );
    }

    return Container(
      padding: const EdgeInsets.all(22),
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
              const Icon(Icons.local_shipping_rounded, color: Color(0xFF2DD4BF), size: 24),
              const SizedBox(width: 10),
              const Text(
                "CHALLAN MANAGEMENT HUB",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 25),
          const Text(
            "PRIMARY CHALLAN MODULES",
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
          const SizedBox(height: 16),

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
                  _challanBtn(
                    title: "Sale Challan",
                    subtitle: "Outward Delivery Note",
                    badgeText: null,
                    icon: Icons.local_shipping_rounded,
                    color: Colors.teal,
                    onTap: () => setState(() => activeSubView = "SALE_CHALLAN_ENTRY"),
                  ),
                  _challanBtn(
                    title: "Pur Challan",
                    subtitle: "Inward Purchase Note",
                    badgeText: null,
                    icon: Icons.inventory_2_rounded,
                    color: Colors.orange,
                    onTap: () => setState(() => activeSubView = "PURCHASE_CHALLAN_ENTRY"),
                  ),
                  _challanBtn(
                    title: "Sale Reg",
                    subtitle: "Outward Dispatch History",
                    badgeText: "${webPh.saleChallans.length} Records",
                    icon: Icons.list_alt_rounded,
                    color: Colors.indigo,
                    onTap: () => setState(() => activeSubView = "SALE_REG"),
                  ),
                  _challanBtn(
                    title: "Pur Reg",
                    subtitle: "Inward Delivery History",
                    badgeText: "${webPh.purchaseChallans.length} Records",
                    icon: Icons.history_edu_rounded,
                    color: Colors.amber.shade800,
                    onTap: () => setState(() => activeSubView = "PUR_REG"),
                  ),
                  _challanBtn(
                    title: "Stitcher / Bill",
                    subtitle: "Convert Challan to GST Bill",
                    badgeText: "Auto Merge",
                    icon: Icons.auto_fix_high_rounded,
                    color: Colors.purpleAccent,
                    onTap: () => setState(() => activeSubView = "STITCHER"),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _challanBtn({
    required String title,
    required String subtitle,
    String? badgeText,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withAlpha(35),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                if (badgeText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withAlpha(100), width: 0.5),
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
