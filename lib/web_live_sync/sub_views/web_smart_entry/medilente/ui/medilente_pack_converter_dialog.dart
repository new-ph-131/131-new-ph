import 'package:flutter/material.dart';
import '../models/medilente_bill_model.dart';

class MedilentePackConverterDialog extends StatefulWidget {
  final MedilenteItem item;
  final Function({
    required String targetPack,
    required int factor,
    required double newQty,
    required double newRate,
    required double newMrp,
    required bool saveMasterAsStrip,
  }) onApply;

  const MedilentePackConverterDialog({
    super.key,
    required this.item,
    required this.onApply,
  });

  @override
  State<MedilentePackConverterDialog> createState() => _MedilentePackConverterDialogState();
}

class _MedilentePackConverterDialogState extends State<MedilentePackConverterDialog> {
  int factor = 10;
  String targetPack = "1*10";
  bool isSplitToSingleStrip = true;
  bool saveMasterAsStrip = true; // True = Strip price in Master, False = Box price in Master

  @override
  void initState() {
    super.initState();
    if (widget.item.pack == "10*10" || widget.item.originalPack == "10*10") {
      factor = 10;
      targetPack = "1*10";
      isSplitToSingleStrip = true;
      saveMasterAsStrip = true;
    } else {
      factor = widget.item.conversionFactor > 0 ? widget.item.conversionFactor : 1;
      targetPack = widget.item.pack;
      isSplitToSingleStrip = factor > 1;
      saveMasterAsStrip = isSplitToSingleStrip;
    }
  }

  @override
  Widget build(BuildContext context) {
    double baseQty = widget.item.originalPack.isNotEmpty && widget.item.conversionFactor > 1
        ? (widget.item.qty / widget.item.conversionFactor)
        : widget.item.qty;
    double baseRate = widget.item.originalPack.isNotEmpty && widget.item.conversionFactor > 1
        ? (widget.item.rate * widget.item.conversionFactor)
        : widget.item.rate;
    double baseMrp = widget.item.originalPack.isNotEmpty && widget.item.conversionFactor > 1
        ? ((widget.item.netMrp > 0 ? widget.item.netMrp : widget.item.oldMrp) * widget.item.conversionFactor)
        : (widget.item.netMrp > 0 ? widget.item.netMrp : widget.item.oldMrp);

    double calculatedQty = isSplitToSingleStrip ? (baseQty * factor) : baseQty;
    double calculatedRate = isSplitToSingleStrip ? (baseRate / factor) : baseRate;
    double calculatedMrp = isSplitToSingleStrip ? (baseMrp / factor) : baseMrp;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF10B981), width: 1.5),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0x3310B981),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.call_split_rounded, color: Color(0xFF34D399), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "PHARMA UNIT & CONVERSION SPLITTER",
                  style: TextStyle(color: Color(0xFF34D399), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                Text(
                  widget.item.productName,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Invoiced Box Pack: ${widget.item.originalPack.isNotEmpty ? widget.item.originalPack : '10*10'}",
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Invoiced Qty: ${baseQty.toInt()} Box",
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "1. Choose Inward Unit:",
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              RadioListTile<bool>(
                value: true,
                groupValue: isSplitToSingleStrip,
                activeColor: const Color(0xFF10B981),
                title: const Text("Split into Strips (1*10) [Recommended]", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: const Text("1 Box (10*10) splits into 10 Strips.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                onChanged: (v) {
                  setState(() {
                    isSplitToSingleStrip = true;
                    saveMasterAsStrip = true;
                    factor = 10;
                    targetPack = "1*10";
                  });
                },
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: isSplitToSingleStrip,
                activeColor: const Color(0xFF10B981),
                title: const Text("Keep Entire Box (10*10)", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: const Text("Do not split. Keep box intact.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                onChanged: (v) {
                  setState(() {
                    isSplitToSingleStrip = false;
                    saveMasterAsStrip = false;
                    factor = 1;
                    targetPack = "10*10";
                  });
                },
              ),
              const Divider(color: Colors.white10, height: 20),
              const Text(
                "2. Master Catalog & Billing Rate Preference:",
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              RadioListTile<bool>(
                value: true,
                groupValue: saveMasterAsStrip,
                activeColor: const Color(0xFF38BDF8),
                title: const Text("Save Master as STRIP (1*10 Pricing)", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: const Text("Sale bills will automatically use per-strip MRP and Rate. Prevents high box billing error!", style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10)),
                onChanged: isSplitToSingleStrip ? (v) => setState(() => saveMasterAsStrip = v!) : null,
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: saveMasterAsStrip,
                activeColor: const Color(0xFF38BDF8),
                title: const Text("Save Master as BOX (10*10 Pricing)", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: const Text("Catalog keeps original high box MRP & Rate.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                onChanged: (v) => setState(() => saveMasterAsStrip = v!),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x3310B981)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.flash_on_rounded, color: Color(0xFF34D399), size: 16),
                        const SizedBox(width: 6),
                        Text(
                          "MASTER & INVENTORY EFFECT (${saveMasterAsStrip ? '1*10 STRIP' : '10*10 BOX'}):",
                          style: const TextStyle(color: Color(0xFF34D399), fontSize: 9.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _calcDetail("INVENTORY STOCK", "${calculatedQty.toInt()} Units", Colors.greenAccent),
                        _calcDetail("PUR. RATE", "₹${(saveMasterAsStrip ? (baseRate / 10) : baseRate).toStringAsFixed(2)}", Colors.white),
                        _calcDetail("MRP IN BILLING", "₹${(saveMasterAsStrip ? (baseMrp / 10) : baseMrp).toStringAsFixed(2)}", Colors.cyanAccent),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            widget.onApply(
              targetPack: isSplitToSingleStrip ? "1*10" : "10*10",
              factor: isSplitToSingleStrip ? 10 : 1,
              newQty: calculatedQty,
              newRate: calculatedRate,
              newMrp: calculatedMrp,
              saveMasterAsStrip: saveMasterAsStrip,
            );
            Navigator.pop(context);
          },
          child: const Text("APPLY & SAVE SETTING", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _calcDetail(String label, String val, Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w900)),
      ],
    );
  }
}
