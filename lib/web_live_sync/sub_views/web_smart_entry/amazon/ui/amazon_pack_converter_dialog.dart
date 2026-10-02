import 'package:flutter/material.dart';
import '../models/amazon_bill_model.dart';

class AmazonPackConverterDialog extends StatefulWidget {
  final AmazonItem item;
  final Function({
    required String targetPack,
    required int factor,
    required double newQty,
    required double newRate,
    required double newMrp,
    required bool saveMasterAsStrip,
  }) onApply;

  const AmazonPackConverterDialog({
    super.key,
    required this.item,
    required this.onApply,
  });

  @override
  State<AmazonPackConverterDialog> createState() => _AmazonPackConverterDialogState();
}

class _AmazonPackConverterDialogState extends State<AmazonPackConverterDialog> {
  int boxMultiplier = 10;
  String unitPerStripStr = "10";
  String targetPack = "1*10";
  bool isSplitToSingleStrip = true;
  bool saveMasterAsStrip = true;
  String originalPackStr = "";

  @override
  void initState() {
    super.initState();
    originalPackStr = widget.item.originalPack.isNotEmpty ? widget.item.originalPack : widget.item.pack;
    String pStr = originalPackStr.trim().toUpperCase();

    var tripleMatch = RegExp(r'^(\d+)[\*xX]1[\*xX](\d+)$').firstMatch(pStr);
    if (tripleMatch != null) {
      boxMultiplier = int.tryParse(tripleMatch.group(1)!) ?? 10;
      unitPerStripStr = tripleMatch.group(2)!;
    } else {
      var standardMatch = RegExp(r'^(\d+)[\*xX](\d+([A-Za-z]+)?)$').firstMatch(pStr);
      if (standardMatch != null) {
        boxMultiplier = int.tryParse(standardMatch.group(1)!) ?? 1;
        unitPerStripStr = standardMatch.group(2)!;
      } else {
        boxMultiplier = widget.item.conversionFactor > 1 ? widget.item.conversionFactor : 1;
        unitPerStripStr = "10";
      }
    }

    targetPack = "1*$unitPerStripStr";
    isSplitToSingleStrip = boxMultiplier > 1;
    saveMasterAsStrip = true;
  }

  @override
  Widget build(BuildContext context) {
    double baseBoxQty = widget.item.conversionFactor > 1 && widget.item.originalPack.isNotEmpty
        ? (widget.item.qty / widget.item.conversionFactor)
        : widget.item.qty;
    double baseBoxRate = widget.item.conversionFactor > 1 && widget.item.originalPack.isNotEmpty
        ? (widget.item.rate * widget.item.conversionFactor)
        : widget.item.rate;
    double baseBoxMrp = widget.item.conversionFactor > 1 && widget.item.originalPack.isNotEmpty
        ? (widget.item.mrp * widget.item.conversionFactor)
        : widget.item.mrp;

    int activeFactor = isSplitToSingleStrip ? boxMultiplier : 1;
    double calculatedQty = baseBoxQty * activeFactor;
    double calculatedRate = baseBoxRate / activeFactor;
    double calculatedMrp = baseBoxMrp / activeFactor;

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
            decoration: const BoxDecoration(color: Color(0x3310B981), shape: BoxShape.circle),
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
                    Text("Invoiced Box Pack: $originalPackStr", style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold)),
                    Text("Invoiced Qty: ${baseBoxQty.toInt()} Box", style: const TextStyle(color: Colors.orangeAccent, fontSize: 11.5, fontWeight: FontWeight.bold)),
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
                title: Text("Split into Single Strips ($targetPack) [Recommended for $originalPackStr]", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text("1 Box ($originalPackStr) contains $boxMultiplier strips. Multiplies qty by $boxMultiplier and divides rate by $boxMultiplier.", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                onChanged: (v) {
                  setState(() {
                    isSplitToSingleStrip = true;
                    saveMasterAsStrip = true;
                  });
                },
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: isSplitToSingleStrip,
                activeColor: const Color(0xFF10B981),
                title: Text("Keep Entire Box ($originalPackStr)", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: const Text("Do not split. Keep box as 1 unit.", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                onChanged: (v) {
                  setState(() {
                    isSplitToSingleStrip = false;
                    saveMasterAsStrip = false;
                  });
                },
              ),
              const Divider(color: Colors.white10, height: 22),
              const Text(
                "2. Master Catalog & Billing Rate Preference:",
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              RadioListTile<bool>(
                value: true,
                groupValue: saveMasterAsStrip,
                activeColor: const Color(0xFF38BDF8),
                title: Text("Save Master as STRIP ($targetPack Pricing)", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: const Text("Sale bills will automatically use per-strip MRP and Rate.", style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10)),
                onChanged: isSplitToSingleStrip ? (v) => setState(() => saveMasterAsStrip = v!) : null,
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: saveMasterAsStrip,
                activeColor: const Color(0xFF38BDF8),
                title: const Text("Save Master as BOX Pricing", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: const Text("Catalog keeps original box MRP & Rate.", style: TextStyle(color: Colors.white54, fontSize: 10)),
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
                          "MASTER & INVENTORY EFFECT (${isSplitToSingleStrip ? targetPack : originalPackStr}):",
                          style: const TextStyle(color: Color(0xFF34D399), fontSize: 9.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _calcDetail("INVENTORY STOCK", "${calculatedQty.toInt()} Units", Colors.greenAccent),
                        _calcDetail("PUR. RATE", "₹${calculatedRate.toStringAsFixed(2)}", Colors.white),
                        _calcDetail("MRP IN BILLING", "₹${calculatedMrp.toStringAsFixed(2)}", Colors.cyanAccent),
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
              targetPack: isSplitToSingleStrip ? targetPack : originalPackStr,
              factor: activeFactor,
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
