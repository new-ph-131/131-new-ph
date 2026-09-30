// FILE: lib/web_live_sync/sub_views/web_challans/sale_challan/ui/web_sale_challan_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pharoah_erp/models.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/sale_challan_controller.dart';
import 'sale_challan_header_widget.dart';
import 'sale_challan_cart_widget.dart';
import 'sale_challan_footer_widget.dart';

class WebSaleChallanScreen extends StatefulWidget {
  final VoidCallback onBack;
  final SaleChallan? existingRecord;
  final bool isReadOnly;

  const WebSaleChallanScreen({
    super.key,
    required this.onBack,
    this.existingRecord,
    this.isReadOnly = false,
  });

  @override
  State<WebSaleChallanScreen> createState() => _WebSaleChallanScreenState();
}

class _WebSaleChallanScreenState extends State<WebSaleChallanScreen> {
  late final SaleChallanController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SaleChallanController();
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    _controller.init(
      webPh: webPh,
      existingRecord: widget.existingRecord,
      readOnly: widget.isReadOnly,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Return Navigation Bar
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 14),
                  label: const Text("BACK TO CHALLANS", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.local_shipping_rounded, color: Color(0xFF2DD4BF), size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.isReadOnly
                      ? "VIEW DELIVERY CHALLAN"
                      : (widget.existingRecord != null ? "MODIFY DELIVERY CHALLAN" : "NEW OUTWARD DELIVERY CHALLAN"),
                  style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Header Section (Customer & Date)
            SaleChallanHeaderWidget(controller: _controller, webPh: webPh),
            const SizedBox(height: 14),

            // Cart & Items Entry Section
            SaleChallanCartWidget(controller: _controller, webPh: webPh),
            const SizedBox(height: 14),

            // Footer Section (Remarks & Action Buttons)
            SaleChallanFooterWidget(
              controller: _controller,
              webPh: webPh,
              onSuccess: widget.onBack,
            ),
          ],
        );
      },
    );
  }
}
