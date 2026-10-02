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
  int unitPerStrip = 10;
  String targetPack = "1*10";
  bool isSplitToSingleStrip = true;
  bool saveMasterAsStrip = true;

  @override
  void initState() {
    super.initState();
    String pStr = widget.item.originalPack.isNotEmpty ? widget.item.originalPack : widget.item.pack;
    var match = RegExp(r'^(\d+)[\*xX](\d+)$').firstMatch(pStr);
    if (match != null) {
      boxMultiplier = int.tryParse(match.group(1)!) ?? 10;
      unitPerStrip = int.tryParse(match.group(2)!) ?? 10;
    } else {
      boxMultiplier = widget.item.conversionFactor > 1 ? widget.item.conversionFactor : 10;
      unitPerStrip = 10;
    }

    targetPack = "1*$unitPerStrip";
    isSplitToSingleStrip = boxMultiplier > 1;
    saveMasterAsStrip = isSplitToSingleStrip;
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
        side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: Color(0x33F59E0B), shape: BoxShape.circle),
            child: const Icon(Icons.call_split_rounded, color: Color(0xFFFBBF24), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("UNIT CONVERSION SPLITTER", style: TextStyle(color: Color(0xFFFBBF24), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 1)),
                Text(widget.item.productName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
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
                  Text("Pack: ${widget.item.pack}", style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  Text("Qty: ${baseBoxQty.toInt()}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 11.5, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            RadioListTile<bool>(
              value: true,
              groupValue: isSplitToSingleStrip,
              activeColor: const Color(0xFFF59E0B),
              title: Text("Split into Single Strips ($targetPack)", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              onChanged: (v) => setState(() => isSplitToSingleStrip = true),
            ),
            RadioListTile<bool>(
              value: false,
              groupValue: isSplitToSingleStrip,
              activeColor: const Color(0xFFF59E0B),
              title: Text("Keep as Box (${widget.item.originalPack})", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              onChanged: (v) => setState(() => isSplitToSingleStrip = false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black),
          onPressed: () {
            widget.onApply(
              targetPack: isSplitToSingleStrip ? targetPack : widget.item.originalPack,
              factor: activeFactor,
              newQty: calculatedQty,
              newRate: calculatedRate,
              newMrp: calculatedMrp,
              saveMasterAsStrip: saveMasterAsStrip,
            );
            Navigator.pop(context);
          },
          child: const Text("APPLY", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
