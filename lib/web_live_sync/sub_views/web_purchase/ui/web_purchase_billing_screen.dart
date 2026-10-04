// FILE: lib/web_live_sync/sub_views/web_purchase/ui/web_purchase_billing_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:pharoah_erp/web_live_sync/web_models.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/web_pdf_router_service.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_billing/quick_add_product_modal.dart';
import '../mechanism/web_purchase_mechanism.dart';
import 'web_purchase_item_dialog.dart';

class WebPurchaseBillingScreen extends StatefulWidget {
  final Party supplier;
  final String internalNo;
  final String supplierBillNo;
  final DateTime billDate;
  final DateTime entryDate;
  final String paymentMode;
  final Purchase? existingPurchase;
  final bool isReadOnly;
  final VoidCallback onCompleted;

  const WebPurchaseBillingScreen({
    super.key,
    required this.supplier,
    required this.internalNo,
    required this.supplierBillNo,
    required this.billDate,
    required this.entryDate,
    required this.paymentMode,
    this.existingPurchase,
    this.isReadOnly = false,
    required this.onCompleted,
  });

  @override
  State<WebPurchaseBillingScreen> createState() => _WebPurchaseBillingScreenState();
}

class _WebPurchaseBillingScreenState extends State<WebPurchaseBillingScreen> {
  List<PurchaseItem> items = [];
  final extraDiscC = TextEditingController(text: "0");
  final extraDiscPerC = TextEditingController(text: "0");
  final productSearchC = TextEditingController();
  final remarksC = TextEditingController();
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingPurchase != null) {
      items = List.from(widget.existingPurchase!.items);
      double exDisc = widget.existingPurchase!.extraDiscount;
      extraDiscC.text = exDisc.toStringAsFixed(2);
      double t = items.fold(0.0, (sum, it) => sum + it.total);
      if (t > 0 && exDisc > 0) {
        extraDiscPerC.text = ((exDisc / t) * 100).toStringAsFixed(1);
      }
    }
  }

  @override
  void dispose() {
    extraDiscC.dispose();
    extraDiscPerC.dispose();
    productSearchC.dispose();
    remarksC.dispose();
    super.dispose();
  }

  void _recalculateSR() {
    setState(() {
      for (int i = 0; i < items.length; i++) {
        items[i] = items[i].copyWith(srNo: i + 1);
      }
    });
  }

  String _formatQty(double v) {
    if (v % 1 == 0) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  double _calculateMargin(PurchaseItem it) {
    if (it.mrp <= 0) return 0.0;
    double netUnitRate = it.purchaseRate;
    if (it.qty > 0 && it.discountRupees > 0) {
      netUnitRate -= (it.discountRupees / it.qty);
    }
    double margin = ((it.mrp - netUnitRate) / it.mrp) * 100;
    return margin;
  }

  bool _isShortExpiry(String exp) {
    if (exp.isEmpty || !exp.contains('/')) return false;
    try {
      final parts = exp.split('/');
      int m = int.parse(parts[0]);
      int y = 2000 + int.parse(parts[1]);
      DateTime expDate = DateTime(y, m + 1, 0);
      return expDate.difference(DateTime.now()).inDays <= 180;
    } catch (_) {
      return false;
    }
  }

  void _openItemDialog(PharoahWebManager webPh, Medicine med, {PurchaseItem? itemToEdit, int? editIndex}) {
    if (widget.isReadOnly) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => WebPurchaseItemDialog(
        med: med,
        srNo: itemToEdit != null ? itemToEdit.srNo : items.length + 1,
        existingItem: itemToEdit,
        onAdd: (newItem) {
          setState(() {
            if (editIndex != null) {
              items[editIndex] = newItem;
            } else {
              items.add(newItem);
            }
          });
          Navigator.pop(context);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  void _openQuickAddProduct(PharoahWebManager webPh) {
    if (widget.isReadOnly) return;
    showDialog(
      context: context,
      builder: (c) => QuickAddProductModal(
        webPh: webPh,
        onProductCreated: (newMedMap) {
          final medObj = Medicine.fromMap(newMedMap);
          _openItemDialog(webPh, medObj);
        },
      ),
    );
  }

  // Two-way synchronization for Bill Discount (% vs ₹)
  void _setPercentDiscount(double per) {
    setState(() {
      extraDiscPerC.text = per.toString();
      double amt = subTotal * (per / 100);
      extraDiscC.text = amt.toStringAsFixed(2);
    });
  }

  void _onRupeeDiscountChanged(String val) {
    double a = double.tryParse(val) ?? 0.0;
    if (subTotal > 0) {
      double p = (a / subTotal) * 100;
      extraDiscPerC.text = p.toStringAsFixed(1);
    } else {
      extraDiscPerC.text = "0";
    }
    setState(() {});
  }

  void _onPercentDiscountChanged(String val) {
    double p = double.tryParse(val) ?? 0.0;
    double a = subTotal * (p / 100);
    extraDiscC.text = a.toStringAsFixed(2);
    setState(() {});
  }

  double get subTotal => items.fold(0.0, (sum, it) => sum + it.total);
  double get totalTaxable => items.fold(0.0, (sum, it) => sum + (it.qty * it.purchaseRate - it.discountRupees));
  double get totalITC => subTotal - totalTaxable;
  double get extraDiscount => double.tryParse(extraDiscC.text) ?? 0.0;
  double get rawGrandTotal => (subTotal - extraDiscount);
  double get finalGrandTotal => rawGrandTotal.roundToDouble();
  double get roundOff => double.parse((finalGrandTotal - rawGrandTotal).toStringAsFixed(2));

  double get totalRetailMrpValue => items.fold(0.0, (sum, it) => sum + (it.mrp * (it.qty + it.freeQty)));
  double get totalProjectedProfit => totalRetailMrpValue > finalGrandTotal ? (totalRetailMrpValue - finalGrandTotal) : 0.0;
  double get overallMarginPercent => totalRetailMrpValue > 0 ? (totalProjectedProfit / totalRetailMrpValue) * 100 : 0.0;

  void _finalizePurchase(PharoahWebManager webPh, {bool andPrint = false}) async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Purchase cannot be empty! Please add products."), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => isSaving = true);

    String id = widget.existingPurchase?.id ?? "PUR-WEB-${DateTime.now().millisecondsSinceEpoch}";
    List<String> links = widget.existingPurchase?.linkedChallanIds ?? [];

    bool ok = await WebPurchaseMechanism.commitPurchase(
      webPh: webPh,
      purchaseId: id,
      internalNo: widget.internalNo,
      billNo: widget.supplierBillNo,
      supplier: widget.supplier,
      billDate: widget.billDate,
      entryDate: widget.entryDate,
      paymentMode: widget.paymentMode,
      items: items,
      totalAmount: finalGrandTotal,
      extraDiscount: extraDiscount,
      roundOff: roundOff,
      linkedChallanIds: links,
      existingId: widget.existingPurchase?.id,
    );

    setState(() => isSaving = false);

    if (ok) {
      if (andPrint) {
        final p = Purchase(
          id: id,
          internalNo: widget.internalNo,
          billNo: widget.supplierBillNo,
          partyId: widget.supplier.id,
          distributorName: widget.supplier.name,
          date: widget.billDate,
          entryDate: widget.entryDate,
          paymentMode: widget.paymentMode,
          totalAmount: finalGrandTotal,
          items: items,
          extraDiscount: extraDiscount,
          roundOff: roundOff,
        );
        final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);
        await WebPdfRouterService.printPurchaseInvoice(purchase: p, party: widget.supplier, shop: shopProfile);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Purchase Inward ${widget.internalNo} Saved & Cloud Synced!"), backgroundColor: Colors.green),
        );
        // Safe pop: Pop Step 2 (Billing Screen) and trigger clean onCompleted callback
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        widget.onCompleted();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "View Inward Items" : "Inward Note: ${widget.internalNo} (Step 2)"),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Download Inward PDF Button
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.greenAccent),
            tooltip: "Download Inward PDF",
            onPressed: items.isEmpty
                ? null
                : () async {
                    final tempPur = Purchase(
                      id: "temp",
                      internalNo: widget.internalNo,
                      billNo: widget.supplierBillNo,
                      partyId: widget.supplier.id,
                      distributorName: widget.supplier.name,
                      date: widget.billDate,
                      entryDate: widget.entryDate,
                      paymentMode: widget.paymentMode,
                      totalAmount: finalGrandTotal,
                      items: items,
                      extraDiscount: extraDiscount,
                      roundOff: roundOff,
                    );
                    await WebPdfRouterService.downloadPurchasePdf(
                      purchase: tempPur,
                      party: widget.supplier,
                      shop: CompanyProfile.fromMap(webPh.companyProfile),
                    );
                  },
          ),
          // Print Inward PDF Button
          IconButton(
            icon: const Icon(Icons.print_rounded, color: Color(0xFF38BDF8)),
            tooltip: "Print Inward Slip",
            onPressed: items.isEmpty
                ? null
                : () async {
                    final tempPur = Purchase(
                      id: "temp",
                      internalNo: widget.internalNo,
                      billNo: widget.supplierBillNo,
                      partyId: widget.supplier.id,
                      distributorName: widget.supplier.name,
                      date: widget.billDate,
                      entryDate: widget.entryDate,
                      paymentMode: widget.paymentMode,
                      totalAmount: finalGrandTotal,
                      items: items,
                      extraDiscount: extraDiscount,
                      roundOff: roundOff,
                    );
                    await WebPdfRouterService.printPurchaseInvoice(
                      purchase: tempPur,
                      party: widget.supplier,
                      shop: CompanyProfile.fromMap(webPh.companyProfile),
                    );
                  },
          ),
          if (!widget.isReadOnly)
            TextButton(
              onPressed: items.isEmpty ? null : () => _finalizePurchase(webPh, andPrint: false),
              child: const Text("FINISH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Top Supplier Info Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: Color(0x33F59E0B), shape: BoxShape.circle),
                        child: const Icon(Icons.business_rounded, color: Color(0xFFF59E0B), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.supplier.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                          Text("Bill No: ${widget.supplierBillNo} • Entry: ${widget.internalNo} • GST: ${widget.supplier.gst}", style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      "DATE: ${DateFormat('dd/MM/yyyy').format(widget.billDate)}",
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (!widget.isReadOnly) _buildCleanSearchBar(webPh),
            if (!widget.isReadOnly) const SizedBox(height: 14),

            _buildCartTable(webPh),
            const SizedBox(height: 14),

            _buildFooter(webPh),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanSearchBar(PharoahWebManager webPh) {
    final query = productSearchC.text.trim().toLowerCase();
    final matchingMeds = query.isEmpty
        ? <Medicine>[]
        : webPh.medicines
            .where((m) =>
                m.name.toLowerCase().contains(query) ||
                m.systemId.toLowerCase().contains(query))
            .take(5)
            .toList();

    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              const Icon(Icons.search_rounded, color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: productSearchC,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: "Search medicine to inward by name, packing, HSN...",
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 11.5),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) => setState(() {}),
                ),
              ),
              if (productSearchC.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                  onPressed: () => setState(() => productSearchC.clear()),
                ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(right: Radius.circular(10)),
                  ),
                  elevation: 0,
                ),
                onPressed: () => _openQuickAddProduct(webPh),
                icon: const Icon(Icons.add_box_rounded, size: 16),
                label: const Text("+ PRODUCT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ],
          ),
        ),
        if (matchingMeds.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x66F59E0B)),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: matchingMeds.length,
              itemBuilder: (context, idx) {
                final med = matchingMeds[idx];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.medication_rounded, color: Color(0xFFF59E0B), size: 18),
                  title: Row(
                    children: [
                      Text(med.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                      const SizedBox(width: 8),
                      Text("(${med.packing})", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      const Spacer(),
                      Text("Stock: ${med.stock.toInt()} Qty", style: TextStyle(color: med.stock > 0 ? Colors.greenAccent : Colors.redAccent, fontSize: 10.5, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  subtitle: Text("MRP: ₹${med.mrp.toStringAsFixed(2)} • Last Pur Rate: ₹${med.purRate.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  onTap: () {
                    setState(() => productSearchC.clear());
                    _openItemDialog(webPh, med);
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCartTable(PharoahWebManager webPh) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Text(
                "INWARD ITEMS (${items.length})",
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                child: const Text("👉 Swipe Left or 1-Tap Trash to delete", style: TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              if (items.isNotEmpty && !widget.isReadOnly)
                TextButton(
                  onPressed: () => setState(() => items.clear()),
                  child: const Text("Clear All", style: TextStyle(color: Colors.redAccent, fontSize: 10.5)),
                ),
            ],
          ),
          const Divider(color: Colors.white10, height: 16),

          if (items.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text("Inward cart is empty. Search products above to add stock.", style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final double tableWidth = constraints.maxWidth > 880 ? constraints.maxWidth : 880;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              _colCell("SN", width: 32),
                              const Expanded(flex: 4, child: Text("PRODUCT NAME", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold))),
                              _colCell("PACK", width: 65),
                              _colCell("BATCH", width: 80),
                              _colCell("EXPIRY", width: 80),
                              _colCell("QTY + FREE", width: 85, isBold: true),
                              _colCell("PUR. RATE", width: 75, isRight: true),
                              _colCell("MRP", width: 65, isRight: true),
                              _colCell("MARGIN %", width: 75),
                              _colCell("GST%", width: 45),
                              _colCell("TOTAL ₹", width: 85, isRight: true, isBold: true),
                              _colCell("ACT", width: 70),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),

                        Container(
                          constraints: const BoxConstraints(minHeight: 180, maxHeight: 500),
                          child: Scrollbar(
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Column(
                                children: items.asMap().entries.map((entry) {
                                  int idx = entry.key;
                                  PurchaseItem it = entry.value;

                                  String qtyDisp = "${_formatQty(it.qty)}${it.freeQty > 0 ? ' + ' + _formatQty(it.freeQty) : ''}";
                                  double margin = _calculateMargin(it);
                                  bool shortExp = _isShortExpiry(it.exp);

                                  return Dismissible(
                                    key: ValueKey("PUR_ITEM_${it.id}_$idx"),
                                    direction: widget.isReadOnly ? DismissDirection.none : DismissDirection.endToStart,
                                    background: Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade900,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      alignment: Alignment.centerRight,
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Text("DELETE ITEM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                          SizedBox(width: 8),
                                          Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 20),
                                        ],
                                      ),
                                    ),
                                    onDismissed: (_) {
                                      setState(() {
                                        items.removeAt(idx);
                                        _recalculateSR();
                                      });
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: Colors.black26,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.white10),
                                      ),
                                      child: Row(
                                        children: [
                                          _colCell("${idx + 1}", width: 32),
                                          Expanded(
                                            flex: 4,
                                            child: InkWell(
                                              onTap: () {
                                                final med = webPh.medicines.firstWhere((m) => m.id == it.medicineID);
                                                _openItemDialog(webPh, med, itemToEdit: it, editIndex: idx);
                                              },
                                              child: Text(
                                                it.name,
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                          _colCell(it.packing, width: 65),
                                          _colCell(it.batch, width: 80),
                                          SizedBox(
                                            width: 80,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(it.exp, style: TextStyle(color: shortExp ? Colors.orangeAccent : Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                                if (shortExp) ...[
                                                  const SizedBox(width: 3),
                                                  const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 12),
                                                ],
                                              ],
                                            ),
                                          ),
                                          _colCell(qtyDisp, width: 85, isBold: true, color: const Color(0xFFFBBF24)),
                                          _colCell("₹${it.purchaseRate.toStringAsFixed(2)}", width: 75, isRight: true),
                                          _colCell("₹${it.mrp.toStringAsFixed(2)}", width: 65, isRight: true, color: Colors.white54),

                                          // Margin % Badge
                                          SizedBox(
                                            width: 75,
                                            child: Center(
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: margin >= 25 ? const Color(0x3310B981) : (margin >= 15 ? const Color(0x33F59E0B) : const Color(0x33DC2626)),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  "${margin.toStringAsFixed(1)}%",
                                                  style: TextStyle(
                                                    color: margin >= 25 ? Colors.greenAccent : (margin >= 15 ? Colors.orangeAccent : const Color(0xFFF87171)),
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),

                                          _colCell("${it.gstRate.toInt()}%", width: 45),
                                          _colCell("₹${it.total.toStringAsFixed(2)}", width: 85, isRight: true, isBold: true, color: Colors.greenAccent),

                                          // 1-Tap Instant Delete Button
                                          SizedBox(
                                            width: 70,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                if (!widget.isReadOnly) ...[
                                                  SizedBox(
                                                    width: 30,
                                                    height: 30,
                                                    child: IconButton(
                                                      padding: EdgeInsets.zero,
                                                      icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF38BDF8)),
                                                      onPressed: () {
                                                        final med = webPh.medicines.firstWhere((m) => m.id == it.medicineID);
                                                        _openItemDialog(webPh, med, itemToEdit: it, editIndex: idx);
                                                      },
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  SizedBox(
                                                    width: 32,
                                                    height: 32,
                                                    child: Material(
                                                      color: Colors.transparent,
                                                      child: InkWell(
                                                        borderRadius: BorderRadius.circular(6),
                                                        onTap: () {
                                                          setState(() {
                                                            items.removeAt(idx);
                                                            _recalculateSR();
                                                          });
                                                        },
                                                        child: const Center(
                                                          child: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ] else
                                                  const Icon(Icons.lock_rounded, size: 14, color: Colors.white38),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
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

  // ===========================================================================
  // 💰 ADVANCED FOOTER (WITH VENDOR PROFIT & 2-WAY % DISCOUNT ENGINE)
  // ===========================================================================
  Widget _buildFooter(PharoahWebManager webPh) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          // VENDOR PROFIT & MARGIN RADAR STRIP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF19243B)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.query_stats_rounded, color: Colors.greenAccent, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "RETAIL MRP VALUE: ₹${totalRetailMrpValue.toStringAsFixed(2)}",
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  "PROJECTED PROFIT: ₹${totalProjectedProfit.toStringAsFixed(2)} (${overallMarginPercent.toStringAsFixed(1)}% MARGIN)",
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  controller: remarksC,
                  readOnly: widget.isReadOnly,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: "INWARD REMARKS / TRANSPORT INFO",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                    prefixIcon: const Icon(Icons.note_alt_outlined, color: Colors.white54, size: 16),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // 2-Way Discount % & ₹ Controls
              Row(
                children: [
                  const Text("Disc %: ", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  SizedBox(
                    width: 55,
                    height: 34,
                    child: TextField(
                      controller: extraDiscPerC,
                      readOnly: widget.isReadOnly,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        suffixText: "%",
                        suffixStyle: const TextStyle(color: Colors.redAccent, fontSize: 10),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      ),
                      onChanged: _onPercentDiscountChanged,
                    ),
                  ),
                  const SizedBox(width: 8),

                  const Text("Disc ₹: ", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  SizedBox(
                    width: 80,
                    height: 34,
                    child: TextField(
                      controller: extraDiscC,
                      readOnly: widget.isReadOnly,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      ),
                      onChanged: _onRupeeDiscountChanged,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Quick Discount Preset Chips: 2%, 3%, 4%, 5%
                  if (!widget.isReadOnly) ...[
                    _quickDiscChip("2%", 2.0),
                    const SizedBox(width: 4),
                    _quickDiscChip("3%", 3.0),
                    const SizedBox(width: 4),
                    _quickDiscChip("4%", 4.0),
                    const SizedBox(width: 4),
                    _quickDiscChip("5%", 5.0),
                  ],
                ],
              ),
              const SizedBox(width: 14),

              Text("R/O: ₹${roundOff.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
              const SizedBox(width: 16),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("NET INWARD VALUE", style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  Text("₹${finalGrandTotal.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 24, fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (!widget.isReadOnly)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSaving ? null : () => _finalizePurchase(webPh, andPrint: false),
                  icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(isSaving ? "SAVING..." : "SAVE & ADD STOCK", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF59E0B),
                    side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSaving ? null : () => _finalizePurchase(webPh, andPrint: true),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text("SAVE & PRINT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _quickDiscChip(String label, double per) {
    return InkWell(
      onTap: () => _setPercentDiscount(per),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 0.8),
        ),
        child: Text(label, style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _colCell(String t, {double? width, bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white70}) {
    TextAlign align = isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center);
    Widget textWidget = Text(
      t,
      textAlign: align,
      style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
      overflow: TextOverflow.ellipsis,
    );
    return width != null ? SizedBox(width: width, child: textWidget) : textWidget;
  }
}
