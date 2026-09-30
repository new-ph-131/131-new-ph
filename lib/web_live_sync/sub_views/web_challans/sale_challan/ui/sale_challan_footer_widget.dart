// FILE: lib/web_live_sync/sub_views/web_challans/sale_challan/ui/sale_challan_footer_widget.dart

import 'package:flutter/material.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/sale_challan_controller.dart';

class SaleChallanFooterWidget extends StatelessWidget {
  final SaleChallanController controller;
  final PharoahWebManager webPh;
  final VoidCallback onSuccess;

  const SaleChallanFooterWidget({
    super.key,
    required this.controller,
    required this.webPh,
    required this.onSuccess,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller.remarksC,
              readOnly: controller.isReadOnly,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                labelText: "DISPATCH REMARKS / VEHICLE DETAILS",
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                prefixIcon: const Icon(Icons.note_alt_outlined, color: Colors.white54, size: 16),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 25),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text("NET CHALLAN VALUE", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              Text("₹${controller.grandTotal.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 22, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(width: 25),
          if (!controller.isReadOnly) ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: controller.isSaving
                  ? null
                  : () async {
                      bool ok = await controller.saveChallan(context, webPh, andPrint: false);
                      if (ok) onSuccess();
                    },
              icon: controller.isSaving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_rounded, size: 16),
              label: Text(controller.isSaving ? "SAVING..." : "SAVE CHALLAN", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2DD4BF),
                side: const BorderSide(color: Color(0xFF2DD4BF), width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: controller.isSaving
                  ? null
                  : () async {
                      bool ok = await controller.saveChallan(context, webPh, andPrint: true);
                      if (ok) onSuccess();
                    },
              icon: const Icon(Icons.print_rounded, size: 16),
              label: const Text("SAVE & PRINT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }
}
