// FILE: lib/challans/challan_stitcher_wizard.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import '../app_date_logic.dart';
import '../pharoah_date_controller.dart';
import '../logic/pharoah_numbering_engine.dart';
import '../pdf/sale_invoice_pdf.dart';
import '../pdf/purchase_pdf.dart';

import '../billing_view.dart';
import '../purchase/purchase_billing_view.dart';
import '../pdf/pdf_router_service.dart'; // Naya Central Router

class ChallanStitcherWizard extends StatefulWidget {
  const ChallanStitcherWizard({super.key});

  static bool evaluateEligibility({
    required DateTime date,
    required String effectiveOriginalFy,
    required String currentFy,
    required String selectionMode,
    required bool includeCarryForward,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final bool isCarry = isStrictCarryForwardFy(effectiveOriginalFy, currentFy);
    if (selectionMode == "CARRY_ONLY") return isCarry;
    if (isCarry) return includeCarryForward;
    final DateTime dOnly = DateTime(date.year, date.month, date.day);
    final DateTime sOnly = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final DateTime eOnly = DateTime(toDate.year, toDate.month, toDate.day);
    return !dOnly.isBefore(sOnly) && !dOnly.isAfter(eOnly);
  }

  static bool partyMatchesChallan({
    required String partyId,
    required String partyName,
    required String challanPartyId,
    required String challanPartyName,
  }) {
    final String cPid = challanPartyId.trim();
    final String pId = partyId.trim();
    if (cPid.isNotEmpty && pId.isNotEmpty && cPid == pId) return true;
    final String cName = challanPartyName.trim().toUpperCase();
    final String pName = partyName.trim().toUpperCase();
    return cName.isNotEmpty && pName.isNotEmpty && cName == pName;
  }

  @override
  State<ChallanStitcherWizard> createState() => _ChallanStitcherWizardState();
}

class _ChallanStitcherWizardState extends State<ChallanStitcherWizard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  String funnelStep = "MODE";
  String selectionMode = "NONE";
  bool includeCarryForward = false;
  bool isProcessing = false;
  double progressValue = 0.0;
  String progressText = "";

  DateTime batchBillDate = DateTime.now();
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  bool _didInitFyDates = false;
  String? selectedRoute;
  List<String> selectedPartyNames = [];
  Map<String, List<String>> selectedChallanIdsByParty = {};
  List<Map<String, dynamic>> draftBills = [];
  String partySearch = "";

  final List<String> fyMonths = ["April", "May", "June", "July", "August", "September", "October", "November", "December", "January", "February", "March"];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() { if(_tabController.indexIsChanging) _resetWizard(); });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInitFyDates) {
      _didInitFyDates = true;
      final ph = Provider.of<PharoahManager>(context, listen: false);
      final DateTime smart = AppDateLogic.getSmartDate(ph.currentFY);
      batchBillDate = smart;
      fromDate = smart;
      toDate = smart;
    }
  }

  void _resetWizard() {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final DateTime smart = AppDateLogic.getSmartDate(ph.currentFY);
    setState(() {
      funnelStep = "MODE";
      selectedRoute = null;
      selectedPartyNames.clear();
      selectedChallanIdsByParty.clear();
      draftBills.clear();
      selectionMode = "NONE";
      includeCarryForward = false;
      partySearch = "";
      batchBillDate = smart;
      fromDate = smart;
      toDate = smart;
    });
  }

  // ===========================================================================
  // ⚡ LOGIC: BATCH SAVE
  // ===========================================================================
  
  Future<void> _handleBatchSave(PharoahManager ph) async {
    var selected = draftBills.where((b) => b['isSelected'] && b['status'] == 'DRAFT' && (b['challanIds'] as List).isNotEmpty && (b['items'] as List).isNotEmpty).toList();
    if (selected.isEmpty) return;

    setState(() { isProcessing = true; progressText = "Finalizing Batch..."; progressValue = 0.1; });

    bool isSale = _tabController.index == 0;
    if (isSale) {
      List<Sale> batchToSave = [];
      var series = ph.getDefaultSeries("SALE");
      String startNoStr = await PharoahNumberingEngine.getNextNumber(type: "SALE", companyID: ph.activeCompany!.id, prefix: series.prefix, startFrom: series.startNumber, currentList: ph.sales);
      int nextNum = int.parse(startNoStr.replaceAll(series.prefix, ""));

      // Line 80 ke aas-paas _handleBatchSave ke andar

      for (var b in selected) {
        String finalBillNo = "${series.prefix}$nextNum";
        final Party pRef = b['party'] as Party; // Renamed to pRef to avoid conflict
        final DateTime safeDate = AppDateLogic.ensureDateInActiveFy(b['date'] as DateTime, ph.currentFY);
        b['date'] = safeDate;

        batchToSave.add(Sale(
          id: DateTime.now().millisecondsSinceEpoch.toString() + finalBillNo,
          billNo: finalBillNo,
          partyId: pRef.id, 
          date: safeDate,
          partyName: pRef.name,
          partyGstin: pRef.gst,
          partyState: pRef.state,
          partyAddress: pRef.address,
          partyCity: pRef.city,
          partyPhone: pRef.phone,
          partyEmail: pRef.email,
          partyDl: pRef.dl,
          items: b['items'].cast<BillItem>(),
          totalAmount: b['total'],
          paymentMode: "CREDIT",
          linkedChallanIds: List<String>.from(b['challanIds'])
        ));
        nextNum++;
      }
      await ph.finalizeBatchSales(batchToSave);
      _updateLocalStatus(batchToSave, true);
    } else {
      List<Purchase> purBatch = [];
      
      // ✅ FIX: Loop se pehle sirf EK baar engine se agla number mango
      String startPNoStr = await PharoahNumberingEngine.getNextNumber(
          type: "PURCHASE",
          companyID: ph.activeCompany!.id,
          prefix: "PUR-",
          startFrom: 1,
          currentList: ph.purchases);

      // ✅ Number nikaalo (e.g., "PUR-11" se sirf 11 lo)
      int nextPurNum = int.parse(startPNoStr.replaceAll("PUR-", ""));

      for (var b in selected) {
        // ✅ Har party ke liye naya sequential number banao
        String finalPurNo = "PUR-$nextPurNum";
        final DateTime safeDate = AppDateLogic.ensureDateInActiveFy(b['date'] as DateTime, ph.currentFY);
        b['date'] = safeDate;

        purBatch.add(Purchase(
            id: DateTime.now().millisecondsSinceEpoch.toString() + finalPurNo,
            internalNo: finalPurNo,
            billNo: "CH-CONV-$nextPurNum", 
            partyId: b['party'].id, // Link Added
            date: safeDate,
            entryDate: DateTime.now(),
            distributorName: b['party'].name,
            items: b['items'].cast<PurchaseItem>(),
            totalAmount: b['total'],
            paymentMode: "CREDIT",
            linkedChallanIds: List<String>.from(b['challanIds'])));

        // ✅ IMPORTANT: Agli party ke liye number ko ek badha do
        nextPurNum++;
      }
      
      await ph.finalizeBatchPurchases(purBatch);
      _updateLocalStatus(purBatch, false);
    }

    setState(() { isProcessing = false; });
  }

  void _updateLocalStatus(List<dynamic> savedBatch, bool isSale) {
    setState(() {
      for (var b in draftBills) {
        if (b['isSelected'] && b['status'] == 'DRAFT') {
          b['status'] = 'SAVED';
          try {
            final Party bParty = b['party'] as Party;
            var saved = savedBatch.firstWhere((s) =>
              (s.partyId.toString().trim().isNotEmpty && bParty.id.trim().isNotEmpty && s.partyId.toString().trim() == bParty.id.trim()) ||
              (isSale ? s.partyName : s.distributorName).toString().trim().toUpperCase() == bParty.name.trim().toUpperCase()
            );
            b['billNo'] = isSale ? saved.billNo : saved.internalNo;
          } catch(e) {}
        }
      }
    });
  }

  // ===========================================================================
  // 📁 ZIP EXPORT
  // ===========================================================================
  // ===========================================================================
  // 📁 UNIVERSAL ZIP EXPORT (Via Router)
  // ===========================================================================
  Future<void> _handleZipExport(PharoahManager ph) async {
    var selected = draftBills.where((b) => b['isSelected']).toList();
    if (selected.isEmpty) return;

    // Storage Permissions
    if (Platform.isAndroid) {
      await Permission.storage.request();
      await Permission.manageExternalStorage.request();
    }

    // Agar koi bill abhi bhi DRAFT hai, toh pehle save karo
    if (selected.any((b) => b['status'] == 'DRAFT')) await _handleBatchSave(ph);

    setState(() { isProcessing = true; progressValue = 0.0; progressText = "Preparing Zip..."; });

    try {
      bool isSale = _tabController.index == 0;
      List<Map<String, dynamic>> payload = [];

      for (var d in selected) {
        final obj = isSale 
          ? ph.sales.firstWhere((s) => s.billNo == d['billNo'])
          : ph.purchases.firstWhere((p) => p.internalNo == d['billNo']);
        
        payload.add({
          'saleObj': obj, 
          'party': d['party'], 
          'billNo': d['billNo']
        });
      }

      // 🚀 THE NEW ROUTER CALL: Ek hi line mein poora bulk logic
      String zipPath = await PdfRouterService.createBulkZip(
        selectedDrafts: payload, 
        ph: ph, 
        onProgress: (v, n) => setState(() { 
          progressValue = v; 
          progressText = "Packing: $n"; 
        })
      );

      setState(() => isProcessing = false);

      if (mounted) {
        showDialog(
          context: context, 
          builder: (c) => AlertDialog(
            title: const Text("Batch ZIP Ready!"),
            content: const Text("All bills have been converted to professional landscape PDF and packed in a ZIP file."),
            actions: [
              TextButton(
                onPressed: () { Navigator.pop(c); Share.shareXFiles([XFile(zipPath)]); }, 
                child: const Text("SHARE ZIP")
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(c);
                  try {
                    final bytes = await File(zipPath).readAsBytes();
                    await FileSaver.instance.saveAs(
                      name: "Invoices_Batch_${DateFormat('ddMM_HHmm').format(DateTime.now())}", 
                      bytes: bytes, 
                      ext: "zip", 
                      mimeType: MimeType.zip
                    );
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Save Error: $e")));
                  }
                }, 
                child: const Text("SAVE TO DEVICE")
              ),
            ],
          ),
        );
      }
    } catch (e) { 
      setState(() => isProcessing = false); 
      debugPrint("Zip Error: $e");
    }
  }

  // ===========================================================================
  // 🖥️ UI BUILDER
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    bool isSale = _tabController.index == 0;
    Color color = isSale ? const Color(0xFF0D47A1) : const Color(0xFFBF360C);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: Text(isSale ? "SALE CONVERTER" : "PURCHASE CONVERTER", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0.5,
        bottom: TabBar(controller: _tabController, labelColor: color, indicatorColor: color, tabs: const [Tab(text: "OUTWARD"), Tab(text: "INWARD")]),
      ),
      body: Stack(children: [
        _buildStepRouter(ph, color),
        if (isProcessing) _buildOverlay(color),
      ]),
    );
  }

  Widget _buildStepRouter(PharoahManager ph, Color color) {
    if (funnelStep == "MODE") return _stepMode(ph, color);
    if (funnelStep == "ROUTE") return _stepRoute(ph, color);
    if (funnelStep == "PARTY") return _stepParty(ph, color);
    if (funnelStep == "REVIEW") return _stepReview(ph, color);
    return const SizedBox();
  }

  bool _isCarryForwardChallan(String effectiveOriginalFy, String currentFy) {
    return isStrictCarryForwardFy(effectiveOriginalFy, currentFy);
  }

  Widget _stepMode(PharoahManager ph, Color color) => Center(child: Padding(padding: const EdgeInsets.all(30.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    _modeCard("MONTHLY BATCH", "Select a month from Apr to Mar", Icons.calendar_month, color, () => _showMonthPicker(ph.currentFY)),
    const SizedBox(height: 20),
    _modeCard("RANDOM RANGE", "Custom selection in current FY", Icons.date_range, Colors.blueGrey, () => _pickRandom(ph.currentFY)),
    const SizedBox(height: 20),
    _modeCard("CARRY-FORWARD PENDING", "Stitch previous FY carried-forward pending challans", Icons.history, Colors.deepPurple, () => setState(() {
      selectionMode = "CARRY_ONLY";
      includeCarryForward = true;
      selectedPartyNames.clear();
      selectedChallanIdsByParty.clear();
      funnelStep = "ROUTE";
    })),
  ])));

  Widget _stepRoute(PharoahManager ph, Color color) => Column(children: [
    _header("STEP 2: FILTER BY ROUTE"),
    ListTile(tileColor: Colors.white, leading: const Icon(Icons.done_all, color: Colors.green), title: const Text("SKIP & SHOW ALL ROUTES"), onTap: () => setState(() { selectedRoute = null; funnelStep = "PARTY"; })),
    Expanded(child: ListView.builder(itemCount: ph.routes.length, itemBuilder: (c, i) => ListTile(tileColor: Colors.white, title: Text(ph.routes[i].name, style: const TextStyle(fontWeight: FontWeight.bold)), onTap: () => setState(() { selectedRoute = ph.routes[i].name; funnelStep = "PARTY"; }))))
  ]);

  bool _partyMatchesChallan(Party p, dynamic c, bool isSale) {
    return ChallanStitcherWizard.partyMatchesChallan(
      partyId: p.id,
      partyName: p.name,
      challanPartyId: (c.partyId ?? '').toString(),
      challanPartyName: isSale ? (c as SaleChallan).partyName : (c as PurchaseChallan).distributorName,
    );
  }

  bool _isChallanEligible(dynamic c, PharoahManager ph) {
    if ((c.isDeleted ?? 0) == 1) return false;
    if (c.status != "Pending") return false;
    final String ofy = c is SaleChallan ? c.effectiveOriginalFy : (c as PurchaseChallan).effectiveOriginalFy;
    return ChallanStitcherWizard.evaluateEligibility(
      date: c.date as DateTime,
      effectiveOriginalFy: ofy,
      currentFy: ph.currentFY,
      selectionMode: selectionMode,
      includeCarryForward: includeCarryForward,
      fromDate: fromDate,
      toDate: toDate,
    );
  }

  String _partyPickKey(Party p) {
    final pid = p.id.trim();
    if (pid.isNotEmpty) return "ID:$pid";
    return "NAME:${p.name.trim().toUpperCase()}";
  }

  List<dynamic> _getEligibleChallansForParty(PharoahManager ph, Party party, bool isSale) {
    final List<dynamic> list = isSale
        ? ph.saleChallans.where((ch) => _partyMatchesChallan(party, ch, true) && _isChallanEligible(ch, ph)).toList()
        : ph.purchaseChallans.where((ch) => _partyMatchesChallan(party, ch, false) && _isChallanEligible(ch, ph)).toList();
    list.sort((a, b) {
      final int cmp = (a.date as DateTime).compareTo(b.date as DateTime);
      if (cmp != 0) return cmp;
      final String aNo = isSale ? (a as SaleChallan).billNo : (a as PurchaseChallan).internalNo;
      final String bNo = isSale ? (b as SaleChallan).billNo : (b as PurchaseChallan).internalNo;
      return aNo.compareTo(bNo);
    });
    return list;
  }

  List<String> _getSelectedChallanIdsForParty(Party party, List<dynamic> eligibleChallans, bool isSale) {
    final key = _partyPickKey(party);
    final eligibleIds = eligibleChallans.map((c) => isSale ? (c as SaleChallan).id : (c as PurchaseChallan).id).toList();
    if (!selectedChallanIdsByParty.containsKey(key)) {
      return eligibleIds;
    }
    final pickedSet = selectedChallanIdsByParty[key]!.toSet();
    return eligibleIds.where((id) => pickedSet.contains(id)).toList();
  }

  Map<String, dynamic> _buildDraftPayload(
    Party pObj,
    List<dynamic> pickedChallans,
    bool isSale,
    String currentFy,
    DateTime draftDate, {
    String status = 'DRAFT',
    String billNo = 'DRAFT',
    bool isSelected = true,
  }) {
    final List<dynamic> items = [];
    for (var c in pickedChallans) {
      if (isSale) {
        final SaleChallan act = c as SaleChallan;
        for (var it in act.items) {
          items.add(it.copyWith(sourceChallanNo: act.billNo, sourceChallanId: act.id));
        }
      } else {
        final PurchaseChallan act = c as PurchaseChallan;
        for (var it in act.items) {
          items.add(it.copyWith(sourceChallanNo: act.billNo, sourceChallanId: act.id));
        }
      }
    }
    final int cfCount = pickedChallans.where((c) {
      final String ofy = isSale ? (c as SaleChallan).effectiveOriginalFy : (c as PurchaseChallan).effectiveOriginalFy;
      return _isCarryForwardChallan(ofy, currentFy);
    }).length;
    return {
      'party': pObj,
      'billNo': billNo,
      'date': draftDate,
      'items': items,
      'total': items.fold(0.0, (s, i) => s + (i.total as double)),
      'status': status,
      'isSelected': isSelected,
      'cfCount': cfCount,
      'challanIds': pickedChallans.map((c) => isSale ? (c as SaleChallan).id : (c as PurchaseChallan).id).toList(),
    };
  }

  Future<void> _openChallanPickerDialog(PharoahManager ph, Party party, bool isSale, {int? draftIndex}) async {
    final eligible = _getEligibleChallansForParty(ph, party, isSale);
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No eligible pending challans for ${party.name}.")),
      );
      return;
    }
    final key = _partyPickKey(party);
    Set<String> tempSelected;
    if (draftIndex != null && draftIndex >= 0 && draftIndex < draftBills.length) {
      tempSelected = List<String>.from(draftBills[draftIndex]['challanIds'] ?? const []).toSet();
    } else {
      tempSelected = _getSelectedChallanIdsForParty(party, eligible, isSale).toSet();
    }

    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          double selTotal = 0.0;
          for (final ch in eligible) {
            final String chId = isSale ? (ch as SaleChallan).id : (ch as PurchaseChallan).id;
            if (tempSelected.contains(chId)) {
              selTotal += isSale ? (ch as SaleChallan).totalAmount : (ch as PurchaseChallan).totalAmount;
            }
          }
          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Select Challans • ${party.name}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  "Selected: ${tempSelected.length} of ${eligible.length} • ₹${selTotal.toStringAsFixed(2)}",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade700),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: Column(
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OutlinedButton(
                        onPressed: () => setDialogState(() {
                          tempSelected = eligible.map((c) => isSale ? (c as SaleChallan).id : (c as PurchaseChallan).id).toSet();
                        }),
                        child: const Text("All", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      OutlinedButton(
                        onPressed: () => setDialogState(() => tempSelected.clear()),
                        child: const Text("None", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
                      ),
                      OutlinedButton(
                        onPressed: () => setDialogState(() {
                          tempSelected = eligible.where((c) {
                            final String ofy = isSale ? (c as SaleChallan).effectiveOriginalFy : (c as PurchaseChallan).effectiveOriginalFy;
                            return !_isCarryForwardChallan(ofy, ph.currentFY);
                          }).map((c) => isSale ? (c as SaleChallan).id : (c as PurchaseChallan).id).toSet();
                        }),
                        child: const Text("Only Current", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal)),
                      ),
                      OutlinedButton(
                        onPressed: () => setDialogState(() {
                          tempSelected = eligible.where((c) {
                            final String ofy = isSale ? (c as SaleChallan).effectiveOriginalFy : (c as PurchaseChallan).effectiveOriginalFy;
                            return _isCarryForwardChallan(ofy, ph.currentFY);
                          }).map((c) => isSale ? (c as SaleChallan).id : (c as PurchaseChallan).id).toSet();
                        }),
                        child: const Text("Only Carry-Fwd", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: eligible.length,
                      itemBuilder: (_, idx) {
                        final ch = eligible[idx];
                        String chId;
                        String chNo;
                        DateTime chDate;
                        double chAmt;
                        String chOfy;
                        int itemCount;
                        if (isSale) {
                          final sc = ch as SaleChallan;
                          chId = sc.id;
                          chNo = sc.billNo;
                          chDate = sc.date;
                          chAmt = sc.totalAmount;
                          chOfy = sc.effectiveOriginalFy;
                          itemCount = sc.items.length;
                        } else {
                          final pc = ch as PurchaseChallan;
                          chId = pc.id;
                          chNo = pc.billNo.isNotEmpty ? "${pc.internalNo} (${pc.billNo})" : pc.internalNo;
                          chDate = pc.date;
                          chAmt = pc.totalAmount;
                          chOfy = pc.effectiveOriginalFy;
                          itemCount = pc.items.length;
                        }
                        final bool isCf = _isCarryForwardChallan(chOfy, ph.currentFY);
                        return CheckboxListTile(
                          dense: true,
                          activeColor: isCf ? Colors.deepPurple : Colors.teal,
                          value: tempSelected.contains(chId),
                          title: Row(
                            children: [
                              Flexible(child: Text(chNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: isCf ? Colors.deepPurple.withOpacity(0.12) : Colors.teal.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isCf ? "CF • ${chOfy.isNotEmpty ? chOfy : 'PREV'}" : "CURRENT",
                                  style: TextStyle(
                                    color: isCf ? Colors.deepPurple : Colors.teal.shade700,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            "${DateFormat('dd/MM/yyyy').format(chDate)} • $itemCount Items • ₹${chAmt.toStringAsFixed(2)}",
                            style: const TextStyle(fontSize: 11),
                          ),
                          onChanged: (v) => setDialogState(() {
                            if (v == true) {
                              tempSelected.add(chId);
                            } else {
                              tempSelected.remove(chId);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, tempSelected.toList()),
                child: Text("APPLY (${tempSelected.length})"),
              ),
            ],
          );
        },
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      selectedChallanIdsByParty[key] = result;
      if (draftIndex == null) {
        if (result.isNotEmpty && !selectedPartyNames.contains(party.name)) {
          selectedPartyNames.add(party.name);
        } else if (result.isEmpty) {
          selectedPartyNames.remove(party.name);
        }
      } else if (draftIndex >= 0 && draftIndex < draftBills.length) {
        final resultSet = result.toSet();
        final pickedChs = eligible.where((c) => resultSet.contains(isSale ? (c as SaleChallan).id : (c as PurchaseChallan).id)).toList();
        final oldDraft = draftBills[draftIndex];
        draftBills[draftIndex] = _buildDraftPayload(
          party,
          pickedChs,
          isSale,
          ph.currentFY,
          oldDraft['date'] as DateTime,
          status: oldDraft['status'] ?? 'DRAFT',
          billNo: oldDraft['billNo'] ?? 'DRAFT',
          isSelected: pickedChs.isNotEmpty ? (oldDraft['isSelected'] ?? true) : false,
        );
      }
    });
  }

  Widget _stepParty(PharoahManager ph, Color color) {
    bool isSale = _tabController.index == 0;
    final list = ph.parties.where((p) {
      bool hasPend = isSale
          ? ph.saleChallans.any((c) => _partyMatchesChallan(p, c, true) && _isChallanEligible(c, ph))
          : ph.purchaseChallans.any((c) => _partyMatchesChallan(p, c, false) && _isChallanEligible(c, ph));
      return hasPend && (selectedRoute == null || p.route == selectedRoute) && p.name.toLowerCase().contains(partySearch.toLowerCase());
    }).toList();
    return Column(children: [
      _header("STEP 3: SELECT PARTIES"),
      Container(padding: const EdgeInsets.all(12), color: Colors.white, child: Row(children: [
        Expanded(child: TextField(decoration: const InputDecoration(hintText: "Search Party..."), onChanged: (v)=>setState(()=>partySearch=v))),
        TextButton(onPressed: () => setState(() => selectedPartyNames = list.map((e)=>e.name).toList()), child: const Text("SELECT ALL")),
      ])),
      if (selectionMode != "CARRY_ONLY")
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: CheckboxListTile(
            dense: true,
            activeColor: Colors.deepPurple,
            contentPadding: EdgeInsets.zero,
            value: includeCarryForward,
            title: const Text(
              "Include Prior-FY Carry-Forward Pending Challans",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurple),
            ),
            onChanged: (v) => setState(() {
              includeCarryForward = v ?? false;
              selectedChallanIdsByParty.clear();
            }),
          ),
        ),
      Expanded(child: ListView.builder(itemCount: list.length, itemBuilder: (c, i) {
        final party = list[i];
        final pChs = _getEligibleChallansForParty(ph, party, isSale);
        final pickedIds = _getSelectedChallanIdsForParty(party, pChs, isSale);
        final cfCount = pChs.where((ch) {
          final String ofy = isSale ? (ch as SaleChallan).effectiveOriginalFy : (ch as PurchaseChallan).effectiveOriginalFy;
          return _isCarryForwardChallan(ofy, ph.currentFY);
        }).length;
        return CheckboxListTile(
          activeColor: color,
          controlAffinity: ListTileControlAffinity.leading,
          value: selectedPartyNames.contains(party.name),
          title: Text(party.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            cfCount > 0
                ? "${pickedIds.length}/${pChs.length} Selected ($cfCount Carry-Fwd)"
                : "${pickedIds.length}/${pChs.length} Pending",
            style: TextStyle(fontSize: 11, color: cfCount > 0 ? Colors.deepPurple : Colors.grey),
          ),
          secondary: OutlinedButton(
            onPressed: () => _openChallanPickerDialog(ph, party, isSale),
            child: Text("CHALLANS (${pickedIds.length}/${pChs.length})", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          onChanged: (v) => setState(() { v! ? selectedPartyNames.add(party.name) : selectedPartyNames.remove(party.name); }),
        );
      })),
      if(selectedPartyNames.isNotEmpty) Container(padding: const EdgeInsets.all(20), child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color, minimumSize: const Size(double.infinity, 50)), onPressed: () => _generateDrafts(ph), child: const Text("CONVERT SELECTED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
    ]);
  }

  Widget _stepReview(PharoahManager ph, Color color) {
    bool allSel = draftBills.isNotEmpty && draftBills.every((b) => b['isSelected']);
    return Column(children: [
      Container(padding: const EdgeInsets.all(10), color: color.withOpacity(0.05), child: InkWell(onTap: () async {
        DateTime? p = await PharoahDateController.pickDate(context: context, currentFY: ph.currentFY, initialDate: batchBillDate);
        if (p != null) setState(() { batchBillDate = p; for (var b in draftBills) { if (b['status'] == 'DRAFT') b['date'] = p; } });
      }, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.calendar_today, size: 14), const SizedBox(width: 8), Text("BILLING DATE FOR ALL: ${DateFormat('dd/MM/yyyy').format(batchBillDate)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), const Icon(Icons.edit, size: 14)]))),
      Container(padding: const EdgeInsets.all(12), color: Colors.white, child: Row(children: [
        Checkbox(value: allSel, onChanged: (v) => setState(() { for(var b in draftBills) { if(b['status']=='DRAFT') b['isSelected'] = v; } })),
        const Text("SEL ALL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
        const Spacer(),
        _bulkBtn("SAVE ALL", Icons.save, Colors.blue.shade700, () => _handleBatchSave(ph)),
        const SizedBox(width: 8),
        _bulkBtn("ZIP PDF", Icons.folder_zip, Colors.green.shade700, () => _handleZipExport(ph)),
      ])),
      Expanded(child: ListView.builder(itemCount: draftBills.length, padding: const EdgeInsets.all(12), itemBuilder: (c, i) {
        final b = draftBills[i]; bool isSaved = b['status'] == 'SAVED';
        final bool isSale = _tabController.index == 0;
        final Party pRef = b['party'] as Party;
        final int eligibleCount = isSaved ? (b['challanIds'] as List).length : _getEligibleChallansForParty(ph, pRef, isSale).length;
        final int pickedCount = (b['challanIds'] as List).length;
        return Container(margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: isSaved ? Colors.green : Colors.grey.shade300, width: 1.5)), child: Column(children: [
          ListTile(leading: Checkbox(value: b['isSelected'], onChanged: isSaved ? null : (v) => setState(() => b['isSelected'] = v)), title: Text(b['party'].name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)), subtitle: Text("${isSaved ? b['billNo'] : 'DRAFT'} | $pickedCount Challans | ${DateFormat('dd/MM/yy').format(b['date'])} | ₹${b['total'].toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)), trailing: Icon(isSaved ? Icons.check_circle : Icons.pending, color: isSaved ? Colors.green : Colors.orange)),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Wrap(alignment: WrapAlignment.spaceAround, spacing: 12, runSpacing: 6, children: [
            if (!isSaved) _iconAct(Icons.checklist, "CHALLANS ($pickedCount/$eligibleCount)", Colors.deepPurple, () => _openChallanPickerDialog(ph, pRef, isSale, draftIndex: i)),
            _iconAct(Icons.remove_red_eye, "VIEW", Colors.blue, () => _viewDraft(b)),
            _iconAct(Icons.edit_note, "EDIT", Colors.orange.shade800, () => _editDraft(b, i)),
            _iconAct(isSaved ? Icons.verified : Icons.save, "SAVE", isSaved ? Colors.green : Colors.grey, () => _saveSingle(ph, i)),
            _iconAct(Icons.print, "PDF", Colors.teal, () => _printSingle(ph, i)),
            _iconAct(Icons.delete_outline, "DEL", Colors.red, () => setState(() => draftBills.removeAt(i))),
          ]))
        ]));
      }))
    ]);
  }

  void _generateDrafts(PharoahManager ph) {
    setState(() => isProcessing = true);
    List<Map<String, dynamic>> temp = []; bool isSale = _tabController.index == 0;
    final DateTime alignedDate = AppDateLogic.ensureDateInActiveFy(batchBillDate, ph.currentFY);
    batchBillDate = alignedDate;
    for (var pName in selectedPartyNames) {
      final Party? pObj = ph.parties.cast<Party?>().firstWhere(
        (p) => p != null && p.name.trim().toUpperCase() == pName.trim().toUpperCase(),
        orElse: () => null,
      );
      if (pObj == null) continue;
      final eligibleChs = _getEligibleChallansForParty(ph, pObj, isSale);
      final selectedIds = _getSelectedChallanIdsForParty(pObj, eligibleChs, isSale).toSet();
      final chs = eligibleChs.where((c) => selectedIds.contains(isSale ? (c as SaleChallan).id : (c as PurchaseChallan).id)).toList();
      if (chs.isEmpty) continue;
      temp.add(_buildDraftPayload(pObj, chs, isSale, ph.currentFY, batchBillDate));
    }
    setState(() {
      draftBills = temp;
      funnelStep = temp.isEmpty ? "PARTY" : "REVIEW";
      isProcessing = false;
    });
    if (temp.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least 1 challan for selected parties!"), backgroundColor: Colors.orange),
      );
    }
  }

  Future<void> _saveSingle(PharoahManager ph, int i) async {
    var b = draftBills[i];
    if ((b['challanIds'] as List).isEmpty || (b['items'] as List).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Select at least 1 challan for ${b['party'].name} before saving!"), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => isProcessing = true);
    bool isSale = _tabController.index == 0; 
    String finalNo;
    final DateTime safeDate = AppDateLogic.ensureDateInActiveFy(b['date'] as DateTime, ph.currentFY);
    b['date'] = safeDate;

    if(isSale) {
      var ser = ph.getDefaultSeries("SALE");
      finalNo = await PharoahNumberingEngine.getNextNumber(type: "SALE", companyID: ph.activeCompany!.id, prefix: ser.prefix, startFrom: ser.startNumber, currentList: ph.sales);
      await ph.finalizeSale(billNo: finalNo, date: safeDate, party: b['party'], items: b['items'].cast<BillItem>(), total: b['total'], mode: "CREDIT", linkedIds: List<String>.from(b['challanIds']));
    } else {
      finalNo = await PharoahNumberingEngine.getNextNumber(type: "PURCHASE", companyID: ph.activeCompany!.id, prefix: "PUR-", startFrom: 1, currentList: ph.purchases);
      final String purBillNo = "CH-CONV-${finalNo.replaceAll("PUR-", "")}";
      final bool savedOk = await ph.finalizePurchase(
        internalNo: finalNo, 
        billNo: purBillNo, 
        date: safeDate, 
        entryDate: DateTime.now(), 
        party: b['party'], 
        items: b['items'].cast<PurchaseItem>(), 
        total: b['total'], 
        mode: "CREDIT",
        linkedChallanIds: List<String>.from(b['challanIds'])
      );
      if (!savedOk) {
        if (mounted) {
          setState(() => isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Could not save Purchase ($purBillNo): Duplicate supplier bill already exists!"), backgroundColor: Colors.red),
          );
        }
        return;
      }
    }
    if (mounted) {
      setState(() { draftBills[i]['status'] = 'SAVED'; draftBills[i]['billNo'] = finalNo; isProcessing = false; });
    }
  }

  void _printSingle(PharoahManager ph, int i) async {
    if(draftBills[i]['status'] == 'DRAFT') await _saveSingle(ph, i);
    if (draftBills[i]['status'] != 'SAVED') return;
    var b = draftBills[i];
    if(_tabController.index == 0) {
      final s = ph.sales.cast<Sale?>().firstWhere((s) => s != null && s.billNo == b['billNo'], orElse: () => null);
      if (s != null) await SaleInvoicePdf.generate(s, b['party'], ph.activeCompany!);
    } else {
      final p = ph.purchases.cast<Purchase?>().firstWhere((p) => p != null && p.internalNo == b['billNo'], orElse: () => null);
      if (p != null) await PurchasePdf.generate(p, b['party'], ph.activeCompany!);
    }
  }

  void _editDraft(Map<String, dynamic> b, int i) async {
    bool isSale = _tabController.index == 0;
    if (isSale) await Navigator.push(context, MaterialPageRoute(builder: (c) => BillingView(party: b['party'], billNo: "DRAFT", billDate: b['date'], mode: "CREDIT", existingItems: b['items'].cast<BillItem>(), linkedChallanIds: List<String>.from(b['challanIds']))));
    else await Navigator.push(context, MaterialPageRoute(builder: (c) => PurchaseBillingView(distributor: b['party'], internalNo: "DRAFT", distBillNo: "", billDate: b['date'], entryDate: DateTime.now(), mode: "CREDIT", existingItems: b['items'].cast<PurchaseItem>(), linkedChallanIds: List<String>.from(b['challanIds']))));
    if (!mounted) return;
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final List<String> cIds = List<String>.from(b['challanIds'] ?? const []);
    bool actuallySaved = false;
    String resolvedNo = "";
    if (cIds.isNotEmpty) {
      if (isSale) {
        final matched = ph.saleChallans.where((c) => cIds.contains(c.id)).toList();
        if (matched.isNotEmpty && matched.every((c) => c.status == "Billed")) {
          actuallySaved = true;
          resolvedNo = matched.first.billedInvoiceNo;
        }
      } else {
        final matched = ph.purchaseChallans.where((c) => cIds.contains(c.id)).toList();
        if (matched.isNotEmpty && matched.every((c) => c.status == "Billed")) {
          actuallySaved = true;
          resolvedNo = matched.first.billedInvoiceNo;
        }
      }
    }
    if (actuallySaved) {
      setState(() {
        draftBills[i]['status'] = 'SAVED';
        draftBills[i]['billNo'] = resolvedNo.isNotEmpty ? resolvedNo : "MANUAL-DONE";
      });
    }
  }

  void _viewDraft(Map<String, dynamic> b) {
    if (_tabController.index == 0) Navigator.push(context, MaterialPageRoute(builder: (c) => BillingView(party: b['party'], billNo: "DRAFT", billDate: b['date'], mode: "CREDIT", existingItems: b['items'].cast<BillItem>(), isReadOnly: true)));
    else Navigator.push(context, MaterialPageRoute(builder: (c) => PurchaseBillingView(distributor: b['party'], internalNo: "DRAFT", distBillNo: "", billDate: b['date'], entryDate: DateTime.now(), mode: "CREDIT", existingItems: b['items'].cast<PurchaseItem>(), isReadOnly: true)));
  }

  void _showMonthPicker(String fy) {
    showModalBottomSheet(context: context, builder: (c) => ListView(children: fyMonths.map((m) => ListTile(title: Text(m), onTap: () { Navigator.pop(c); _setDt(m, fy); })).toList()));
  }

  void _setDt(String m, String fy) {
    int yr = int.parse(fy.split('-')[0]); if(yr < 2000) yr+=2000;
    int idx = fyMonths.indexOf(m); int tM = idx+4; if(tM>12) { tM-=12; yr++; }
    setState(() {
      fromDate = DateTime(yr, tM, 1);
      toDate = DateTime(yr, tM+1, 0);
      funnelStep = "ROUTE";
      selectionMode = "MONTHLY";
      includeCarryForward = false;
      selectedPartyNames.clear();
      selectedChallanIdsByParty.clear();
    });
  }

  void _pickRandom(String fy) async {
    DateTime? s = await PharoahDateController.pickDate(context: context, currentFY: fy, initialDate: AppDateLogic.getSmartDate(fy));
    if(s!=null) { DateTime? e = await PharoahDateController.pickDate(context: context, currentFY: fy, initialDate: s);
      if(e!=null) setState(() {
        fromDate = s;
        toDate = e;
        funnelStep = "ROUTE";
        selectionMode = "RANDOM";
        includeCarryForward = false;
        selectedPartyNames.clear();
        selectedChallanIdsByParty.clear();
      });
    }
  }

  Widget _modeCard(String t, String s, IconData i, Color c, VoidCallback onTap) => InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(25), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withOpacity(0.1), width: 2)), child: Row(children: [Icon(i, size: 40, color: c), const SizedBox(width: 20), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c)), Text(s, style: const TextStyle(fontSize: 12, color: Colors.grey))])), const Icon(Icons.arrow_forward_ios, size: 16)])));
  Widget _header(String t) => Container(width: double.infinity, padding: const EdgeInsets.all(12), color: Colors.grey.shade200, child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)));
  Widget _iconAct(IconData i, String l, Color c, VoidCallback onTap) => InkWell(onTap: onTap, child: Column(children: [Icon(i, color: c, size: 22), Text(l, style: TextStyle(fontSize: 8, color: c, fontWeight: FontWeight.bold))]));
  Widget _bulkBtn(String l, IconData i, Color c, VoidCallback onTap) => ElevatedButton.icon(onPressed: onTap, icon: Icon(i, size: 14), label: Text(l, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white));
  Widget _buildOverlay(Color c) => Container(color: Colors.black87, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(value: progressValue > 0 ? progressValue : null, color: c), const SizedBox(height: 20), Text(progressText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))])));
}
