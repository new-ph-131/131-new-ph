import 'mechanism/web_billing_gst_engine.dart';
// FILE: lib/web_live_sync/sub_views/web_billing/web_new_sale_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../web_models.dart';
import '../../pharoah_web_manager.dart';
import '../../web_app_date_logic.dart';
import '../../web_pharoah_numbering_engine.dart';
import '../../web_pdf_router_service.dart';
import 'web_item_entry_card.dart';
import 'quick_add_party_modal.dart';
import 'quick_add_product_modal.dart';

class WebNewSaleView extends StatefulWidget {
  final VoidCallback onBack;
  final Party? initialParty;
  final String? initialBillNo;
  final DateTime? initialDate;
  final String? initialMode;
  final List<BillItem>? existingItems;
  final List<String>? linkedChallanIds;
  final String? modifySaleId;
  final bool isReadOnly;

  const WebNewSaleView({
    super.key, 
    required this.onBack,
    this.initialParty,
    this.initialBillNo,
    this.initialDate,
    this.initialMode,
    this.existingItems,
    this.linkedChallanIds,
    this.modifySaleId,
    this.isReadOnly = false,
  });

  @override
  State<WebNewSaleView> createState() => _WebNewSaleViewState();
}

class _WebNewSaleViewState extends State<WebNewSaleView> {
  final billNoC = TextEditingController();
  final extraDiscC = TextEditingController(text: "0.0");
  final extraDiscPercentC = TextEditingController(text: "0.0");
  final productSearchC = TextEditingController();
  final customerSearchC = TextEditingController();

  DateTime billDate = DateTime.now();
  String paymentMode = "CASH";

  NumberingSeries? selectedSeries;
  Party? selectedParty;
  List<BillItem> billItems = [];
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    _initBillingSession(webPh);
  }

  void _initBillingSession(PharoahWebManager webPh) {
    if (widget.initialParty != null || widget.existingItems != null) {
      billDate = widget.initialDate ?? DateTime.now();
      paymentMode = widget.initialMode ?? "CASH";
      billNoC.text = widget.initialBillNo ?? "DRAFT";
      selectedParty = widget.initialParty;
      
      if (widget.existingItems != null) {
        billItems = List.from(widget.existingItems!);
      }
      
      if (widget.modifySaleId != null) {
        try {
          final exSale = webPh.sales.firstWhere(
            (s) => s.id == widget.modifySaleId || s.billNo == widget.initialBillNo,
          );
          extraDiscC.text = exSale.extraDiscount.toStringAsFixed(2);
          if (subTotal > 0 && exSale.extraDiscount > 0) {
            extraDiscPercentC.text = ((exSale.extraDiscount / subTotal) * 100.0).toStringAsFixed(2);
          }
          if (exSale.partyName.isNotEmpty) {
            try {
              selectedParty = webPh.parties.firstWhere(
                (p) => p.id == exSale.partyId || p.name.trim().toLowerCase() == exSale.partyName.trim().toLowerCase(),
                orElse: () => selectedParty ?? Party(
                  id: exSale.partyId.isNotEmpty ? exSale.partyId : 'party_${DateTime.now().millisecondsSinceEpoch}',
                  name: exSale.partyName,
                  gst: exSale.partyGstin,
                  state: exSale.partyState,
                  address: exSale.partyAddress,
                  city: exSale.partyCity,
                  phone: exSale.partyPhone,
                  email: exSale.partyEmail,
                  dl: exSale.partyDl,
                  pan: exSale.partyPan,
                ),
              );
            } catch (_) {}
          }
          billDate = exSale.date;
          paymentMode = exSale.paymentMode;
        } catch (_) {}
      }
    } else {
      billDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
      final activeSeriesList = webPh.numberingSeries.where((s) => s.type == "SALE" && s.isActive).toList();
      if (activeSeriesList.isNotEmpty) {
        selectedSeries = activeSeriesList.firstWhere((s) => s.isDefault, orElse: () => activeSeriesList.first);
      }
      _refreshBillNumber(webPh);
    }
  }

  void _refreshBillNumber(PharoahWebManager webPh) {
    if (widget.initialBillNo != null && widget.initialBillNo != "DRAFT") return;
    String prefix = selectedSeries != null && selectedSeries!.prefix != "INV-" ? selectedSeries!.prefix : "W-";
    int start = selectedSeries?.startNumber ?? 101;
    billNoC.text = WebPharoahNumberingEngine.getNextNumber(
      prefix: prefix,
      startFrom: start,
      currentList: webPh.sales,
    );
  }

  void _handlePartySelected(PharoahWebManager webPh, Party party) {
    setState(() {
      selectedParty = party;
      customerSearchC.clear();
      if (party.defaultSeriesId.isNotEmpty) {
        try {
          selectedSeries = webPh.numberingSeries.firstWhere((s) => s.id == party.defaultSeriesId);
        } catch (_) {}
      }
    });
    _refreshBillNumber(webPh);
  }

  @override
  void dispose() {
    billNoC.dispose();
    extraDiscC.dispose();
    extraDiscPercentC.dispose();
    productSearchC.dispose();
    customerSearchC.dispose();
    super.dispose();
  }

  void _openItemEntry(Medicine med, {BillItem? itemToEdit, int? editIndex}) {
    if (widget.isReadOnly) return;

    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    String shopState = (webPh.companyProfile['state'] ?? 'Rajasthan').toString();
    String partyState = selectedParty?.state ?? 'Rajasthan';

    List<BatchInfo> batches = webPh.batchHistory[med.identityKey] ?? [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => WebItemEntryCard(
        med: med,
        srNo: itemToEdit != null ? itemToEdit.srNo : billItems.length + 1,
        partyState: partyState,
        shopState: shopState,
        availableBatches: batches,
        existingItem: itemToEdit,
        onAdd: (newItem) {
          setState(() {
            if (editIndex != null) {
              billItems[editIndex] = newItem;
            } else {
              billItems.add(newItem);
            }
          });
          Navigator.pop(context);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }


  void _onExtraDiscPercentChanged(String v) {
    double p = double.tryParse(v) ?? 0.0;
    if (subTotal > 0) {
      double rupees = subTotal * (p / 100.0);
      extraDiscC.text = rupees.toStringAsFixed(2);
    }
    setState(() {});
  }

  void _onExtraDiscAmountChanged(String v) {
    double amt = double.tryParse(v) ?? 0.0;
    if (subTotal > 0) {
      double pct = (amt / subTotal) * 100.0;
      extraDiscPercentC.text = pct.toStringAsFixed(2);
    }
    setState(() {});
  }

  void _openPartyPickerModal(PharoahWebManager webPh) {
    if (widget.isReadOnly) return;
    String searchTxt = "";
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final list = webPh.parties.where((p) {
            if (searchTxt.isEmpty) return true;
            final q = searchTxt.toLowerCase();
            return p.name.toLowerCase().contains(q) ||
                p.city.toLowerCase().contains(q) ||
                p.gst.toLowerCase().contains(q) ||
                p.phone.toLowerCase().contains(q);
          }).toList();

          return Dialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 550,
              height: 520,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_alt_rounded, color: Color(0xFF38BDF8), size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        "SELECT CUSTOMER / PARTY",
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "Search customer by name, city, GST, phone...",
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 20),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onChanged: (v) => setDlgState(() => searchTxt = v.trim()),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () {
                      _handlePartySelected(webPh, Party(id: 'cash', name: 'CASH', group: 'Cash in Hand'));
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.greenAccent.withAlpha(100)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.payments_rounded, color: Colors.greenAccent, size: 18),
                          SizedBox(width: 10),
                          Text("CASH CUSTOMER (Walk-in)", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: list.isEmpty
                        ? const Center(child: Text("No customers found.", style: TextStyle(color: Colors.white38)))
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                            itemBuilder: (context, idx) {
                              final p = list[idx];
                              final isSelected = selectedParty?.id == p.id;
                              return ListTile(
                                dense: true,
                                selected: isSelected,
                                selectedTileColor: Colors.blue.withAlpha(40),
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: isSelected ? const Color(0xFF2563EB) : Colors.white12,
                                  child: Text(
                                    p.name.isNotEmpty ? p.name[0].toUpperCase() : "P",
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text(
                                  "${p.city.isNotEmpty ? p.city : 'Local'} • GST: ${p.gst.isNotEmpty ? p.gst : 'Unregistered'}",
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                                trailing: Text(
                                  "Bal: ₹${p.opBal.toStringAsFixed(0)}",
                                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                                onTap: () {
                                  _handlePartySelected(webPh, p);
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openQuickAddCustomer(PharoahWebManager webPh) {
    if (widget.isReadOnly) return;
    showDialog(
      context: context,
      builder: (c) => QuickAddPartyModal(
        webPh: webPh,
        onPartyCreated: (newParty) {
          _handlePartySelected(webPh, newParty);
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
          _openItemEntry(medObj);
        },
      ),
    );
  }

  bool get _isLocalState {
    final ph = Provider.of<PharoahWebManager>(context, listen: false);
    String shopState = (ph.companyProfile['state'] ?? 'Rajasthan').toString().trim().toLowerCase();
    String partyState = (selectedParty?.state ?? 'Rajasthan').toString().trim().toLowerCase();
    return shopState == partyState;
  }

  double get extraDiscount => double.tryParse(extraDiscC.text) ?? 0.0;

  BillGstSummary get _gstSummary => WebBillingGstEngine.calculate(
    items: billItems,
    extraDiscount: extraDiscount,
    isLocal: _isLocalState,
  );

  double get grossTaxable => _gstSummary.grossTaxable;
  double get totalTaxable => _gstSummary.netTaxable;
  double get totalCGST => _gstSummary.totalCGST;
  double get totalSGST => _gstSummary.totalSGST;
  double get totalIGST => _gstSummary.totalIGST;
  double get subTotal => _gstSummary.grossTaxable;
  double get rawGrandTotal => _gstSummary.rawGrandTotal;
  double get finalGrandTotal => _gstSummary.finalGrandTotal;
  double get roundOff => _gstSummary.roundOff;

  void _saveInvoice(PharoahWebManager webPh, {bool andPrint = false}) async {
    if (billItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot save empty bill! Please add products."), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => isSaving = true);

    final Party activeParty = selectedParty ?? Party(id: 'cash', name: 'CASH', group: 'Cash in Hand');
    final String targetSaleId = widget.modifySaleId ?? "SALE-WEB-${DateTime.now().millisecondsSinceEpoch}";
    final String targetBillNo = billNoC.text.trim();

    int currentVer = 1;
    try {
      final existingSale = webPh.sales.firstWhere((s) => s.id == targetSaleId || s.billNo == targetBillNo);
      currentVer = existingSale.version + 1;
    } catch (_) {}

    final newSale = Sale(
      id: targetSaleId,
      billNo: targetBillNo,
      partyId: activeParty.id,
      partyName: activeParty.name,
      partyGstin: activeParty.gst,
      partyState: activeParty.state,
      date: DateTime(billDate.year, billDate.month, billDate.day, 12, 0, 0),
      paymentMode: paymentMode,
      totalAmount: finalGrandTotal,
      extraDiscount: extraDiscount,
      roundOff: roundOff,
      status: "Active",
      items: List.from(billItems),
      linkedChallanIds: widget.linkedChallanIds ?? [],
      sourceTag: "WEB-PORTAL",
      partyAddress: activeParty.address,
      partyCity: activeParty.city,
      partyPhone: activeParty.phone,
      partyEmail: activeParty.email,
      partyDl: activeParty.dl,
      partyPan: activeParty.pan,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      version: currentVer,
    );

    // Atomically purge previous versions (by ID or Bill No) so modifications are 100% clean
    webPh.sales.removeWhere((s) => s.id == targetSaleId || s.billNo == targetBillNo);
    webPh.addSaleAndSync(newSale);
    
    if (widget.linkedChallanIds != null) {
      for (var id in widget.linkedChallanIds!) {
        int idx = webPh.saleChallans.indexWhere((c) => c.id == id);
        if (idx != -1) webPh.saleChallans[idx].status = "Billed";
      }
      await webPh.pushUpdatedDataToCloud();
    }

    setState(() => isSaving = false);

    if (andPrint) {
      final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);
      await WebPdfRouterService.printSaleInvoice(
        sale: newSale,
        party: activeParty,
        shop: shopProfile,
        config: webPh.appConfig,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Invoice ${billNoC.text} Saved Successfully!"), backgroundColor: Colors.green),
      );
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: LayoutBuilder(
          builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 1100;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderBar(webPh),
            const SizedBox(height: 16),
            if (isWideScreen)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 13,
                    child: Column(
                      children: [
                        if (!widget.isReadOnly) _buildProductSearchCard(webPh),
                        if (!widget.isReadOnly) const SizedBox(height: 16),
                        _buildCartTable(webPh),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 340, maxWidth: 420),
                    child: Column(
                      children: [
                        _buildCustomerCard(webPh),
                        const SizedBox(height: 16),
                        _buildGrandTotalCard(webPh),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _buildCustomerCard(webPh),
                  const SizedBox(height: 16),
                  if (!widget.isReadOnly) _buildProductSearchCard(webPh),
                  if (!widget.isReadOnly) const SizedBox(height: 16),
                  _buildCartTable(webPh),
                  const SizedBox(height: 16),
                  _buildGrandTotalCard(webPh),
                ],
              ),
          ],
        );
      },
    ),
    ),
    );
  }

  Widget _buildHeaderBar(PharoahWebManager webPh) {
    final activeSeriesList = webPh.numberingSeries.where((s) => s.type == "SALE" && s.isActive).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Icon(Icons.receipt_long_rounded, color: widget.isReadOnly ? Colors.purpleAccent : const Color(0xFF38BDF8), size: 20),
              const SizedBox(width: 8),
              Text(
                widget.isReadOnly ? "VIEW INVOICE" : "TAX INVOICE",
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (activeSeriesList.isNotEmpty && widget.existingItems == null) ...[
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<NumberingSeries>(
                      value: selectedSeries,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      items: activeSeriesList.map((s) => DropdownMenuItem(value: s, child: Text("${s.name} (${s.prefix})"))).toList(),
                      onChanged: (v) {
                        setState(() => selectedSeries = v);
                        _refreshBillNumber(webPh);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              SizedBox(
                width: 110,
                height: 36,
                child: TextField(
                  controller: billNoC,
                  readOnly: widget.initialBillNo != null || widget.isReadOnly,
                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: "BILL NO",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              InkWell(
                onTap: widget.isReadOnly ? null : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: billDate,
                    firstDate: WebAppDateLogic.getFYStart(webPh.financialYear),
                    lastDate: WebAppDateLogic.getFYEnd(webPh.financialYear),
                  );
                  if (picked != null) {
                    setState(() => billDate = picked);
                  }
                },
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('dd/MM/yyyy').format(billDate),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

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
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x662563EB), width: 1.2),
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
                    labelText: "SEARCH PRODUCT / MEDICINE",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                    hintText: "Type medicine name (e.g. DOLO, PAN, AZITHRAL)...",
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                    suffixIcon: productSearchC.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
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
                border: Border.all(color: const Color(0x3338BDF8)),
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
                      leading: const Icon(Icons.medication_rounded, color: Color(0xFF38BDF8), size: 18),
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
                        "MRP: ₹${med.mrp.toStringAsFixed(2)} | Rate A: ₹${med.rateA.toStringAsFixed(2)} | GST: ${med.gst.toInt()}%",
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                      onTap: () {
                        setState(() => productSearchC.clear());
                        _openItemEntry(med);
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
              const Icon(Icons.shopping_cart_outlined, color: Colors.cyanAccent, size: 18),
              const SizedBox(width: 8),
              Text(
                "INVOICE ITEMS (${billItems.length})",
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const Spacer(),
              if (billItems.isNotEmpty && !widget.isReadOnly)
                TextButton(
                  onPressed: () => setState(() => billItems.clear()),
                  child: const Text("Clear All", style: TextStyle(color: Colors.redAccent, fontSize: 10)),
                ),
            ],
          ),
          const Divider(color: Colors.white10, height: 20),
          if (billItems.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text("Cart is empty. Search and add products above.", style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            )
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
                    0: FixedColumnWidth(40),
                    1: FlexColumnWidth(3),
                    2: FixedColumnWidth(70),
                    3: FixedColumnWidth(80),
                    4: FixedColumnWidth(60),
                    5: FixedColumnWidth(70),
                    6: FixedColumnWidth(70),
                    7: FixedColumnWidth(50),
                    8: FixedColumnWidth(85),
                    9: FixedColumnWidth(70),
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
                        _th("RATE"),
                        _th("GST%"),
                        _th("TOTAL"),
                        _th("ACTIONS"),
                      ],
                    ),
                    ...billItems.asMap().entries.map((entry) {
                      int idx = entry.key;
                      BillItem it = entry.value;
                      String qtyDisp = "${it.qty.toInt()}${it.freeQty > 0 ? ' + ${it.freeQty.toInt()}' : ''}";

                      return TableRow(
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                        children: [
                          _td("${idx + 1}"),
                          _td(it.name, isLeft: true, isBold: true),
                          _td(it.packing),
                          _td(it.batch),
                          _td(it.exp),
                          _td(qtyDisp, isBold: true, color: Colors.cyanAccent),
                          _td("₹${it.rate.toStringAsFixed(2)}"),
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
                                    _openItemEntry(med, itemToEdit: it, editIndex: idx);
                                  },
                                ),
                              if (!widget.isReadOnly)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                                  onPressed: () => setState(() => billItems.removeAt(idx)),
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
      ),
        ],
      ),
    );
  }

  Widget _th(String t, {bool isLeft = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
    child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    child: Text(t, textAlign: isLeft ? TextAlign.left : TextAlign.center, style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
  );

  Widget _buildCustomerCard(PharoahWebManager webPh) {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0x332563EB),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_rounded, color: Color(0xFF38BDF8), size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "CUSTOMER / CONSIGNEE",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              if (!widget.isReadOnly)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(color: Color(0xFF38BDF8), width: 1.0),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _openPartyPickerModal(webPh),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                      label: const Text("CHANGE PARTY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      onPressed: () => _openQuickAddCustomer(webPh),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
                      label: const Text("+ NEW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
            ],
          ),
          const Divider(color: Colors.white10, height: 20),
          if (selectedParty != null)
            InkWell(
              onTap: widget.isReadOnly ? null : () => _openPartyPickerModal(webPh),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x662563EB)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedParty!.name.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            "GST: ${selectedParty!.gst.isNotEmpty ? selectedParty!.gst : 'N/A'} | State: ${selectedParty!.state} | Bal: ₹${selectedParty!.opBal.toStringAsFixed(0)}",
                            style: const TextStyle(color: Colors.white54, fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (!widget.isReadOnly) ...[
                      const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: Colors.redAccent),
                        tooltip: "Reset to Cash",
                        onPressed: () {
                          setState(() => selectedParty = Party(id: 'cash', name: 'CASH', group: 'Cash in Hand'));
                          _refreshBillNumber(webPh);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            )
          else ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                foregroundColor: const Color(0xFF38BDF8),
                side: const BorderSide(color: Color(0xFF38BDF8)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _openPartyPickerModal(webPh),
              icon: const Icon(Icons.person_search_rounded, size: 18),
              label: const Text("TAP TO SELECT CUSTOMER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrandTotalCard(PharoahWebManager webPh) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF19243B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x662563EB), width: 1.2),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 15, offset: Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("BILL CALCULATION SUMMARY", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const Divider(color: Colors.white10, height: 20),
          _sumRow("Items Taxable Value", "₹${totalTaxable.toStringAsFixed(2)}"),
          if (totalCGST > 0) _sumRow("Total CGST (+)", "₹${totalCGST.toStringAsFixed(2)}"),
          if (totalSGST > 0) _sumRow("Total SGST (+)", "₹${totalSGST.toStringAsFixed(2)}"),
          if (totalIGST > 0) _sumRow("Total IGST (+)", "₹${totalIGST.toStringAsFixed(2)}"),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Extra Discount (-)", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 65,
                    height: 30,
                    child: TextField(
                      controller: extraDiscPercentC,
                      readOnly: widget.isReadOnly,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      onChanged: _onExtraDiscPercentChanged,
                      style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 11),
                      decoration: InputDecoration(
                        suffixText: "%",
                        suffixStyle: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
                        filled: true,
                        fillColor: Colors.black38,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 75,
                    height: 30,
                    child: TextField(
                      controller: extraDiscC,
                      readOnly: widget.isReadOnly,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      onChanged: _onExtraDiscAmountChanged,
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
                      decoration: InputDecoration(
                        prefixText: "₹",
                        prefixStyle: const TextStyle(color: Colors.redAccent, fontSize: 10),
                        filled: true,
                        fillColor: Colors.black38,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          _sumRow("Auto Round Off", "₹${roundOff.toStringAsFixed(2)}"),
          const Divider(color: Colors.white24, height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("NET PAYABLE", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
              Text(
                "₹${finalGrandTotal.toStringAsFixed(0)}.00",
                style: const TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.w900),
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
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: isSaving ? null : () => _saveInvoice(webPh, andPrint: false),
                icon: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded, size: 18),
                label: Text(
                  isSaving ? "SAVING..." : "SAVE & SYNC INVOICE",
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                style: ElevatedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isSaving ? null : () => _saveInvoice(webPh, andPrint: true),
                icon: const Icon(Icons.print_rounded, size: 16),
                label: const Text("SAVE & PRINT INVOICE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () async {
                  final Party activeParty = selectedParty ?? Party(id: 'cash', name: 'CASH', group: 'Cash in Hand');
                  final tempSale = Sale(
                    id: "temp", billNo: billNoC.text.trim(), partyId: activeParty.id, partyName: activeParty.name,
                    partyGstin: activeParty.gst, partyState: activeParty.state, date: billDate, paymentMode: paymentMode,
                    totalAmount: finalGrandTotal, extraDiscount: extraDiscount, roundOff: roundOff,
                    status: "Active", items: List.from(billItems), sourceTag: "WEB-PORTAL",
                  );
                  final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);
                  await WebPdfRouterService.printSaleInvoice(sale: tempSale, party: activeParty, shop: shopProfile, config: webPh.appConfig);
                },
                icon: const Icon(Icons.print_rounded, size: 18),
                label: const Text("PRINT THIS INVOICE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 0.5)),
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
}
