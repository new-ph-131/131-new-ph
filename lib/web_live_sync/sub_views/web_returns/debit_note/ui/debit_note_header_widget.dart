// FILE: lib/web_live_sync/sub_views/web_returns/debit_note/ui/debit_note_header_widget.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/debit_note_controller.dart';
import '../../../web_billing/quick_add_party_modal.dart';
import '../../../../../logic/gst_compliance_helper.dart';

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
    final supQuery = controller.supplierSearchC.text.trim().toLowerCase();
    final matchingSuppliers = webPh.parties
        .where((p) {
          if (supQuery.isEmpty) return true;
          return p.name.toLowerCase().contains(supQuery) ||
              p.city.toLowerCase().contains(supQuery) ||
              p.gst.toLowerCase().contains(supQuery) ||
              p.phone.toLowerCase().contains(supQuery) ||
              p.group.toLowerCase().contains(supQuery);
        })
        .take(30)
        .toList();

    final originSummary = GstComplianceHelper.summarizeOriginInvoices(
      controller.items,
      fallbackBillNo: controller.origBillNoC.text,
      fallbackDate: controller.origBillDate,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.business_rounded, color: Color(0xFFFBBF24), size: 16),
              const SizedBox(width: 6),
              const Text(
                "SUPPLIER & POS INTELLIGENCE",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              if (!controller.isReadOnly && controller.selectedSupplier == null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFBBF24),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                  onPressed: () => _openQuickAddSupplier(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
                  label: const Text("+ SUPPLIER",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (controller.selectedSupplier != null) ...[
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x55F59E0B)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: const BoxDecoration(
                          color: Color(0x33F59E0B),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.local_shipping_rounded,
                            color: Color(0xFFFBBF24), size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              controller.selectedSupplier!.name.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              "${controller.selectedSupplier!.city.isNotEmpty ? controller.selectedSupplier!.city : 'General'} • GST: ${controller.selectedSupplier!.gst.isNotEmpty ? controller.selectedSupplier!.gst : 'URP'}",
                              style: const TextStyle(color: Colors.white54, fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (!controller.isReadOnly)
                        IconButton(
                          tooltip: "Change Supplier",
                          icon: const Icon(Icons.swap_horiz_rounded,
                              color: Colors.redAccent, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => controller.clearSupplier(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _infoBadge(
                        "POS ${controller.posCode} • ${controller.isLocal ? 'INTRA (CGST+SGST)' : 'INTER (IGST)'}",
                        controller.isLocal
                            ? const Color(0xFF34D399)
                            : const Color(0xFF38BDF8),
                        controller.isLocal
                            ? const Color(0x2210B981)
                            : const Color(0x2238BDF8),
                      ),
                      _infoBadge(
                        "Bal: ₹${controller.selectedSupplier!.opBal.toStringAsFixed(0)}",
                        Colors.white70,
                        Colors.white10,
                      ),
                      if (controller.selectedSupplier!.dlNo.isNotEmpty)
                        _infoBadge(
                          "DL: ${controller.selectedSupplier!.dlNo}",
                          Colors.white54,
                          Colors.white10,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            TextField(
              controller: controller.supplierSearchC,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: "Search supplier by name, city, phone or GSTIN...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon:
                    const Icon(Icons.person_search_rounded, color: Color(0xFFFBBF24), size: 18),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  border: Border.all(color: Colors.white12),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: matchingSuppliers.length,
                  itemBuilder: (ctx, idx) {
                    final party = matchingSuppliers[idx];
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(party.name,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                      subtitle: Text(
                        "${party.city} • GST: ${party.gst.isNotEmpty ? party.gst : 'URP'}",
                        style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                      ),
                      onTap: () => controller.setSupplier(party),
                    );
                  },
                ),
              ),
            ],
          ],

          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: controller.origBillNoC,
                  readOnly: controller.isReadOnly,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: "SUPPLIER INVOICE NO (R53)",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                    prefixIcon: const Icon(Icons.receipt_long_rounded,
                        color: Color(0xFFFBBF24), size: 15),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: controller.isReadOnly
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: GstComplianceHelper.clampPickerDate(
                              controller.origBillDate ?? controller.selectedDate,
                              DateTime(2017, 7, 1),
                              controller.selectedDate,
                            ),
                            firstDate: DateTime(2017, 7, 1),
                            lastDate: controller.selectedDate,
                          );
                          if (picked != null) {
                            controller.setOrigBillDate(picked, webPh: webPh);
                          }
                        },
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            controller.origBillDate != null
                                ? DateFormat('dd/MM/yy').format(controller.origBillDate!)
                                : "ORIG. DATE",
                            style: TextStyle(
                              color: controller.origBillDate != null
                                  ? Colors.white
                                  : Colors.white54,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.event_note_rounded,
                            color: Color(0xFFFBBF24), size: 15),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (originSummary.uniqueCount > 1) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0x22F59E0B),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: const Color(0x44F59E0B)),
              ),
              child: Text(
                "Refs: ${originSummary.footerRefText}",
                style: const TextStyle(
                    color: Color(0xFFFDE68A), fontSize: 9.5, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          if (controller.isSection34Expired && controller.expiredOriginDate != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0x33F59E0B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFFBBF24), size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Sec 34(2) cutoff (${DateFormat('dd/MM/yyyy').format(GstComplianceHelper.getSection34CutoffDate(controller.expiredOriginDate!))}) crossed — Commercial Note recommended.",
                      style: const TextStyle(
                        color: Color(0xFFFDE68A),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (!controller.isReadOnly &&
                      !controller.isCommercial &&
                      GstComplianceHelper.isCommercialNoteAllowed(webPh.appConfig))
                    TextButton(
                      onPressed: () => controller.toggleCommercial(true, webPh: webPh),
                      child: const Text("SWITCH",
                          style: TextStyle(
                              color: Color(0xFFFBBF24),
                              fontSize: 10,
                              fontWeight: FontWeight.w900)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoBadge(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 9.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}
