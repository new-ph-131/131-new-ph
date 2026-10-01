import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../pharoah_web_manager.dart';
import '../../../../web_models.dart';
import '../../../../web_pharoah_numbering_engine.dart';
import '../models/medilente_bill_model.dart';
import '../../../web_billing/quick_add_party_modal.dart';
import '../../../web_billing/quick_add_product_modal.dart';
import 'medilente_pack_converter_dialog.dart';

class MedilenteReviewScreen extends StatefulWidget {
  final MedilenteBill bill;
  final VoidCallback onBack;

  const MedilenteReviewScreen({
    super.key,
    required this.bill,
    required this.onBack,
  });

  @override
  State<MedilenteReviewScreen> createState() => _MedilenteReviewScreenState();
}

class _MedilenteReviewScreenState extends State<MedilenteReviewScreen> {
  Party? matchedSupplier;
  List<Map<String, dynamic>> verifiedItems = [];
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _reconcileWithMasters();
  }

  String _cleanStr(String s) => s.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();

  void _reconcileWithMasters() {
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);

    // 1. Match Supplier By Clean GST or Name
    String cleanGst = widget.bill.supplierGstin.trim().toUpperCase();
    String cleanSupName = _cleanStr(widget.bill.supplierName);

    try {
      matchedSupplier = webPh.parties.firstWhere(
        (p) {
          if (cleanGst.isNotEmpty && p.gst.trim().toUpperCase() == cleanGst) return true;
          if (_cleanStr(p.name) == cleanSupName) return true;
          if (p.name.toUpperCase().contains("MEDILENTE") && cleanSupName.contains("MEDILENTE")) return true;
          return false;
        },
      );
    } catch (_) {
      matchedSupplier = null;
    }

    // 2. Match Items & Apply Auto Pharma Strip Conversion by Default
    verifiedItems.clear();
    for (var it in widget.bill.items) {
      Medicine? matchedMed;
      String cleanItemName = _cleanStr(it.productName);

      try {
        matchedMed = webPh.medicines.firstWhere((m) {
          return _cleanStr(m.name) == cleanItemName;
        });
      } catch (_) {
        matchedMed = null;
      }

      // Auto-detect Multi-Pack Box (e.g. 10*10, 2*15) and convert to single strip (1*10, 1*15)
      if (it.conversionFactor == 1) {
        var match = RegExp(r'^(\d+)[\*xX](\d+)$').firstMatch(it.pack.trim());
        if (match != null) {
          int n = int.tryParse(match.group(1)!) ?? 1;
          int mUnits = int.tryParse(match.group(2)!) ?? 10;
          if (n > 1) {
            it.originalPack = it.pack;
            it.pack = "1*$mUnits";
            it.conversionFactor = n;
            it.qty = it.qty * n;
            it.rate = it.rate / n;
            it.netMrp = it.netMrp / n;
            if (it.oldMrp > 0) it.oldMrp = it.oldMrp / n;
          }
        }
      }

      double gross = it.qty * it.rate;
      double discAmt = gross * (it.discountPer / 100);
      double taxable = gross - discAmt;
      double taxAmt = taxable * (it.igstRate / 100);
      double systemCalcTotal = taxable + taxAmt;

      verifiedItems.add({
        'raw': it,
        'matchedMed': matchedMed,
        'isSelected': matchedMed != null,
        'status': matchedMed == null ? 'NEW' : 'VERIFIED',
        'taxable': taxable,
        'taxAmt': taxAmt,
        'systemTotal': systemCalcTotal,
        'saveMasterAsStrip': true, // Strip pricing in Master by default!
      });
    }

    setState(() => isLoading = false);
  }

  void _openPackConverter(int idx) {
    final row = verifiedItems[idx];
    final MedilenteItem it = row['raw'];

    showDialog(
      context: context,
      builder: (c) => MedilentePackConverterDialog(
        item: it,
        onApply: ({
          required String targetPack,
          required int factor,
          required double newQty,
          required double newRate,
          required double newMrp,
          required bool saveMasterAsStrip,
        }) {
          setState(() {
            it.pack = targetPack;
            it.conversionFactor = factor;
            it.qty = newQty;
            it.rate = newRate;
            it.netMrp = newMrp;
            row['saveMasterAsStrip'] = saveMasterAsStrip;

            double gross = it.qty * it.rate;
            double discAmt = gross * (it.discountPer / 100);
            double taxable = gross - discAmt;
            double taxAmt = taxable * (it.igstRate / 100);
            row['taxable'] = taxable;
            row['taxAmt'] = taxAmt;
            row['systemTotal'] = taxable + taxAmt;
          });
        },
      ),
    );
  }

  void _propagateItemLink(Medicine med, String targetName) {
    String cleanTarget = _cleanStr(targetName);
    setState(() {
      for (var row in verifiedItems) {
        final MedilenteItem raw = row['raw'];
        if (row['matchedMed'] == null && _cleanStr(raw.productName) == cleanTarget) {
          row['matchedMed'] = med;
          row['status'] = 'VERIFIED';
          row['isSelected'] = true;
        }
      }
    });
  }

  void _autoResolveAllNewProducts(PharoahWebManager webPh) {
    setState(() => isLoading = true);

    for (var row in verifiedItems) {
      if (row['matchedMed'] == null) {
        final MedilenteItem it = row['raw'];
        String cleanName = _cleanStr(it.productName);

        Medicine? existingInMaster;
        try {
          existingInMaster = webPh.medicines.firstWhere((m) => _cleanStr(m.name) == cleanName);
        } catch (_) {
          existingInMaster = null;
        }

        if (existingInMaster != null) {
          // Update master with strip pricing if needed
          if (row['saveMasterAsStrip'] == true && existingInMaster.packing != it.pack) {
            existingInMaster.packing = it.pack;
            existingInMaster.mrp = it.netMrp;
            existingInMaster.purRate = it.rate;
            existingInMaster.rateA = it.netMrp;
            existingInMaster.rateB = it.netMrp * 0.95;
            existingInMaster.rateC = it.netMrp * 0.92;
            webPh.updateMedicine(existingInMaster);
          }
          row['matchedMed'] = existingInMaster;
          row['status'] = 'VERIFIED';
          row['isSelected'] = true;
        } else {
          String sysId = "PH-MED-${10000 + webPh.medicines.length + 1}";

          final newMed = Medicine(
            id: "MED-${DateTime.now().millisecondsSinceEpoch}-${it.srNo}",
            systemId: sysId,
            name: it.productName.toUpperCase().trim(),
            packing: it.pack, // Saved as "1*10"!
            hsnCode: it.hsn,
            gst: it.igstRate,
            mrp: it.netMrp,   // Saved as Strip MRP!
            purRate: it.rate, // Saved as Strip PurRate!
            rateA: it.netMrp, // Saved as Strip Rate A!
            rateB: it.netMrp * 0.95,
            rateC: it.netMrp * 0.92,
          );

          webPh.addMedicine(newMed);
          row['matchedMed'] = newMed;
          row['status'] = 'VERIFIED';
          row['isSelected'] = true;
        }
      }
    }

    setState(() => isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Products created with STRIP (1*10) pricing in Master!"), backgroundColor: Colors.green),
    );
  }

  void _finalizeAndCommitInward(PharoahWebManager webPh) async {
    if (matchedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please link or create the supplier first!"), backgroundColor: Colors.orange),
      );
      return;
    }

    if (verifiedItems.any((row) => row['isSelected'] && row['matchedMed'] == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please resolve all unlinked items before finalizing!"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => isSaving = true);

    DateTime invoiceDt = DateTime.now();
    try {
      final parts = widget.bill.invoiceDate.split('/');
      invoiceDt = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
    } catch (_) {}

    String internalNo = WebPharoahNumberingEngine.getNextNumber(
      prefix: "PUR-",
      startFrom: 1,
      currentList: webPh.purchases,
    );

    List<PurchaseItem> commitItems = [];
    int sNo = 1;

    for (var row in verifiedItems.where((r) => r['isSelected'])) {
      final MedilenteItem raw = row['raw'];
      Medicine med = row['matchedMed'];

      // Update Medicine Master with Strip Pricing if flagged
      if (row['saveMasterAsStrip'] == true) {
        med.packing = raw.pack; // e.g. "1*10"
        med.mrp = raw.netMrp;   // Strip MRP
        med.purRate = raw.rate; // Strip PurRate
        med.rateA = raw.netMrp; // Strip Sale Rate A
        med.rateB = raw.netMrp * 0.95;
        med.rateC = raw.netMrp * 0.92;
        webPh.updateMedicine(med);
      }

      commitItems.add(PurchaseItem(
        id: "PITM-${DateTime.now().millisecondsSinceEpoch}-$sNo",
        srNo: sNo++,
        medicineID: med.id,
        name: med.name,
        packing: raw.pack,
        batch: raw.batch,
        exp: raw.exp,
        hsn: raw.hsn,
        mrp: raw.netMrp,
        qty: raw.qty,
        freeQty: raw.freeQty,
        purchaseRate: raw.rate,
        gstRate: raw.igstRate,
        total: row['systemTotal'],
        rateA: raw.netMrp,
        rateB: raw.netMrp * 0.95,
        rateC: raw.netMrp * 0.92,
        discountPer: raw.discountPer,
      ));

      webPh.registerBatchActivity(
        productKey: med.identityKey,
        batchNo: raw.batch,
        exp: raw.exp,
        packing: raw.pack,
        mrp: raw.netMrp,
        rate: raw.rate,
        rateA: raw.netMrp,
        rateB: raw.netMrp * 0.95,
        rateC: raw.netMrp * 0.92,
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
      date: invoiceDt,
      entryDate: DateTime.now(),
      paymentMode: "CREDIT",
      totalAmount: widget.bill.grandTotal,
      extraDiscount: 0.0,
      roundOff: widget.bill.roundOff,
      gstStatus: "Matched",
      items: commitItems,
      sourceTag: "WEB-PORTAL",
    );

    webPh.purchases.removeWhere((p) => p.billNo.trim().toUpperCase() == widget.bill.invoiceNo.trim().toUpperCase());
    webPh.purchases.add(newPurchase);
    webPh.rebuildInventory();

    bool pushed = await webPh.pushUpdatedDataToCloud();
    setState(() => isSaving = false);

    if (pushed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("🎉 Purchase Inward ${newPurchase.billNo} Saved & Master Updated to Strips!"), backgroundColor: Colors.green),
        );
        widget.onBack();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ Saved locally! Cloud push retrying in background."), backgroundColor: Colors.orange),
        );
        widget.onBack();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    if (isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));

    int unlinkedCount = verifiedItems.where((r) => r['matchedMed'] == null).length;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
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
              const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 22),
              const SizedBox(width: 8),
              Text(
                "VERIFY INVOICE • #${widget.bill.invoiceNo}",
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
              const Spacer(),
              if (unlinkedCount > 0)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black),
                  onPressed: () => _autoResolveAllNewProducts(webPh),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: Text("AUTO-RESOLVE ($unlinkedCount UNLINKED)", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 18),

          _buildSupplierVerificationCard(webPh),
          const SizedBox(height: 16),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: verifiedItems.length,
            itemBuilder: (context, idx) => _buildItemVerificationRow(webPh, idx),
          ),
          const SizedBox(height: 16),

          _buildReconciledFooter(webPh),
        ],
      ),
    );
  }

  Widget _buildSupplierVerificationCard(PharoahWebManager webPh) {
    bool isVerified = matchedSupplier != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isVerified ? const Color(0xFF10B981) : Colors.redAccent, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isVerified ? const Color(0x3310B981) : const Color(0x33EF4444),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isVerified ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              color: isVerified ? const Color(0xFF10B981) : Colors.redAccent,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      matchedSupplier != null ? matchedSupplier!.name : widget.bill.supplierName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isVerified ? const Color(0x2610B981) : const Color(0x26EF4444),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: isVerified ? Colors.greenAccent : Colors.redAccent, width: 0.5),
                      ),
                      child: Text(
                        isVerified ? "VERIFIED SUPPLIER" : "UNLINKED SENDER",
                        style: TextStyle(color: isVerified ? Colors.greenAccent : Colors.redAccent, fontSize: 8.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "GST: ${widget.bill.supplierGstin} • Date: ${widget.bill.invoiceDate} • Phone: ${widget.bill.supplierPhone}",
                  style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                ),
              ],
            ),
          ),
          if (!isVerified) ...[
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              onPressed: () => _quickCreateMedilenteSupplier(webPh),
              child: const Text("CREATE SUPPLIER", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemVerificationRow(PharoahWebManager webPh, int idx) {
    final row = verifiedItems[idx];
    final MedilenteItem raw = row['raw'];
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
            leading: Checkbox(
              value: row['isSelected'],
              activeColor: const Color(0xFF10B981),
              onChanged: isLinked ? (v) => setState(() => row['isSelected'] = v!) : null,
            ),
            title: Row(
              children: [
                Text(raw.productName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _openPackConverter(idx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: raw.conversionFactor > 1 ? const Color(0x3310B981) : Colors.black38,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: raw.conversionFactor > 1 ? Colors.greenAccent : Colors.white24),
                    ),
                    child: Row(
                      children: [
                        Text(
                          "${raw.pack} (${raw.conversionFactor > 1 ? 'STRIP' : 'BOX'})",
                          style: TextStyle(color: raw.conversionFactor > 1 ? Colors.greenAccent : Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.swap_horiz_rounded, size: 12, color: Colors.white54),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isLinked ? const Color(0x2610B981) : const Color(0x26F59E0B),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isLinked ? "LINKED: ${match.name} (${match.packing})" : "NOT FOUND IN MASTERS",
                    style: TextStyle(color: isLinked ? Colors.greenAccent : Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              "Batch: ${raw.batch} • Exp: ${raw.exp} • Qty: ${raw.qty.toInt()} ${raw.pack} • Pur.Rate: ₹${raw.rate.toStringAsFixed(2)} • MRP: ₹${raw.netMrp.toStringAsFixed(2)}",
              style: const TextStyle(color: Colors.white54, fontSize: 10.5),
            ),
            trailing: isLinked
                ? IconButton(
                    icon: const Icon(Icons.call_split_rounded, color: Color(0xFF34D399), size: 20),
                    tooltip: "Configure Pack Split / Unit",
                    onPressed: () => _openPackConverter(idx),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.call_split_rounded, color: Color(0xFF34D399), size: 20),
                        tooltip: "Configure Pack Split / Unit",
                        onPressed: () => _openPackConverter(idx),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_box_rounded, color: Color(0xFFF59E0B), size: 20),
                        tooltip: "Create product master with strip pricing",
                        onPressed: () => _quickCreateMedicineMaster(webPh, raw, idx),
                      ),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.vertical(bottom: Radius.circular(11))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("INVOICE ROW AMOUNT: ₹${raw.amount.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
                Text(
                  "RECONCILED: ₹${row['systemTotal'].toStringAsFixed(2)}",
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReconciledFooter(PharoahWebManager webPh) {
    double selectedTotal = verifiedItems.where((r) => r['isSelected']).fold(0.0, (sum, r) => sum + r['systemTotal']);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Invoice Total: ₹${widget.bill.grandTotal.toStringAsFixed(2)} (Taxable: ₹${widget.bill.taxableTotal.toStringAsFixed(2)} + IGST: ₹${widget.bill.igstTotal.toStringAsFixed(2)})",
                  style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text(
                "VERIFIED PURCHASE TOTAL: ₹${selectedTotal.toStringAsFixed(2)}",
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: isSaving ? null : () => _finalizeAndCommitInward(webPh),
              icon: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.cloud_done_rounded, size: 20),
              label: Text(
                isSaving ? "INWARDING..." : "FINALIZE & COMMIT INWARD",
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _quickCreateMedilenteSupplier(PharoahWebManager webPh) {
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        preFillData: {
          'name': widget.bill.supplierName,
          'gst': widget.bill.supplierGstin,
          'pan': widget.bill.supplierPan,
          'dl': widget.bill.supplierDl,
          'email': widget.bill.supplierEmail,
          'phone': widget.bill.supplierPhone,
          'address': widget.bill.supplierAddress,
          'city': 'PANCHKULA',
          'state': 'Haryana',
          'group': 'Sundry Creditors',
        },
        onPartyCreated: (newParty) {
          setState(() => matchedSupplier = newParty);
        },
      ),
    );
  }

  void _quickCreateMedicineMaster(PharoahWebManager webPh, MedilenteItem it, int idx) {
    showDialog(
      context: context,
      builder: (c) => QuickAddProductModal(
        webPh: webPh,
        preFillData: {
          'name': it.productName,
          'pack': it.pack, // Passed as "1*10"!
          'hsn': it.hsn,
          'gst': it.igstRate,
          'mrp': it.netMrp > 0 ? it.netMrp : it.oldMrp, // Per Strip MRP!
          'purRate': it.rate, // Per Strip PurRate!
          'rateA': it.netMrp > 0 ? it.netMrp : it.oldMrp, // Per Strip Rate A!
          'rateB': (it.netMrp > 0 ? it.netMrp : it.oldMrp) * 0.95,
          'form': 'TAB',
        },
        onProductCreated: (newMedMap) {
          final med = Medicine.fromMap(newMedMap);
          setState(() {
            verifiedItems[idx]['matchedMed'] = med;
            verifiedItems[idx]['status'] = 'VERIFIED';
            verifiedItems[idx]['isSelected'] = true;
          });
          _propagateItemLink(med, it.productName);
        },
      ),
    );
  }
}
