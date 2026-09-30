// FILE: lib/web_live_sync/sub_views/web_billing/web_batch_lookup_dialog.dart

import 'package:flutter/material.dart';
import '../../web_models.dart';
import '../../web_expiry_master.dart';

class WebBatchLookupDialog extends StatefulWidget {
  final Medicine medicine;
  final List<BatchInfo> batches;
  final bool prioritizeExpired;

  const WebBatchLookupDialog({
    super.key,
    required this.medicine,
    required this.batches,
    this.prioritizeExpired = false,
  });

  @override
  State<WebBatchLookupDialog> createState() => _WebBatchLookupDialogState();
}

class _WebBatchLookupDialogState extends State<WebBatchLookupDialog> {
  DateTime _parseExpiry(String exp) {
    try {
      final parts = exp.split('/');
      int m = int.parse(parts[0]);
      int y = 2000 + int.parse(parts[1]);
      return DateTime(y, m + 1, 0);
    } catch (_) {
      return DateTime(2100);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedBatches = List<BatchInfo>.from(widget.batches);
    sortedBatches.sort((a, b) => _parseExpiry(a.exp).compareTo(_parseExpiry(b.exp)));

    double grandTotalQty = widget.batches.fold(0.0, (sum, b) => sum + b.qty);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 600 ? 560.0 : (screenWidth * 0.94);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.white12),
      ),
      backgroundColor: const Color(0xFF1E293B),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: const BoxDecoration(
              color: Color(0x2622D3EE),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.layers_rounded, color: Colors.cyanAccent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.medicine.name,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "Pack: ${widget.medicine.packing} • Select batch to auto-fill prices",
                  style: const TextStyle(color: Colors.white54, fontSize: 9.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Expanded(flex: 3, child: Text("BATCH NO", style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text("EXPIRY", style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text("MRP", textAlign: TextAlign.right, style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text("RATE A", textAlign: TextAlign.right, style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold))),
                  Expanded(flex: 3, child: Text("STOCK", textAlign: TextAlign.right, style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: sortedBatches.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(25),
                      child: Text(
                        "No batch history recorded for this medicine.\nClick 'Manual New Batch' below to enter details.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: sortedBatches.length,
                      itemBuilder: (context, idx) {
                        final b = sortedBatches[idx];
                        final status = WebExpiryMaster.getStatus(b.exp);
                        final statusColor = WebExpiryMaster.getStatusColor(b.exp);
                        String statusLabel = "Safe";
                        if (status == ExpiryStatus.expired) statusLabel = "Expired";
                        if (status == ExpiryStatus.nearExpiry) statusLabel = "Near Exp";

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0x0DFFFFFF)),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            onTap: () => Navigator.pop(context, b),
                            title: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(b.batch, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    children: [
                                      Text(b.exp, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10.5)),
                                      const SizedBox(width: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                        decoration: BoxDecoration(color: statusColor.withAlpha(40), borderRadius: BorderRadius.circular(3)),
                                        child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 6.5, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text("₹${b.mrp.toStringAsFixed(2)}", textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text("₹${b.rateA.toStringAsFixed(2)}", textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text("${b.qty.toInt()} Qty", textAlign: TextAlign.right, style: TextStyle(color: b.qty > 0 ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10.5)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("TOTAL INVENTORY STOCK", style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
                      Text(
                        "${grandTotalQty.toInt()} Units",
                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context, "MANUAL"),
                    icon: const Icon(Icons.add_circle_outline, size: 14, color: Colors.orangeAccent),
                    label: const Text("Manual New Batch", style: TextStyle(color: Colors.orangeAccent, fontSize: 10.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
