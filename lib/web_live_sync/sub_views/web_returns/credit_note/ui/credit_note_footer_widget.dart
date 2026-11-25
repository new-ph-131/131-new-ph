// FILE: lib/web_live_sync/sub_views/web_returns/credit_note/ui/credit_note_footer_widget.dart

import 'package:flutter/material.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/credit_note_controller.dart';
import '../../../../../logic/gst_compliance_helper.dart';

class CreditNoteFooterWidget extends StatelessWidget {
  final CreditNoteController controller;
  final PharoahWebManager webPh;
  final VoidCallback onSuccess;

  const CreditNoteFooterWidget({
    super.key,
    required this.controller,
    required this.webPh,
    required this.onSuccess,
  });

  @override
  Widget build(BuildContext context) {
    final bool showCommTaxText = controller.isCommercial;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: controller.selectedReason,
            isExpanded: true,
            dropdownColor: const Color(0xFF0F172A),
            style: const TextStyle(color: Colors.white, fontSize: 11.5),
            decoration: InputDecoration(
              labelText: "RETURN REASON (GST RULE 53(1A))",
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
              prefixIcon: const Icon(Icons.gavel_rounded, color: Color(0xFFF87171), size: 15),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: GstComplianceHelper.standardReasons
                .map((r) => DropdownMenuItem<String>(
                    value: r, child: Text(r, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: controller.isReadOnly
                ? null
                : (val) {
                    if (val != null) controller.setReason(val);
                  },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: GstComplianceHelper.isOtherReason(controller.selectedReason)
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      controller: controller.remarksC,
                      readOnly: controller.isReadOnly,
                      style: const TextStyle(color: Colors.white, fontSize: 11.5),
                      decoration: InputDecoration(
                        labelText: "CUSTOM REMARKS / EXPIRY / DAMAGE DETAILS",
                        labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                        prefixIcon: const Icon(Icons.note_alt_outlined,
                            color: Colors.white54, size: 15),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),

          // SALE-STYLE CALCULATION & SETTLEMENT BOX
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                _calcRow("GROSS TAXABLE", "₹${controller.subTotal.toStringAsFixed(2)}",
                    valueColor: Colors.white70),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Text(
                      "EXTRA DISC (-)",
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 62,
                      height: 30,
                      child: TextField(
                        controller: controller.extraDiscPerC,
                        readOnly: controller.isReadOnly,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          suffixText: "%",
                          suffixStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
                          filled: true,
                          fillColor: Colors.black26,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide.none),
                        ),
                        onChanged: controller.setExtraDiscPercent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 78,
                      height: 30,
                      child: TextField(
                        controller: controller.extraDiscC,
                        readOnly: controller.isReadOnly,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          prefixText: "₹",
                          prefixStyle: const TextStyle(color: Colors.redAccent, fontSize: 10),
                          filled: true,
                          fillColor: Colors.black26,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide.none),
                        ),
                        onChanged: controller.setExtraDiscRupees,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10, height: 14),
                _calcRow("NET TAXABLE", "₹${controller.totalTaxable.toStringAsFixed(2)}",
                    valueColor: Colors.white, isBold: true),
                const SizedBox(height: 5),
                if (showCommTaxText) ...[
                  _calcRow("COMMERCIAL NOTE (SEC 34)", "GST EXEMPT (₹0.00)",
                      valueColor: Colors.orangeAccent, isBold: true),
                ] else if (controller.isLocal) ...[
                  _calcRow("CGST TOTAL", "₹${controller.totalCGST.toStringAsFixed(2)}",
                      valueColor: Colors.white70),
                  const SizedBox(height: 4),
                  _calcRow("SGST TOTAL", "₹${controller.totalSGST.toStringAsFixed(2)}",
                      valueColor: Colors.white70),
                ] else ...[
                  _calcRow("IGST TOTAL", "₹${controller.totalIGST.toStringAsFixed(2)}",
                      valueColor: Colors.white70),
                ],
                const SizedBox(height: 4),
                _calcRow(
                  "ROUND OFF",
                  "${controller.roundOff >= 0 ? '+' : ''}₹${controller.roundOff.toStringAsFixed(2)}",
                  valueColor: Colors.white54,
                ),
                const Divider(color: Colors.white12, height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "NET CREDIT VALUE",
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                        Text(
                          "Sec 34 Settlement",
                          style: TextStyle(color: Colors.white38, fontSize: 9),
                        ),
                      ],
                    ),
                    Text(
                      "₹${controller.grandTotal.toStringAsFixed(2)}",
                      style: const TextStyle(
                        color: Color(0xFFF87171),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (!controller.isReadOnly) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: controller.isSaving
                        ? null
                        : () async {
                            bool ok = await controller.saveCreditNote(context, webPh,
                                andPrint: false);
                            if (ok) onSuccess();
                          },
                    icon: controller.isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 16),
                    label: Text(
                      controller.isSaving ? "SAVING..." : "SAVE (F2)",
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 11.5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF87171),
                      side: const BorderSide(color: Color(0xFFF87171), width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: controller.isSaving
                        ? null
                        : () async {
                            bool ok = await controller.saveCreditNote(context, webPh,
                                andPrint: true);
                            if (ok) onSuccess();
                          },
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: const Text(
                      "PRINT",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _calcRow(String label, String value,
      {Color valueColor = Colors.white, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white54,
            fontSize: 10.5,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 11.5,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
