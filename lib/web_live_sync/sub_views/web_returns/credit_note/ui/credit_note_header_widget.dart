// FILE: lib/web_live_sync/sub_views/web_returns/credit_note/ui/credit_note_header_widget.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/credit_note_controller.dart';
import '../../../web_billing/quick_add_party_modal.dart';
import '../../../../../logic/gst_compliance_helper.dart';

class CreditNoteHeaderWidget extends StatelessWidget {
  final CreditNoteController controller;
  final PharoahWebManager webPh;

  const CreditNoteHeaderWidget({
    super.key,
    required this.controller,
    required this.webPh,
  });

  void _openQuickAddCustomer(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        onPartyCreated: (newParty) {
          controller.setCustomer(newParty);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final custQuery = controller.customerSearchC.text.trim().toLowerCase();
    final matchingParties = webPh.parties
        .where((p) {
          if (custQuery.isEmpty) return true;
          return p.name.toLowerCase().contains(custQuery) ||
              p.city.toLowerCase().contains(custQuery) ||
              p.gst.toLowerCase().contains(custQuery) ||
              p.phone.toLowerCase().contains(custQuery) ||
              p.group.toLowerCase().contains(custQuery);
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
              const Icon(Icons.person_pin_rounded, color: Color(0xFFF87171), size: 16),
              const SizedBox(width: 6),
              const Text(
                "CUSTOMER & POS INTELLIGENCE",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              if (!controller.isReadOnly && controller.selectedCustomer == null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                  onPressed: () => _openQuickAddCustomer(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
                  label: const Text("+ CUSTOMER",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (controller.selectedCustomer != null) ...[
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x55EF4444)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: const BoxDecoration(
                          color: Color(0x33EF4444),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.storefront_rounded,
                            color: Color(0xFFF87171), size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              controller.selectedCustomer!.name.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              "${controller.selectedCustomer!.city.isNotEmpty ? controller.selectedCustomer!.city : 'General'} • GST: ${controller.selectedCustomer!.gst.isNotEmpty ? controller.selectedCustomer!.gst : 'URP'}",
                              style: const TextStyle(color: Colors.white54, fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (!controller.isReadOnly)
                        IconButton(
                          tooltip: "Change Customer",
                          icon: const Icon(Icons.swap_horiz_rounded,
                              color: Colors.redAccent, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => controller.clearCustomer(),
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
                        "Bal: ₹${controller.selectedCustomer!.opBal.toStringAsFixed(0)}",
                        Colors.white70,
                        Colors.white10,
                      ),
                      if (controller.selectedCustomer!.dl.isNotEmpty)
                        _infoBadge(
                          "DL: ${controller.selectedCustomer!.dl}",
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
              controller: controller.customerSearchC,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: "Search customer by name, city, phone or GSTIN...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon:
                    const Icon(Icons.person_search_rounded, color: Color(0xFFF87171), size: 18),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (_) => controller.notifySearch(),
            ),
            if (matchingParties.isNotEmpty) ...[
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
                  itemCount: matchingParties.length,
                  itemBuilder: (ctx, idx) {
                    final party = matchingParties[idx];
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
                      onTap: () => controller.setCustomer(party),
                    );
                  },
                ),
              ),
            ],
          ],

          const SizedBox(height: 10),
          // Rule 53(1A) Original Invoice Reference
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: controller.origBillNoC,
                  readOnly: controller.isReadOnly,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: "ORIG. INVOICE NO (RULE 53)",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                    prefixIcon: const Icon(Icons.receipt_long_rounded, color: Color(0xFF38BDF8), size: 15),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                          if (picked != null) controller.setOrigBillDate(picked, webPh: webPh);
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
                        const Icon(Icons.event_note_rounded, color: Color(0xFF38BDF8), size: 15),
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
                color: const Color(0x2238BDF8),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: const Color(0x4438BDF8)),
              ),
              child: Text(
                "Refs: ${originSummary.footerRefText}",
                style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 9.5, fontWeight: FontWeight.bold),
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
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24), size: 15),
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
                      child: const Text("SWITCH", style: TextStyle(color: Color(0xFFFBBF24), fontSize: 10, fontWeight: FontWeight.w900)),
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
