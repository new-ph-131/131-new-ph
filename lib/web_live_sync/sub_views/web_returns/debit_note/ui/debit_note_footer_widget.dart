// FILE: lib/web_live_sync/sub_views/web_returns/debit_note/ui/debit_note_footer_widget.dart
// ignore_for_file: prefer_const_constructors, unnecessary_const

import 'package:flutter/material.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/debit_note_controller.dart';

class DebitNoteFooterWidget extends StatelessWidget {
  final DebitNoteController controller;
  final PharoahWebManager webPh;
  final VoidCallback onSuccess;

  const DebitNoteFooterWidget({
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
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  controller: controller.remarksC,
                  readOnly: controller.isReadOnly,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: "RETURN REMARKS / REASON",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                    prefixIcon: const Icon(Icons.note_alt_outlined, color: Colors.white54, size: 16),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Row(
                children: [
                  const Text("Extra Disc (-): ", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  SizedBox(
                    width: 75,
                    height: 34,
                    child: TextField(
                      controller: controller.extraDiscC,
                      readOnly: controller.isReadOnly,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      ),
                      onChanged: (_) => controller.notifySearch(),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 15),
              Text(
                "R/O: ₹${controller.roundOff.toStringAsFixed(2)}",
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("NET DEBIT VALUE", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  Text(
                    "₹${controller.grandTotal.toStringAsFixed(2)}",
                    style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (!controller.isReadOnly)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: controller.isSaving
                      ? null
                      : () async {
                          bool ok = await controller.saveDebitNote(context, webPh, andPrint: false);
                          if (ok) onSuccess();
                        },
                  icon: controller.isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_circle_rounded, size: 16),
                  label: Text(controller.isSaving ? "SAVING..." : "SAVE DEBIT NOTE", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFBBF24),
                    side: const BorderSide(color: Color(0xFFFBBF24), width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: controller.isSaving
                      ? null
                      : () async {
                          bool ok = await controller.saveDebitNote(context, webPh, andPrint: true);
                          if (ok) onSuccess();
                        },
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: const Text("SAVE & PRINT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
