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
  String partySearch = ""; // 🔥 FIXED: Added missing variable
  bool isLoading = true;

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
      discountC.text = ex.extraDiscount.toString();
      paymentMode = ex.paymentMode.isNotEmpty ? ex.paymentMode : "CREDIT";
      origBillNoC.text = ex.origBillNo;
      origBillDate = ex.origBillDate;
      final parsedReason = GstComplianceHelper.parseReason(ex.reason);
      selectedReason = parsedReason.selectedReason;
      reasonC.text = parsedReason.customRemark;
      isCommercial = ex.isCommercial;
      isBreakageMode = ex.returnType.toLowerCase().contains("breakage") || ex.returnType.toLowerCase().contains("expiry");
      selectedParty = ph.parties.firstWhere(
        (p) => (ex.partyId.isNotEmpty && p.id == ex.partyId) ||
               p.name.trim().toLowerCase() == ex.partyName.trim().toLowerCase(),
        orElse: () => Party(
          id: ex.partyId.isNotEmpty ? ex.partyId : "0",
          name: ex.partyName,
          gst: ex.partyGstin,
          state: ex.partyState.isNotEmpty ? ex.partyState : (ph.activeCompany?.state ?? "Rajasthan"),
        ),
      );
      _syncHeaderOriginFromItems(ph, silent: true);
      setState(() => isLoading = false);
    } else {
      if (ph.activeCompany != null) {
        var series = ph.getDefaultSeries("RETURN");
        final pref = (series.prefix.isNotEmpty && series.prefix != "SR-" && series.prefix != "CN-")
            ? series.prefix
            : "TXN-";
        final startNo = series.startNumber > 0 ? series.startNumber : 1;
        String nextNo = await PharoahNumberingEngine.getNextNumber(
          type: "RETURN", companyID: ph.activeCompany!.id,
          prefix: pref, startFrom: startNo, currentList: ph.saleReturns,
        );
        setState(() {
          returnNoC.text = nextNo;
          selectedDate = AppDateLogic.getSmartDate(ph.currentFY);
          isLoading = false;
        });
      }
    }
  }

  String get _effectiveReason => GstComplianceHelper.formatReason(selectedReason, reasonC.text);

  Future<void> _refreshNumberForCommercialMode(PharoahManager ph, bool commercial) async {
    if (widget.existingRecord != null || ph.activeCompany == null) return;
    if (commercial) {
      var series = ph.getDefaultSeries("COMMERCIAL_NOTE");
      final pref = series.prefix.isNotEmpty
          ? series.prefix
          : (ph.config.commercialNotePrefix.isNotEmpty ? ph.config.commercialNotePrefix : "CCN-");
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
      final pref = (series.prefix.isNotEmpty && series.prefix != "SR-" && series.prefix != "CN-")
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

  // --- GST COMPLIANT CALCULATIONS (Section 15 & 34) ---
  bool get isLocal {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    return GstComplianceHelper.isIntraStateReturn(
      shopGstin: ph.activeCompany?.gstin,
      shopState: ph.activeCompany?.state ?? "Rajasthan",
      partyGstin: selectedParty?.gst,
      partyState: selectedParty?.state,
    );
  }

  DateTime? get expiredOriginDate => GstComplianceHelper.getExpiredOriginDate(
    headerOrigDate: origBillDate,
    items: items,
    noteDate: selectedDate,
  );

  bool get isSec34Expired => expiredOriginDate != null;

  Future<void> _syncHeaderOriginFromItems(PharoahManager ph, {bool silent = false}) async {
    final summary = GstComplianceHelper.summarizeOriginInvoices(items);
    if (summary.uniqueCount > 0) {
      origBillNoC.text = summary.headerBillNo;
      origBillDate = summary.headerDate;
    } else if (items.isNotEmpty && items.every((it) => it.isManualOrigin)) {
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

  void _showMagicHistoryBox(Medicine med, PharoahManager ph) {
    if (selectedParty == null) return;
    final history = ph.getMedicineHistory(
      partyId: selectedParty!.id,
      medicineId: med.id,
      partyName: selectedParty!.name,
      medicineName: med.name,
      isSale: true,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(color: Color(0xFFF8F9FA), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(children: [
          Container(margin: const EdgeInsets.all(15), height: 5, width: 60, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10))),
          Text("TRANSACTION HISTORY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blue.shade900, letterSpacing: 2)),
          const SizedBox(height: 5),
          Text(med.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          Expanded(
            child: history.isEmpty 
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.history_toggle_off, size: 40, color: Colors.grey.shade300),
                  const Text("No history for this party.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: history.length,
                  itemBuilder: (c, i) {
                    final h = history[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 1,
                      child: ListTile(
                        onTap: effectiveReadOnly ? null : () { Navigator.pop(c); _showEntryCard(med, existingItem: null, historyData: h); },
                        title: Text("Bill: ${h['billNo']} | ${DateFormat('dd/MM/yy').format(h['date'])}"),
                        subtitle: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          _miniInfo("BATCH", h['batch']),
                          _miniInfo("LAST QTY", "${formatQty(h['qty'])} + ${formatQty(h['free'])}", isBold: true),
                          _miniInfo("RATE", "₹${h['rate']}"),
                        ]),
                      ),
                    );
                  },
                ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity, height: 50,
              child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(c); _showEntryCard(med); },
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.blue), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.edit_document), label: const Text("NOT IN HISTORY? ENTER MANUALLY"),
              ),
            ),
          )
        ]),
      ),
    );
  }

  Widget _miniInfo(String l, String v, {bool isBold = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(l, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
    Text(v, style: TextStyle(fontSize: 11, fontWeight: isBold ? FontWeight.w900 : FontWeight.bold, color: isBold ? Colors.indigo : Colors.black87)),
  ]);

  void _showEntryCard(Medicine med, {BillItem? existingItem, Map<String, dynamic>? historyData}) {
    BillItem? preFilled = existingItem;
    final String histBillNo = (historyData?['billNo'] ?? '').toString().trim();
    final DateTime? histDate = historyData?['date'] is DateTime ? historyData!['date'] as DateTime : null;
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
        qty: 0,
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
        srNo: existingItem?.srNo ?? items.length + 1,
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
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text(isCancelledRecord ? "Cancelled Credit Note (Read-Only)" : (effectiveReadOnly ? "Audit Credit Note" : (widget.existingRecord != null ? "Modify Credit Note" : "New Credit Note"))),
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.print_rounded), onPressed: items.isEmpty ? null : () => _handlePrint(ph)),
          if (!effectiveReadOnly && items.isNotEmpty) 
            IconButton(icon: const Icon(Icons.check_circle_rounded, size: 28), onPressed: () => _handleSave(ph)),
        ],
      ),
      body: IgnorePointer(
        ignoring: effectiveReadOnly,
        child: Column(children: [
          if (isCancelledRecord)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                "CANCELLED CREDIT NOTE — READ ONLY AUDIT LOCK",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.red.shade900),
              ),
            ),
          _buildHeader(ph),
          if (selectedParty != null) ...[
            _buildQuickModeToggle(),
            _buildLiveSearch(ph),
          ],
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text("No items added for return"))
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: items.length,
                    itemBuilder: (c, i) => _buildItemCard(items[i], i, ph),
                  ),
          ),
          _buildAdvancedFooter(),
        ]),
      ),
    );
  }

  Widget _buildItemCard(BillItem it, int index, PharoahManager ph) {
    Color themeColor = it.isBreakage ? Colors.orange.shade900 : Colors.green.shade800;
    Color bgColor = it.isBreakage ? Colors.orange.shade50 : Colors.green.shade50;
    return Card(
      elevation: 1, margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: themeColor.withOpacity(0.2))),
      child: ListTile(
        onTap: () {
          final med = ph.medicines.firstWhere(
            (m) => (it.medicineID.isNotEmpty && m.id == it.medicineID) ||
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
          _showEntryCard(med, existingItem: it);
        },
        tileColor: bgColor,
        title: Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: themeColor, borderRadius: BorderRadius.circular(5)), child: Text(it.isBreakage ? "EXP" : "RET", style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Batch: ${it.batch} | Qty: ${formatQty(it.qty)} + ${formatQty(it.freeQty)}"),
            if (it.origBillNo.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Text(
                    "Inv: ${it.origBillNo}${it.origBillDate != null ? ' (${DateFormat('dd/MM/yy').format(it.origBillDate!)})' : ''}",
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.indigo.shade800),
                  ),
                ),
              ),
          ],
        ),
        trailing: Text("₹${it.total.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.w900, color: themeColor)),
        onLongPress: () {
          setState(() => items.removeAt(index));
          _syncHeaderOriginFromItems(ph, silent: true);
        },
      ),
    );
  }

  Widget _buildHeader(PharoahManager ph) => Container(
    padding: const EdgeInsets.all(15), color: Colors.white,
    child: Column(children: [
        // 🗓️ DATE SELECTOR & CREDIT NOTE NO BAR
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Icon(Icons.assignment_return_rounded, color: Color(0xFFB71C1C), size: 18),
              const SizedBox(width: 6),
              Text("CREDIT NOTE #${returnNoC.text}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFFB71C1C))),
            ]),
            InkWell(
              onTap: effectiveReadOnly ? null : () async {
                DateTime? p = await PharoahDateController.pickDate(
                  context: context,
                  currentFY: ph.currentFY,
                  initialDate: selectedDate,
                );
                if (p != null) {
                  final canComm = GstComplianceHelper.isCommercialNoteAllowed(ph.config);
                  final expired = GstComplianceHelper.isSection34Expired(origInvoiceDate: origBillDate, noteDate: p);
                  setState(() {
                    selectedDate = p;
                    if (expired && canComm && !isCommercial) {
                      isCommercial = true;
                    }
                  });
                  if (expired && canComm) {
                    await _refreshNumberForCommercialMode(ph, true);
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_month_rounded, size: 14, color: Color(0xFFB71C1C)),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('dd/MM/yyyy').format(selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFB71C1C)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFFB71C1C)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (selectedParty == null) ...[
          TextField(
            decoration: const InputDecoration(
              hintText: "Search Customer / Party by Name, City or GST...",
              prefixIcon: Icon(Icons.person_search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() { partySearch = v; }),
          ),
          Container(
            height: 160, margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(10)),
            child: ListView(
              children: ph.parties.where((p) {
                final q = partySearch.trim().toLowerCase();
                if (q.isEmpty) return true;
                return p.name.toLowerCase().contains(q) ||
                       p.city.toLowerCase().contains(q) ||
                       p.gst.toLowerCase().contains(q) ||
                       p.phone.toLowerCase().contains(q);
              }).map((p) => ListTile(
                dense: true,
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text("${p.city.isNotEmpty ? p.city : 'General'} | GST: ${p.gst.isNotEmpty ? p.gst : 'URP'} | Group: ${p.group.isNotEmpty ? p.group : 'Party'}", style: const TextStyle(fontSize: 11)),
                onTap: () => setState(() { selectedParty = p; partySearch = ""; }),
              )).toList(),
            ),
          )
        ] else
          ListTile(
            tileColor: Colors.red.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Text(selectedParty!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("City: ${selectedParty!.city.isNotEmpty ? selectedParty!.city : 'N/A'} | GST: ${selectedParty!.gst.isNotEmpty ? selectedParty!.gst : 'URP'}"),
            trailing: widget.isReadOnly ? null : IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() => selectedParty = null)),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: effectiveReadOnly ? null : () => setState(() => paymentMode = "CREDIT"),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: paymentMode == "CREDIT" ? Colors.blue.shade800 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text("CREDIT (LEDGER)", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: paymentMode == "CREDIT" ? Colors.white : Colors.black54)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: effectiveReadOnly ? null : () => setState(() => paymentMode = "CASH"),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: paymentMode == "CASH" ? Colors.green.shade700 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text("CASH REFUND", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: paymentMode == "CASH" ? Colors.white : Colors.black54)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: origBillNoC,
              readOnly: widget.isReadOnly,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(labelText: "Orig. Invoice No (R53)", isDense: true, border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: effectiveReadOnly ? null : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: GstComplianceHelper.clampPickerDate(origBillDate ?? selectedDate, DateTime(2017, 7, 1), selectedDate),
                  firstDate: DateTime(2017, 7, 1),
                  lastDate: selectedDate,
                );
                if (picked != null) {
                  final canComm = GstComplianceHelper.isCommercialNoteAllowed(ph.config);
                  final expired = GstComplianceHelper.isSection34Expired(origInvoiceDate: picked, noteDate: selectedDate);
                  setState(() {
                    origBillDate = picked;
                    if (expired && canComm) {
                      isCommercial = true;
                    }
                  });
                  if (expired && canComm) {
                    await _refreshNumberForCommercialMode(ph, true);
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
                child: Text(
                  origBillDate != null ? DateFormat("dd/MM/yy").format(origBillDate!) : "Orig. Date",
                  style: TextStyle(fontSize: 11, color: origBillDate != null ? Colors.black87 : Colors.grey.shade600, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ]),
        if (GstComplianceHelper.isCommercialNoteAllowed(ph.config) || isCommercial) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isCommercial ? Colors.amber.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isCommercial ? Colors.amber.shade700 : Colors.grey.shade300),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Commercial Note (Non-GST)",
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isCommercial ? Colors.amber.shade900 : Colors.black87,
                        ),
                      ),
                      Text(
                        isCommercial
                            ? "Active: Tax 0% • Excluded from GSTR-1/3B • CCN- Series"
                            : "Toggle ON to issue a Non-GST Commercial Credit Note (CCN-)",
                        style: TextStyle(fontSize: 9.5, color: isCommercial ? Colors.amber.shade800 : Colors.black54),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: isCommercial,
                  activeColor: Colors.amber.shade800,
                  onChanged: (effectiveReadOnly || !GstComplianceHelper.isCommercialNoteAllowed(ph.config))
                      ? null
                      : (val) async {
                          setState(() => isCommercial = val);
                          await _refreshNumberForCommercialMode(ph, val);
                        },
                ),
              ],
            ),
          ),
        ],
        if (isSec34Expired) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade400)),
            child: Text(
              "Sec 34(2) cutoff (${DateFormat('dd/MM/yyyy').format(GstComplianceHelper.getSection34CutoffDate(expiredOriginDate!))}) crossed — Commercial Note (No GST) recommended.",
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
            ),
          ),
        ],
    ]),
  );

  Widget _buildQuickModeToggle() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    child: Row(children: [
        _modeBtn("SELLABLE RETURN", !isBreakageMode, Colors.green.shade700, () => setState(() => isBreakageMode = false)),
        const SizedBox(width: 10),
        _modeBtn("EXPIRY / BREAKAGE", isBreakageMode, Colors.orange.shade900, () => setState(() => isBreakageMode = true)),
    ]),
  );

  Widget _modeBtn(String l, bool act, Color c, VoidCallback tap) => Expanded(child: InkWell(onTap: tap, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: act ? c : Colors.grey.shade200, borderRadius: BorderRadius.circular(10)), child: Text(l, textAlign: TextAlign.center, style: TextStyle(color: act ? Colors.white : Colors.black54, fontWeight: FontWeight.bold, fontSize: 10)))));

  Widget _buildLiveSearch(PharoahManager ph) => Padding(
    padding: const EdgeInsets.all(10),
    child: Column(children: [
        TextField(
          controller: medSearchC, 
          decoration: InputDecoration(
            hintText: "Type product to return...",
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(), filled: true, fillColor: Colors.white
          ),
          onChanged: (v) => setState(() => medSearch = v),
        ),
        if (medSearch.isNotEmpty)
          Container(
            height: 200, decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
            child: ListView(children: ph.medicines.where((m) => m.name.toLowerCase().contains(medSearch.toLowerCase())).map((m) => ListTile(
              title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { 
                setState(() { medSearch = ""; medSearchC.clear(); }); 
                _showMagicHistoryBox(m, ph); 
              },
            )).toList()),
          )
    ]),
  );

  Widget _buildAdvancedFooter() => Container(
    padding: const EdgeInsets.all(15), color: Colors.white,
    child: Column(children: [
        DropdownButtonFormField<String>(
          value: selectedReason,
          isExpanded: true,
          style: const TextStyle(fontSize: 11.5, color: Colors.black87),
          decoration: const InputDecoration(
            labelText: "Return Reason (GST Rule 53(1A))",
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: GstComplianceHelper.standardReasons
              .map((r) => DropdownMenuItem<String>(value: r, child: Text(r, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: effectiveReadOnly
              ? null
              : (val) {
                  if (val != null) setState(() => selectedReason = val);
                },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: GstComplianceHelper.isOtherReason(selectedReason)
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: reasonC,
                    readOnly: effectiveReadOnly,
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(
                      labelText: "Custom Remarks / Expiry / Damage Details",
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Extra Discount (-)", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          SizedBox(
            width: 100,
            child: TextField(
              controller: discountC,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              onChanged: (v) => setState(() {}),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Taxable Value", style: TextStyle(fontSize: 11, color: Colors.black87)),
              Text("₹${gstSummary.netTaxable.toStringAsFixed(2)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            if (isCommercial)
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text("Commercial Note (Sec 34)", style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
                Text("GST EXEMPT (₹0.00)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
              ])
            else if (isLocal)
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text("CGST + SGST", style: TextStyle(fontSize: 11, color: Colors.red.shade900)),
                Text("₹${gstSummary.totalCGST.toStringAsFixed(2)} + ₹${gstSummary.totalSGST.toStringAsFixed(2)}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
              ])
            else
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text("IGST", style: TextStyle(fontSize: 11, color: Colors.red.shade900)),
                Text("₹${gstSummary.totalIGST.toStringAsFixed(2)}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
              ]),
          ]),
        ),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("NET CREDIT VALUE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            Text("₹${grandTotal.toStringAsFixed(2)}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFB71C1C))),
          ]),
          Text("R/O: ${roundOff.toStringAsFixed(2)}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
    ]),
  );

  void _handleSave(PharoahManager ph) {
    if (effectiveReadOnly) return;
    if (selectedParty == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a Customer first."), backgroundColor: Colors.red));
      return;
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please add at least one item before saving."), backgroundColor: Colors.orange));
      return;
    }
    final usedNo = returnNoC.text.trim();
    final String rType = items.isNotEmpty && items.every((it) => it.isBreakage)
        ? "Breakage"
        : (items.any((it) => it.isBreakage) ? "Mixed" : "Sellable");
    if (widget.existingRecord != null) {
      ph.updateSaleReturn(
        id: widget.existingRecord!.id, billNo: usedNo, date: selectedDate, party: selectedParty!,
        items: items, total: grandTotal, extraDiscount: extraDiscount, roundOff: roundOff,
        paymentMode: paymentMode, origBillNo: origBillNoC.text.trim(), origBillDate: origBillDate,
        reason: _effectiveReason, isCommercial: isCommercial,
      );
    } else {
      ph.finalizeSaleReturn(
        billNo: usedNo, date: selectedDate, party: selectedParty!,
        items: items, total: grandTotal, extraDiscount: extraDiscount, roundOff: roundOff,
        type: rType, paymentMode: paymentMode, origBillNo: origBillNoC.text.trim(),
        origBillDate: origBillDate, reason: _effectiveReason, isCommercial: isCommercial,
      );
      if (ph.activeCompany != null) {
        if (isCommercial) {
          var ccnSeries = ph.getDefaultSeries("COMMERCIAL_NOTE");
          final ccnPref = ccnSeries.prefix.isNotEmpty
              ? ccnSeries.prefix
              : (ph.config.commercialNotePrefix.isNotEmpty ? ph.config.commercialNotePrefix : "CCN-");
          PharoahNumberingEngine.updateSeriesCounter(
            type: "COMMERCIAL_NOTE",
            companyID: ph.activeCompany!.id,
            usedNumber: usedNo,
            prefix: ccnPref,
          );
        } else {
          var series = ph.getDefaultSeries("RETURN");
          final pref = (series.prefix.isNotEmpty && series.prefix != "SR-" && series.prefix != "CN-")
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
      id: "temp", billNo: returnNoC.text, date: selectedDate,
      partyId: selectedParty!.id, partyName: selectedParty!.name,
      partyGstin: selectedParty!.gst, partyState: selectedParty!.state,
      items: resolvedItems, totalAmount: grandTotal, extraDiscount: extraDiscount, roundOff: roundOff,
      paymentMode: paymentMode, origBillNo: origBillNoC.text.trim(), origBillDate: origBillDate,
      reason: _effectiveReason, isCommercial: isCommercial,
    );
    await PdfRouterService.printCreditNote(returnObj: returnObj, party: selectedParty!, ph: ph);
  }
}
