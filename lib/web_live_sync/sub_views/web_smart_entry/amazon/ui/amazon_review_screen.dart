import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../pharoah_web_manager.dart';
import '../../../../web_models.dart';
import '../../../../web_app_date_logic.dart';
import '../../../../web_pharoah_numbering_engine.dart';
import '../models/amazon_bill_model.dart';
import '../../../web_billing/quick_add_party_modal.dart';
import '../../../web_billing/quick_add_product_modal.dart';

class AmazonReviewScreen extends StatefulWidget {
  final AmazonBill bill;
  final VoidCallback onBack;

  const AmazonReviewScreen({super.key, required this.bill, required this.onBack});

  @override
  State<AmazonReviewScreen> createState() => _AmazonReviewScreenState();
}

class _AmazonReviewScreenState extends State<AmazonReviewScreen> {
  Party? matchedSupplier;
  List<Map<String, dynamic>> verifiedItems = [];
  bool isLoading = true;
  bool isSaving = false;

  late DateTime activeInvoiceDate;
  late String activeDateDisplay;

  @override
  void initState() {
    super.initState();
    _initDateAndSupplier();
  }

  String _cleanStr(String s) => s.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();

  void _initDateAndSupplier() {
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    activeDateDisplay = widget.bill.invoiceDate;

    DateTime parsedDt = DateTime.now();
    try {
      final parts = widget.bill.invoiceDate.split('/');
      parsedDt = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
    } catch (_) {}
    activeInvoiceDate = parsedDt;

    // Match Supplier
    String cleanGst = widget.bill.supplierGstin.trim().toUpperCase();
    String cleanSup = _cleanStr(widget.bill.supplierName);

    try {
      matchedSupplier = webPh.parties.firstWhere((p) {
        if (cleanGst.isNotEmpty && p.gst.trim().toUpperCase() == cleanGst) return true;
        if (_cleanStr(p.name) == cleanSup) return true;
        if (p.name.toUpperCase().contains("AMAGEN")) return true;
        return false;
      });
    } catch (_) {
      matchedSupplier = null;
    }

    // Match Items
    verifiedItems.clear();
    for (var it in widget.bill.items) {
      Medicine? matchedMed;
      String cleanItemName = _cleanStr(it.productName);

      try {
        matchedMed = webPh.medicines.firstWhere((m) => _cleanStr(m.name) == cleanItemName);
      } catch (_) {
        matchedMed = null;
      }

      double gross = it.qty * it.rate;
      double discAmt = gross * (it.discountPer / 100);
      double taxable = gross - discAmt;
      double taxAmt = taxable * (it.totalTaxRate / 100);
      double systemCalcTotal = taxable + taxAmt;

      verifiedItems.add({
        'raw': it,
        'matchedMed': matchedMed,
        'isSelected': true,
        'status': matchedMed == null ? 'NEW' : 'VERIFIED',
        'taxable': taxable,
        'taxAmt': taxAmt,
        'systemTotal': systemCalcTotal,
      });
    }

    setState(() => isLoading = false);
  }

  void _autoResolveAllNewProducts(PharoahWebManager webPh) {
    setState(() => isLoading = true);

    for (var row in verifiedItems) {
      if (row['matchedMed'] == null) {
        final AmazonItem it = row['raw'];
        String cleanName = _cleanStr(it.productName);

        Medicine? existing;
        try {
          existing = webPh.medicines.firstWhere((m) => _cleanStr(m.name) == cleanName);
        } catch (_) {
          existing = null;
        }

        if (existing != null) {
          row['matchedMed'] = existing;
          row['status'] = 'VERIFIED';
        } else {
          String sysId = "PH-MED-${10000 + webPh.medicines.length + 1}";
          final newMed = Medicine(
            id: "MED-${DateTime.now().millisecondsSinceEpoch}-${it.srNo}",
            systemId: sysId,
            name: it.productName.toUpperCase().trim(),
            packing: it.pack,
            hsnCode: it.hsn,
            gst: it.totalTaxRate,
            mrp: it.mrp,
            purRate: it.rate,
            rateA: it.mrp,
            rateB: it.mrp * 0.95,
            rateC: it.mrp * 0.92,
          );

          webPh.addMedicine(newMed);
          row['matchedMed'] = newMed;
          row['status'] = 'VERIFIED';
        }
      }
    }

    setState(() => isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Products added to Catalog!"), backgroundColor: Colors.green),
    );
  }

  void _finalizeAndCommitInward(PharoahWebManager webPh) async {
    if (matchedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please create or select Supplier first!"), backgroundColor: Colors.orange),
      );
      return;
    }

    if (verifiedItems.any((row) => row['matchedMed'] == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Click AUTO-RESOLVE to link all products first!"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => isSaving = true);

    String internalNo = WebPharoahNumberingEngine.getNextNumber(
      prefix: "PUR-",
      startFrom: 1,
      currentList: webPh.purchases,
    );

    List<PurchaseItem> commitItems = [];
    int sNo = 1;

    for (var row in verifiedItems) {
      final AmazonItem raw = row['raw'];
      Medicine med = row['matchedMed'];

      med.packing = raw.pack;
      med.mrp = raw.mrp;
      med.purRate = raw.rate;
      med.rateA = raw.mrp;
      med.rateB = raw.mrp * 0.95;
      med.rateC = raw.mrp * 0.92;
      webPh.updateMedicine(med);

      commitItems.add(PurchaseItem(
        id: "PITM-${DateTime.now().millisecondsSinceEpoch}-$sNo",
        srNo: sNo++,
        medicineID: med.id,
        name: med.name,
        packing: raw.pack,
        batch: raw.batch,
        exp: raw.exp,
        hsn: raw.hsn,
        mrp: raw.mrp,
        qty: raw.qty,
        freeQty: raw.freeQty,
        purchaseRate: raw.rate,
        gstRate: raw.totalTaxRate,
        total: row['systemTotal'],
        rateA: raw.mrp,
        rateB: raw.mrp * 0.95,
        rateC: raw.mrp * 0.92,
        discountPer: raw.discountPer,
      ));

      webPh.registerBatchActivity(
        productKey: med.identityKey,
        batchNo: raw.batch,
        exp: raw.exp,
        packing: raw.pack,
        mrp: raw.mrp,
        rate: raw.rate,
        rateA: raw.mrp,
        rateB: raw.mrp * 0.95,
        rateC: raw.mrp * 0.92,
        appliedRateType: "A",
        qtyChange: raw.qty + raw.freeQty,
      );
    }

    final newPurchase = Purchase(
      id: "PUR-WEB-${DateTime.now().millisecondsSinceEpoch}",
      internalNo: internalNo,
      billNo: widget.bill.invoiceNo,
      partyId: matchedSupplier!.id,
      distributorName: matchedSupplier!.name,
      date: activeInvoiceDate,
      entryDate: DateTime.now(),
      paymentMode: "CREDIT",
      totalAmount: widget.bill.grandTotal,
      extraDiscount: 0.0,
      roundOff: widget.bill.roundOff,
      gstStatus: "Matched",
      items: commitItems,
      sourceTag: "WEB-PORTAL AMAGEN",
    );

    webPh.purchases.removeWhere((p) => p.billNo.trim().toUpperCase() == widget.bill.invoiceNo.trim().toUpperCase());
    webPh.purchases.add(newPurchase);
    webPh.rebuildInventory();

    await webPh.pushUpdatedDataToCloud();
    setState(() => isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("🎉 Inward #${newPurchase.billNo} Saved for ${matchedSupplier!.name}! Total: ₹${widget.bill.grandTotal.toStringAsFixed(2)}"), backgroundColor: Colors.green),
      );
      widget.onBack();
    }
  }

  void _quickCreateSupplier(PharoahWebManager webPh) {
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        preFillData: {
          'name': widget.bill.supplierName,
          'gst': widget.bill.supplierGstin,
          'pan': widget.bill.supplierPan,
          'dl': widget.bill.supplierDl,
          'phone': widget.bill.supplierPhone,
          'address': widget.bill.supplierAddress,
          'city': 'JAIPUR',
          'state': 'Rajasthan',
          'group': 'Sundry Creditors',
        },
        onPartyCreated: (p) => setState(() => matchedSupplier = p),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    if (isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)));

    int unlinked = verifiedItems.where((r) => r['matchedMed'] == null).length;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.verified_user_rounded, color: Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 8),
              Text(
                "VERIFY AMAGEN INVOICE • #${widget.bill.invoiceNo} (${verifiedItems.length} ITEMS)",
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
              const Spacer(),
              if (unlinked > 0)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black),
                  onPressed: () => _autoResolveAllNewProducts(webPh),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: Text("AUTO-RESOLVE ($unlinked UNLINKED)", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 18),

          // Supplier Verification Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: matchedSupplier != null ? const Color(0xFF10B981) : Colors.redAccent, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(matchedSupplier != null ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: matchedSupplier != null ? Colors.greenAccent : Colors.redAccent, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(matchedSupplier != null ? matchedSupplier!.name : widget.bill.supplierName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                      Text("GST: ${widget.bill.supplierGstin} • Date: $activeDateDisplay • Phone: ${widget.bill.supplierPhone}", style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                    ],
                  ),
                ),
                if (matchedSupplier == null)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black),
                    onPressed: () => _quickCreateSupplier(webPh),
                    child: const Text("CREATE SUPPLIER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Item Rows
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: verifiedItems.length,
            itemBuilder: (c, idx) {
              final row = verifiedItems[idx];
              final AmazonItem raw = row['raw'];
              final Medicine? match = row['matchedMed'];
              bool isLinked = match != null;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isLinked ? const Color(0x3310B981) : Colors.orangeAccent.withAlpha(120), width: 1.2),
                ),
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      title: Row(
                        children: [
                          Text(raw.productName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(4)),
                            child: Text(raw.pack, style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold)),
                          ),
                          const Spacer(),
                          Text(isLinked ? "LINKED: ${match.name}" : "NOT FOUND IN MASTERS", style: TextStyle(color: isLinked ? Colors.greenAccent : Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      subtitle: Text(
                        "Batch: ${raw.batch} • Exp: ${raw.exp} • Qty: ${raw.qty.toInt()} + ${raw.freeQty.toInt()} Free • Rate: ₹${raw.rate.toStringAsFixed(2)} • MRP: ₹${raw.mrp.toStringAsFixed(2)} • GST: ${raw.totalTaxRate.toStringAsFixed(1)}% (CGST+SGST)",
                        style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: const BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.vertical(bottom: Radius.circular(11))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("INVOICE TAXABLE: ₹${raw.amount.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                          Text("NET INWARD: ₹${row['systemTotal'].toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Footer
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Taxable: ₹${widget.bill.taxableTotal.toStringAsFixed(2)} + CGST: ₹${widget.bill.cgstTotal.toStringAsFixed(2)} + SGST: ₹${widget.bill.sgstTotal.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text("GRAND TOTAL: ₹${widget.bill.grandTotal.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 15, fontWeight: FontWeight.w900)),
                  ],
                ),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: isSaving ? null : () => _finalizeAndCommitInward(webPh),
                    icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) : const Icon(Icons.cloud_done_rounded, size: 20),
                    label: Text(isSaving ? "INWARDING..." : "COMMIT INWARD & SYNC", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
