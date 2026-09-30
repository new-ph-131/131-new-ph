// FILE: lib/web_live_sync/sub_views/web_challans/web_challan_hub.dart

import 'package:flutter/material.dart';
import 'sale_challan/ui/web_sale_challan_screen.dart';

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
    activeSubView = (widget.initialAction == "GO_CHALLAN_SALE") ? "SALE_CHALLAN_ENTRY" : "HUB";
  }

  @override
  Widget build(BuildContext context) {
    if (activeSubView == "SALE_CHALLAN_ENTRY") {
      return WebSaleChallanScreen(
        onBack: () => setState(() => activeSubView = "HUB"),
      );
    }

    return Container(
      padding: const EdgeInsets.all(25),
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
              int crossAxisCount = constraints.maxWidth > 1100 ? 5 : (constraints.maxWidth > 700 ? 3 : 1);

              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.15,
                children: [
                  _challanBtn(
                    title: "Sale Challan",
                    subtitle: "Outward Delivery Note",
                    icon: Icons.local_shipping_rounded,
                    color: Colors.teal,
                    onTap: () => setState(() => activeSubView = "SALE_CHALLAN_ENTRY"),
                  ),
                  _challanBtn(
                    title: "Pur Challan",
                    subtitle: "Inward Stock Note",
                    icon: Icons.inventory_2_rounded,
                    color: Colors.orange,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pur Challan next...")));
                    },
                  ),
                  _challanBtn(
                    title: "Sale Reg",
                    subtitle: "Outward Dispatch History",
                    icon: Icons.list_alt_rounded,
                    color: Colors.indigo,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sale Reg next...")));
                    },
                  ),
                  _challanBtn(
                    title: "Pur Reg",
                    subtitle: "Inward Delivery History",
                    icon: Icons.history_edu_rounded,
                    color: Colors.amber.shade800,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pur Reg next...")));
                    },
                  ),
                  _challanBtn(
                    title: "Stitcher / Bill",
                    subtitle: "Convert Challan to GST Bill",
                    icon: Icons.auto_fix_high_rounded,
                    color: Colors.purpleAccent,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stitcher next...")));
                    },
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
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withAlpha(100), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(20),
              blurRadius: 14,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withAlpha(35),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
