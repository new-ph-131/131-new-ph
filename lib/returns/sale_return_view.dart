// FILE: lib/returns/sale_return_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../logic/pharoah_numbering_engine.dart';
import '../item_entry_card.dart';
import '../pharoah_date_controller.dart';
import '../app_date_logic.dart';
import '../pdf/pdf_router_service.dart';
import '../logic/app_billing_gst_engine.dart';
import '../logic/gst_compliance_helper.dart';
import '../logic/return_history_engine.dart';
import 'widgets/return_smart_pickers.dart';

class SaleReturnView extends StatefulWidget {
  final SaleReturn? existingRecord;
  final bool isReadOnly;

  const SaleReturnView({super.key, this.existingRecord, this.isReadOnly = false});

  @override
  State<SaleReturnView> createState() => _SaleReturnViewState();
}

class _SaleReturnViewState extends State<SaleReturnView> {
  final returnNoC = TextEditingController();
  final discountC = TextEditingController(text: "0");
  final discountPerC = TextEditingController(text: "0");
  final medSearchC = TextEditingController();
  final origBillNoC = TextEditingController();
  final reasonC = TextEditingController();
  String selectedReason = GstComplianceHelper.standardReasons.first;
  DateTime? origBillDate;
  String paymentMode = "CREDIT";
  bool isCommercial = false;

  DateTime selectedDate = DateTime.now();
  Party? selectedParty;

  List<BillItem> items = [];
  bool isBreakageMode = false;
  String medSearch = "";
  String partySearch = "";
  bool isLoading = true;
  bool _headerExpanded = false;
  bool _footerExpanded = false;

  @override
  void initState() {
    super.initState();
    _initReturnFlow();
  }

  @override
  void dispose() {
    medSearchC.dispose();
    returnNoC.dispose();
    discountC.dispose();
    discountPerC.dispose();
    origBillNoC.dispose();
    reasonC.dispose();
    super.dispose();
  }

  void _initReturnFlow() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    if (widget.existingRecord != null) {
      final ex = widget.existingRecord!;
      returnNoC.text = ex.billNo;
      selectedDate = ex.date;
      items = GstComplianceHelper.resolveMissingBillItemOrigins(
        items: ex.items,
        sales: ph.sales,
        partyId: ex.partyId,
        partyName: ex.partyName,
      );
      discountC.text = ex.extraDiscount.toStringAsFixed(2);
      paymentMode = ex.paymentMode.isNotEmpty ? ex.paymentMode : "CREDIT";
      origBillNoC.text = ex.origBillNo;
      origBillDate = ex.origBillDate;
      final parsedReason = GstComplianceHelper.parseReason(ex.reason);
      selectedReason = parsedReason.selectedReason;
      reasonC.text = parsedReason.customRemark;
      isCommercial = ex.isCommercial;
      isBreakageMode = ex.returnType.toLowerCase().contains("breakage") ||
          ex.returnType.toLowerCase().contains("expiry");
      selectedParty = ph.parties.firstWhere(
        (p) =>
            (ex.partyId.isNotEmpty && p.id == ex.partyId) ||
            p.name.trim().toLowerCase() == ex.partyName.trim().toLowerCase(),
        orElse: () => Party(
          id: ex.partyId.isNotEmpty ? ex.partyId : "0",
          name: ex.partyName,
          gst: ex.partyGstin,
          state: ex.partyState.isNotEmpty
              ? ex.partyState
              : (ph.activeCompany?.state ?? "Rajasthan"),
        ),
      );
      await _syncHeaderOriginFromItems(ph, silent: true);
      _syncDiscPerFromRupees();
      if (mounted) setState(() => isLoading = false);
    } else {
      if (ph.activeCompany != null) {
        var series = ph.getDefaultSeries("RETURN");
        final pref = (series.prefix.isNotEmpty &&
                series.prefix != "SR-" &&
                series.prefix != "CN-")
            ? series.prefix
            : "TXN-";
        final startNo = series.startNumber > 0 ? series.startNumber : 1;
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
            selectedDate = AppDateLogic.getSmartDate(ph.currentFY);
            isLoading = false;
          });
        }
      } else {
        setState(() => isLoading = false);
      }
    }
  }

  String get _effectiveReason =>
      GstComplianceHelper.formatReason(selectedReason, reasonC.text);

  Future<void> _refreshNumberForCommercialMode(
      PharoahManager ph, bool commercial) async {
    if (widget.existingRecord != null || ph.activeCompany == null) return;
    if (commercial) {
      var series = ph.getDefaultSeries("COMMERCIAL_NOTE");
      final pref = series.prefix.isNotEmpty
          ? series.prefix
          : (ph.config.commercialNotePrefix.isNotEmpty
              ? ph.config.commercialNotePrefix
              : "CCN-");
      final startNo = series.startNumber > 0 ? series.startNumber : 1;
      final nextNo = await PharoahNumberingEngine.getNextNumber(
        type: "COMMERCIAL_NOTE",
        companyID: ph.activeCompany!.id,
        prefix: pref,
        startFrom: startNo,
        currentList: [...ph.saleReturns, ...ph.purchaseReturns],
      );
      if (mounted) setState(() => returnNoC.text = nextNo);
    } else {
      var series = ph.getDefaultSeries("RETURN");
      final pref = (series.prefix.isNotEmpty &&
              series.prefix != "SR-" &&
              series.prefix != "CN-")
          ? series.prefix
          : "TXN-";
      final startNo = series.startNumber > 0 ? series.startNumber : 1;
      final nextNo = await PharoahNumberingEngine.getNextNumber(
        type: "RETURN",
        companyID: ph.activeCompany!.id,
        prefix: pref,
        startFrom: startNo,
        currentList: ph.saleReturns,
      );
      if (mounted) setState(() => returnNoC.text = nextNo);
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

  void _syncDiscPerFromRupees() {
    final gross = gstSummary.grossTaxable;
    final rs = double.tryParse(discountC.text) ?? 0.0;
    if (gross > 0 && rs > 0) {
      discountPerC.text = ((rs / gross) * 100.0).toStringAsFixed(2);
    } else {
      discountPerC.text = "0";
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

  AppBillGstSummary get gstSummary => AppBillingGstEngine.calculate(
        items: items,
        extraDiscount: extraDiscount,
        isLocal: isLocal,
        isCommercial: isCommercial,
      );

  bool get isCancelledRecord => widget.existingRecord?.status == "Cancelled";
  bool get effectiveReadOnly => widget.isReadOnly || isCancelledRecord;
  double get extraDiscount => double.tryParse(discountC.text) ?? 0.0;
  double get grandTotal => gstSummary.finalGrandTotal;
  double get roundOff => gstSummary.roundOff;

  void _recalculateSR() {
    for (int i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(srNo: i + 1);
    }
  }

  void _showMagicHistoryBox(Medicine med, PharoahManager ph) {
    if (selectedParty == null) return;
    showReturnBatchHistorySheet(
      context: context,
      isSale: true,
      medicine: med,
      party: selectedParty!,
      ph: ph,
      currentCartItems: items,
      excludeNoteId: widget.existingRecord?.id,
      onSelect: effectiveReadOnly
          ? (_) {}
          : (h) => _showEntryCard(med, existingItem: null, historyData: h),
      onAutoSplit: effectiveReadOnly
          ? null
          : (allocations, hasOverReturn) async {
              final newLines = <BillItem>[];
              int sr = items.length + 1;
              for (final a in allocations) {
                newLines.add(ReturnHistoryEngine.buildBillItemFromLine(
                  med: med,
                  line: a.line,
                  qty: a.allocatedQty,
                  srNo: sr++,
                  isLocal: isLocal,
                  isBreakage: isBreakageMode,
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
                          ? "Added ${newLines.length} split line(s) (Notice: exceeded batch returnable balance)."
                          : "Added ${newLines.length} auto-split line(s) from batch history.",
                    ),
                    backgroundColor: hasOverReturn
                        ? Colors.orange.shade800
                        : Colors.green.shade700,
                  ),
                );
              }
            },
    );
  }

  void _openPullFromBillSheet(PharoahManager ph, {String? initialBillNo}) {
    if (effectiveReadOnly || selectedParty == null) return;
    showPullFromBillSheet(
      context: context,
      isSale: true,
      party: selectedParty!,
      ph: ph,
      currentCartItems: items,
      excludeNoteId: widget.existingRecord?.id,
      initialBillNo: initialBillNo,
      onAddSelected: (picked) async {
        final newLines = <BillItem>[];
        int sr = items.length + 1;
        for (final p in picked) {
          newLines.add(ReturnHistoryEngine.buildBillItemFromLine(
            med: p.medicine,
            line: p.line,
            qty: p.qty,
            srNo: sr++,
            isLocal: isLocal,
            isBreakage: isBreakageMode,
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
              content: Text("Pulled ${newLines.length} item(s) from bill."),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      },
    );
  }

  void _showEntryCard(Medicine med,
      {BillItem? existingItem, Map<String, dynamic>? historyData}) {
    BillItem? preFilled = existingItem;
    final String histBillNo = (historyData?['billNo'] ?? '').toString().trim();
    final DateTime? histDate =
        historyData?['date'] is DateTime ? historyData!['date'] as DateTime : null;
    final bool isManualNew = existingItem == null && historyData == null;
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
        discountRupees: 0.0,
        appliedRateType: histRateType.isNotEmpty ? histRateType : "A",
        rateCFormula: ((historyData['rateCFormula'] ?? 0.0) as num).toDouble(),
        qty: ((historyData['availableQty'] ?? historyData['qty'] ?? 1.0) as num)
            .toDouble(),
        total: 0,
        origBillNo: histBillNo,
        origBillDate: histDate,
        isManualOrigin: histBillNo.isEmpty,
      );
    }
    showDialog(
      context: context,
      builder: (c) => ItemEntryCard(
        med: med,
        srNo: existingItem?.srNo ?? (items.length + 1),
        partyState: selectedParty?.state ?? "Rajasthan",
        existingItem: preFilled,
        allowExpired: true,
        onAdd: (newItem) async {
          final finalized = existingItem != null
              ? newItem.copyWith(
                  isBreakage: existingItem.isBreakage,
                  origBillNo: existingItem.origBillNo,
                  origBillDate: existingItem.origBillDate,
                  isManualOrigin: existingItem.isManualOrigin,
                )
              : newItem.copyWith(
                  isBreakage: isBreakageMode,
                  origBillNo: isManualNew ? "" : histBillNo,
                  origBillDate: isManualNew ? null : histDate,
                  clearOrigBillDate: isManualNew,
                  isManualOrigin: isManualNew || histBillNo.isEmpty,
                );
          final ph = Provider.of<PharoahManager>(context, listen: false);
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
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCancelledRecord
                  ? "Cancelled Credit Note"
                  : (effectiveReadOnly
                      ? "Audit Credit Note"
                      : (widget.existingRecord != null
                          ? "Modify Credit Note"
                          : "Credit Note Studio")),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            Text(
              "#${returnNoC.text} • ${DateFormat('dd/MM/yy').format(selectedDate)}",
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: "Print Credit Note",
            icon: const Icon(Icons.print_rounded),
            onPressed: items.isEmpty ? null : () => _handlePrint(ph),
          ),
          if (!effectiveReadOnly && items.isNotEmpty)
            IconButton(
              tooltip: "Save Credit Note",
              icon: const Icon(Icons.check_circle_rounded, size: 26),
              onPressed: () => _handleSave(ph),
            ),
        ],
      ),
      body: Column(
        children: [
          if (isCancelledRecord)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                "CANCELLED CREDIT NOTE — READ ONLY AUDIT LOCK",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.red.shade900,
                ),
              ),
            ),
          _buildCollapsibleHeader(ph),
          if (selectedParty != null) ...[
            _buildStickyModeAndLookup(ph),
          ],
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.layers_clear_rounded,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text(
                            selectedParty == null
                                ? "Select a customer above to begin."
                                : "Search Medicine / Batch / Bill above or tap PULL BILL to load items.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
                    itemCount: items.length,
                    itemBuilder: (c, i) => _buildModernItemCard(
                        items[i], i, ph, dupCounts),
                  ),
          ),
          _buildExpandableFooter(ph),
        ],
      ),
    );
  }

  Widget _buildCollapsibleHeader(PharoahManager ph) {
    final canComm = GstComplianceHelper.isCommercialNoteAllowed(ph.config);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          if (selectedParty == null) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: "Search Customer by Name, City or GST...",
                      prefixIcon: Icon(Icons.person_search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => partySearch = v),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: effectiveReadOnly ? null : () => _pickNoteDate(ph),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      DateFormat('dd/MM/yy').format(selectedDate),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                        color: Color(0xFFB71C1C),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Container(
              height: 150,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListView(
                children: ph.parties.where((p) {
                  final q = partySearch.trim().toLowerCase();
                  if (q.isEmpty) return true;
                  return p.name.toLowerCase().contains(q) ||
                      p.city.toLowerCase().contains(q) ||
                      p.gst.toLowerCase().contains(q) ||
                      p.phone.toLowerCase().contains(q);
                }).map((p) {
                  return ListTile(
                    dense: true,
                    title: Text(p.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(
                      "${p.city.isNotEmpty ? p.city : 'General'} | GST: ${p.gst.isNotEmpty ? p.gst : 'URP'}",
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => setState(() {
                      selectedParty = p;
                      partySearch = "";
                    }),
                  );
                }).toList(),
              ),
            ),
          ] else ...[
            // COMPACT COLLAPSED PARTY STRIP
            InkWell(
              onTap: () => setState(() => _headerExpanded = !_headerExpanded),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50.withAlpha(140),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_rounded,
                        color: Color(0xFFB71C1C), size: 18),
                    const SizedBox(width: 8),
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
                      color: const Color(0xFFB71C1C),
                      size: 19,
                    ),
                    if (!effectiveReadOnly) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => setState(() => selectedParty = null),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.red, size: 19),
                      ),
                    ],
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
                                  onTap: effectiveReadOnly
                                      ? null
                                      : () => setState(
                                          () => paymentMode = "CREDIT"),
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
                                  onTap: effectiveReadOnly
                                      ? null
                                      : () =>
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
                                onTap: effectiveReadOnly
                                    ? null
                                    : () => _pickNoteDate(ph),
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
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFB71C1C),
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
                                  controller: origBillNoC,
                                  readOnly: effectiveReadOnly,
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
                                  onTap: effectiveReadOnly
                                      ? null
                                      : () => _pickOrigDate(ph),
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
                                              : "Toggle ON for Non-GST Credit Note",
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
                                    onChanged: (effectiveReadOnly || !canComm)
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

  Widget _buildStickyModeAndLookup(PharoahManager ph) {
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
            excludeNoteId: widget.existingRecord?.id,
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
              _modeBtn("SELLABLE (+)", !isBreakageMode, Colors.green.shade700,
                  effectiveReadOnly ? null : () => setState(() => isBreakageMode = false)),
              const SizedBox(width: 8),
              _modeBtn("EXPIRY / BREAKAGE", isBreakageMode, Colors.orange.shade900,
                  effectiveReadOnly ? null : () => setState(() => isBreakageMode = true)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: medSearchC,
                  readOnly: effectiveReadOnly,
                  decoration: InputDecoration(
                    hintText: "Product, Batch No, or Bill No...",
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
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
                    fillColor: const Color(0xFFF8FAFC),
                  ),
                  onChanged: (v) => setState(() => medSearch = v),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed:
                    effectiveReadOnly ? null : () => _openPullFromBillSheet(ph),
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
                            color: Colors.teal.shade700, size: 18),
                        title: Text("Bill ${b.billNo}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.5)),
                        subtitle: Text(
                          "${DateFormat('dd/MM/yy').format(b.date)} • ${b.lines.length} items • ₹${b.totalAmount.toStringAsFixed(0)}",
                          style: const TextStyle(fontSize: 10.5),
                        ),
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
                        leading: const Icon(Icons.medication_rounded,
                            color: Color(0xFFB71C1C), size: 18),
                        title: Text(m.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.5)),
                        subtitle: Text(
                          "Pack: ${m.packing} • MRP ₹${m.mrp.toStringAsFixed(0)} • Stk: ${formatQty(m.stock)}",
                          style: const TextStyle(fontSize: 10.5),
                        ),
                        trailing: const Icon(Icons.layers_rounded,
                            size: 16, color: Color(0xFFB71C1C)),
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
          else if (recentBills.isNotEmpty && !effectiveReadOnly) ...[
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
                      backgroundColor: Colors.teal.shade50,
                      side: BorderSide(color: Colors.teal.shade200),
                      label: Text(
                        "${b.billNo} • ${DateFormat('dd/MM').format(b.date)} • ₹${b.totalAmount.toStringAsFixed(0)}",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade900,
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

  Widget _modeBtn(String l, bool act, Color c, VoidCallback? tap) => Expanded(
        child: InkWell(
          onTap: tap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: act ? c : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: act ? Colors.white : Colors.black54,
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ),
            ),
          ),
        ),
      );

  Widget _buildModernItemCard(
      BillItem it, int index, PharoahManager ph, Map<String, int> dupCounts) {
    final Color themeColor =
        it.isBreakage ? Colors.orange.shade900 : Colors.green.shade800;
    final dupKey =
        "${it.origBillNo.trim().toUpperCase()}||${it.batch.trim().toUpperCase()}||${it.name.trim().toUpperCase()}";
    final bool isDup =
        it.origBillNo.trim().isNotEmpty && (dupCounts[dupKey] ?? 0) > 1;

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDup ? Colors.orange.shade700 : themeColor.withAlpha(70),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: effectiveReadOnly
            ? null
            : () {
                final med = ph.medicines.firstWhere(
                  (m) =>
                      (it.medicineID.isNotEmpty && m.id == it.medicineID) ||
                      m.name.trim().toUpperCase() ==
                          it.name.trim().toUpperCase(),
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
                _showEntryCard(med, existingItem: it);
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
                      color: themeColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      it.isBreakage ? "EXP" : "RET",
                      style: const TextStyle(
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
                      color: themeColor,
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
                                border:
                                    Border.all(color: Colors.indigo.shade200),
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
                  if (!effectiveReadOnly)
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
                              color:
                                  it.qty > 1 ? Colors.black87 : Colors.black26,
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
                              items[index] =
                                  ReturnHistoryEngine.recalcBillItemQty(
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
  }

  Widget _buildExpandableFooter(PharoahManager ph) {
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
                              onChanged: effectiveReadOnly
                                  ? null
                                  : (val) {
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
                                readOnly: effectiveReadOnly,
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
                                    readOnly: effectiveReadOnly,
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
                                    readOnly: effectiveReadOnly,
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
                                  _ftRow(
                                      "Gross Taxable",
                                      "₹${gstSummary.grossTaxable.toStringAsFixed(2)}"),
                                  _ftRow(
                                      "Net Taxable",
                                      "₹${gstSummary.netTaxable.toStringAsFixed(2)}",
                                      isBold: true),
                                  if (isCommercial)
                                    _ftRow("Commercial Note (Sec 34)",
                                        "GST EXEMPT (₹0.00)",
                                        color: Colors.amber.shade900)
                                  else if (isLocal) ...[
                                    _ftRow(
                                        "CGST Total",
                                        "₹${gstSummary.totalCGST.toStringAsFixed(2)}",
                                        color: Colors.red.shade900),
                                    _ftRow(
                                        "SGST Total",
                                        "₹${gstSummary.totalSGST.toStringAsFixed(2)}",
                                        color: Colors.red.shade900),
                                  ] else
                                    _ftRow(
                                        "IGST Total",
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
                                "NET CREDIT VALUE",
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
                                color: const Color(0xFFB71C1C),
                              ),
                            ],
                          ),
                          Text(
                            "₹${grandTotal.toStringAsFixed(2)}",
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFB71C1C),
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
                        foregroundColor: const Color(0xFFB71C1C),
                        side: const BorderSide(color: Color(0xFFB71C1C)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 11),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _handlePrint(ph),
                      child: const Icon(Icons.print_rounded, size: 19),
                    ),
                  if (!effectiveReadOnly) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB71C1C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _handleSave(ph),
                      icon: const Icon(Icons.check_circle_rounded, size: 17),
                      label: const Text(
                        "SAVE",
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                  ],
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
    if (effectiveReadOnly) return;
    if (selectedParty == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please select a Customer first."),
          backgroundColor: Colors.red));
      return;
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please add at least one item before saving."),
          backgroundColor: Colors.orange));
      return;
    }
    final usedNo = returnNoC.text.trim();
    final String rType = items.isNotEmpty && items.every((it) => it.isBreakage)
        ? "Breakage"
        : (items.any((it) => it.isBreakage) ? "Mixed" : "Sellable");
    if (widget.existingRecord != null) {
      ph.updateSaleReturn(
        id: widget.existingRecord!.id,
        billNo: usedNo,
        date: selectedDate,
        party: selectedParty!,
        items: items,
        total: grandTotal,
        extraDiscount: extraDiscount,
        roundOff: roundOff,
        paymentMode: paymentMode,
        origBillNo: origBillNoC.text.trim(),
        origBillDate: origBillDate,
        reason: _effectiveReason,
        isCommercial: isCommercial,
      );
    } else {
      ph.finalizeSaleReturn(
        billNo: usedNo,
        date: selectedDate,
        party: selectedParty!,
        items: items,
        total: grandTotal,
        extraDiscount: extraDiscount,
        roundOff: roundOff,
        type: rType,
        paymentMode: paymentMode,
        origBillNo: origBillNoC.text.trim(),
        origBillDate: origBillDate,
        reason: _effectiveReason,
        isCommercial: isCommercial,
      );
      if (ph.activeCompany != null) {
        if (isCommercial) {
          var ccnSeries = ph.getDefaultSeries("COMMERCIAL_NOTE");
          final ccnPref = ccnSeries.prefix.isNotEmpty
              ? ccnSeries.prefix
              : (ph.config.commercialNotePrefix.isNotEmpty
                  ? ph.config.commercialNotePrefix
                  : "CCN-");
          PharoahNumberingEngine.updateSeriesCounter(
            type: "COMMERCIAL_NOTE",
            companyID: ph.activeCompany!.id,
            usedNumber: usedNo,
            prefix: ccnPref,
          );
        } else {
          var series = ph.getDefaultSeries("RETURN");
          final pref = (series.prefix.isNotEmpty &&
                  series.prefix != "SR-" &&
                  series.prefix != "CN-")
              ? series.prefix
              : "TXN-";
          PharoahNumberingEngine.updateSeriesCounter(
            type: "RETURN",
            companyID: ph.activeCompany!.id,
            usedNumber: usedNo,
            prefix: pref,
          );
        }
      }
    }
    Navigator.pop(context);
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
      totalAmount: grandTotal,
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
