// FILE: lib/returns/expiry_breakage_return_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../logic/pharoah_numbering_engine.dart';
import '../item_entry_card.dart';
import '../pharoah_date_controller.dart';
import '../logic/app_billing_gst_engine.dart';
import '../logic/gst_compliance_helper.dart';

class ExpiryBreakageReturnView extends StatefulWidget {
  const ExpiryBreakageReturnView({super.key});

  @override
  State<ExpiryBreakageReturnView> createState() => _ExpiryBreakageReturnViewState();
}

class _ExpiryBreakageReturnViewState extends State<ExpiryBreakageReturnView> {
  final returnNoC = TextEditingController();
  final discountC = TextEditingController(text: "0");
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
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initBreakage();
  }

  void _initBreakage() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    if (ph.activeCompany != null) {
      var defaultRetSeries = ph.getDefaultSeries("RETURN");
      final pref = (defaultRetSeries.prefix.isNotEmpty && defaultRetSeries.prefix != "SR-" && defaultRetSeries.prefix != "CN-")
          ? defaultRetSeries.prefix
          : "TXN-";
      final startNo = defaultRetSeries.startNumber > 0 ? defaultRetSeries.startNumber : 1;
      
      String nextNo = await PharoahNumberingEngine.getNextNumber(
        type: "RETURN",
        companyID: ph.activeCompany!.id,
        prefix: pref,
        startFrom: startNo,
        currentList: ph.saleReturns,
      );
      
      setState(() {
        returnNoC.text = nextNo;
        selectedDate = PharoahDateController.getInitialBillDate(ph.currentFY);
        isLoading = false;
      });
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

  bool get isSec34Expired => GstComplianceHelper.isSection34Expired(
    origInvoiceDate: origBillDate,
    noteDate: selectedDate,
  );

  double get extraDiscount => double.tryParse(discountC.text) ?? 0.0;

  AppBillGstSummary get gstSummary => AppBillingGstEngine.calculate(
    items: items,
    extraDiscount: extraDiscount,
    isLocal: isLocal,
    isCommercial: isCommercial,
  );

  double get totalAmt => gstSummary.finalGrandTotal;
  double get roundOff => gstSummary.roundOff;

  @override
  void dispose() {
    returnNoC.dispose();
    discountC.dispose();
    origBillNoC.dispose();
    reasonC.dispose();
    super.dispose();
  }

  void _recalculateSR() {
    setState(() {
      for (int i = 0; i < items.length; i++) {
        items[i] = items[i].copyWith(srNo: i + 1);
      }
    });
  }

  void _showItemSearch(PharoahManager ph) {
    String localSearch = "";
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filteredMeds = ph.medicines
              .where((m) => m.name.toLowerCase().contains(localSearch.toLowerCase()))
              .toList();
              
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
                  height: 5, width: 50,
                  decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10)),
                ),
                Padding(
                  padding: const EdgeInsets.all(15), 
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: "Search expired/breakage item...",
                      prefixIcon: const Icon(Icons.search, color: Colors.red),
                      filled: true, fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) => setSheetState(() => localSearch = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredMeds.length,
                    itemBuilder: (c, i) => ListTile(
                      leading: const Icon(Icons.delete_sweep, color: Colors.red),
                      title: Text(filteredMeds[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Pack: ${filteredMeds[i].packing} | Current Stock: ${filteredMeds[i].stock}"),
                      onTap: () {
                        Navigator.pop(context);
                        _showQuantityEntry(filteredMeds[i]);
                      },
                    ),
                  ),
                )
              ],
            ),
          );
        }
      ),
    );
  }

  void _showQuantityEntry(Medicine med) {
    showDialog(
      context: context,
      builder: (c) => ItemEntryCard(
        med: med,
        srNo: items.length + 1,
        partyState: selectedParty?.state ?? "Rajasthan", // NAYA: Added partyState parameter
        allowExpired: true,
        onAdd: (newItem) {
          setState(() { items.add(newItem.copyWith(isBreakage: true)); });
          Navigator.pop(context);
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
      backgroundColor: const Color(0xFFFFEBEE), 
      appBar: AppBar(
        title: const Text("Expiry / Breakage Return"),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (items.isNotEmpty && selectedParty != null)
            TextButton(
              onPressed: () => _handleSave(ph),
              child: const Text("SAVE AS BREAKAGE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          _buildWarningBanner(), 
          Expanded(
            child: selectedParty == null 
              ? _buildPartyPicker(ph) 
              : _buildReturnItemsList(ph),
          ),
          if (selectedParty != null) _buildSummaryFooter(),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 15),
      color: Colors.red.shade100,
      child: Row(
        children: [
          Icon(Icons.report_problem, size: 16, color: Colors.red.shade900),
          const SizedBox(width: 10),
          const Text("Items added here will NOT be added to Sellable Stock.", 
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(child: TextField(controller: returnNoC, decoration: const InputDecoration(labelText: "BREAKAGE NO", border: OutlineInputBorder(), isDense: true))),
          const SizedBox(width: 15),
          Expanded(
            child: InkWell(
              onTap: () async {
                DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: Provider.of<PharoahManager>(context, listen: false).currentFY, initialDate: selectedDate);
                if (p != null) setState(() => selectedDate = p);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(5)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat('dd/MM/yyyy').format(selectedDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Icon(Icons.calendar_today, color: Colors.red, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartyPicker(PharoahManager ph) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(15),
          child: TextField(
            decoration: const InputDecoration(hintText: "Customer Name...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            onChanged: (v) => setState(() => searchQuery = v),
          ),
        ),
        Expanded(
          child: ListView(
            children: ph.parties.where((p) => p.name.toLowerCase().contains(searchQuery.toLowerCase())).map((p) => ListTile(
              leading: const Icon(Icons.person),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => setState(() => selectedParty = p),
            )).toList(),
          ),
        )
      ],
    );
  }

  Widget _buildReturnItemsList(PharoahManager ph) {
    return Column(
      children: [
        ListTile(
          tileColor: Colors.red.withOpacity(0.05),
          title: Text(selectedParty!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          trailing: IconButton(onPressed: () => setState(() => selectedParty = null), icon: const Icon(Icons.close)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => paymentMode = "CREDIT"),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(color: paymentMode == "CREDIT" ? Colors.blue.shade800 : Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                    child: Text("CREDIT (LEDGER)", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: paymentMode == "CREDIT" ? Colors.white : Colors.black54)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => paymentMode = "CASH"),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(color: paymentMode == "CASH" ? Colors.green.shade700 : Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                    child: Text("CASH REFUND", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: paymentMode == "CASH" ? Colors.white : Colors.black54)),
                  ),
                ),
              ),
              if (GstComplianceHelper.isCommercialNoteAllowed(ph.config) || isCommercial) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: !GstComplianceHelper.isCommercialNoteAllowed(ph.config)
                      ? null
                      : () async {
                          final nextVal = !isCommercial;
                          setState(() => isCommercial = nextVal);
                          if (ph.activeCompany != null) {
                            if (nextVal) {
                              var ccnSer = ph.getDefaultSeries("COMMERCIAL_NOTE");
                              final ccnPref = ccnSer.prefix.isNotEmpty
                                  ? ccnSer.prefix
                                  : (ph.config.commercialNotePrefix.isNotEmpty ? ph.config.commercialNotePrefix : "CCN-");
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
                              final pref = (defaultRetSeries.prefix.isNotEmpty && defaultRetSeries.prefix != "SR-" && defaultRetSeries.prefix != "CN-")
                                  ? defaultRetSeries.prefix
                                  : "TXN-";
                              final n = await PharoahNumberingEngine.getNextNumber(
                                type: "RETURN",
                                companyID: ph.activeCompany!.id,
                                prefix: pref,
                                startFrom: defaultRetSeries.startNumber > 0 ? defaultRetSeries.startNumber : 1,
                                currentList: ph.saleReturns,
                              );
                              if (mounted) setState(() => returnNoC.text = n);
                            }
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isCommercial ? Colors.amber.shade100 : Colors.grey.shade200,
                      border: Border.all(color: isCommercial ? Colors.amber.shade800 : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(isCommercial ? "CCN (NO-GST)" : "GST", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isCommercial ? Colors.amber.shade900 : Colors.black54)),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: origBillNoC,
                  style: const TextStyle(fontSize: 11),
                  decoration: const InputDecoration(labelText: "Orig. Invoice No (R53)", isDense: true, filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () async {
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
                      if (expired && canComm && ph.activeCompany != null) {
                        var ccnSer = ph.getDefaultSeries("COMMERCIAL_NOTE");
                        final ccnPref = ccnSer.prefix.isNotEmpty
                            ? ccnSer.prefix
                            : (ph.config.commercialNotePrefix.isNotEmpty ? ph.config.commercialNotePrefix : "CCN-");
                        final n = await PharoahNumberingEngine.getNextNumber(
                          type: "COMMERCIAL_NOTE",
                          companyID: ph.activeCompany!.id,
                          prefix: ccnPref,
                          startFrom: ccnSer.startNumber > 0 ? ccnSer.startNumber : 1,
                          currentList: [...ph.saleReturns, ...ph.purchaseReturns],
                        );
                        if (mounted) setState(() => returnNoC.text = n);
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      origBillDate != null ? DateFormat("dd/MM/yy").format(origBillDate!) : "Orig. Date",
                      style: TextStyle(fontSize: 11, color: origBillDate != null ? Colors.black87 : Colors.grey.shade600, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ]),
            if (isSec34Expired) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade400)),
                child: Text(
                  "Sec 34(2) cutoff (${DateFormat('dd/MM/yyyy').format(GstComplianceHelper.getSection34CutoffDate(origBillDate!))}) crossed — Commercial Note (No GST) recommended.",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                ),
              ),
            ],
          ]),
        ),
        
        _buildSearchBarTrigger(ph),

        Expanded(
          child: items.isEmpty 
            ? const Center(child: Text("No items selected for return."))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                itemCount: items.length,
                itemBuilder: (c, i) => _buildItemCard(items[i], i),
              ),
        ),
      ],
    );
  }

  Widget _buildSearchBarTrigger(PharoahManager ph) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: InkWell(
        onTap: () => _showItemSearch(ph),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade300, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.red.shade700),
              const SizedBox(width: 10),
              Text("Tap here to search breakage item...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
              const Spacer(),
              Icon(Icons.add_circle, color: Colors.red.shade700),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemCard(BillItem it, int index) {
    final card = Card(
      elevation: 2, margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: Colors.red.shade50, child: Text("${it.srNo}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade900))),
        title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("Batch: ${it.batch} | Reason: Expiry/Breakage"),
        trailing: Text("₹${it.total.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      ),
    );

    return Dismissible(
      key: Key(it.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: Colors.red.shade900, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white, size: 28),
      ),
      onDismissed: (direction) {
        setState(() { items.removeAt(index); });
        _recalculateSR(); 
      },
      child: card,
    );
  }

  Widget _buildSummaryFooter() {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: Column(
        children: [
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
            onChanged: (val) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Extra Discount (-)", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: discountC,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Taxable Value", style: TextStyle(fontSize: 11, color: Colors.black87)),
                    Text("₹${gstSummary.netTaxable.toStringAsFixed(2)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                if (isCommercial)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Commercial Note (Sec 34)", style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
                      Text("GST EXEMPT (₹0.00)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                    ],
                  )
                else if (isLocal)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("CGST + SGST", style: TextStyle(fontSize: 11, color: Colors.red.shade900)),
                      Text("₹${gstSummary.totalCGST.toStringAsFixed(2)} + ₹${gstSummary.totalSGST.toStringAsFixed(2)}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("IGST", style: TextStyle(fontSize: 11, color: Colors.red.shade900)),
                      Text("₹${gstSummary.totalIGST.toStringAsFixed(2)}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("NON-SELLABLE BREAKAGE TOTAL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  Text("₹${totalAmt.toStringAsFixed(2)}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.red.shade900)),
                ],
              ),
              Text("R/O: ${roundOff.toStringAsFixed(2)}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  void _handleSave(PharoahManager ph) {
    if (selectedParty == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a Party first."), backgroundColor: Colors.red));
      return;
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please add at least one item before saving."), backgroundColor: Colors.orange));
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
      reason: GstComplianceHelper.formatReason(selectedReason, reasonC.text),
      isCommercial: isCommercial,
    );
    
    if (ph.activeCompany != null) {
      if (isCommercial) {
        var ccnSer = ph.getDefaultSeries("COMMERCIAL_NOTE");
        final ccnPref = ccnSer.prefix.isNotEmpty
            ? ccnSer.prefix
            : (ph.config.commercialNotePrefix.isNotEmpty ? ph.config.commercialNotePrefix : "CCN-");
        PharoahNumberingEngine.updateSeriesCounter(
          type: "COMMERCIAL_NOTE",
          companyID: ph.activeCompany!.id,
          usedNumber: returnNoC.text.trim(),
          prefix: ccnPref,
        );
      } else {
        var defaultRetSeries = ph.getDefaultSeries("RETURN");
        final pref = (defaultRetSeries.prefix.isNotEmpty && defaultRetSeries.prefix != "SR-" && defaultRetSeries.prefix != "CN-")
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
      backgroundColor: Colors.red.shade900
    ));
  }
}
