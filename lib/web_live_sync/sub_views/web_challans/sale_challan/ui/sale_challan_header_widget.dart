// FILE: lib/web_live_sync/sub_views/web_challans/sale_challan/ui/sale_challan_header_widget.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/app_date_logic.dart';
import '../../../../pharoah_web_manager.dart';
import '../logic/sale_challan_controller.dart';
import '../../../web_billing/quick_add_party_modal.dart';

class SaleChallanHeaderWidget extends StatelessWidget {
  final SaleChallanController controller;
  final PharoahWebManager webPh;

  const SaleChallanHeaderWidget({
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
    final matchingParties = custQuery.isEmpty
        ? <Party>[]
        : webPh.parties
            .where((p) =>
                p.group == "Sundry Debtors" &&
                (p.name.toLowerCase().contains(custQuery) || p.city.toLowerCase().contains(custQuery)))
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
                  controller: controller.challanNoC,
                  readOnly: true,
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2DD4BF), fontSize: 13),
                  decoration: InputDecoration(
                    labelText: "CHALLAN NUMBER",
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
                            firstDate: AppDateLogic.getFYStart(webPh.financialYear),
                            lastDate: AppDateLogic.getFYEnd(webPh.financialYear),
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
                            const Text("DISPATCH DATE", style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
                            Text(
                              DateFormat('dd/MM/yyyy').format(controller.selectedDate),
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Icon(Icons.calendar_month_rounded, color: Color(0xFF2DD4BF), size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              if (!controller.isReadOnly) ...[
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _openQuickAddCustomer(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                  label: const Text("+ CUSTOMER", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          if (controller.selectedCustomer != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2DD4BF), width: 1.2),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Color(0x332DD4BF), shape: BoxShape.circle),
                    child: const Icon(Icons.person_rounded, color: Color(0xFF2DD4BF), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.selectedCustomer!.name.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                        Text(
                          "${controller.selectedCustomer!.city} | GST: ${controller.selectedCustomer!.gst} | State: ${controller.selectedCustomer!.state}",
                          style: const TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  if (!controller.isReadOnly)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                      onPressed: () => controller.clearCustomer(),
                    ),
                ],
              ),
            )
          else ...[
            TextField(
              controller: controller.customerSearchC,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: "Search Customer by Name or City...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon: const Icon(Icons.person_search_rounded, color: Color(0xFF2DD4BF), size: 18),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                  border: Border.all(color: const Color(0x332DD4BF)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: matchingParties.length,
                  itemBuilder: (ctx, idx) {
                    final party = matchingParties[idx];
                    return ListTile(
                      dense: true,
                      title: Text(party.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      subtitle: Text("${party.city} | GST: ${party.gst}", style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
                      onTap: () => controller.setCustomer(party),
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
