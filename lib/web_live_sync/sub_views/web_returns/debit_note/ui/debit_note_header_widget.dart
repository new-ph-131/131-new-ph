// FILE: lib/web_live_sync/sub_views/web_returns/debit_note/ui/debit_note_header_widget.dart
// ignore_for_file: prefer_const_constructors, unnecessary_const

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../../../../web_app_date_logic.dart';
import '../logic/debit_note_controller.dart';
import '../../../web_billing/quick_add_party_modal.dart';

class DebitNoteHeaderWidget extends StatelessWidget {
  final DebitNoteController controller;
  final PharoahWebManager webPh;

  const DebitNoteHeaderWidget({
    super.key,
    required this.controller,
    required this.webPh,
  });

  void _openQuickAddSupplier(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        preFillData: const {'group': 'Sundry Creditors'},
        onPartyCreated: (newParty) {
          controller.setSupplier(newParty);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suppQuery = controller.supplierSearchC.text.trim().toLowerCase();
    final matchingSuppliers = suppQuery.isEmpty
        ? <Party>[]
        : webPh.parties
            .where((p) =>
                (p.group == "Sundry Creditors" || p.group.isEmpty) &&
                (p.name.toLowerCase().contains(suppQuery) ||
                 p.city.toLowerCase().contains(suppQuery) ||
                 p.gst.toLowerCase().contains(suppQuery) ||
                 p.phone.toLowerCase().contains(suppQuery)))
            .take(5)
            .toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: controller.noteNoC,
                  readOnly: true,
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFBBF24), fontSize: 13),
                  decoration: InputDecoration(
                    labelText: "DEBIT NOTE NUMBER",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: controller.isReadOnly
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: controller.selectedDate,
                            firstDate: WebAppDateLogic.getFYStart(webPh.financialYear),
                            lastDate: WebAppDateLogic.getFYEnd(webPh.financialYear),
                          );
                          if (picked != null) controller.setDate(picked);
                        },
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("RETURN DATE", style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
                            Text(
                              DateFormat('dd/MM/yyyy').format(controller.selectedDate),
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Icon(Icons.calendar_month_rounded, color: Color(0xFFFBBF24), size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              if (!controller.isReadOnly) ...[
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _openQuickAddSupplier(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                  label: const Text("+ SUPPLIER", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Dual Mode Segmented Bar: SELLABLE vs BREAKAGE
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: controller.isReadOnly ? null : () => controller.toggleBreakageMode(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !controller.isBreakageMode ? const Color(0xFF0F766E) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_rounded, color: !controller.isBreakageMode ? Colors.white : Colors.white54, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            "SELLABLE RETURN (STOCK OUT -)",
                            style: TextStyle(
                              color: !controller.isBreakageMode ? Colors.white : Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    onTap: controller.isReadOnly ? null : () => controller.toggleBreakageMode(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: controller.isBreakageMode ? const Color(0xFFEA580C) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_sweep_rounded, color: controller.isBreakageMode ? Colors.white : Colors.white54, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            "EXPIRY / BREAKAGE (DAMAGE OUT)",
                            style: TextStyle(
                              color: controller.isBreakageMode ? Colors.white : Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Selected Supplier Card or Search Field
          if (controller.selectedSupplier != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD97706), width: 1.2),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Color(0x33F59E0B), shape: BoxShape.circle),
                    child: const Icon(Icons.business_rounded, color: Color(0xFFFBBF24), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.selectedSupplier!.name.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                        Text(
                          "${controller.selectedSupplier!.city} | GST: ${controller.selectedSupplier!.gst} | Balance: ₹${controller.selectedSupplier!.opBal.toStringAsFixed(0)}",
                          style: const TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  if (!controller.isReadOnly)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                      onPressed: () => controller.clearSupplier(),
                    ),
                ],
              ),
            )
          else ...[
            TextField(
              controller: controller.supplierSearchC,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: "Type distributor / supplier name, city or GSTIN to search...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon: const Icon(Icons.person_search_rounded, color: Color(0xFFFBBF24), size: 18),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (_) => controller.notifySearch(),
            ),
            if (matchingSuppliers.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x33F59E0B)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: matchingSuppliers.length,
                  itemBuilder: (ctx, idx) {
                    final party = matchingSuppliers[idx];
                    return ListTile(
                      dense: true,
                      title: Text(party.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      subtitle: Text("${party.city} | GST: ${party.gst} | Group: ${party.group}", style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
                      onTap: () => controller.setSupplier(party),
                    );
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
