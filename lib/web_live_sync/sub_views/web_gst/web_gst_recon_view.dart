// FILE: lib/web_live_sync/sub_views/web_gst/web_gst_recon_view.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../pharoah_web_manager.dart';

class WebGstReconView extends StatefulWidget {
  final PharoahWebManager webPh;
  final VoidCallback onBack;

  const WebGstReconView({super.key, required this.webPh, required this.onBack});

  @override
  State<WebGstReconView> createState() => _WebGstReconViewState();
}

class _WebGstReconViewState extends State<WebGstReconView> {
  DateTime selectedMonth = DateTime.now();
  String filterStatus = "ALL"; // ALL, MATCHED, PENDING

  @override
  Widget build(BuildContext context) {
    final list = widget.webPh.purchases.where((p) =>
      p.date.month == selectedMonth.month && p.date.year == selectedMonth.year
    ).toList();

    int matchedCount = list.where((p) => p.gstStatus == "Matched").length;
    int pendingCount = list.length - matchedCount;

    final displayList = list.where((p) {
      if (filterStatus == "MATCHED") return p.gstStatus == "Matched";
      if (filterStatus == "PENDING") return p.gstStatus != "Matched";
      return true;
    }).toList();

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () async {
                  final p = await showDatePicker(context: context, initialDate: selectedMonth, firstDate: DateTime(2020), lastDate: DateTime(2035));
                  if (p != null) setState(() => selectedMonth = p);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 8),
                      Text("MONTH: ${DateFormat('MMMM yyyy').format(selectedMonth).toUpperCase()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              _filterTag("ALL (${list.length})", filterStatus == "ALL", () => setState(() => filterStatus = "ALL")),
              const SizedBox(width: 6),
              _filterTag("MATCHED ($matchedCount)", filterStatus == "MATCHED", () => setState(() => filterStatus = "MATCHED"), color: Colors.green),
              const SizedBox(width: 6),
              _filterTag("PENDING ($pendingCount)", filterStatus == "PENDING", () => setState(() => filterStatus = "PENDING"), color: Colors.orange),
            ],
          ),
          const SizedBox(height: 16),

          if (displayList.isEmpty)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("No purchases in this month matching filter.", style: TextStyle(color: Colors.white38))))
          else
            ListView.builder(
              shrinkWrap: true,
              itemCount: displayList.length,
              itemBuilder: (ctx, i) {
                final p = displayList[i];
                bool isMatched = p.gstStatus == "Matched";

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(10), border: Border.all(color: isMatched ? const Color(0x3310B981) : Colors.white10)),
                  child: ListTile(
                    dense: true,
                    title: Text(p.distributorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text("Bill No: ${p.billNo} • Date: ${DateFormat('dd/MM/yyyy').format(p.date)} • Amount: ₹${p.totalAmount.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(isMatched ? "MATCHED (2A)" : "PENDING", style: TextStyle(color: isMatched ? Colors.greenAccent : Colors.orangeAccent, fontSize: 9.5, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 8),
                        Switch(
                          value: isMatched,
                          activeColor: const Color(0xFF10B981),
                          onChanged: (val) {
                            setState(() {
                              p.gstStatus = val ? "Matched" : "Pending";
                            });
                            widget.webPh.pushUpdatedDataToCloud();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _filterTag(String label, bool isSelected, VoidCallback onTap, {Color? color}) {
    Color activeC = color ?? const Color(0xFF2563EB);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: isSelected ? activeC : Colors.black26, borderRadius: BorderRadius.circular(6), border: Border.all(color: isSelected ? activeC : Colors.white12)),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontSize: 9.5, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
