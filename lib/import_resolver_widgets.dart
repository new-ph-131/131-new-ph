import 'package:flutter/material.dart';
import 'models.dart';

class ImportResolver {
  static Future<Party?> showPartyFixer(BuildContext context, String name, String gstin) async {
    final nameC = TextEditingController(text: name);
    final gstC = TextEditingController(text: gstin);
    final cityC = TextEditingController();

    return showDialog<Party>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Create New Party"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameC, decoration: const InputDecoration(labelText: "Party Name")),
          TextField(controller: gstC, decoration: const InputDecoration(labelText: "GSTIN")),
          TextField(controller: cityC, decoration: const InputDecoration(labelText: "City")),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () => Navigator.pop(c, Party(id: DateTime.now().toString(), name: nameC.text.toUpperCase(), gst: gstC.text.toUpperCase(), city: cityC.text.toUpperCase())), child: const Text("SAVE")),
        ],
      ),
    );
  }

  static Future<Medicine?> showItemFixer(BuildContext context, String name, double rate, double gst) async {
    final nameC = TextEditingController(text: name);
    return showDialog<Medicine>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Create New Product"),
        content: TextField(controller: nameC, decoration: const InputDecoration(labelText: "Product Name")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () => Navigator.pop(c, Medicine(id: DateTime.now().toString(), name: nameC.text.toUpperCase(), packing: "N/A", mrp: rate * 1.2, rateA: rate, rateB: rate, rateC: rate, stock: 0, purRate: rate, gst: gst)), child: const Text("CREATE")),
        ],
      ),
    );
  }
}
