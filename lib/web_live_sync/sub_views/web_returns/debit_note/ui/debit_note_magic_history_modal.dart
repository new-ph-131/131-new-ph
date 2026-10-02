// FILE: lib/web_live_sync/sub_views/web_returns/debit_note/ui/debit_note_magic_history_modal.dart
// ignore_for_file: prefer_const_constructors, unnecessary_const

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../web_models.dart';
import '../../../../pharoah_web_manager.dart';
import '../mechanism/debit_note_mechanism.dart';

class DebitNoteMagicHistoryModal extends StatelessWidget {
  final Medicine medicine;
  final Party supplier;
  final PharoahWebManager webPh;
  final Function(Map<String, dynamic>? selectedHistory) onSelect;

  const DebitNoteMagicHistoryModal({
    super.key,
    required this.medicine,
    required this.supplier,
    required this.webPh,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final history = DebitNoteMechanism.fetchSupplierPurchaseHistory(
      webPh: webPh,
      supplierId: supplier.id,
      supplierName: supplier.name,
      medicineId: medicine.id,
      medicineName: medicine.name,
    );

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFD97706), width: 1.5),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0x33F59E0B),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history_edu_rounded, color: Color(0xFFFBBF24), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "MAGIC INWARD PURCHASE RECALL",
                  style: TextStyle(color: Color(0xFFFBBF24), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                Text(
                  "${medicine.name} (${medicine.packing})",
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
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
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.business_rounded, color: Color(0xFFF59E0B), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Supplier: ${supplier.name} • Tap any past inward bill to auto-fill exact purchase rate & batch",
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Flexible(
              child: history.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_toggle_off_rounded, size: 40, color: Colors.white.withAlpha(50)),
                            const SizedBox(height: 10),
                            const Text(
                              "No past purchase records found from this supplier for this medicine.\nYou can enter the rate and batch manually.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white38, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: history.length,
                      itemBuilder: (c, i) {
                        final h = history[i];
                        DateTime dt = h['date'] as DateTime;
                        String dateStr = DateFormat('dd/MM/yyyy').format(dt);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            leading: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: const BoxDecoration(
                                color: Color(0x33D97706),
                                borderRadius: BorderRadius.all(Radius.circular(6)),
                              ),
                              child: Text(
                                h['billNo'],
                                style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Row(
                              children: [
                                Text("Batch: ${h['batch']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(width: 8),
                                Text("Exp: ${h['exp']}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                const Spacer(),
                                Text(
                                  "Pur. Rate: ₹${(h['purchaseRate'] as double).toStringAsFixed(2)}",
                                  style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 12.5),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              "Date: $dateStr • Inward Qty: ${h['qty'].toInt()} + ${h['free'].toInt()} Free • MRP: ₹${(h['mrp'] as double).toStringAsFixed(2)} • GST: ${h['gst'].toInt()}%",
                              style: const TextStyle(color: Colors.white38, fontSize: 10),
                            ),
                            trailing: const Icon(Icons.touch_app_rounded, color: Color(0xFFFBBF24), size: 18),
                            onTap: () {
                              Navigator.pop(context);
                              onSelect(h);
                            },
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  onSelect(null);
                },
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text(
                  "NOT IN HISTORY? ENTER RETURN MANUALLY",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
