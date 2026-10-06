// FILE: lib/web_live_sync/sub_views/web_data_exchange/ui/web_import_review_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../web_models.dart';
import '../../../pharoah_web_manager.dart';
import '../../../web_app_date_logic.dart';
import '../../../web_pharoah_numbering_engine.dart';
import '../../web_billing/quick_add_party_modal.dart';
import '../../web_billing/quick_add_product_modal.dart';
import '../../web_billing/mechanism/web_billing_gst_engine.dart';

class WebImportReviewScreen extends StatefulWidget {
  final List<List<dynamic>> csvData;
  final String importType; // "PURCHASE" or "SALE"
  final String exchangeMode; // "C2C" or "C2V"
  final VoidCallback onBack;

  const WebImportReviewScreen({
    super.key,
    required this.csvData,
    required this.importType,
    required this.exchangeMode,
    required this.onBack,
  });

  @override
  State<WebImportReviewScreen> createState() => _WebImportReviewScreenState();
}

class _WebImportReviewScreenState extends State<WebImportReviewScreen> {
  List<Map<String, dynamic>> reviewedItems = [];
  Map<String, dynamic> partyInfoInFile = {};
  Party? matchedParty;
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _processUniversalCsvLogic();
  }

  String _cleanStr(String s) => s.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();

  void _processUniversalCsvLogic() {
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    final data = widget.csvData;
    if (data.length < 2) {
      setState(() => isLoading = false);
      return;
    }

    var r1 = data[1];

    // Smart Date Watchdog
    String rawCsvDate = r1[0]?.toString() ?? "";
    DateTime finalAdjustedDate;
    String dateAdjustmentNote = "";
    bool isDateAdjusted = false;

    DateTime fyStart = WebAppDateLogic.getFYStart(webPh.financialYear);
    DateTime fyEnd = WebAppDateLogic.getFYEnd(webPh.financialYear);

    try {
      DateTime parsed = DateFormat('dd/MM/yyyy').parse(rawCsvDate.trim());
      if (parsed.isBefore(fyStart)) {
        finalAdjustedDate = fyStart;
        isDateAdjusted = true;
        dateAdjustmentNote = "[Shifted to FY Start 01/04 | Orig: $rawCsvDate]";
      } else if (parsed.isAfter(fyEnd)) {
        finalAdjustedDate = fyEnd;
        isDateAdjusted = true;
        dateAdjustmentNote = "[Shifted to FY End 31/03 | Orig: $rawCsvDate]";
      } else {
        finalAdjustedDate = parsed;
      }
    } catch (_) {
      finalAdjustedDate = fyStart;
      isDateAdjusted = true;
      dateAdjustmentNote = "[Date Adjusted: Fallback]";
    }

    partyInfoInFile = {
      'name': (r1[2] ?? "UNKNOWN").toString().trim().toUpperCase(),
      'gst': (r1[3] ?? "").toString().trim().toUpperCase(),
      'dl': (r1[4] ?? "").toString().trim().toUpperCase(),
      'pan': (r1[5] ?? "").toString().trim().toUpperCase(),
      'phone': (r1[6] ?? "").toString().trim(),
      'email': (r1[7] ?? "").toString().trim().toLowerCase(),
      'address': (r1[8] ?? "").toString().trim().toUpperCase(),
      'city': (r1[9] ?? "").toString().trim().toUpperCase(),
      'state': (r1[10] ?? "Rajasthan").toString().trim(),
      'billNo': (r1[1] ?? "DRAFT").toString().trim(),
      'date': finalAdjustedDate,
      'isDateAdjusted': isDateAdjusted,
      'dateAdjustmentNote': dateAdjustmentNote,
      'rawCsvDate': rawCsvDate,
      'extraDisc': r1.length >= 39 ? (double.tryParse(r1[37].toString()) ?? 0.0) : 0.0,
      'roundOff': r1.length >= 39
          ? (double.tryParse(r1[38].toString()) ?? 0.0)
          : (r1.length >= 38 ? (double.tryParse(r1[37].toString()) ?? 0.0) : 0.0),
    };

    // Match Party
    String cleanGst = partyInfoInFile['gst'].toString().trim().toUpperCase();
    String cleanPName = _cleanStr(partyInfoInFile['name'].toString());

    try {
      matchedParty = webPh.parties.firstWhere((p) {
        if (cleanGst.isNotEmpty && cleanGst != 'N/A' && p.gst.trim().toUpperCase() == cleanGst) return true;
        return _cleanStr(p.name) == cleanPName;
      });
    } catch (_) {
      matchedParty = null;
    }

    // Process 39-Col Items
    reviewedItems.clear();
    for (int i = 1; i < data.length; i++) {
      var row = data[i];
      if (row.length < 34) continue;

      String csvName = (row[18] ?? "UNKNOWN").toString().trim().toUpperCase();
      String csvPack = (row[19] ?? "1*10").toString().trim().toUpperCase();
      double qty = double.tryParse(row[28].toString()) ?? 0.0;
      double free = double.tryParse(row[29].toString()) ?? 0.0;

      double rate = widget.importType == "PURCHASE"
          ? (double.tryParse(row[31].toString()) ?? 0.0)
          : (double.tryParse(row[32].toString()) ?? 0.0);

      double gstPer = double.tryParse(row[33].toString()) ?? 12.0;
      double csvTotal = double.tryParse(row[34].toString()) ?? 0.0;
      double itemDiscPer = row.length > 35 ? (double.tryParse(row[35].toString()) ?? 0.0) : 0.0;
      double gross = qty * rate;
      double discAmt = row.length > 36 
          ? (double.tryParse(row[36].toString()) ?? (gross * (itemDiscPer / 100))) 
          : (gross * (itemDiscPer / 100));

      double taxable = gross - discAmt;
      if (taxable < 0) taxable = 0.0;
      double taxAmt = taxable * (gstPer / 100);
      double systemTotal = double.parse((taxable + taxAmt).toStringAsFixed(2));

      Medicine? match;
      String cleanItem = _cleanStr(csvName);
      try {
        match = webPh.medicines.firstWhere((m) => _cleanStr(m.name) == cleanItem && m.packing.toUpperCase() == csvPack);
      } catch (_) {
        try {
          match = webPh.medicines.firstWhere((m) => _cleanStr(m.name) == cleanItem);
        } catch (_) {
          match = null;
        }
      }

      reviewedItems.add({
        'name': csvName,
        'pack': csvPack,
        'hsn': (row[20] ?? "3004").toString().trim(),
        'mfg': (row[21] ?? "N/A").toString().trim().toUpperCase(),
        'salt': (row[22] ?? "N/A").toString().trim().toUpperCase(),
        'form': (row[23] ?? "TAB").toString().trim().toUpperCase(),
        'isNaco': row[24].toString().toUpperCase() == "YES",
        'isH1': row[25].toString().toUpperCase() == "YES",
        'batch': (row[26] ?? "AUTO").toString().trim(),
        'exp': (row[27] ?? "12/28").toString().trim(),
        'qty': qty,
        'free': free,
        'mrp': double.tryParse(row[30].toString()) ?? 0.0,
        'purRate': double.tryParse(row[31].toString()) ?? 0.0,
        'rate': rate,
        'gstPer': gstPer,
        'csvTotal': csvTotal,
        'sysTotal': systemTotal,
        'itemDiscPer': itemDiscPer,
        'discAmt': discAmt,
        'match': match,
        'isSelected': true,
        'status': match == null ? 'new' : 'exact',
        'isFixed': false,
        'taxable': taxable,
      });
    }

    setState(() => isLoading = false);
  }

  void _propagateMatchingLinks(Medicine matchedMed) {
    String cleanTarget = _cleanStr(matchedMed.name);
    setState(() {
      for (var it in reviewedItems) {
        if (it['match'] == null && _cleanStr(it['name'].toString()) == cleanTarget) {
          it['match'] = matchedMed;
          it['status'] = 'exact';
          it['isSelected'] = true;
        }
      }
    });
  }

  void _showInstantLinkOverlay(int itemIndex) {
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    String localSearch = "";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filteredMeds = webPh.medicines
              .where((m) => m.name.toLowerCase().contains(localSearch.toLowerCase()))
              .take(6)
              .toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 18, right: 18, top: 14),
            child: Column(
              children: [
                Container(height: 5, width: 50, decoration: const BoxDecoration(color: Colors.white24)),
                const SizedBox(height: 12),
                const Text("SELECT SYSTEM PRODUCT TO LINK", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: "Type medicine name...",
                    prefixIcon: Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                    filled: true,
                    fillColor: Colors.black26,
                  ),
                  onChanged: (v) => setSheetState(() => localSearch = v),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredMeds.length,
                    itemBuilder: (c, idx) {
                      final m = filteredMeds[idx];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.medication_rounded, color: Color(0xFF38BDF8), size: 18),
                        title: Text(m.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                        subtitle: Text("Pack: ${m.packing} • Stock: ${m.stock.toInt()} • MRP: ₹${m.mrp.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                        trailing: const Icon(Icons.link_rounded, color: Colors.greenAccent, size: 18),
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
          reviewedItems[itemIndex]['match'] = selectedMed;
          reviewedItems[itemIndex]['status'] = 'exact';
          reviewedItems[itemIndex]['isSelected'] = true;
        });
        _propagateMatchingLinks(selectedMed);
      }
    });
  }

  void _autoResolveAllNewProducts(PharoahWebManager webPh) async {
    setState(() => isLoading = true);

    for (int idx = 0; idx < reviewedItems.length; idx++) {
      var it = reviewedItems[idx];
      if (it['status'] == 'new' || it['match'] == null) {
        String cleanTarget = _cleanStr(it['name'].toString());

        Medicine? match;
        try {
          match = webPh.medicines.firstWhere((m) => _cleanStr(m.name) == cleanTarget);
        } catch (_) {
          match = null;
        }

        if (match != null) {
          it['match'] = match;
          it['status'] = 'exact';
          it['isSelected'] = true;
        } else {
          String sysId = WebPharoahNumberingEngine.getNextNumber(
            prefix: "PH-",
            startFrom: 10001,
            currentList: webPh.medicines,
          );

          final newMed = Medicine(
            id: "MED-CSV-${DateTime.now().millisecondsSinceEpoch}-$idx",
            systemId: sysId,
            name: it['name'].toString().trim().toUpperCase(),
            packing: it['pack'].toString().trim().toUpperCase(),
            hsnCode: it['hsn'].toString(),
            gst: (it['gstPer'] as num).toDouble(),
            mrp: (it['mrp'] as num).toDouble(),
            purRate: (it['purRate'] as num).toDouble(),
            rateA: (it['rate'] as num).toDouble(),
            drugForm: it['form'].toString(),
            isNarcotic: it['isNaco'] == true,
            isScheduleH1: it['isH1'] == true,
            companyId: webPh.getOrCreateCompany(it['mfg'].toString()),
            saltId: webPh.getOrCreateSalt(it['salt'].toString()),
          );

          webPh.addMedicine(newMed);
          it['match'] = newMed;
          it['status'] = 'exact';
          it['isSelected'] = true;
        }
      }
    }

    await webPh.pushUpdatedDataToCloud();
    setState(() => isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ All new medicines auto-resolved and added to master!"), backgroundColor: Colors.green),
      );
    }
  }

  void _handleFinalImport(PharoahWebManager webPh) async {
    if (matchedParty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select or create the Party/Supplier first!"), backgroundColor: Colors.orange),
      );
      return;
    }

    if (reviewedItems.any((it) => it['isSelected'] && it['match'] == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please resolve all unlinked items (Click AUTO-CREATE)!"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => isSaving = true);

    DateTime adjustedDate = partyInfoInFile['date'] as DateTime;
    String auditTag = "${widget.exchangeMode} ${partyInfoInFile['dateAdjustmentNote'] ?? ''}".trim();
    bool isLocal = (partyInfoInFile['state']?.toString().toLowerCase() ?? '') == (webPh.companyProfile.state.isEmpty ? 'rajasthan' : webPh.companyProfile.state.toLowerCase());

    if (widget.importType == "PURCHASE") {
      String internalNo = WebPharoahNumberingEngine.getNextNumber(
        prefix: "PUR-",
        startFrom: 1,
        currentList: webPh.purchases,
      );

      List<PurchaseItem> items = [];
      List<BillItem> tempItemsForGst = [];
      int sNo = 1;

      for (var it in reviewedItems.where((e) => e['isSelected'])) {
        Medicine m = it['match'];
        double pRate = (it['rate'] as num).toDouble();
        double q = (it['qty'] as num).toDouble();
        double freeQ = (it['free'] as num).toDouble();
        double discAmt = (it['discAmt'] as num).toDouble();
        double discPer = (it['itemDiscPer'] as num).toDouble();
        double gstR = (it['gstPer'] as num).toDouble();

        items.add(PurchaseItem(
          id: "PITM-CSV-${DateTime.now().millisecondsSinceEpoch}-$sNo",
          srNo: sNo++,
          medicineID: m.id,
          name: m.name,
          packing: m.packing,
          batch: it['batch'],
          exp: it['exp'],
          hsn: it['hsn'],
          mrp: (it['mrp'] as num).toDouble(),
          qty: q,
          freeQty: freeQ,
          purchaseRate: pRate,
          gstRate: gstR,
          total: (it['sysTotal'] as num).toDouble(),
          discountPer: discPer,
          discountRupees: discAmt,
        ));

        tempItemsForGst.add(BillItem(
          id: "TEMP-$sNo",
          srNo: sNo,
          medicineID: m.id,
          name: m.name,
          packing: m.packing,
          batch: it['batch'],
          exp: it['exp'],
          hsn: it['hsn'],
          mrp: (it['mrp'] as num).toDouble(),
          qty: q,
          freeQty: freeQ,
          rate: pRate,
          gstRate: gstR,
          total: (it['sysTotal'] as num).toDouble(),
          discountRupees: discAmt,
          discountPer: discPer,
        ));

        webPh.registerBatchActivity(
          productKey: m.identityKey,
          batchNo: it['batch'],
          exp: it['exp'],
          packing: m.packing,
          mrp: (it['mrp'] as num).toDouble(),
          rate: pRate,
          qtyChange: q + freeQ,
        );
      }

      final double exDiscPur = (partyInfoInFile['extraDisc'] as num).toDouble();
      final summary = WebBillingGstEngine.calculate(
        items: tempItemsForGst,
        extraDiscount: exDiscPur,
        isLocal: isLocal,
      );

      final newPur = Purchase(
        id: "PUR-CSV-${DateTime.now().millisecondsSinceEpoch}",
        internalNo: internalNo,
        billNo: partyInfoInFile['billNo'],
        partyId: matchedParty!.id,
        distributorName: matchedParty!.name,
        date: adjustedDate,
        entryDate: DateTime.now(),
        paymentMode: "CREDIT",
        totalAmount: summary.finalGrandTotal,
        extraDiscount: summary.extraDiscount,
        roundOff: summary.roundOff,
        sourceTag: auditTag,
        items: items,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        version: 1,
      );

      webPh.unmarkDeletedId(newPur.id, referenceNo: newPur.internalNo);
      if (newPur.billNo.isNotEmpty) webPh.unmarkDeletedId(newPur.billNo);
      webPh.addPurchaseAndSync(newPur);
    } else {
      String nextBillNo = partyInfoInFile['billNo'];
      List<BillItem> rawItems = [];
      int sNo = 1;

      for (var it in reviewedItems.where((e) => e['isSelected'])) {
        Medicine m = it['match'];
        double sRate = (it['rate'] as num).toDouble();
        double q = (it['qty'] as num).toDouble();
        double freeQ = (it['free'] as num).toDouble();
        double discAmt = (it['discAmt'] as num).toDouble();
        double discPer = (it['itemDiscPer'] as num).toDouble();
        double gstR = (it['gstPer'] as num).toDouble();

        rawItems.add(BillItem(
          id: "SITM-CSV-${DateTime.now().millisecondsSinceEpoch}-$sNo",
          srNo: sNo++,
          medicineID: m.id,
          name: m.name,
          packing: m.packing,
          batch: it['batch'],
          exp: it['exp'],
          hsn: it['hsn'],
          mrp: (it['mrp'] as num).toDouble(),
          qty: q,
          freeQty: freeQ,
          rate: sRate,
          gstRate: gstR,
          total: (it['sysTotal'] as num).toDouble(),
          discountRupees: discAmt,
          discountPer: discPer,
        ));

        webPh.registerBatchActivity(
          productKey: m.identityKey,
          batchNo: it['batch'],
          exp: it['exp'],
          packing: m.packing,
          mrp: (it['mrp'] as num).toDouble(),
          rate: sRate,
        );
      }

      final double exDiscSale = (partyInfoInFile['extraDisc'] as num).toDouble();
      final summary = WebBillingGstEngine.calculate(
        items: rawItems,
        extraDiscount: exDiscSale,
        isLocal: isLocal,
      );

      // Map accurate GST tax components per item
      double totalGrossTaxable = rawItems.fold(0.0, (sum, it) => sum + ((it.qty * it.rate) - it.discountRupees));
      double discountRatio = totalGrossTaxable > 0 ? (summary.extraDiscount / totalGrossTaxable) : 0.0;

      List<BillItem> finalizedItems = [];
      for (var it in rawItems) {
        double itemGross = (it.qty * it.rate) - it.discountRupees;
        if (itemGross < 0) itemGross = 0.0;
        double itemNetTaxable = itemGross * (1.0 - discountRatio);
        double itemTax = itemNetTaxable * (it.gstRate / 100.0);
        double cgstVal = isLocal ? (itemTax / 2.0) : 0.0;
        double sgstVal = isLocal ? (itemTax / 2.0) : 0.0;
        double igstVal = isLocal ? 0.0 : itemTax;

        finalizedItems.add(it.copyWith(
          cgst: double.parse(cgstVal.toStringAsFixed(2)),
          sgst: double.parse(sgstVal.toStringAsFixed(2)),
          igst: double.parse(igstVal.toStringAsFixed(2)),
        ));
      }

      final newSale = Sale(
        id: "SALE-CSV-${DateTime.now().millisecondsSinceEpoch}",
        billNo: nextBillNo,
        partyId: matchedParty!.id,
        partyName: matchedParty!.name,
        partyGstin: matchedParty!.gst,
        partyState: matchedParty!.state,
        date: adjustedDate,
        paymentMode: "CREDIT",
        totalAmount: summary.finalGrandTotal,
        extraDiscount: summary.extraDiscount,
        roundOff: summary.roundOff,
        sourceTag: auditTag,
        items: finalizedItems,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        version: 1,
      );

      webPh.unmarkDeletedId(newSale.id, referenceNo: newSale.billNo);
      webPh.addSaleAndSync(newSale);
    }

    setState(() => isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("🎉 39-Col CSV Imported & Synced into ${widget.importType} successfully!"),
          backgroundColor: Colors.green,
        ),
      );
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    if (isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(50), child: CircularProgressIndicator(color: Color(0xFF38BDF8))));
    }

    int unlinkedCount = reviewedItems.where((it) => it['match'] == null).length;
    bool isLocal = (partyInfoInFile['state']?.toString().toLowerCase() ?? '') == (webPh.companyProfile.state.isEmpty ? 'rajasthan' : webPh.companyProfile.state.toLowerCase());

    List<BillItem> selectedTempItems = [];
    int sIndex = 1;
    for (var it in reviewedItems.where((e) => e['isSelected'])) {
      Medicine? m = it['match'];
      selectedTempItems.add(BillItem(
        id: "TMP-$sIndex",
        srNo: sIndex++,
        medicineID: m?.id ?? '',
        name: it['name'],
        packing: it['pack'],
        batch: it['batch'],
        exp: it['exp'],
        hsn: it['hsn'],
        mrp: (it['mrp'] as num).toDouble(),
        qty: (it['qty'] as num).toDouble(),
        freeQty: (it['free'] as num).toDouble(),
        rate: (it['rate'] as num).toDouble(),
        gstRate: (it['gstPer'] as num).toDouble(),
        total: (it['sysTotal'] as num).toDouble(),
        discountRupees: (it['discAmt'] as num).toDouble(),
        discountPer: (it['itemDiscPer'] as num).toDouble(),
      ));
    }

    double extraDisc = (partyInfoInFile['extraDisc'] as num?)?.toDouble() ?? 0.0;
    final gstSummary = WebBillingGstEngine.calculate(
      items: selectedTempItems,
      extraDiscount: extraDisc,
      isLocal: isLocal,
    );

    double csvTotalSum = reviewedItems.where((e) => e['isSelected']).fold(0.0, (s, e) => s + (e['csvTotal'] as double));
    double diff = gstSummary.finalGrandTotal - csvTotalSum;

    bool wasDateAdjusted = partyInfoInFile['isDateAdjusted'] ?? false;
    String rawDateStr = partyInfoInFile['rawCsvDate'] ?? "";
    String adjustedDateStr = DateFormat('dd/MM/yyyy').format(partyInfoInFile['date'] as DateTime);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                    onPressed: widget.onBack,
                    tooltip: "Back",
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "39-COL CSV MIRROR AUDIT • ${widget.exchangeMode} • INVOICE #${partyInfoInFile['billNo']}",
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      Text(
                        "Import Destination: ${widget.importType} REGISTER • Total Items: ${reviewedItems.length}",
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
              if (unlinkedCount > 0)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: Text("AUTO-RESOLVE ($unlinkedCount NEW ITEMS)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  onPressed: () => _autoResolveAllNewProducts(webPh),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Date Watchdog Alert if Adjusted
          if (wasDateAdjusted)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x33F59E0B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orangeAccent),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Date Watchdog: Original CSV date was '$rawDateStr'. Auto-adjusted to '$adjustedDateStr' for Financial Year ${webPh.financialYear} compliance.",
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          // Party Banner Card
          _buildPartyInfoCard(webPh),
          const SizedBox(height: 14),

          // Mirror Review Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: const {
                    0: FixedColumnWidth(40),
                    1: FlexColumnWidth(2.5),
                    2: FixedColumnWidth(80),
                    3: FixedColumnWidth(75),
                    4: FixedColumnWidth(65),
                    5: FixedColumnWidth(75),
                    6: FixedColumnWidth(65),
                    7: FixedColumnWidth(65),
                    8: FixedColumnWidth(90),
                    9: FixedColumnWidth(90),
                    10: FixedColumnWidth(110),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F172A),
                        border: Border(bottom: BorderSide(color: Colors.white24)),
                      ),
                      children: [
                        const Center(child: Icon(Icons.check_box_outline_blank, color: Colors.white54, size: 16)),
                        _th("PRODUCT NAME", isLeft: true),
                        _th("PACKING"),
                        _th("BATCH"),
                        _th("EXP"),
                        _th("QTY"),
                        _th("RATE", isRight: true),
                        _th("GST %", isRight: true),
                        _th("SYS TOTAL", isRight: true),
                        _th("CSV TOTAL", isRight: true),
                        _th("ACTIONS"),
                      ],
                    ),
                    for (int i = 0; i < reviewedItems.length; i++)
                      _buildRow(i, reviewedItems[i], webPh),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Bottom Metric & Action Dock with Section 15 GST Breakdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Wrap(
                  spacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _metric("NET TAXABLE", gstSummary.netTaxable),
                    _metric(isLocal ? "CGST + SGST" : "IGST TAX", gstSummary.totalTax),
                    if (gstSummary.extraDiscount > 0)
                      _metric("EXTRA DISC (-)", gstSummary.extraDiscount, color: Colors.orangeAccent),
                    if (gstSummary.roundOff != 0)
                      _metric("ROUND OFF", gstSummary.roundOff),
                    _metric("SYS GRAND TOTAL", gstSummary.finalGrandTotal, color: const Color(0xFF38BDF8)),
                    _metric("CSV NET", csvTotalSum),
                    _metric("DIFF", diff, color: diff.abs() > 0.1 ? Colors.redAccent : Colors.greenAccent),
                  ],
                ),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isSaving ? null : () => _handleFinalImport(webPh),
                    icon: isSaving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.cloud_done_rounded, size: 18),
                    label: Text(
                      isSaving ? "SYNCING..." : "COMMIT & INWARD TO ${widget.importType}",
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartyInfoCard(PharoahWebManager webPh) {
    bool isMatched = matchedParty != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isMatched ? const Color(0xFF10B981) : Colors.orangeAccent),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: isMatched ? const Color(0x3310B981) : const Color(0x33EA580C), shape: BoxShape.circle),
            child: Icon(isMatched ? Icons.check_circle_rounded : Icons.person_search_rounded, color: isMatched ? Colors.greenAccent : Colors.orangeAccent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(isMatched ? matchedParty!.name : partyInfoInFile['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(color: isMatched ? const Color(0x3310B981) : const Color(0x33EA580C), borderRadius: BorderRadius.circular(4)),
                      child: Text(isMatched ? "VERIFIED PARTY" : "NEW PARTY IN CSV", style: TextStyle(color: isMatched ? Colors.greenAccent : Colors.orangeAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                Text("GST: ${partyInfoInFile['gst']} • Phone: ${partyInfoInFile['phone']} • State: ${partyInfoInFile['state']} • DL: ${partyInfoInFile['dl']}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
          if (!isMatched)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (c) => QuickAddPartyModal(
                    webPh: webPh,
                    preFillData: partyInfoInFile,
                    onPartyCreated: (p) => setState(() => matchedParty = p),
                  ),
                );
              },
              child: const Text("CREATE PARTY", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  TableRow _buildRow(int i, Map<String, dynamic> it, PharoahWebManager webPh) {
    bool hasErr = (it['sysTotal'] - it['csvTotal']).abs() > 0.1 && !it['isFixed'];
    bool isLinked = it['match'] != null;
    String qtyDisp = "${(it['qty'] as num).toInt()}${it['free'] > 0 ? ' + ${(it['free'] as num).toInt()}' : ''}";

    return TableRow(
      decoration: BoxDecoration(
        color: i % 2 == 1 ? const Color(0x0DFFFFFF) : Colors.transparent,
        border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      children: [
        Center(
          child: Checkbox(
            value: it['isSelected'],
            activeColor: const Color(0xFF38BDF8),
            onChanged: isLinked ? (v) => setState(() => it['isSelected'] = v!) : null,
          ),
        ),
        _td(it['name'].toString(), isLeft: true, isBold: true),
        _td(it['pack'].toString()),
        _td(it['batch'].toString()),
        _td(it['exp'].toString()),
        _td(qtyDisp),
        _td("₹${(it['rate'] as num).toStringAsFixed(2)}", isRight: true),
        _td("${(it['gstPer'] as num).toStringAsFixed(0)}%", isRight: true),
        _td("₹${(it['sysTotal'] as num).toStringAsFixed(2)}", isRight: true, isBold: true, color: Colors.greenAccent),
        _td("₹${(it['csvTotal'] as num).toStringAsFixed(2)}", isRight: true),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLinked)
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18)
            else ...[
              IconButton(
                icon: const Icon(Icons.link_rounded, color: Color(0xFF38BDF8), size: 18),
                tooltip: "Link to Master",
                onPressed: () => _showInstantLinkOverlay(i),
              ),
              IconButton(
                icon: const Icon(Icons.add_box_rounded, color: Color(0xFFF59E0B), size: 18),
                tooltip: "Quick Add Product",
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (c) => QuickAddProductModal(
                      webPh: webPh,
                      preFillData: {
                        'name': it['name'],
                        'pack': it['pack'],
                        'hsn': it['hsn'],
                        'gst': it['gstPer'],
                        'mrp': it['mrp'],
                        'purRate': it['purRate'],
                        'rateA': it['rate'],
                        'form': it['form'],
                        'mfg': it['mfg'],
                        'salt': it['salt'],
                      },
                      onProductCreated: (newM) {
                        setState(() {
                          it['match'] = newM;
                          it['status'] = 'exact';
                          it['isSelected'] = true;
                        });
                        _propagateMatchingLinks(newM);
                      },
                    ),
                  );
                },
              ),
            ],
            if (hasErr)
              IconButton(
                icon: const Icon(Icons.build_circle_rounded, color: Colors.orangeAccent, size: 18),
                tooltip: "Override System Total to Match CSV Total",
                onPressed: () {
                  setState(() {
                    it['sysTotal'] = it['csvTotal'];
                    it['isFixed'] = true;
                  });
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _metric(String label, num val, {Color color = Colors.white}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text("₹${val.toStringAsFixed(2)}", style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.bold)),
    ],
  );

  Widget _th(String t, {bool isLeft = false, bool isRight = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
  );
}
