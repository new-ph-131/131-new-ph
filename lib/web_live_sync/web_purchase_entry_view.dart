import 'web_pdf_router_service.dart';
// FILE: lib/web_live_sync/web_purchase_entry_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'sub_views/web_billing/quick_add_party_modal.dart';
import 'sub_views/web_billing/quick_add_product_modal.dart';
import 'sub_views/web_billing/web_batch_lookup_dialog.dart';

class WebPurchaseEntryView extends StatefulWidget {
  final VoidCallback onBack;
  final int initialTabIndex;

  // 🆕 ADDED FOR DRAFT / STITCHER & EDIT SUPPORT
  final Party? initialSupplier;
  final String? initialInternalNo;
  final String? initialBillNo;
  final DateTime? initialDate;
  final DateTime? initialEntryDate;
  final String? initialMode;
  final List<PurchaseItem>? existingItems;
  final List<String>? linkedChallanIds;
  final String? modifyPurchaseId;
  final bool isReadOnly;

  const WebPurchaseEntryView({
    super.key,
    required this.onBack,
    this.initialTabIndex = 0,
    this.initialSupplier,
    this.initialInternalNo,
    this.initialBillNo,
    this.initialDate,
    this.initialEntryDate,
    this.initialMode,
    this.existingItems,
    this.linkedChallanIds,
    this.modifyPurchaseId,
    this.isReadOnly = false,
  });

  @override
  State<WebPurchaseEntryView> createState() => _WebPurchaseEntryViewState();
}

class _WebPurchaseEntryViewState extends State<WebPurchaseEntryView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final supplierBillNoC = TextEditingController();
  final internalNoC = TextEditingController();
  final extraDiscC = TextEditingController(text: "0");
  final productSearchC = TextEditingController();
  final supplierSearchC = TextEditingController();

  DateTime billDate = DateTime.now();
  DateTime entryDate = DateTime.now();
  String paymentMode = "CREDIT";

  Party? selectedSupplier;
  List<PurchaseItem> purchaseItems = [];
  bool isSaving = false;

  String registerSearchQuery = "";
  static const String currentTestId = "#PH-REV-116";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    _initBillingSession(webPh);
  }

  void _initBillingSession(PharoahWebManager webPh) {
    if (widget.initialSupplier != null || widget.existingItems != null) {
      // 🆕 DRAFT / MODIFY MODE
      billDate = widget.initialDate ?? DateTime.now();
      entryDate = widget.initialEntryDate ?? DateTime.now();
      paymentMode = widget.initialMode ?? "CREDIT";
      internalNoC.text = widget.initialInternalNo ?? "DRAFT";
      supplierBillNoC.text = widget.initialBillNo ?? "";
      selectedSupplier = widget.initialSupplier;
      
      if (widget.existingItems != null) {
        purchaseItems = List.from(widget.existingItems!);
      }
      
      if (widget.modifyPurchaseId != null) {
        try {
          final exPur = webPh.purchases.firstWhere((p) => p.id == widget.modifyPurchaseId);
          extraDiscC.text = exPur.extraDiscount.toString();
        } catch (_) {}
      }
    } else {
      // NORMAL NEW ENTRY
      internalNoC.text = webPh.getNextBillNumber("PURCHASE", "PUR-", 1);
      billDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
      entryDate = DateTime.now();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    supplierBillNoC.dispose();
    internalNoC.dispose();
    extraDiscC.dispose();
    productSearchC.dispose();
    supplierSearchC.dispose();
    super.dispose();
  }

  void _openPurchaseItemDialog(PharoahWebManager webPh, Medicine med, {PurchaseItem? itemToEdit, int? editIndex}) {
    if (widget.isReadOnly) return;

    final batchC = TextEditingController(text: itemToEdit?.batch ?? "");
    final expC = TextEditingController(text: itemToEdit?.exp ?? "12/28");
    final mrpC = TextEditingController(text: itemToEdit?.mrp.toStringAsFixed(2) ?? med.mrp.toStringAsFixed(2));
    final purRateC = TextEditingController(text: itemToEdit?.purchaseRate.toStringAsFixed(2) ?? med.purRate.toStringAsFixed(2));
    final rateAC = TextEditingController(text: itemToEdit?.rateA.toStringAsFixed(2) ?? med.rateA.toStringAsFixed(2));
    final rateBC = TextEditingController(text: itemToEdit?.rateB.toStringAsFixed(2) ?? med.rateB.toStringAsFixed(2));
    final rateCC = TextEditingController(text: itemToEdit?.rateC.toStringAsFixed(2) ?? med.rateC.toStringAsFixed(2));
    final rateCDiscC = TextEditingController(text: itemToEdit?.rateCFormula.toString() ?? "0.0");
    final qtyC = TextEditingController(text: itemToEdit?.qty.toInt().toString() ?? "1");
    final freeC = TextEditingController(text: itemToEdit?.freeQty.toInt().toString() ?? "0");
    final gstC = TextEditingController(text: itemToEdit?.gstRate.toString() ?? med.gst.toString());
    final discPerC = TextEditingController(text: itemToEdit?.discountPer.toString() ?? "0.0");
    final discAmtC = TextEditingController(text: itemToEdit?.discountRupees.toString() ?? "0.0");

    String selectedRateType = itemToEdit?.appliedRateType ?? "A";
    List<BatchInfo> availableBatches = webPh.batchHistory[med.identityKey] ?? [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          void calculateRateC() {
            double mrp = double.tryParse(mrpC.text) ?? 0.0;
            double gst = double.tryParse(gstC.text) ?? 0.0;
            double formulaDisc = double.tryParse(rateCDiscC.text) ?? 0.0;
            double baseTaxable = (mrp / (1 + (gst / 100)));
            double finalDerivedRate = baseTaxable - (baseTaxable * (formulaDisc / 100));
            rateCC.text = finalDerivedRate.toStringAsFixed(2);
          }

          void syncDiscount(bool isPercentSource) {
            double q = double.tryParse(qtyC.text) ?? 0;
            double pRate = double.tryParse(purRateC.text) ?? 0;
            double gross = q * pRate;
            if (gross <= 0) return;
            if (isPercentSource) {
              double p = double.tryParse(discPerC.text) ?? 0;
              discAmtC.text = (gross * (p / 100)).toStringAsFixed(2);
            } else {
              double a = double.tryParse(discAmtC.text) ?? 0;
              discPerC.text = ((a / gross) * 100).toStringAsFixed(2);
            }
          }

          double q = double.tryParse(qtyC.text) ?? 0.0;
          double pRate = double.tryParse(purRateC.text) ?? 0.0;
          double dAmt = double.tryParse(discAmtC.text) ?? 0.0;
          double gPer = double.tryParse(gstC.text) ?? 0.0;

          double gross = q * pRate;
          double taxable = gross - dAmt;
          double itemTotal = taxable * (1 + gPer / 100);

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.white12),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0x33F59E0B),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.downloading_rounded, color: Color(0xFFF59E0B), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "PURCHASE INWARD ITEM ENTRY",
                        style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                      ),
                      Text(
                        "${med.name} (${med.packing})",
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(c),
                ),
              ],
            ),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: _dialogInput(
                            "BATCH NO (CASE-SENSITIVE) *",
                            batchC,
                            isHighlight: true,
                            suffix: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF59E0B),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                final selected = await showDialog<dynamic>(
                                  context: context,
                                  builder: (ctx) => WebBatchLookupDialog(
                                    medicine: med,
                                    batches: availableBatches,
                                    prioritizeExpired: false,
                                  ),
                                );
                                if (selected != null && selected is BatchInfo) {
                                  setDialogState(() {
                                    batchC.text = selected.batch;
                                    expC.text = selected.exp;
                                    mrpC.text = selected.mrp.toStringAsFixed(2);
                                    purRateC.text = selected.purRate.toStringAsFixed(2);
                                    rateAC.text = selected.rateA.toStringAsFixed(2);
                                    rateBC.text = selected.rateB.toStringAsFixed(2);
                                    rateCC.text = selected.rateC.toStringAsFixed(2);
                                    rateCDiscC.text = selected.rateCFormula.toStringAsFixed(2);
                                    selectedRateType = selected.appliedRateType;
                                    syncDiscount(true);
                                  });
                                }
                              },
                              icon: const Icon(Icons.layers_rounded, size: 14),
                              label: const Text("BATCHES", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: _dialogInput("EXPIRY (MM/YY) *", expC, isNum: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dialogInput("MRP ₹", mrpC, isNum: true, onChanged: (_) => setDialogState(() {}))),
                        const SizedBox(width: 10),
                        Expanded(child: _dialogInput("PUR. RATE ₹ *", purRateC, isNum: true, isHighlight: true, onChanged: (_) => setDialogState(() => syncDiscount(true)))),
                        const SizedBox(width: 10),
                        Expanded(child: _dialogInput("GST %", gstC, isNum: true, onChanged: (_) => setDialogState(() {}))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dialogInput("QTY *", qtyC, isNum: true, isHighlight: true, onChanged: (_) => setDialogState(() => syncDiscount(true)))),
                        const SizedBox(width: 10),
                        Expanded(child: _dialogInput("FREE QTY", freeC, isNum: true)),
                        const SizedBox(width: 10),
                        Expanded(child: _dialogInput("DISC %", discPerC, isNum: true, onChanged: (_) => setDialogState(() => syncDiscount(true)))),
                        const SizedBox(width: 10),
                        Expanded(child: _dialogInput("DISC ₹", discAmtC, isNum: true, onChanged: (_) => setDialogState(() => syncDiscount(false)))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white10),
                    Row(
                      children: [
                        const Text("APPLY RATE SCHEME:", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 10),
                        _segmentRate("RATE A", selectedRateType == "A", () => setDialogState(() => selectedRateType = "A")),
                        const SizedBox(width: 6),
                        _segmentRate("RATE B", selectedRateType == "B", () => setDialogState(() => selectedRateType = "B")),
                        const SizedBox(width: 6),
                        _segmentRate("RATE C", selectedRateType == "C", () {
                          setDialogState(() {
                            selectedRateType = "C";
                            calculateRateC();
                          });
                        }),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (selectedRateType == "C") ...[
                          Expanded(child: _dialogInput("C FORMULA %", rateCDiscC, isNum: true, onChanged: (_) => setDialogState(() => calculateRateC()))),
                          const SizedBox(width: 8),
                        ],
                        Expanded(child: _dialogInput("RATE A ₹", rateAC, isNum: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _dialogInput("RATE B ₹", rateBC, isNum: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _dialogInput("RATE C ₹", rateCC, isNum: true, isReadOnly: selectedRateType == "C")),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Taxable: ₹${taxable.toStringAsFixed(2)} | GST: ₹${(itemTotal - taxable).toStringAsFixed(2)}",
                              style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.bold)),
                          Text("₹${itemTotal.toStringAsFixed(2)}",
                              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 18, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  if (batchC.text.trim().isEmpty || expC.text.trim().isEmpty || q <= 0 || pRate <= 0) return;

                  double mrp = double.tryParse(mrpC.text) ?? 0.0;
                  double a = double.tryParse(rateAC.text) ?? mrp;
                  double b = double.tryParse(rateBC.text) ?? (a * 0.95);
                  double rateCVal = double.tryParse(rateCC.text) ?? (a * 0.92);

                  final newItem = PurchaseItem(
                    id: itemToEdit?.id ?? "PITM-${DateTime.now().millisecondsSinceEpoch}",
                    srNo: itemToEdit != null ? itemToEdit.srNo : purchaseItems.length + 1,
                    medicineID: med.id,
                    name: med.name,
                    packing: med.packing,
                    batch: batchC.text.trim(),
                    exp: expC.text.trim(),
                    hsn: med.hsnCode,
                    mrp: mrp,
                    qty: q,
                    freeQty: double.tryParse(freeC.text) ?? 0.0,
                    purchaseRate: pRate,
                    gstRate: gPer,
                    total: itemTotal,
                    rateA: a,
                    rateB: b,
                    rateC: rateCVal,
                    discountPer: double.tryParse(discPerC.text) ?? 0.0,
                    discountRupees: dAmt,
                    appliedRateType: selectedRateType,
                    rateCFormula: double.tryParse(rateCDiscC.text) ?? 0.0,
                  );

                  setState(() {
                    if (editIndex != null) {
                      purchaseItems[editIndex] = newItem;
                    } else {
                      purchaseItems.add(newItem);
                    }
                  });

                  Navigator.pop(c);
                },
                child: Text(itemToEdit != null ? "UPDATE ITEM" : "ADD TO INWARD", style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          );
        },
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
          _openPurchaseItemDialog(webPh, medObj);
        },
      ),
    );
  }

  void _openQuickAddSupplier(PharoahWebManager webPh) {
    if (widget.isReadOnly) return;
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        onPartyCreated: (newSupplier) {
          setState(() => selectedSupplier = newSupplier);
        },
      ),
    );
  }

  double get subTotal => purchaseItems.fold(0.0, (sum, it) => sum + it.total);
  double get totalTaxable => purchaseItems.fold(0.0, (sum, it) => sum + (it.qty * it.purchaseRate - it.discountRupees));
  double get totalITC => subTotal - totalTaxable;
  double get extraDiscount => double.tryParse(extraDiscC.text) ?? 0.0;
  double get rawGrandTotal => (subTotal - extraDiscount);
  double get finalGrandTotal => rawGrandTotal.roundToDouble();
  double get roundOff => double.parse((finalGrandTotal - rawGrandTotal).toStringAsFixed(2));

  void _savePurchase(PharoahWebManager webPh) {
    if (selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a Supplier / Distributor!"), backgroundColor: Colors.orange),
      );
      return;
    }

    if (supplierBillNoC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Supplier Bill No is required!"), backgroundColor: Colors.orange),
      );
      return;
    }

    if (purchaseItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Purchase cannot be empty! Please add products."), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => isSaving = true);

    final newPurchase = Purchase(
      id: widget.modifyPurchaseId ?? "PUR-WEB-${DateTime.now().millisecondsSinceEpoch}",
      internalNo: internalNoC.text.trim(),
      billNo: supplierBillNoC.text.trim(),
      partyId: selectedSupplier!.id,
      distributorName: selectedSupplier!.name,
      date: billDate,
      entryDate: entryDate,
      paymentMode: paymentMode,
      totalAmount: finalGrandTotal,
      extraDiscount: extraDiscount,
      roundOff: roundOff,
      gstStatus: "Pending",
      items: List.from(purchaseItems),
      linkedChallanIds: widget.linkedChallanIds ?? [],
      sourceTag: "WEB-PORTAL",
    );

    if (widget.modifyPurchaseId != null) webPh.deletePurchase(widget.modifyPurchaseId!);
    webPh.addPurchaseAndSync(newPurchase);
    
    // 🆕 Mark challans as billed if from stitcher
    if (widget.linkedChallanIds != null) {
      for (var id in widget.linkedChallanIds!) {
        int idx = webPh.purchaseChallans.indexWhere((c) => c.id == id);
        if (idx != -1) webPh.purchaseChallans[idx].status = "Billed";
      }
      webPh.pushUpdatedDataToCloud();
    }

    setState(() => isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✅ Purchase Inward ${internalNoC.text} Saved & Stock Updated!"), backgroundColor: Colors.green),
    );

    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    // Agar hum sirf ek single record view/edit kar rahe hain toh tab menu hide kardo
    if (widget.initialSupplier != null || widget.existingItems != null) {
      return _buildNewPurchaseTab(webPh);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.downloading_rounded, color: Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 10),
              const Text(
                "PURCHASE INWARD & REGISTER",
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x33F59E0B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: const Text(
                  currentTestId,
                  style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          // Tabs Switcher
          Container(
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFFF59E0B),
              labelColor: const Color(0xFFFBBF24),
              unselectedLabelColor: Colors.white54,
              tabs: [
                const Tab(text: "NEW PURCHASE INWARD", icon: Icon(Icons.add_shopping_cart_rounded, size: 16)),
                Tab(text: "PURCHASE REGISTER (${webPh.purchases.length})", icon: const Icon(Icons.history_rounded, size: 16)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildNewPurchaseTab(webPh),
                _buildPurchaseRegisterTab(webPh),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 1: NEW PURCHASE INWARD ENTRY / MODIFY
  Widget _buildNewPurchaseTab(PharoahWebManager webPh) {
    return IgnorePointer(
      ignoring: widget.isReadOnly,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderBar(webPh),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 7,
                  child: Column(
                    children: [
                      if (!widget.isReadOnly) _buildProductSearchCard(webPh),
                      if (!widget.isReadOnly) const SizedBox(height: 16),
                      Expanded(child: _buildCartTable(webPh)),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      _buildSupplierCard(webPh),
                      const SizedBox(height: 16),
                      _buildGrandTotalCard(webPh),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 2: PURCHASE REGISTER (ALL PURCHASES FROM APP & WEB)
  Widget _buildPurchaseRegisterTab(PharoahWebManager webPh) {
    List<Purchase> allPurchases = List.from(webPh.purchases);
    allPurchases.sort((a, b) => b.date.compareTo(a.date));

    final filtered = allPurchases.where((p) =>
        p.distributorName.toLowerCase().contains(registerSearchQuery.toLowerCase()) ||
        p.billNo.toLowerCase().contains(registerSearchQuery.toLowerCase()) ||
        p.internalNo.toLowerCase().contains(registerSearchQuery.toLowerCase())).toList();

    double totalInwardVal = allPurchases.fold(0.0, (sum, p) => sum + p.totalAmount);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 38,
                decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: "Search Purchase by Supplier Name, Bill No or Entry ID...",
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                    prefixIcon: Icon(Icons.search, color: Color(0xFFF59E0B), size: 16),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) => setState(() => registerSearchQuery = v),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Text("TOTAL PURCHASES: ₹${totalInwardVal.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 12, fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text("No purchase records found in database.", style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (c, i) {
                    final p = filtered[i];
                    bool isWeb = p.sourceTag == "WEB-PORTAL" || p.id.startsWith("PUR-WEB");

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0x33F59E0B),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            p.internalNo.isNotEmpty ? p.internalNo : "PUR-${i + 1}",
                            style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(p.distributorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isWeb ? const Color(0x3338BDF8) : const Color(0x3310B981),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isWeb ? "WEB" : "APP",
                                style: TextStyle(color: isWeb ? const Color(0xFF38BDF8) : Colors.greenAccent, fontSize: 7.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          "Supplier Bill: ${p.billNo} • Date: ${WebAppDateLogic.format(p.date)} • Mode: ${p.paymentMode} • Items: ${p.items.length}",
                          style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "₹${p.totalAmount.toStringAsFixed(2)}",
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                              tooltip: "Delete Purchase",
                              onPressed: () {
                                webPh.deletePurchase(p.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHeaderBar(PharoahWebManager webPh) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          // Agar hum Draft/Modify mode me hain, toh back button dikhayein
          if (widget.initialSupplier != null || widget.existingItems != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 14),
                label: const Text("BACK", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
            
          SizedBox(
            width: 110,
            height: 36,
            child: TextField(
              controller: internalNoC,
              readOnly: widget.initialInternalNo != null || widget.isReadOnly,
              style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w900, fontSize: 12),
              decoration: InputDecoration(
                labelText: "ENTRY ID",
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            height: 36,
            child: TextField(
              controller: supplierBillNoC,
              readOnly: widget.initialBillNo != null || widget.isReadOnly,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
              decoration: InputDecoration(
                labelText: "BILL NO *",
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: widget.isReadOnly ? null : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: billDate,
                firstDate: WebAppDateLogic.getFYStart(webPh.financialYear),
                lastDate: WebAppDateLogic.getFYEnd(webPh.financialYear),
              );
              if (picked != null) setState(() => billDate = picked);
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: Color(0xFFF59E0B), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    WebAppDateLogic.format(billDate),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'CASH', label: Text('CASH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
              ButtonSegment(value: 'CREDIT', label: Text('CREDIT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
            ],
            selected: {paymentMode},
            onSelectionChanged: widget.isReadOnly ? null : (v) => setState(() => paymentMode = v.first),
          ),
        ],
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
            .take(6)
            .toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
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
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                    hintText: "Type medicine name to add inward stock...",
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFFF59E0B), size: 18),
                    suffixIcon: productSearchC.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                            onPressed: () => setState(() => productSearchC.clear()),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                  onChanged: (v) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: () => _openQuickAddProduct(webPh),
                icon: const Icon(Icons.add_box_rounded, size: 18),
                label: const Text("+ PRODUCT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
              ),
            ],
          ),
          if (matchingMeds.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
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
                  return Container(
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      leading: const Icon(Icons.medication_rounded, color: Color(0xFFF59E0B), size: 18),
                      title: Row(
                        children: [
                          Text(med.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                          const SizedBox(width: 8),
                          Text("(${med.packing})", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          const Spacer(),
                          Text(
                            "Stock: ${med.stock.toInt()} Qty",
                            style: TextStyle(
                              color: med.stock > 0 ? Colors.greenAccent : Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        "MRP: ₹${med.mrp.toStringAsFixed(2)} | Pur Rate: ₹${med.purRate.toStringAsFixed(2)} | GST: ${med.gst.toInt()}%",
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                      onTap: () {
                        setState(() => productSearchC.clear());
                        _openPurchaseItemDialog(webPh, med);
                      },
                    ),
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
              const Icon(Icons.inventory_2_rounded, color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Text(
                "INWARD ITEMS (${purchaseItems.length})",
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const Spacer(),
              if (purchaseItems.isNotEmpty && !widget.isReadOnly)
                TextButton(
                  onPressed: () => setState(() => purchaseItems.clear()),
                  child: const Text("Clear All", style: TextStyle(color: Colors.redAccent, fontSize: 10)),
                ),
            ],
          ),
          const Divider(color: Colors.white10, height: 20),
          if (purchaseItems.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text("Inward cart is empty. Search products above to add stock.", style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 650),
                  child: SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FixedColumnWidth(35),
                        1: FlexColumnWidth(3),
                        2: FixedColumnWidth(65),
                        3: FixedColumnWidth(75),
                        4: FixedColumnWidth(55),
                        5: FixedColumnWidth(65),
                        6: FixedColumnWidth(70),
                        7: FixedColumnWidth(45),
                        8: FixedColumnWidth(80),
                        9: FixedColumnWidth(55),
                      },
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                          children: [
                            _th("SN"),
                            _th("PRODUCT NAME", isLeft: true),
                            _th("PACK"),
                            _th("BATCH"),
                            _th("EXP"),
                            _th("QTY"),
                            _th("PUR. RATE"),
                            _th("GST%"),
                            _th("TOTAL"),
                            _th("ACT"),
                          ],
                        ),
                        ...purchaseItems.asMap().entries.map((entry) {
                          int idx = entry.key;
                          PurchaseItem it = entry.value;
                          String qtyDisp = "${it.qty.toInt()}${it.freeQty > 0 ? ' + ${it.freeQty.toInt()}' : ''}";

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
                              _td("${it.gstRate.toInt()}%"),
                              _td("₹${it.total.toStringAsFixed(2)}", isBold: true, color: Colors.greenAccent),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (!widget.isReadOnly)
                                    IconButton(
                                      icon: const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF38BDF8)),
                                      onPressed: () {
                                        final med = webPh.medicines.firstWhere(
                                          (m) => m.id == it.medicineID || m.name == it.name,
                                          orElse: () => Medicine(id: it.medicineID, name: it.name, packing: it.packing),
                                        );
                                        _openPurchaseItemDialog(webPh, med, itemToEdit: it, editIndex: idx);
                                      },
                                    ),
                                  if (!widget.isReadOnly)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                                      onPressed: () => setState(() => purchaseItems.removeAt(idx)),
                                    ),
                                  if (widget.isReadOnly)
                                    const Icon(Icons.lock_rounded, size: 14, color: Colors.white38)
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
        ],
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: TextStyle(color: color, fontSize: 10.5, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
  );

  Widget _buildSupplierCard(PharoahWebManager webPh) {
    final suppQuery = supplierSearchC.text.trim().toLowerCase();
    final matchingSuppliers = suppQuery.isEmpty
        ? <Party>[]
        : webPh.parties
            .where((p) =>
                p.group == "Sundry Creditors" &&
                (p.name.toLowerCase().contains(suppQuery) ||
                 p.city.toLowerCase().contains(suppQuery)))
            .take(5)
            .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.business_rounded, color: Color(0xFFF59E0B), size: 16),
                  SizedBox(width: 8),
                  Text("SUPPLIER / DISTRIBUTOR", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ],
              ),
              if (!widget.isReadOnly)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                  ),
                  onPressed: () => _openQuickAddSupplier(webPh),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 12),
                  label: const Text("+ SUPPLIER", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const Divider(color: Colors.white10, height: 16),
          if (selectedSupplier != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x66F59E0B)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selectedSupplier!.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text("GST: ${selectedSupplier!.gst} | City: ${selectedSupplier!.city}", style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
                      ],
                    ),
                  ),
                  if (!widget.isReadOnly)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
                      onPressed: () => setState(() => selectedSupplier = null),
                    ),
                ],
              ),
            )
          else ...[
            TextField(
              controller: supplierSearchC,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              decoration: InputDecoration(
                hintText: "Search Supplier by Name or City...",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon: const Icon(Icons.search, color: Color(0xFFF59E0B), size: 16),
                suffixIcon: supplierSearchC.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54, size: 14),
                        onPressed: () => setState(() => supplierSearchC.clear()),
                      )
                    : null,
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              onChanged: (v) => setState(() {}),
            ),
            if (matchingSuppliers.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 140),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0x33F59E0B)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  itemCount: matchingSuppliers.length,
                  itemBuilder: (context, idx) {
                    final party = matchingSuppliers[idx];
                    return ListTile(
                      dense: true,
                      title: Text(party.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                      subtitle: Text("${party.city} | GST: ${party.gst}", style: const TextStyle(color: Colors.white38, fontSize: 9)),
                      onTap: () {
                        setState(() {
                          selectedSupplier = party;
                          supplierSearchC.clear();
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildGrandTotalCard(PharoahWebManager webPh) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF19243B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x66F59E0B), width: 1.2),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 15, offset: Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("INWARD SUMMARY", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const Divider(color: Colors.white10, height: 20),
          _sumRow("Taxable Inward Value", "₹${totalTaxable.toStringAsFixed(2)}"),
          _sumRow("Input GST (ITC)", "₹${totalITC.toStringAsFixed(2)}"),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Extra Discount (-)", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              SizedBox(
                width: 80,
                height: 30,
                child: TextField(
                  controller: extraDiscC,
                  readOnly: widget.isReadOnly,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black38,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ],
          ),
          _sumRow("Round Off", "₹${roundOff.toStringAsFixed(2)}"),
          const Divider(color: Colors.white24, height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TOTAL INWARD VALUE", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
              Text(
                "₹${finalGrandTotal.toStringAsFixed(0)}.00",
                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 24, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 25),
          if (!widget.isReadOnly) ...[
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: isSaving ? null : () => _savePurchase(webPh),
                icon: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.check_circle_rounded, size: 18),
                label: Text(
                  isSaving ? "SAVING..." : "SAVE & ADD STOCK",
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 0.5),
                ),
              ),
            ),
          ] else ...[
             SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () async {
                  final Party activeParty = selectedSupplier ?? Party(id: 'cash', name: 'CASH', group: 'Cash in Hand');
                  final tempPur = Purchase(
                    id: "temp", internalNo: internalNoC.text.trim(), billNo: supplierBillNoC.text.trim(), partyId: activeParty.id, distributorName: activeParty.name,
                    date: billDate, entryDate: entryDate, paymentMode: paymentMode,
                    totalAmount: finalGrandTotal, extraDiscount: extraDiscount, roundOff: roundOff,
                    gstStatus: "Pending", items: List.from(purchaseItems), sourceTag: "WEB-PORTAL",
                  );
                  await WebPdfRouterService.printPurchaseInvoice(purchase: tempPur, party: activeParty, shop: CompanyProfile.fromMap(webPh.companyProfile));
                },
                icon: const Icon(Icons.print_rounded, size: 18),
                label: const Text("PRINT THIS INWARD SLIP", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 0.5)),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _sumRow(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
    ]),
  );

  Widget _dialogInput(
    String label,
    TextEditingController ctrl, {
    bool isNum = false,
    bool isCaps = false,
    bool isHighlight = false,
    bool isReadOnly = false,
    Widget? suffix,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: isReadOnly ? Colors.black38 : (isHighlight ? const Color(0x33F59E0B) : Colors.black26),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isHighlight ? const Color(0xFFF59E0B) : Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  readOnly: isReadOnly,
                  onChanged: onChanged,
                  keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                  textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (suffix != null) suffix,
            ],
          ),
        ),
      ],
    );
  }

  Widget _segmentRate(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF59E0B) : Colors.black26,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
