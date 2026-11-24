// FILE: lib/web_live_sync/sub_views/web_returns/debit_note/ui/debit_note_header_widget.dart
// ignore_for_file: prefer_const_constructors, unnecessary_const

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../../../../web_app_date_logic.dart';
import '../../../../../logic/gst_compliance_helper.dart';
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
    // 🔍 ROBUST PARTY SEARCH: Accessible to all party master suppliers with instant preview
    final matchingSuppliers = webPh.parties
        .where((p) {
          if (suppQuery.isEmpty) return true;
          return p.name.toLowerCase().contains(suppQuery) ||
                 p.city.toLowerCase().contains(suppQuery) ||
                 p.gst.toLowerCase().contains(suppQuery) ||
                 p.phone.toLowerCase().contains(suppQuery) ||
                 p.group.toLowerCase().contains(suppQuery);
        })
        .take(30)
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
                          final fyStart = WebAppDateLogic.getFYStart(webPh.financialYear);
                          final fyEnd = WebAppDateLogic.getFYEnd(webPh.financialYear);
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: GstComplianceHelper.clampPickerDate(controller.selectedDate, fyStart, fyEnd),
                            firstDate: fyStart,
                            lastDate: fyEnd,
                          );
                          if (picked != null) controller.setDate(picked, webPh: webPh);
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
          const SizedBox(height: 10),
          // Cash/Credit Mode & Rule 53(1A) Reference Row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: controller.isReadOnly ? null : () => controller.setPaymentMode("CREDIT"),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: controller.paymentMode == "CREDIT" ? const Color(0xFFD97706) : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text("CREDIT", textAlign: TextAlign.center, style: TextStyle(color: controller.paymentMode == "CREDIT" ? Colors.white : Colors.white54, fontSize: 9.5, fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: controller.isReadOnly ? null : () => controller.setPaymentMode("CASH"),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: controller.paymentMode == "CASH" ? const Color(0xFF059669) : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text("CASH REFUND", textAlign: TextAlign.center, style: TextStyle(color: controller.paymentMode == "CASH" ? Colors.white : Colors.white54, fontSize: 9.5, fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: controller.origBillNoC,
                  readOnly: controller.isReadOnly,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5),
                  decoration: InputDecoration(
                    labelText: "ORIG. PUR BILL NO (RULE 53)",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 8.5),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          controller.origBillDate != null
                              ? "Orig: ${DateFormat('dd/MM/yy').format(controller.origBillDate!)}"
                              : "ORIG. BILL DATE",
                          style: TextStyle(color: controller.origBillDate != null ? Colors.white : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const Icon(Icons.event_note_rounded, color: Color(0xFFFBBF24), size: 15),
                      ],
                    ),
                  ),
                ),
              ),
              if (GstComplianceHelper.isCommercialNoteAllowed(webPh.appConfig) || controller.isCommercial) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: controller.isCommercial ? const Color(0x44F59E0B) : Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: controller.isCommercial ? const Color(0xFFF59E0B) : Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        controller.isCommercial ? "COMMERCIAL (CCN-)" : "GST NOTE",
                        style: TextStyle(
                          color: controller.isCommercial ? const Color(0xFFFBBF24) : Colors.white70,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Switch.adaptive(
                        value: controller.isCommercial,
                        activeColor: const Color(0xFFF59E0B),
                        onChanged: (controller.isReadOnly || !GstComplianceHelper.isCommercialNoteAllowed(webPh.appConfig))
                            ? null
                            : (val) => controller.toggleCommercial(val, webPh: webPh),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (controller.isSection34Expired) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0x33F59E0B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: Text(
                "Sec 34(2) Cutoff (${DateFormat('dd/MM/yyyy').format(GstComplianceHelper.getSection34CutoffDate(controller.origBillDate!))}) Crossed — Commercial Note (Without GST) recommended.",
                style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 10.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
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
