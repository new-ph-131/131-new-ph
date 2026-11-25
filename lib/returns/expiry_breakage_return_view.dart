// FILE: lib/returns/expiry_breakage_return_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../logic/pharoah_numbering_engine.dart';
import '../item_entry_card.dart';
import '../pharoah_date_controller.dart';
import '../pdf/pdf_router_service.dart';
import '../logic/app_billing_gst_engine.dart';
import '../logic/gst_compliance_helper.dart';
import '../logic/return_history_engine.dart';
import 'widgets/return_smart_pickers.dart';

class ExpiryBreakageReturnView extends StatefulWidget {
  const ExpiryBreakageReturnView({super.key});

  @override
  State<ExpiryBreakageReturnView> createState() =>
      _ExpiryBreakageReturnViewState();
}

class _ExpiryBreakageReturnViewState extends State<ExpiryBreakageReturnView> {
  final returnNoC = TextEditingController();
  final discountC = TextEditingController(text: "0");
  final discountPerC = TextEditingController(text: "0");
  final medSearchC = TextEditingController();
  final origBillNoC = TextEditingController();
  final reasonC = TextEditingController();

  String selectedReason = GstComplianceHelper.otherReasonCode;
  DateTime selectedDate = DateTime.now();
  DateTime? origBillDate;
  String paymentMode = "CREDIT";
  bool isCommercial = false;
  Party? selectedParty;
  List<BillItem> items = [];
  String searchQuery = "";
  String medSearch = "";
  bool isLoading = true;
  bool _headerExpanded = false;
  bool _footerExpanded = false;

  @override
  void initState() {
    super.initState();
    _initBreakage();
  }

  @override
  void dispose() {
    returnNoC.dispose();
    discountC.dispose();
    discountPerC.dispose();
    medSearchC.dispose();
    origBillNoC.dispose();
    reasonC.dispose();
    super.dispose();
  }

  void _initBreakage() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    if (ph.activeCompany != null) {
      var defaultRetSeries = ph.getDefaultSeries("RETURN");
      final pref = (defaultRetSeries.prefix.isNotEmpty &&
              defaultRetSeries.prefix != "SR-" &&
              defaultRetSeries.prefix != "CN-")
          ? defaultRetSeries.prefix
          : "TXN-";
      final startNo =
          defaultRetSeries.startNumber > 0 ? defaultRetSeries.startNumber : 1;

      String nextNo = await PharoahNumberingEngine.getNextNumber(
        type: "RETURN",
        companyID: ph.activeCompany!.id,
        prefix: pref,
        startFrom: startNo,
        currentList: ph.saleReturns,
      );

      if (mounted) {
        setState(() {
          returnNoC.text = nextNo;
          selectedDate = PharoahDateController.getInitialBillDate(ph.currentFY);
          isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _refreshNumberForCommercialMode(
      PharoahManager ph, bool commercial) async {
    if (ph.activeCompany == null) return;
    if (commercial) {
      var ccnSer = ph.getDefaultSeries("COMMERCIAL_NOTE");
      final ccnPref = ccnSer.prefix.isNotEmpty
          ? ccnSer.prefix
          : (ph.config.commercialNotePrefix.isNotEmpty
              ? ph.config.commercialNotePrefix
              : "CCN-");
      final n = await PharoahNumberingEngine.getNextNumber(
        type: "COMMERCIAL_NOTE",
        companyID: ph.activeCompany!.id,
        prefix: ccnPref,
        startFrom: ccnSer.startNumber > 0 ? ccnSer.startNumber : 1,
        currentList: [...ph.saleReturns, ...ph.purchaseReturns],
      );
      if (mounted) setState(() => returnNoC.text = n);
    } else {
      var defaultRetSeries = ph.getDefaultSeries("RETURN");
      final pref = (defaultRetSeries.prefix.isNotEmpty &&
              defaultRetSeries.prefix != "SR-" &&
              defaultRetSeries.prefix != "CN-")
          ? defaultRetSeries.prefix
          : "TXN-";
      final n = await PharoahNumberingEngine.getNextNumber(
        type: "RETURN",
        companyID: ph.activeCompany!.id,
        prefix: pref,
        startFrom:
            defaultRetSeries.startNumber > 0 ? defaultRetSeries.startNumber : 1,
        currentList: ph.saleReturns,
      );
      if (mounted) setState(() => returnNoC.text = n);
    }
  }

  bool get isLocal {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    return GstComplianceHelper.isIntraStateReturn(
      shopGstin: ph.activeCompany?.gstin,
      shopState: ph.activeCompany?.state ?? "Rajasthan",
      partyGstin: selectedParty?.gst,
      partyState: selectedParty?.state,
    );
  }

  String _posCode(PharoahManager ph) => GstComplianceHelper.resolvePartyPosCode(
        shopGstin: ph.activeCompany?.gstin,
        shopState: ph.activeCompany?.state ?? "Rajasthan",
        partyGstin: selectedParty?.gst,
        partyState: selectedParty?.state,
      );

  DateTime? get expiredOriginDate => GstComplianceHelper.getExpiredOriginDate(
        headerOrigDate: origBillDate,
        items: items,
        noteDate: selectedDate,
      );

  bool get isSec34Expired => expiredOriginDate != null;

  Future<void> _syncHeaderOriginFromItems(PharoahManager ph,
      {bool silent = false}) async {
    final summary = GstComplianceHelper.summarizeOriginInvoices(items);
    if (summary.uniqueCount > 0) {
      origBillNoC.text = summary.headerBillNo;
      origBillDate = summary.headerDate;
    } else if (items.isEmpty || items.every((it) => it.isManualOrigin)) {
      origBillNoC.text = "";
      origBillDate = null;
    }
    final canComm = GstComplianceHelper.isCommercialNoteAllowed(ph.config);
    final expDate = GstComplianceHelper.getExpiredOriginDate(
      headerOrigDate: origBillDate,
      items: items,
      noteDate: selectedDate,
    );
    if (!silent && expDate != null && canComm && !isCommercial) {
      setState(() => isCommercial = true);
      await _refreshNumberForCommercialMode(ph, true);
    }
  }

  void _onDiscRupeesChanged(String val) {
    final gross = gstSummary.grossTaxable;
    final rs = double.tryParse(val) ?? 0.0;
    if (gross > 0 && rs > 0) {
      discountPerC.text = ((rs / gross) * 100.0).toStringAsFixed(2);
    } else {
      discountPerC.text = "0";
    }
    setState(() {});
  }

  void _onDiscPerChanged(String val) {
    final gross = gstSummary.grossTaxable;
    final per = double.tryParse(val) ?? 0.0;
    if (gross > 0 && per > 0) {
      discountC.text = (gross * (per / 100.0)).toStringAsFixed(2);
    } else {
      discountC.text = "0";
    }
    setState(() {});
  }

  void _reapplyDiscFromPerIfActive() {
    final per = double.tryParse(discountPerC.text) ?? 0.0;
    final gross = gstSummary.grossTaxable;
    if (per > 0 && gross > 0) {
      discountC.text = (gross * (per / 100.0)).toStringAsFixed(2);
    }
  }

  double get extraDiscount => double.tryParse(discountC.text) ?? 0.0;

  AppBillGstSummary get gstSummary => AppBillingGstEngine.calculate(
        items: items,
        extraDiscount: extraDiscount,
        isLocal: isLocal,
        isCommercial: isCommercial,
      );

  double get totalAmt => gstSummary.finalGrandTotal;
  double get roundOff => gstSummary.roundOff;
  String get _effectiveReason =>
      GstComplianceHelper.formatReason(selectedReason, reasonC.text);

  void _recalculateSR() {
    for (int i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(srNo: i + 1);
    }
  }

  void _showMagicHistoryBox(Medicine med, PharoahManager ph) {
    if (selectedParty == null) {
      _showQuantityEntry(med);
      return;
    }
    showReturnBatchHistorySheet(
      context: context,
      isSale: true,
      medicine: med,
      party: selectedParty!,
      ph: ph,
      currentCartItems: items,
      onSelect: (h) => _showQuantityEntry(med, historyData: h),
      onAutoSplit: (allocations, hasOverReturn) async {
        final newLines = <BillItem>[];
        int sr = items.length + 1;
        for (final a in allocations) {
          newLines.add(ReturnHistoryEngine.buildBillItemFromLine(
            med: med,
            line: a.line,
            qty: a.allocatedQty,
            freeQty: a.allocatedFreeQty,
            useSchemeNetRate: a.useSchemeNetRate,
            srNo: sr++,
            isLocal: isLocal,
            isBreakage: true,
            isCommercial: isCommercial,
          ));
        }
        setState(() {
          items.addAll(newLines);
          _recalculateSR();
          _reapplyDiscFromPerIfActive();
        });
        await _syncHeaderOriginFromItems(ph);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                hasOverReturn
                    ? "Added ${newLines.length} breakage split line(s) (Notice: exceeded batch returnable balance)."
                    : "Added ${newLines.length} auto-split breakage line(s).",
              ),
              backgroundColor: hasOverReturn
                  ? Colors.orange.shade800
                  : Colors.red.shade900,
            ),
          );
        }
      },
    );
  }

  void _openPullFromBillSheet(PharoahManager ph, {String? initialBillNo}) {
    if (selectedParty == null) return;
    showPullFromBillSheet(
      context: context,
      isSale: true,
      party: selectedParty!,
      ph: ph,
      currentCartItems: items,
      initialBillNo: initialBillNo,
      onAddSelected: (picked) async {
        final newLines = <BillItem>[];
        int sr = items.length + 1;
        for (final p in picked) {
          newLines.add(ReturnHistoryEngine.buildBillItemFromLine(
            med: p.medicine,
            line: p.line,
            qty: p.qty,
            freeQty: p.freeQty,
            useSchemeNetRate: p.useSchemeNetRate,
            srNo: sr++,
            isLocal: isLocal,
            isBreakage: true,
            isCommercial: isCommercial,
          ));
        }
        setState(() {
          items.addAll(newLines);
          _recalculateSR();
          _reapplyDiscFromPerIfActive();
        });
        await _syncHeaderOriginFromItems(ph);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Pulled ${newLines.length} breakage item(s) from bill."),
              backgroundColor: Colors.red.shade900,
            ),
          );
        }
      },
    );
  }

  void _showQuantityEntry(Medicine med,
      {BillItem? existingItem, Map<String, dynamic>? historyData}) {
    final String histBillNo = (historyData?['billNo'] ?? '').toString().trim();
    final DateTime? histDate =
        historyData?['date'] is DateTime ? historyData!['date'] as DateTime : null;
    final bool isManual = existingItem == null && historyData == null;
    BillItem? preFilled = existingItem;
    if (historyData != null && existingItem == null) {
      final histPacking = (historyData['packing'] ?? '').toString().trim();
      final histHsn = (historyData['hsn'] ?? '').toString().trim();
      final histExp = (historyData['exp'] ?? '').toString().trim();
      final histRateType = (historyData['appliedRateType'] ?? '').toString().trim();
      preFilled = BillItem(
        id: "temp",
        srNo: items.length + 1,
        medicineID: med.id,
        name: med.name,
        packing: histPacking.isNotEmpty ? histPacking : med.packing,
        batch: (historyData['batch'] ?? '').toString(),
        exp: histExp,
        hsn: histHsn.isNotEmpty ? histHsn : med.hsnCode,
        mrp: ((historyData['mrp'] ?? med.mrp) as num).toDouble(),
        rate: ((historyData['rate'] ?? med.rateA) as num).toDouble(),
        gstRate: ((historyData['gst'] ?? med.gst) as num).toDouble(),
        discountPer: ((historyData['discountPer'] ?? 0.0) as num).toDouble(),
        appliedRateType: histRateType.isNotEmpty ? histRateType : "A",
        rateCFormula: ((historyData['rateCFormula'] ?? 0.0) as num).toDouble(),
        qty: ((historyData['qty'] ?? historyData['availableQty'] ?? 1.0) as num)
            .toDouble(),
        freeQty: ((historyData['free'] ?? 0.0) as num).toDouble(),
        total: 0,
        isBreakage: true,
        origBillNo: histBillNo,
        origBillDate: histDate,
        isManualOrigin: histBillNo.isEmpty,
      );
    }
    ReturnSchemeContext? schemeCtx;
    if (historyData != null) {
      final bq = (historyData['billedQty'] as num?)?.toDouble() ?? 0.0;
      final bf = (historyData['billedFreeQty'] as num?)?.toDouble() ?? 0.0;
      final origR =
          ((historyData['originalRate'] ?? historyData['rate']) as num?)
                  ?.toDouble() ??
              med.rateA;
      if (bf > 0 && bq > 0) {
        schemeCtx = ReturnSchemeContext(
          billedQty: bq,
          billedFreeQty: bf,
          originalRate: origR,
          initialUseSchemeNetRate: historyData['useSchemeNetRate'] == true,
        );
      }
    }
    showDialog(
      context: context,
      builder: (c) => ItemEntryCard(
        med: med,
        srNo: existingItem?.srNo ?? (items.length + 1),
        partyState: selectedParty?.state ?? "Rajasthan",
        existingItem: preFilled,
        allowExpired: true,
        returnScheme: schemeCtx,
        onAdd: (newItem) async {
          final ph = Provider.of<PharoahManager>(context, listen: false);
          final finalized = existingItem != null
              ? newItem.copyWith(
                  isBreakage: true,
                  origBillNo: existingItem.origBillNo,
                  origBillDate: existingItem.origBillDate,
                  isManualOrigin: existingItem.isManualOrigin,
                )
              : newItem.copyWith(
                  isBreakage: true,
                  origBillNo: isManual ? "" : histBillNo,
                  origBillDate: isManual ? null : histDate,
                  clearOrigBillDate: isManual,
                  isManualOrigin: isManual || histBillNo.isEmpty,
                );
          setState(() {
            if (existingItem != null) {
              int idx = items.indexWhere((it) => it.id == existingItem.id);
              if (idx != -1) items[idx] = finalized;
            } else {
              items.add(finalized);
            }
            _recalculateSR();
            _reapplyDiscFromPerIfActive();
          });
          Navigator.pop(context);
          await _syncHeaderOriginFromItems(ph);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final Map<String, int> dupCounts = {};
    for (final it in items) {
      final k =
          "${it.origBillNo.trim().toUpperCase()}||${it.batch.trim().toUpperCase()}||${it.name.trim().toUpperCase()}";
      dupCounts[k] = (dupCounts[k] ?? 0) + 1;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Expiry / Breakage Return",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            Text(
              "#${returnNoC.text} • ${DateFormat('dd/MM/yy').format(selectedDate)}",
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (items.isNotEmpty && selectedParty != null)
            IconButton(
              tooltip: "Print Breakage Note",
              icon: const Icon(Icons.print_rounded),
              onPressed: () => _handlePrint(ph),
            ),
          if (items.isNotEmpty && selectedParty != null)
            TextButton(
              onPressed: () => _handleSave(ph),
              child: const Text(
                "SAVE AS BREAKAGE",
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildWarningBanner(),
          _buildCollapsiblePartyCard(ph),
          if (selectedParty != null) _buildSmartLookupBar(ph),
          Expanded(
            child: selectedParty == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_search_rounded,
                            size: 48, color: Colors.red.shade200),
                        const SizedBox(height: 8),
                        const Text(
                          "Select a customer above to record breakage/expiry",
                          style: TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                : items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_sweep_rounded,
                                size: 46, color: Colors.red.shade200),
                            const SizedBox(height: 8),
                            const Text(
                              "Search expired/breakage product or tap BILL",
                              style: TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                        itemCount: items.length,
                        itemBuilder: (c, i) => _buildItemCard(
                            items[i], i, ph, dupCounts),
                      ),
          ),
          if (selectedParty != null) _buildSummaryFooter(ph),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
      color: Colors.red.shade100,
      child: Row(
        children: [
          Icon(Icons.report_problem, size: 16, color: Colors.red.shade900),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "Items added here will NOT be added to Sellable Stock.",
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsiblePartyCard(PharoahManager ph) {
    final canComm = GstComplianceHelper.isCommercialNoteAllowed(ph.config);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))
        ],
      ),
      child: Column(
        children: [
          if (selectedParty == null) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: returnNoC,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: "BREAKAGE NO",
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _pickNoteDate(ph),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 14, color: Colors.red.shade900),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('dd/MM/yy').format(selectedDate),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.red.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: "Search Customer Name / GST / City...",
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 155,
              child: ListView(
                children: ph.parties
                    .where((p) {
                      final q = searchQuery.trim().toLowerCase();
                      if (q.isEmpty) return true;
                      return p.name.toLowerCase().contains(q) ||
                          p.city.toLowerCase().contains(q) ||
                          p.gst.toLowerCase().contains(q) ||
                          p.phone.toLowerCase().contains(q);
                    })
                    .take(25)
                    .map((p) => ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          leading: CircleAvatar(
                            radius: 15,
                            backgroundColor: Colors.red.shade50,
                            child: Text(
                              p.name.isNotEmpty ? p.name[0].toUpperCase() : "C",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900,
                              ),
                            ),
                          ),
                          title: Text(p.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text(
                            "${p.city.isNotEmpty ? p.city : 'General'} • GST: ${p.gst.isNotEmpty ? p.gst : 'URP'}",
                            style: const TextStyle(fontSize: 10.5),
                          ),
                          onTap: () => setState(() {
                            selectedParty = p;
                            searchQuery = "";
                          }),
                        ))
                    .toList(),
              ),
            ),
          ] else ...[
            InkWell(
              onTap: () => setState(() => _headerExpanded = !_headerExpanded),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.red.shade900,
                      child: Text(
                        selectedParty!.name.isNotEmpty
                            ? selectedParty!.name[0].toUpperCase()
                            : "P",
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedParty!.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                "GST: ${selectedParty!.gst.isNotEmpty ? selectedParty!.gst : 'URP'}",
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.black54),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isLocal
                                      ? Colors.green.shade100
                                      : Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "POS ${_posCode(ph)} • ${isLocal ? 'INTRA' : 'IGST'}",
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: isLocal
                                        ? Colors.green.shade900
                                        : Colors.blue.shade900,
                                  ),
                                ),
                              ),
                              if (isCommercial) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "CCN",
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _headerExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.tune_rounded,
                      color: Colors.red.shade900,
                      size: 19,
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => setState(() => selectedParty = null),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.red, size: 19),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: !_headerExpanded
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () =>
                                      setState(() => paymentMode = "CREDIT"),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 7),
                                    decoration: BoxDecoration(
                                      color: paymentMode == "CREDIT"
                                          ? Colors.blue.shade800
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "CREDIT (LEDGER)",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: paymentMode == "CREDIT"
                                            ? Colors.white
                                            : Colors.black54,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: InkWell(
                                  onTap: () =>
                                      setState(() => paymentMode = "CASH"),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 7),
                                    decoration: BoxDecoration(
                                      color: paymentMode == "CASH"
                                          ? Colors.green.shade700
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "CASH REFUND",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: paymentMode == "CASH"
                                            ? Colors.white
                                            : Colors.black54,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => _pickNoteDate(ph),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: Colors.red.shade200),
                                  ),
                                  child: Text(
                                    DateFormat('dd/MM/yy').format(selectedDate),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: returnNoC,
                                  style: const TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.bold),
                                  decoration: const InputDecoration(
                                    labelText: "Breakage Note No",
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 4,
                                child: TextField(
                                  controller: origBillNoC,
                                  style: const TextStyle(fontSize: 11),
                                  decoration: const InputDecoration(
                                    labelText: "Orig. Invoice No (R53)",
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: InkWell(
                                  onTap: () => _pickOrigDate(ph),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 10),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: Colors.grey.shade400),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      origBillDate != null
                                          ? DateFormat('dd/MM/yy')
                                              .format(origBillDate!)
                                          : "Orig. Date",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: origBillDate != null
                                            ? Colors.black87
                                            : Colors.grey.shade600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (canComm || isCommercial) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isCommercial
                                    ? Colors.amber.shade50
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isCommercial
                                      ? Colors.amber.shade700
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Commercial Note (Non-GST)",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isCommercial
                                                ? Colors.amber.shade900
                                                : Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          isCommercial
                                              ? "Active: Tax 0% • Excluded from GSTR-1 • CCN-"
                                              : "Toggle ON for Non-GST Breakage Note",
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: isCommercial
                                                ? Colors.amber.shade800
                                                : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: isCommercial,
                                    activeColor: Colors.amber.shade800,
                                    onChanged: !canComm
                                        ? null
                                        : (val) async {
                                            setState(() => isCommercial = val);
                                            await _refreshNumberForCommercialMode(
                                                ph, val);
                                          },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
          if (isSec34Expired && expiredOriginDate != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Text(
                "Sec 34(2) cutoff (${DateFormat('dd/MM/yyyy').format(GstComplianceHelper.getSection34CutoffDate(expiredOriginDate!))}) crossed — Commercial Note recommended.",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickNoteDate(PharoahManager ph) async {
    DateTime? p = await PharoahDateController.pickDate(
      context: context,
      currentFY: ph.currentFY,
      initialDate: selectedDate,
    );
    if (p != null) {
      final canComm = GstComplianceHelper.isCommercialNoteAllowed(ph.config);
      final expired = GstComplianceHelper.isSection34Expired(
          origInvoiceDate: origBillDate, noteDate: p);
      setState(() {
        selectedDate = p;
        if (expired && canComm && !isCommercial) isCommercial = true;
      });
      if (expired && canComm) {
        await _refreshNumberForCommercialMode(ph, true);
      }
    }
  }

  Future<void> _pickOrigDate(PharoahManager ph) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: GstComplianceHelper.clampPickerDate(
          origBillDate ?? selectedDate, DateTime(2017, 7, 1), selectedDate),
      firstDate: DateTime(2017, 7, 1),
      lastDate: selectedDate,
    );
    if (picked != null) {
      final canComm = GstComplianceHelper.isCommercialNoteAllowed(ph.config);
      final expired = GstComplianceHelper.isSection34Expired(
          origInvoiceDate: picked, noteDate: selectedDate);
      setState(() {
        origBillDate = picked;
        if (expired && canComm && !isCommercial) isCommercial = true;
      });
      if (expired && canComm) {
        await _refreshNumberForCommercialMode(ph, true);
      }
    }
  }

  Widget _buildSmartLookupBar(PharoahManager ph) {
    final recentBills = selectedParty == null
        ? const <ReturnRecentBill>[]
        : ReturnHistoryEngine.getRecentPartyBills(
            isSale: true,
            partyId: selectedParty!.id,
            partyName: selectedParty!.name,
            sales: ph.sales,
            purchases: ph.purchases,
            saleReturns: ph.saleReturns,
            purchaseReturns: ph.purchaseReturns,
            currentCartItems: items,
            limit: 10,
          );

    final q = medSearch.trim().toLowerCase();
    final matchingMeds = q.isEmpty
        ? const <Medicine>[]
        : ph.medicines.where((m) {
            if (m.name.toLowerCase().contains(q) ||
                m.uniqueCode.toLowerCase().contains(q)) return true;
            return ph
                .getBatchesForMedicine(m)
                .any((b) => b.batch.toLowerCase().contains(q));
          }).take(15).toList();

    final matchingBills = q.isEmpty
        ? const <ReturnRecentBill>[]
        : recentBills
            .where((b) =>
                b.billNo.toLowerCase().contains(q) ||
                b.lines.any((l) => l.batch.toLowerCase().contains(q)))
            .take(5)
            .toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: medSearchC,
                  decoration: InputDecoration(
                    hintText: "Search Breakage Product, Batch No, or Bill No...",
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon:
                        Icon(Icons.search_rounded, size: 19, color: Colors.red.shade800),
                    suffixIcon: medSearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() {
                              medSearchC.clear();
                              medSearch = "";
                            }),
                          )
                        : null,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: const Color(0xFFFFF5F5),
                  ),
                  onChanged: (v) => setState(() => medSearch = v),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _openPullFromBillSheet(ph),
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: Text(
                  recentBills.isNotEmpty
                      ? "BILL (${recentBills.length})"
                      : "BILL",
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          if (matchingMeds.isNotEmpty || matchingBills.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 210),
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8)
                ],
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  ...matchingBills.map((b) => ListTile(
                        dense: true,
                        leading: Icon(Icons.receipt_long_rounded,
                            color: Colors.red.shade800, size: 18),
                        title: Text("Bill ${b.billNo}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.5)),
                        subtitle: Text(
                          "${DateFormat('dd/MM/yy').format(b.date)} • ${b.lines.length} items • ₹${b.totalAmount.toStringAsFixed(0)}",
                          style: const TextStyle(fontSize: 10.5),
                        ),
                        trailing: Text("PULL",
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Colors.red.shade900)),
                        onTap: () {
                          setState(() {
                            medSearch = "";
                            medSearchC.clear();
                          });
                          _openPullFromBillSheet(ph, initialBillNo: b.billNo);
                        },
                      )),
                  ...matchingMeds.map((m) => ListTile(
                        dense: true,
                        leading: Icon(Icons.delete_sweep,
                            color: Colors.red.shade700, size: 18),
                        title: Text(m.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.5)),
                        subtitle: Text(
                          "Pack: ${m.packing} • Stock: ${m.stock}",
                          style: const TextStyle(fontSize: 10.5),
                        ),
                        onTap: () {
                          setState(() {
                            medSearch = "";
                            medSearchC.clear();
                          });
                          _showMagicHistoryBox(m, ph);
                        },
                      )),
                ],
              ),
            )
          else if (recentBills.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: recentBills.take(8).length,
                itemBuilder: (c, idx) {
                  final b = recentBills[idx];
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.red.shade50,
                      side: BorderSide(color: Colors.red.shade200),
                      label: Text(
                        "${b.billNo} • ${DateFormat('dd/MM').format(b.date)} • ₹${b.totalAmount.toStringAsFixed(0)}",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                        ),
                      ),
                      onPressed: () =>
                          _openPullFromBillSheet(ph, initialBillNo: b.billNo),
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

  Widget _buildItemCard(
      BillItem it, int index, PharoahManager ph, Map<String, int> dupCounts) {
    final dupKey =
        "${it.origBillNo.trim().toUpperCase()}||${it.batch.trim().toUpperCase()}||${it.name.trim().toUpperCase()}";
    final bool isDup =
        it.origBillNo.trim().isNotEmpty && (dupCounts[dupKey] ?? 0) > 1;

    final card = Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDup ? Colors.orange.shade700 : Colors.red.shade200,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final med = ph.medicines.firstWhere(
            (m) =>
                (it.medicineID.isNotEmpty && m.id == it.medicineID) ||
                m.name.trim().toUpperCase() == it.name.trim().toUpperCase(),
            orElse: () => Medicine(
              id: it.medicineID,
              name: it.name,
              packing: it.packing,
              mrp: it.mrp,
              gst: it.gstRate,
              hsnCode: it.hsn,
              rateA: it.rate,
            ),
          );
          _showQuantityEntry(med, existingItem: it);
        },
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      "EXP",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      it.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 13.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isDup)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "DUP",
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  Text(
                    "₹${it.total.toStringAsFixed(2)}",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                      color: Colors.red.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Batch: ${it.batch} • Exp: ${it.exp} • Rate: ₹${it.rate.toStringAsFixed(2)}${it.discountPer > 0 ? ' (-${it.discountPer.toStringAsFixed(1)}%)' : ''} • GST ${it.gstRate.toInt()}%",
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54),
                        ),
                        if (it.origBillNo.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.indigo.shade200),
                              ),
                              child: Text(
                                "Inv: ${it.origBillNo}${it.origBillDate != null ? ' (${DateFormat('dd/MM/yy').format(it.origBillDate!)})' : ''}",
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo.shade800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: it.qty > 1
                            ? () {
                                setState(() {
                                  items[index] =
                                      ReturnHistoryEngine.recalcBillItemQty(
                                    it,
                                    qty: it.qty - 1,
                                    isLocal: isLocal,
                                    isCommercial: isCommercial,
                                  );
                                  _reapplyDiscFromPerIfActive();
                                });
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.remove_rounded,
                            size: 16,
                            color: it.qty > 1 ? Colors.black87 : Colors.black26,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          formatQtyPair(it.qty, it.freeQty),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 12.5),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          setState(() {
                            items[index] = ReturnHistoryEngine.recalcBillItemQty(
                              it,
                              qty: it.qty + 1,
                              isLocal: isLocal,
                              isCommercial: isCommercial,
                            );
                            _reapplyDiscFromPerIfActive();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.add_rounded,
                              size: 16, color: Colors.black87),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          setState(() {
                            items.removeAt(index);
                            _recalculateSR();
                            _reapplyDiscFromPerIfActive();
                          });
                          _syncHeaderOriginFromItems(ph, silent: true);
                        },
                        child: const Icon(Icons.delete_outline_rounded,
                            color: Colors.red, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey("${it.id}-$index"),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white, size: 26),
      ),
      onDismissed: (direction) {
        setState(() {
          items.removeAt(index);
          _recalculateSR();
          _reapplyDiscFromPerIfActive();
        });
        _syncHeaderOriginFromItems(ph, silent: true);
      },
      child: card,
    );
  }

  Widget _buildSummaryFooter(PharoahManager ph) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))
        ],
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                child: !_footerExpanded
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: selectedReason,
                              isExpanded: true,
                              style: const TextStyle(
                                  fontSize: 11.5, color: Colors.black87),
                              decoration: const InputDecoration(
                                labelText: "Return Reason (GST Rule 53(1A))",
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: GstComplianceHelper.standardReasons
                                  .map((r) => DropdownMenuItem<String>(
                                      value: r,
                                      child: Text(r,
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => selectedReason = val);
                                }
                              },
                            ),
                            if (GstComplianceHelper.isOtherReason(
                                selectedReason)) ...[
                              const SizedBox(height: 6),
                              TextField(
                                controller: reasonC,
                                style: const TextStyle(fontSize: 11),
                                decoration: const InputDecoration(
                                  labelText:
                                      "Custom Remarks / Expiry / Damage Details",
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text(
                                  "Extra Disc (-):",
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const Spacer(),
                                SizedBox(
                                  width: 68,
                                  child: TextField(
                                    controller: discountPerC,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.right,
                                    onChanged: _onDiscPerChanged,
                                    decoration: const InputDecoration(
                                      suffixText: "%",
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 7),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 88,
                                  child: TextField(
                                    controller: discountC,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.right,
                                    onChanged: _onDiscRupeesChanged,
                                    decoration: const InputDecoration(
                                      prefixText: "₹",
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 7),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  _ftRow("Gross Taxable",
                                      "₹${gstSummary.grossTaxable.toStringAsFixed(2)}"),
                                  _ftRow("Net Taxable",
                                      "₹${gstSummary.netTaxable.toStringAsFixed(2)}",
                                      isBold: true),
                                  if (isCommercial)
                                    _ftRow("Commercial Note (Sec 34)",
                                        "GST EXEMPT (₹0.00)",
                                        color: Colors.amber.shade900)
                                  else if (isLocal) ...[
                                    _ftRow("CGST Total",
                                        "₹${gstSummary.totalCGST.toStringAsFixed(2)}",
                                        color: Colors.red.shade900),
                                    _ftRow("SGST Total",
                                        "₹${gstSummary.totalSGST.toStringAsFixed(2)}",
                                        color: Colors.red.shade900),
                                  ] else
                                    _ftRow("IGST Total",
                                        "₹${gstSummary.totalIGST.toStringAsFixed(2)}",
                                        color: Colors.red.shade900),
                                  _ftRow("Round Off",
                                      "₹${roundOff.toStringAsFixed(2)}"),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () =>
                          setState(() => _footerExpanded = !_footerExpanded),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                "NON-SELLABLE BREAKAGE TOTAL",
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _footerExpanded
                                    ? Icons.keyboard_arrow_down_rounded
                                    : Icons.keyboard_arrow_up_rounded,
                                size: 17,
                                color: Colors.red.shade900,
                              ),
                            ],
                          ),
                          Text(
                            "₹${totalAmt.toStringAsFixed(2)}",
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Colors.red.shade900,
                            ),
                          ),
                          Text(
                            "${items.length} Items • Tax ₹${(isCommercial ? 0.0 : gstSummary.totalTax).toStringAsFixed(2)}",
                            style: const TextStyle(
                                fontSize: 10, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (items.isNotEmpty)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade900,
                        side: BorderSide(color: Colors.red.shade900),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 11),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _handlePrint(ph),
                      child: const Icon(Icons.print_rounded, size: 19),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _handleSave(ph),
                    icon: const Icon(Icons.check_circle_rounded, size: 17),
                    label: const Text(
                      "SAVE BREAKAGE",
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ftRow(String l, String v, {bool isBold = false, Color? color}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l,
              style: TextStyle(
                  fontSize: 11,
                  color: color ?? Colors.black87,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(v,
              style: TextStyle(
                  fontSize: 11,
                  color: color ?? Colors.black87,
                  fontWeight: FontWeight.bold)),
        ],
      );

  void _handleSave(PharoahManager ph) {
    if (selectedParty == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please select a Party first."),
          backgroundColor: Colors.red));
      return;
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please add at least one item before saving."),
          backgroundColor: Colors.orange));
      return;
    }
    ph.finalizeSaleReturn(
      billNo: returnNoC.text,
      date: selectedDate,
      party: selectedParty!,
      items: items,
      total: totalAmt,
      extraDiscount: extraDiscount,
      roundOff: roundOff,
      type: "Breakage",
      paymentMode: paymentMode,
      origBillNo: origBillNoC.text.trim(),
      origBillDate: origBillDate,
      reason: _effectiveReason,
      isCommercial: isCommercial,
    );

    if (ph.activeCompany != null) {
      if (isCommercial) {
        var ccnSer = ph.getDefaultSeries("COMMERCIAL_NOTE");
        final ccnPref = ccnSer.prefix.isNotEmpty
            ? ccnSer.prefix
            : (ph.config.commercialNotePrefix.isNotEmpty
                ? ph.config.commercialNotePrefix
                : "CCN-");
        PharoahNumberingEngine.updateSeriesCounter(
          type: "COMMERCIAL_NOTE",
          companyID: ph.activeCompany!.id,
          usedNumber: returnNoC.text.trim(),
          prefix: ccnPref,
        );
      } else {
        var defaultRetSeries = ph.getDefaultSeries("RETURN");
        final pref = (defaultRetSeries.prefix.isNotEmpty &&
                defaultRetSeries.prefix != "SR-" &&
                defaultRetSeries.prefix != "CN-")
            ? defaultRetSeries.prefix
            : "TXN-";
        PharoahNumberingEngine.updateSeriesCounter(
          type: "RETURN",
          companyID: ph.activeCompany!.id,
          usedNumber: returnNoC.text.trim(),
          prefix: pref,
        );
      }
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("⚠️ Saved to Breakage/Expiry Stock!"),
      backgroundColor: Colors.red.shade900,
    ));
  }

  void _handlePrint(PharoahManager ph) async {
    if (selectedParty == null) return;
    final resolvedItems = GstComplianceHelper.resolveMissingBillItemOrigins(
      items: items,
      sales: ph.sales,
      partyId: selectedParty!.id,
      partyName: selectedParty!.name,
    );
    final returnObj = SaleReturn(
      id: "temp",
      billNo: returnNoC.text,
      date: selectedDate,
      partyId: selectedParty!.id,
      partyName: selectedParty!.name,
      partyGstin: selectedParty!.gst,
      partyState: selectedParty!.state,
      items: resolvedItems,
      totalAmount: totalAmt,
      extraDiscount: extraDiscount,
      roundOff: roundOff,
      paymentMode: paymentMode,
      origBillNo: origBillNoC.text.trim(),
      origBillDate: origBillDate,
      reason: _effectiveReason,
      isCommercial: isCommercial,
    );
    await PdfRouterService.printCreditNote(
        returnObj: returnObj, party: selectedParty!, ph: ph);
  }
}
