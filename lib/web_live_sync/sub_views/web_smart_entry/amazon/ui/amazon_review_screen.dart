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
import 'amazon_pack_converter_dialog.dart';

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
        matchedMed = webPh.medicines.firstWhere((m) {
          return _cleanStr(m.name) == cleanItemName;
        });
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
        'saveMasterAsStrip': true,
      });
    }

    setState(() => isLoading = false);
  }

  void _openPackConverter(int idx) {
    final row = verifiedItems[idx];
    final AmazonItem it = row['raw'];

    showDialog(
      context: context,
      builder: (c) => AmazonPackConverterDialog(
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
            it.mrp = newMrp;

            double gross = it.qty * it.rate;
            double discAmt = gross * (it.discountPer / 100);
            double taxable = gross - discAmt;
            double taxAmt = taxable * (it.totalTaxRate / 100);
            row['taxable'] = taxable;
            row['taxAmt'] = taxAmt;
            row['systemTotal'] = taxable + taxAmt;
          });
        },
      ),
    );
  }

  void _showInstantLinkOverlay(int itemIndex) {
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    String localSearch = "";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filteredMeds = webPh.medicines
              .where((m) => m.name.toLowerCase().contains(localSearch.toLowerCase()))
              .toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 15),
            child: Column(
              children: [
                Container(height: 5, width: 50, decoration: const BoxDecoration(color: Colors.white24)),
                const SizedBox(height: 15),
                const Text(
                  "SELECT SYSTEM PRODUCT TO LINK",
                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 15),
                TextField(
                  style: const TextStyle(color: Colors.white),
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: "Search catalog by name...",
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFFF59E0B)),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setSheetState(() => localSearch = v),
                ),
                const SizedBox(height: 15),
                Expanded(
                  child: filteredMeds.isEmpty
                      ? const Center(child: Text("No products found.", style: TextStyle(color: Colors.white38)))
                      : ListView.builder(
                          itemCount: filteredMeds.length,
                          itemBuilder: (c, idx) {
                            final m = filteredMeds[idx];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.medication_rounded, color: Color(0xFFF59E0B)),
                              title: Text(m.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text("Pack: ${m.packing} | Stock: ${m.stock.toInt()} | MRP: ₹${m.mrp.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                              trailing: const Icon(Icons.link_rounded, color: Colors.greenAccent, size: 20),
                              onTap: () => Navigator.pop(context, m),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    ).then((selectedMed) {
      if (selectedMed != null && selectedMed is Medicine) {
        setState(() {
          verifiedItems[itemIndex]['matchedMed'] = selectedMed;
          verifiedItems[itemIndex]['status'] = 'VERIFIED';
          verifiedItems[itemIndex]['isSelected'] = true;
        });
        _propagateItemLink(selectedMed, verifiedItems[itemIndex]['raw'].productName);
      }
    });
  }

  void _propagateItemLink(Medicine med, String targetName) {
    String cleanTarget = _cleanStr(targetName);
    setState(() {
      for (var row in verifiedItems) {
        final AmazonItem raw = row['raw'];
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
          'dl': widget.bill.supplierDl, // Full DL Number DRUG/24-25/20B-21B/120460-61,20-21/120458-59
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

  void _showQuickPartyPicker(PharoahWebManager webPh) {
    String search = "";
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => StatefulBuilder(
        builder: (context, setPickerState) {
          final list = webPh.parties.where((p) => p.name.toLowerCase().contains(search.toLowerCase())).toList();
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text("SELECT SUPPLIER FROM MASTER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                TextField(
                  style: const TextStyle(color: Colors.white),
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: "Search party by name...",
                    prefixIcon: Icon(Icons.search, color: Color(0xFFF59E0B)),
                    filled: true,
                    fillColor: Colors.white10,
                  ),
                  onChanged: (v) => setPickerState(() => search = v),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (ctx, i) => ListTile(
                      title: Text(list[i].name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text("${list[i].city} | GST: ${list[i].gst}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      onTap: () {
                        setState(() => matchedSupplier = list[i]);
                        Navigator.pop(c);
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _quickCreateMedicineMaster(PharoahWebManager webPh, AmazonItem it, int idx) {
    showDialog(
      context: context,
      builder: (c) => QuickAddProductModal(
        webPh: webPh,
        preFillData: {
          'name': it.productName,
          'pack': it.pack,
          'hsn': it.hsn,
          'gst': it.totalTaxRate,
          'mrp': it.mrp,
          'purRate': it.rate,
          'rateA': it.mrp,
          'rateB': it.mrp * 0.95,
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

          // Supplier Verification Card with Create, Link & Change Actions
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
                      Row(
                        children: [
                          Text(matchedSupplier != null ? matchedSupplier!.name : widget.bill.supplierName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: matchedSupplier != null ? const Color(0x2610B981) : const Color(0x26EF4444),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: matchedSupplier != null ? Colors.greenAccent : Colors.redAccent, width: 0.5),
                            ),
                            child: Text(
                              matchedSupplier != null ? "VERIFIED SUPPLIER" : "UNLINKED SENDER",
                              style: TextStyle(color: matchedSupplier != null ? Colors.greenAccent : Colors.redAccent, fontSize: 8.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text("GST: ${widget.bill.supplierGstin} • DL: ${widget.bill.supplierDl} • Date: $activeDateDisplay • Phone: ${widget.bill.supplierPhone}", style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                    ],
                  ),
                ),
                if (matchedSupplier == null) ...[
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                    onPressed: () => _quickCreateSupplier(webPh),
                    child: const Text("CREATE SUPPLIER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF38BDF8), side: const BorderSide(color: Color(0xFF38BDF8))),
                    onPressed: () => _showQuickPartyPicker(webPh),
                    child: const Text("LINK SUPPLIER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ] else ...[
                  TextButton.icon(
                    onPressed: () => setState(() => matchedSupplier = null),
                    icon: const Icon(Icons.sync_alt_rounded, size: 14, color: Colors.orangeAccent),
                    label: const Text("CHANGE", style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Item Rows with Full Actions: Add, Link & Split
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
                          InkWell(
                            onTap: () => _openPackConverter(idx),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white24)),
                              child: Row(
                                children: [
                                  Text(raw.pack, style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.swap_horiz_rounded, size: 12, color: Colors.white54),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: isLinked ? const Color(0x2610B981) : const Color(0x26F59E0B), borderRadius: BorderRadius.circular(4)),
                            child: Text(isLinked ? "LINKED: ${match.name}" : "NOT FOUND IN MASTERS", style: TextStyle(color: isLinked ? Colors.greenAccent : Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        "Batch: ${raw.batch} • Exp: ${raw.exp} • Qty: ${raw.qty.toInt()} + ${raw.freeQty.toInt()} Free • Rate: ₹${raw.rate.toStringAsFixed(2)} • MRP: ₹${raw.mrp.toStringAsFixed(2)} • GST: ${raw.totalTaxRate.toStringAsFixed(1)}% (CGST+SGST)",
                        style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                      ),
                      trailing: isLinked
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.call_split_rounded, color: Color(0xFF34D399), size: 20),
                                  tooltip: "Configure Pack Split",
                                  onPressed: () => _openPackConverter(idx),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.link_off_rounded, color: Colors.redAccent, size: 18),
                                  tooltip: "Unlink Product",
                                  onPressed: () => setState(() {
                                    row['matchedMed'] = null;
                                    row['status'] = 'NEW';
                                  }),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.link_rounded, color: Color(0xFF38BDF8), size: 20),
                                  tooltip: "Link to Existing Catalog Product",
                                  onPressed: () => _showInstantLinkOverlay(idx),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_box_rounded, color: Color(0xFFF59E0B), size: 20),
                                  tooltip: "Quick Create in Master",
                                  onPressed: () => _quickCreateMedicineMaster(webPh, raw, idx),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.call_split_rounded, color: Color(0xFF34D399), size: 20),
                                  tooltip: "Configure Pack Split",
                                  onPressed: () => _openPackConverter(idx),
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
