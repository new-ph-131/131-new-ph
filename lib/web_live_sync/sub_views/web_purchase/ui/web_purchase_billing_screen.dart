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
  final productSearchC = TextEditingController();
  final remarksC = TextEditingController();
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingPurchase != null) {
      items = List.from(widget.existingPurchase!.items);
      extraDiscC.text = widget.existingPurchase!.extraDiscount.toString();
    }
  }

  @override
  void dispose() {
    extraDiscC.dispose();
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

  double get subTotal => items.fold(0.0, (sum, it) => sum + it.total);
  double get totalTaxable => items.fold(0.0, (sum, it) => sum + (it.qty * it.purchaseRate - it.discountRupees));
  double get totalITC => subTotal - totalTaxable;
  double get extraDiscount => double.tryParse(extraDiscC.text) ?? 0.0;
  double get rawGrandTotal => (subTotal - extraDiscount);
  double get finalGrandTotal => rawGrandTotal.roundToDouble();
  double get roundOff => double.parse((finalGrandTotal - rawGrandTotal).toStringAsFixed(2));

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
        Navigator.pop(context); // Close Step 2
        widget.onCompleted();   // Return to Step 1 or Hub
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
          IconButton(
            icon: const Icon(Icons.print_rounded),
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

            if (!widget.isReadOnly) _buildProductSearchCard(webPh),
            if (!widget.isReadOnly) const SizedBox(height: 14),

            _buildCartTable(webPh),
            const SizedBox(height: 14),

            _buildFooter(webPh),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSearchCard(PharoahWebManager webPh) {
    final query = productSearchC.text.trim().toLowerCase();
    final matchingMeds = query.isEmpty
        ? <Medicine>[]
        : webPh.medicines
            .where((m) =>
                m.name.toLowerCase().contains(query) ||
                m.systemId.toLowerCase().contains(query) ||
                m.hsnCode.toLowerCase().contains(query))
            .take(5)
            .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x66F59E0B), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: productSearchC,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: "SEARCH PRODUCT TO INWARD",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 9.5),
                    hintText: "Type medicine name...",
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFFF59E0B), size: 18),
                    suffixIcon: productSearchC.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 16),
                            onPressed: () => setState(() => productSearchC.clear()),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: (v) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _openQuickAddProduct(webPh),
                icon: const Icon(Icons.add_box_rounded, size: 18),
                label: const Text("+ PRODUCT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ],
          ),
          if (matchingMeds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x33F59E0B)),
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
                      ],
                    ),
                    subtitle: Text("MRP: ₹${med.mrp.toStringAsFixed(2)} | Pur.Rate: ₹${med.purRate.toStringAsFixed(2)} | Stock: ${med.stock.toInt()}", style: const TextStyle(color: Colors.white38, fontSize: 10)),
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
      ),
    );
  }

  Widget _buildCartTable(PharoahWebManager webPh) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Text("INWARD ITEMS (${items.length})", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
          const Divider(color: Colors.white10, height: 16),
          if (items.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("Inward cart is empty. Search products above to add stock.", style: TextStyle(color: Colors.white38, fontSize: 11))))
          else
            Container(
              constraints: const BoxConstraints(minHeight: 220, maxHeight: 520),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 700),
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(35),
                          1: FlexColumnWidth(3),
                          2: FixedColumnWidth(65),
                          3: FixedColumnWidth(75),
                          4: FixedColumnWidth(55),
                          5: FixedColumnWidth(65),
                          6: FixedColumnWidth(70),
                          7: FixedColumnWidth(55),
                          8: FixedColumnWidth(50),
                          9: FixedColumnWidth(80),
                          10: FixedColumnWidth(65),
                        },
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                            children: [
                              _th("SN"), _th("PRODUCT NAME", isLeft: true), _th("PACK"), _th("BATCH"), _th("EXP"), _th("QTY"), _th("RATE"), _th("DISC"), _th("GST%"), _th("TOTAL"), _th("ACT")
                            ],
                          ),
                          ...items.asMap().entries.map((entry) {
                            int idx = entry.key;
                            PurchaseItem it = entry.value;
                            String qtyDisp = "${it.qty.toInt()}${it.freeQty > 0 ? ' + ${it.freeQty.toInt()}' : ''}";
                            String discDisp = it.discountRupees > 0 ? "₹${it.discountRupees.toStringAsFixed(1)}" : (it.discountPer > 0 ? "${it.discountPer}%" : "-");

                            return TableRow(
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                              children: [
                                _td("${idx + 1}"),
                                _td(it.name, isLeft: true, isBold: true),
                                _td(it.packing),
                                _td(it.batch),
                                _td(it.exp),
                                _td(qtyDisp, isBold: true, color: const Color(0xFFF59E0B)),
                                _td("₹${it.purchaseRate.toStringAsFixed(2)}"),
                                _td(discDisp, color: Colors.orangeAccent),
                                _td("${it.gstRate.toInt()}%"),
                                _td("₹${it.total.toStringAsFixed(2)}", isBold: true, color: Colors.greenAccent),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (!widget.isReadOnly)
                                      IconButton(
                                        icon: const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF38BDF8)),
                                        onPressed: () {
                                          final med = webPh.medicines.firstWhere((m) => m.id == it.medicineID);
                                          _openItemDialog(webPh, med, itemToEdit: it, editIndex: idx);
                                        },
                                      ),
                                    if (!widget.isReadOnly)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                                        onPressed: () => setState(() {
                                          items.removeAt(idx);
                                          _recalculateSR();
                                        }),
                                      ),
                                  ],
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter(PharoahWebManager webPh) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text("Extra Disc (-): ", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  SizedBox(
                    width: 80,
                    height: 34,
                    child: TextField(
                      controller: extraDiscC,
                      readOnly: widget.isReadOnly,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              Text("R/O: ₹${roundOff.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: isSaving ? null : () => _finalizePurchase(webPh, andPrint: false),
                  icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(isSaving ? "SAVING..." : "SAVE & ADD STOCK", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFF59E0B), side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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

  Widget _th(String t, {bool isLeft = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)));
  Widget _td(String t, {bool isLeft = false, bool isBold = false, Color color = Colors.white}) => Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4), child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: TextStyle(color: color, fontSize: 10.5, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)));
}
