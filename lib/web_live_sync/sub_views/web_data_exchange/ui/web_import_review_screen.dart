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
      double discAmt = gross * (itemDiscPer / 100);
      double taxable = gross - discAmt;
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

    if (widget.importType == "PURCHASE") {
      String internalNo = WebPharoahNumberingEngine.getNextNumber(
        prefix: "PUR-",
        startFrom: 1,
        currentList: webPh.purchases,
      );

      List<PurchaseItem> items = [];
      int sNo = 1;

      for (var it in reviewedItems.where((e) => e['isSelected'])) {
        Medicine m = it['match'];
        double pRate = (it['rate'] as num).toDouble();
        double q = (it['qty'] as num).toDouble();
        double freeQ = (it['free'] as num).toDouble();

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
          gstRate: (it['gstPer'] as num).toDouble(),
          total: (it['sysTotal'] as num).toDouble(),
          discountPer: (it['itemDiscPer'] as num).toDouble(),
          discountRupees: (it['discAmt'] as num).toDouble(),
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

      final newPur = Purchase(
        id: "PUR-CSV-${DateTime.now().millisecondsSinceEpoch}",
        internalNo: internalNo,
        billNo: partyInfoInFile['billNo'],
        partyId: matchedParty!.id,
        distributorName: matchedParty!.name,
        date: adjustedDate,
        entryDate: DateTime.now(),
        paymentMode: "CREDIT",
        totalAmount: items.fold(0.0, (s, e) => s + e.total),
        extraDiscount: (partyInfoInFile['extraDisc'] as num).toDouble(),
        roundOff: (partyInfoInFile['roundOff'] as num).toDouble(),
        sourceTag: auditTag,
        items: items,
      );

      await webPh.addPurchaseAndSync(newPur);
    } else {
      String nextBillNo = partyInfoInFile['billNo'];
      List<BillItem> items = [];
      int sNo = 1;

      for (var it in reviewedItems.where((e) => e['isSelected'])) {
        Medicine m = it['match'];
        double sRate = (it['rate'] as num).toDouble();
        double q = (it['qty'] as num).toDouble();
        double freeQ = (it['free'] as num).toDouble();

        items.add(BillItem(
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
          gstRate: (it['gstPer'] as num).toDouble(),
          total: (it['sysTotal'] as num).toDouble(),
          discountRupees: (it['discAmt'] as num).toDouble(),
          discountPer: (it['itemDiscPer'] as num).toDouble(),
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

      final newSale = Sale(
        id: "SALE-CSV-${DateTime.now().millisecondsSinceEpoch}",
        billNo: nextBillNo,
        partyId: matchedParty!.id,
        partyName: matchedParty!.name,
        partyGstin: matchedParty!.gst,
        partyState: matchedParty!.state,
        date: adjustedDate,
        paymentMode: "CREDIT",
        totalAmount: items.fold(0.0, (s, e) => s + e.total),
        extraDiscount: (partyInfoInFile['extraDisc'] as num).toDouble(),
        roundOff: (partyInfoInFile['roundOff'] as num).toDouble(),
        sourceTag: auditTag,
        items: items,
      );

      await webPh.addSaleAndSync(newSale);
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
    double sysTotalSum = reviewedItems.where((e) => e['isSelected']).fold(0.0, (s, e) => s + (e['sysTotal'] as double));
    double csvTotalSum = reviewedItems.where((e) => e['isSelected']).fold(0.0, (s, e) => s + (e['csvTotal'] as double));
    double diff = sysTotalSum - csvTotalSum;

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
          // Header Bar
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.table_view_rounded, color: Color(0xFF38BDF8), size: 24),
              const SizedBox(width: 8),
              Text(
                "39-COL CSV MIRROR AUDIT • ${widget.exchangeMode} • INVOICE #${partyInfoInFile['billNo']}",
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
              const Spacer(),
              if (unlinkedCount > 0)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white),
                  onPressed: () => _autoResolveAllNewProducts(webPh),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: Text("AUTO-CREATE ($unlinkedCount NEW ITEMS)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Party Card & Date Watchdog Banner
          _buildPartyInfoCard(webPh),

          if (wasDateAdjusted) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x33D97706),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD97706)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Date Watchdog: Original CSV date was '$rawDateStr'. Auto-adjusted to '$adjustedDateStr' for Financial Year ${webPh.financialYear} compliance.",
                      style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Interactive 39-Col Table
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
                    0: FixedColumnWidth(45),
                    1: FlexColumnWidth(3),
                    2: FixedColumnWidth(75),
                    3: FixedColumnWidth(80),
                    4: FixedColumnWidth(60),
                    5: FixedColumnWidth(70),
                    6: FixedColumnWidth(75),
                    7: FixedColumnWidth(55),
                    8: FixedColumnWidth(95),
                    9: FixedColumnWidth(95),
                    10: FixedColumnWidth(90),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFF0F172A), border: Border(bottom: BorderSide(color: Colors.white24))),
                      children: [
                        const Center(child: Icon(Icons.check_box_outline_blank, color: Colors.white54, size: 16)),
                        _th("PRODUCT NAME", isLeft: true),
                        _th("PACK"),
                        _th("BATCH"),
                        _th("EXP"),
                        _th("QTY"),
                        _th("RATE ₹", isRight: true),
                        _th("GST%"),
                        _th("CSV TOTAL", isRight: true),
                        _th("SYS CALC", isRight: true),
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

          // Bottom Analytics Dock
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _metric("SYSTEM TOTAL", sysTotalSum),
                    const SizedBox(width: 18),
                    _metric("CSV TOTAL", csvTotalSum),
                    const SizedBox(width: 18),
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
        _td(qtyDisp, isBold: true),
        _td("₹${(it['rate'] as num).toStringAsFixed(2)}", isRight: true),
        _td("${(it['gstPer'] as num).toInt()}%"),
        _td("₹${(it['csvTotal'] as num).toStringAsFixed(2)}", isRight: true),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                "₹${(it['sysTotal'] as num).toStringAsFixed(2)}",
                style: TextStyle(
                  color: hasErr ? Colors.redAccent : Colors.greenAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
              if (hasErr) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => setState(() {
                    it['isFixed'] = true;
                    it['sysTotal'] = it['csvTotal'];
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
                    child: const Text("FIX", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isLinked) ...[
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
                      },
                      onProductCreated: (newMed) {
                        final m = Medicine.fromMap(newMed);
                        setState(() {
                          it['match'] = m;
                          it['status'] = 'exact';
                          it['isSelected'] = true;
                        });
                        _propagateMatchingLinks(m);
                      },
                    ),
                  );
                },
              ),
            ] else ...[
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
            ],
          ],
        ),
      ],
    );
  }

  Widget _metric(String label, double val, {Color color = Colors.white}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text("₹${val.toStringAsFixed(2)}", style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
    ],
  );

  Widget _th(String t, {bool isLeft = false, bool isRight = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold)),
  );

  Widget _td(String t, {bool isLeft = false, bool isRight = false, bool isBold = false, Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    child: Text(t, textAlign: isLeft ? TextAlign.left : (isRight ? TextAlign.right : TextAlign.center), style: TextStyle(color: color, fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
  );
}
