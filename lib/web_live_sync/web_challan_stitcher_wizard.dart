// FILE: lib/web_live_sync/web_challan_stitcher_wizard.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:archive/archive.dart';
import 'package:file_saver/file_saver.dart';

import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'web_pharoah_numbering_engine.dart';
import 'web_pdf_router_service.dart';
import 'sub_views/web_billing/web_new_sale_view.dart';
import 'web_purchase_entry_view.dart';

class WebChallanStitcherWizard extends StatefulWidget {
  final VoidCallback onBack;

  const WebChallanStitcherWizard({super.key, required this.onBack});

  @override
  State<WebChallanStitcherWizard> createState() => _WebChallanStitcherWizardState();
}

class _WebChallanStitcherWizardState extends State<WebChallanStitcherWizard> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String funnelStep = "MODE"; // MODE -> ROUTE -> PARTY -> REVIEW
  String selectionMode = "NONE";
  bool isProcessing = false;
  double progressValue = 0.0;
  String progressText = "";

  DateTime batchBillDate = DateTime.now();
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  String? selectedRoute;
  List<String> selectedPartyNames = [];
  List<Map<String, dynamic>> draftBills = [];
  String partySearch = "";

  final List<String> fyMonths = [
    "April", "May", "June", "July", "August", "September",
    "October", "November", "December", "January", "February", "March"
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) _resetWizard();
    });

    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    batchBillDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
    fromDate = WebAppDateLogic.getFYStart(webPh.financialYear);
    toDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
  }

  void _resetWizard() {
    setState(() {
      funnelStep = "MODE";
      selectedRoute = null;
      selectedPartyNames.clear();
      draftBills.clear();
      selectionMode = "NONE";
      partySearch = "";
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isInDateRange(DateTime dt) {
    DateTime d = DateTime(dt.year, dt.month, dt.day);
    DateTime start = DateTime(fromDate.year, fromDate.month, fromDate.day);
    DateTime end = DateTime(toDate.year, toDate.month, toDate.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  // ===========================================================================
  // ⚡ DRAFT GENERATOR
  // ===========================================================================
  void _generateDrafts(PharoahWebManager webPh) async {
    setState(() {
      isProcessing = true;
      progressValue = 0.0;
      progressText = "Stitching Challans...";
    });

    List<Map<String, dynamic>> temp = [];
    bool isSale = _tabController.index == 0;

    for (int k = 0; k < selectedPartyNames.length; k++) {
      var pName = selectedPartyNames[k];

      setState(() {
        progressValue = (k + 1) / selectedPartyNames.length;
        progressText = "Analyzing Challans for $pName...";
      });
      await Future.delayed(const Duration(milliseconds: 10)); // Breathe

      Party? pObj;
      try {
        pObj = webPh.parties.firstWhere((p) => p.name.trim().toUpperCase() == pName.trim().toUpperCase());
      } catch (_) {
        pObj = Party(id: 'temp', name: pName);
      }

      var chs = isSale
          ? webPh.saleChallans.where((c) =>
              c.partyName.trim().toUpperCase() == pName.trim().toUpperCase() &&
              c.status == "Pending" &&
              _isInDateRange(c.date)).toList()
          : webPh.purchaseChallans.where((c) =>
              c.distributorName.trim().toUpperCase() == pName.trim().toUpperCase() &&
              c.status == "Pending" &&
              _isInDateRange(c.date)).toList();

      if (chs.isEmpty) continue;

      List<dynamic> combinedItems = [];
      for (var c in chs) {
        if (isSale) {
          SaleChallan act = c as SaleChallan;
          for (var it in act.items) {
            combinedItems.add(it.copyWith(sourceChallanNo: act.billNo, sourceChallanId: act.id));
          }
        } else {
          PurchaseChallan act = c as PurchaseChallan;
          for (var it in act.items) {
            combinedItems.add(it.copyWith(sourceChallanNo: act.billNo, sourceChallanId: act.id));
          }
        }
      }

      double total = combinedItems.fold(0.0, (s, i) => s + (i.total as double));

      temp.add({
        'party': pObj,
        'billNo': 'DRAFT',
        'date': batchBillDate,
        'items': combinedItems,
        'total': total,
        'status': 'DRAFT',
        'isSelected': true,
        'challanIds': chs.map((c) => isSale ? (c as SaleChallan).id : (c as PurchaseChallan).id).toList(),
      });
    }

    setState(() {
      draftBills = temp;
      funnelStep = "REVIEW";
      isProcessing = false;
    });
  }

  // ===========================================================================
  // 💾 SAVE SINGLE DRAFT BILL
  // ===========================================================================
  Future<void> _saveSingle(PharoahWebManager webPh, int i) async {
    var b = draftBills[i];
    if (b['status'] == 'SAVED') return;

    setState(() {
      isProcessing = true;
      progressValue = 0.5;
      progressText = "Saving Invoice for ${b['party'].name}...";
    });
    await Future.delayed(const Duration(milliseconds: 50));

    bool isSale = _tabController.index == 0;
    String finalNo;

    if (isSale) {
      String prefix = "INV-";
      int start = 101;
      try {
        final defSeries = webPh.numberingSeries.firstWhere((s) => s.type == "SALE" && s.isDefault && s.isActive);
        prefix = defSeries.prefix;
        start = defSeries.startNumber;
      } catch (_) {}

      finalNo = WebPharoahNumberingEngine.getNextNumber(prefix: prefix, startFrom: start, currentList: webPh.sales);
      final Party pRef = b['party'] as Party;

      final newSale = Sale(
        id: "SALE-WEB-${DateTime.now().millisecondsSinceEpoch}-$finalNo",
        billNo: finalNo,
        partyId: pRef.id,
        partyName: pRef.name,
        partyGstin: pRef.gst,
        partyState: pRef.state,
        partyAddress: pRef.address,
        partyCity: pRef.city,
        partyPhone: pRef.phone,
        partyEmail: pRef.email,
        partyDl: pRef.dl,
        partyPan: pRef.pan,
        date: b['date'],
        paymentMode: "CREDIT",
        totalAmount: b['total'],
        items: (b['items'] as List).cast<BillItem>(),
        linkedChallanIds: List<String>.from(b['challanIds']),
        sourceTag: "WEB-PORTAL STITCHED",
      );

      webPh.sales.add(newSale);
      for (var cId in b['challanIds']) {
        int idx = webPh.saleChallans.indexWhere((c) => c.id == cId);
        if (idx != -1) webPh.saleChallans[idx].status = "Billed";
      }

      for (var item in newSale.items) {
        String resolvedKey = item.medicineID;
        try {
          final med = webPh.medicines.firstWhere((m) => m.id == item.medicineID);
          resolvedKey = med.identityKey;
        } catch (_) {}

        webPh.registerBatchActivity(
          productKey: resolvedKey,
          batchNo: item.batch,
          exp: item.exp,
          packing: item.packing,
          mrp: item.mrp,
          rate: item.rate,
        );
      }
    } else {
      finalNo = WebPharoahNumberingEngine.getNextNumber(prefix: "PUR-", startFrom: 1, currentList: webPh.purchases);
      final Party pRef = b['party'] as Party;

      final newPurchase = Purchase(
        id: "PUR-WEB-${DateTime.now().millisecondsSinceEpoch}-$finalNo",
        internalNo: finalNo,
        billNo: "CH-CONV-${finalNo.replaceAll('PUR-', '')}",
        partyId: pRef.id,
        distributorName: pRef.name,
        date: b['date'],
        entryDate: DateTime.now(),
        paymentMode: "CREDIT",
        totalAmount: b['total'],
        items: (b['items'] as List).cast<PurchaseItem>(),
        linkedChallanIds: List<String>.from(b['challanIds']),
        sourceTag: "WEB-PORTAL STITCHED",
      );

      webPh.purchases.add(newPurchase);
      for (var cId in b['challanIds']) {
        int idx = webPh.purchaseChallans.indexWhere((c) => c.id == cId);
        if (idx != -1) webPh.purchaseChallans[idx].status = "Billed";
      }

      for (var item in newPurchase.items) {
        String resolvedKey = item.medicineID;
        try {
          final med = webPh.medicines.firstWhere((m) => m.id == item.medicineID);
          resolvedKey = med.identityKey;
        } catch (_) {}

        webPh.registerBatchActivity(
          productKey: resolvedKey,
          batchNo: item.batch,
          exp: item.exp,
          packing: item.packing,
          mrp: item.mrp,
          rate: item.purchaseRate,
        );
      }
    }

    setState(() { progressText = "Syncing Inventory to Cloud..."; });
    await Future.delayed(const Duration(milliseconds: 50));

    webPh.rebuildInventory();
    await webPh.pushUpdatedDataToCloud();

    setState(() {
      draftBills[i]['status'] = 'SAVED';
      draftBills[i]['billNo'] = finalNo;
      isProcessing = false;
    });
  }

  // ===========================================================================
  // 💾 BATCH SAVE ALL DRAFTS (WITH DYNAMIC PERCENTAGE LOADER)
  // ===========================================================================
  Future<void> _handleBatchSave(PharoahWebManager webPh) async {
    var selected = draftBills.where((b) => b['isSelected'] && b['status'] == 'DRAFT').toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No pending drafts selected to save!"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      isProcessing = true;
      progressValue = 0.0;
      progressText = "Initializing batch process...";
    });

    bool isSale = _tabController.index == 0;

    if (isSale) {
      String prefix = "INV-";
      int start = 101;
      try {
        final defSeries = webPh.numberingSeries.firstWhere((s) => s.type == "SALE" && s.isDefault && s.isActive);
        prefix = defSeries.prefix;
        start = defSeries.startNumber;
      } catch (_) {}

      for (int k = 0; k < selected.length; k++) {
        var b = selected[k];

        // 🧠 Dynamic Yield & UI Update
        setState(() {
          progressValue = (k + 1) / selected.length;
          progressText = "Saving Invoice ${k + 1} of ${selected.length}: ${b['party'].name}...";
        });
        await Future.delayed(const Duration(milliseconds: 50)); // Allow UI to paint

        String finalBillNo = WebPharoahNumberingEngine.getNextNumber(prefix: prefix, startFrom: start, currentList: webPh.sales);
        final Party pRef = b['party'] as Party;

        final newSale = Sale(
          id: "SALE-WEB-${DateTime.now().millisecondsSinceEpoch}-$finalBillNo",
          billNo: finalBillNo,
          partyId: pRef.id,
          partyName: pRef.name,
          partyGstin: pRef.gst,
          partyState: pRef.state,
          partyAddress: pRef.address,
          partyCity: pRef.city,
          partyPhone: pRef.phone,
          partyEmail: pRef.email,
          partyDl: pRef.dl,
          partyPan: pRef.pan,
          date: b['date'],
          paymentMode: "CREDIT",
          totalAmount: b['total'],
          items: (b['items'] as List).cast<BillItem>(),
          linkedChallanIds: List<String>.from(b['challanIds']),
          sourceTag: "WEB-PORTAL STITCHED",
        );

        webPh.sales.add(newSale);
        for (var cId in b['challanIds']) {
          int idx = webPh.saleChallans.indexWhere((c) => c.id == cId);
          if (idx != -1) webPh.saleChallans[idx].status = "Billed";
        }

        for (var item in newSale.items) {
          String resolvedKey = item.medicineID;
          try {
            final med = webPh.medicines.firstWhere((m) => m.id == item.medicineID);
            resolvedKey = med.identityKey;
          } catch (_) {}

          webPh.registerBatchActivity(
            productKey: resolvedKey,
            batchNo: item.batch,
            exp: item.exp,
            packing: item.packing,
            mrp: item.mrp,
            rate: item.rate,
          );
        }

        b['status'] = 'SAVED';
        b['billNo'] = finalBillNo;
      }
    } else {
      for (int k = 0; k < selected.length; k++) {
        var b = selected[k];

        // 🧠 Dynamic Yield & UI Update
        setState(() {
          progressValue = (k + 1) / selected.length;
          progressText = "Saving Inward ${k + 1} of ${selected.length}: ${b['party'].name}...";
        });
        await Future.delayed(const Duration(milliseconds: 50)); // Allow UI to paint

        String finalInternalNo = WebPharoahNumberingEngine.getNextNumber(prefix: "PUR-", startFrom: 1, currentList: webPh.purchases);
        final Party pRef = b['party'] as Party;

        final newPurchase = Purchase(
          id: "PUR-WEB-${DateTime.now().millisecondsSinceEpoch}-$finalInternalNo",
          internalNo: finalInternalNo,
          billNo: "CH-CONV-${finalInternalNo.replaceAll('PUR-', '')}",
          partyId: pRef.id,
          distributorName: pRef.name,
          date: b['date'],
          entryDate: DateTime.now(),
          paymentMode: "CREDIT",
          totalAmount: b['total'],
          items: (b['items'] as List).cast<PurchaseItem>(),
          linkedChallanIds: List<String>.from(b['challanIds']),
          sourceTag: "WEB-PORTAL STITCHED",
        );

        webPh.purchases.add(newPurchase);
        for (var cId in b['challanIds']) {
          int idx = webPh.purchaseChallans.indexWhere((c) => c.id == cId);
          if (idx != -1) webPh.purchaseChallans[idx].status = "Billed";
        }

        for (var item in newPurchase.items) {
          String resolvedKey = item.medicineID;
          try {
            final med = webPh.medicines.firstWhere((m) => m.id == item.medicineID);
            resolvedKey = med.identityKey;
          } catch (_) {}

          webPh.registerBatchActivity(
            productKey: resolvedKey,
            batchNo: item.batch,
            exp: item.exp,
            packing: item.packing,
            mrp: item.mrp,
            rate: item.purchaseRate,
          );
        }

        b['status'] = 'SAVED';
        b['billNo'] = finalInternalNo;
      }
    }

    setState(() {
      progressText = "Syncing Inventory to Cloud...";
    });
    await Future.delayed(const Duration(milliseconds: 100));

    webPh.rebuildInventory();
    await webPh.pushUpdatedDataToCloud();
    setState(() => isProcessing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ ${selected.length} Invoices Stitched & Saved!"), backgroundColor: Colors.green),
      );
    }
  }

  // ===========================================================================
  // 📦 BULK ZIP PDF EXPORT FOR WEB
  // ===========================================================================
  Future<void> _handleZipExport(PharoahWebManager webPh) async {
    var selected = draftBills.where((b) => b['isSelected']).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select bills to export ZIP!"), backgroundColor: Colors.orange),
      );
      return;
    }

    // Step A: Auto-save any remaining drafts first
    if (selected.any((b) => b['status'] == 'DRAFT')) {
      await _handleBatchSave(webPh);
    }

    setState(() {
      isProcessing = true;
      progressValue = 0.0;
      progressText = "Preparing Invoices ZIP Package...";
    });
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final archive = Archive();
      bool isSale = _tabController.index == 0;
      final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);

      for (int k = 0; k < selected.length; k++) {
        var d = selected[k];
        String targetBillNo = d['billNo'];

        setState(() {
          progressValue = (k + 1) / selected.length;
          progressText = "Generating PDF ${k + 1}/${selected.length}: ${d['party'].name}";
        });

        await Future.delayed(const Duration(milliseconds: 50));

        Uint8List? pdfBytes;
        if (isSale) {
          Sale? sObj;
          try {
            sObj = webPh.sales.firstWhere((s) => s.billNo == targetBillNo);
          } catch (_) {}

          if (sObj != null) {
            pdfBytes = await WebPdfRouterService.generateSaleBytes(
              sale: sObj,
              party: d['party'],
              shop: shopProfile,
              config: webPh.appConfig,
            );
          }
        } else {
          Purchase? pObj;
          try {
            pObj = webPh.purchases.firstWhere((p) => p.internalNo == targetBillNo);
          } catch (_) {}

          if (pObj != null) {
            pdfBytes = await WebPdfRouterService.generatePurchaseChallanBytes(
              challan: PurchaseChallan(
                id: 'temp',
                internalNo: pObj.internalNo,
                billNo: pObj.billNo,
                partyId: pObj.partyId,
                distributorName: pObj.distributorName,
                date: pObj.date,
                items: pObj.items,
                totalAmount: pObj.totalAmount,
              ),
              party: d['party'],
              shop: shopProfile,
            );
          }
        }

        if (pdfBytes != null && pdfBytes.isNotEmpty) {
          String safeParty = d['party'].name.replaceAll(RegExp(r'[^A-Z0-9]'), '');
          String fileName = "${targetBillNo}_$safeParty.pdf";
          archive.addFile(ArchiveFile(fileName, pdfBytes.length, pdfBytes));
        }
      }

      setState(() {
        progressText = "Compressing ZIP file...";
      });
      await Future.delayed(const Duration(milliseconds: 50));

      final zipData = ZipEncoder().encode(archive);

      if (zipData != null && zipData.isNotEmpty) {
        String zipName = "Stitched_Invoices_${DateFormat('ddMM_HHmm').format(DateTime.now())}";

        await FileSaver.instance.saveFile(
          name: zipName,
          bytes: Uint8List.fromList(zipData),
          ext: "zip",
          mimeType: MimeType.zip,
        );

        setState(() => isProcessing = false);

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.folder_zip_rounded, color: Color(0xFF10B981), size: 22),
                  SizedBox(width: 8),
                  Text("ZIP BUNDLE READY", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(
                "Successfully exported ${selected.length} invoices into '$zipName.zip'.\nCheck your browser's Downloads folder.",
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("OK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      } else {
        throw Exception("Failed to encode ZIP archive data.");
      }
    } catch (e) {
      setState(() => isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export Error: $e"), backgroundColor: Colors.redAccent));
      }
    }
  }

  // ===========================================================================
  // 🖨️ PRINT SINGLE BILL
  // ===========================================================================
  void _printSingle(PharoahWebManager webPh, int i) async {
    if (draftBills[i]['status'] == 'DRAFT') {
      await _saveSingle(webPh, i);
    }
    var b = draftBills[i];
    final shopProfile = CompanyProfile.fromMap(webPh.companyProfile);

    if (_tabController.index == 0) {
      try {
        var s = webPh.sales.firstWhere((s) => s.billNo == b['billNo']);
        await WebPdfRouterService.printSaleInvoice(sale: s, party: b['party'], shop: shopProfile, config: webPh.appConfig);
      } catch (_) {}
    } else {
      try {
        var p = webPh.purchases.firstWhere((p) => p.internalNo == b['billNo']);
        await WebPdfRouterService.printPurchaseInvoice(purchase: p, party: b['party'], shop: shopProfile);
      } catch (_) {}
    }
  }

  // ===========================================================================
  // 👁️ VIEW DRAFT (READ-ONLY INVOICE PREVIEW)
  // ===========================================================================
  void _viewDraft(Map<String, dynamic> b) {
    if (_tabController.index == 0) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (c) => Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: WebNewSaleView(
              onBack: () => Navigator.pop(c),
              initialParty: b['party'],
              initialBillNo: b['billNo'],
              initialDate: b['date'],
              initialMode: "CREDIT",
              existingItems: (b['items'] as List).cast<BillItem>(),
              isReadOnly: true,
            ),
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (c) => Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: WebPurchaseEntryView(
              onBack: () => Navigator.pop(c),
              initialSupplier: b['party'],
              initialInternalNo: b['billNo'],
              initialBillNo: "",
              initialDate: b['date'],
              initialMode: "CREDIT",
              existingItems: (b['items'] as List).cast<PurchaseItem>(),
              isReadOnly: true,
            ),
          ),
        ),
      );
    }
  }

  // ===========================================================================
  // ✏️ EDIT DRAFT (INTERACTIVE MODIFICATION BEFORE BILLING)
  // ===========================================================================
  void _editDraft(Map<String, dynamic> b, int i) async {
    if (_tabController.index == 0) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (c) => Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: WebNewSaleView(
              onBack: () => Navigator.pop(c),
              initialParty: b['party'],
              initialBillNo: b['billNo'] == 'DRAFT' ? null : b['billNo'],
              initialDate: b['date'],
              initialMode: "CREDIT",
              existingItems: (b['items'] as List).cast<BillItem>(),
              linkedChallanIds: List<String>.from(b['challanIds']),
              isReadOnly: false,
            ),
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (c) => Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: WebPurchaseEntryView(
              onBack: () => Navigator.pop(c),
              initialSupplier: b['party'],
              initialInternalNo: b['billNo'] == 'DRAFT' ? null : b['billNo'],
              initialBillNo: "",
              initialDate: b['date'],
              initialMode: "CREDIT",
              existingItems: (b['items'] as List).cast<PurchaseItem>(),
              linkedChallanIds: List<String>.from(b['challanIds']),
              isReadOnly: false,
            ),
          ),
        ),
      );
    }
    setState(() {
      draftBills[i]['status'] = 'SAVED';
      draftBills[i]['billNo'] = "MANUAL-DONE";
    });
  }

  // ===========================================================================
  // 🖥️ UI STEP ROUTER
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    bool isSale = _tabController.index == 0;
    Color color = isSale ? const Color(0xFF2563EB) : const Color(0xFFD97706);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                onPressed: funnelStep != "MODE" ? () => setState(() => funnelStep = "MODE") : widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: Text(funnelStep != "MODE" ? "BACK TO MODES" : "BACK TO DASHBOARD", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 15),
              Icon(Icons.auto_fix_high_rounded, color: color, size: 24),
              const SizedBox(width: 10),
              Text(
                isSale ? "OUTWARD CHALLAN TO BILL STITCHER" : "INWARD CHALLAN TO BILL STITCHER",
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
              const Spacer(),
              if (funnelStep == "MODE")
                SizedBox(
                  width: 320,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: color,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    tabs: const [Tab(text: "OUTWARD (SALE)"), Tab(text: "INWARD (PURCHASE)")],
                  ),
                ),
            ],
          ),
          const Divider(color: Colors.white10, height: 25),

          if (isProcessing)
            Container(
              padding: const EdgeInsets.all(50),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white24),
                  const SizedBox(height: 20),
                  Text("${(progressValue * 100).toInt()}%", style: TextStyle(color: color, fontSize: 40, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 320,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(value: progressValue > 0 ? progressValue : null, color: color, backgroundColor: Colors.white10, minHeight: 8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(progressText, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
                ],
              ),
            )
          else ...[
            if (funnelStep == "MODE") _buildModeStep(webPh, color),
            if (funnelStep == "ROUTE") _buildRouteStep(webPh, color),
            if (funnelStep == "PARTY") _buildPartyStep(webPh, color),
            if (funnelStep == "REVIEW") _buildReviewStep(webPh, color),
          ]
        ],
      ),
    );
  }

  // --- STEP 1: MODE SELECTOR ---
  Widget _buildModeStep(PharoahWebManager webPh, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _showMonthPicker(webPh.financialYear),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withAlpha(120), width: 1.5),
                ),
                child: Column(
                  children: [
                    Icon(Icons.calendar_month_rounded, color: color, size: 36),
                    const SizedBox(height: 12),
                    const Text("MONTHLY BATCH STITCH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 6),
                    const Text("Select a full financial month (Apr-Mar)", style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: InkWell(
              onTap: () => _pickCustomRange(webPh.financialYear),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2DD4BF), width: 1.5),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.date_range_rounded, color: Color(0xFF2DD4BF), size: 36),
                    SizedBox(height: 12),
                    Text("RANDOM CUSTOM RANGE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    SizedBox(height: 6),
                    Text("Choose specific custom date interval in FY", style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMonthPicker(String fy) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Select Financial Month", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: fyMonths.length,
            itemBuilder: (ctx, i) => ListTile(
              dense: true,
              title: Text(fyMonths[i], style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 12),
              onTap: () {
                Navigator.pop(c);
                int yr = int.parse(fy.split('-')[0]);
                if (yr < 2000) yr += 2000;
                int tM = i + 4;
                if (tM > 12) {
                  tM -= 12;
                  yr++;
                }
                setState(() {
                  fromDate = DateTime(yr, tM, 1);
                  toDate = DateTime(yr, tM + 1, 0);
                  funnelStep = "ROUTE";
                  selectionMode = "MONTHLY";
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  void _pickCustomRange(String fy) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: WebAppDateLogic.getFYStart(fy),
      lastDate: WebAppDateLogic.getFYEnd(fy),
    );
    if (picked != null) {
      setState(() {
        fromDate = picked.start;
        toDate = picked.end;
        funnelStep = "ROUTE";
        selectionMode = "RANDOM";
      });
    }
  }

  // --- STEP 2: ROUTE FILTER ---
  Widget _buildRouteStep(PharoahWebManager webPh, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
          child: Text(
            "STEP 2: FILTER BY DELIVERY ROUTE (${DateFormat('dd/MM/yy').format(fromDate)} to ${DateFormat('dd/MM/yy').format(toDate)})",
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 14),
        ListTile(
          tileColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFF2DD4BF))),
          leading: const Icon(Icons.done_all, color: Color(0xFF2DD4BF)),
          title: const Text("SKIP & SHOW ALL ROUTES", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          onTap: () => setState(() {
            selectedRoute = null;
            funnelStep = "PARTY";
          }),
        ),
        const SizedBox(height: 10),
        ...webPh.routes.map((r) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.map_rounded, color: Colors.white54, size: 18),
            title: Text(r.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 12),
            onTap: () => setState(() {
              selectedRoute = r.name;
              funnelStep = "PARTY";
            }),
          ),
        )),
      ],
    );
  }

  // --- STEP 3: PARTY SELECTION ---
  Widget _buildPartyStep(PharoahWebManager webPh, Color color) {
    bool isSale = _tabController.index == 0;
    final list = webPh.parties.where((p) {
      bool hasPending = isSale
          ? webPh.saleChallans.any((c) =>
              c.partyName.trim().toUpperCase() == p.name.trim().toUpperCase() &&
              c.status == "Pending" &&
              _isInDateRange(c.date))
          : webPh.purchaseChallans.any((c) =>
              c.distributorName.trim().toUpperCase() == p.name.trim().toUpperCase() &&
              c.status == "Pending" &&
              _isInDateRange(c.date));
      bool matchesRoute = selectedRoute == null || p.route == selectedRoute;
      bool matchesSearch = partySearch.isEmpty || p.name.toLowerCase().contains(partySearch.toLowerCase());
      return hasPending && matchesRoute && matchesSearch;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: "Search customer/party...",
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                onChanged: (v) => setState(() => partySearch = v),
              ),
            ),
            const SizedBox(width: 14),
            TextButton.icon(
              onPressed: () => setState(() {
                if (selectedPartyNames.length == list.length) {
                  selectedPartyNames.clear();
                } else {
                  selectedPartyNames = list.map((e) => e.name).toList();
                }
              }),
              icon: Icon(selectedPartyNames.length == list.length ? Icons.deselect_rounded : Icons.select_all_rounded, size: 16),
              label: Text(
                selectedPartyNames.length == list.length ? "UNSELECT ALL" : "SELECT ALL",
                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(35),
              child: Text("No parties with pending challans in this range.", style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            itemBuilder: (c, i) {
              final p = list[i];
              bool isChecked = selectedPartyNames.contains(p.name);
              int pendCount = isSale
                  ? webPh.saleChallans.where((ch) => ch.partyName.trim().toUpperCase() == p.name.trim().toUpperCase() && ch.status == "Pending" && _isInDateRange(ch.date)).length
                  : webPh.purchaseChallans.where((ch) => ch.distributorName.trim().toUpperCase() == p.name.trim().toUpperCase() && ch.status == "Pending" && _isInDateRange(ch.date)).length;

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: CheckboxListTile(
                  dense: true,
                  activeColor: color,
                  value: isChecked,
                  title: Row(
                    children: [
                      Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(4)),
                        child: Text("$pendCount Challans", style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  subtitle: Text("${p.city} • Route: ${p.route.isEmpty ? 'General' : p.route}", style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                  onChanged: (v) => setState(() {
                    v == true ? selectedPartyNames.add(p.name) : selectedPartyNames.remove(p.name);
                  }),
                ),
              );
            },
          ),
        if (selectedPartyNames.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _generateDrafts(webPh),
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: Text("STITCH SELECTED (${selectedPartyNames.length} PARTIES) ➔", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
            ),
          ),
        ],
      ],
    );
  }

  // --- STEP 4: REVIEW STITCHED DRAFTS ---
  Widget _buildReviewStep(PharoahWebManager webPh, Color color) {
    bool allSelected = draftBills.isNotEmpty && draftBills.every((b) => b['isSelected'] == true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Batch Date Override Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withAlpha(80)),
          ),
          child: InkWell(
            onTap: () async {
              final p = await showDatePicker(
                context: context,
                initialDate: batchBillDate,
                firstDate: WebAppDateLogic.getFYStart(webPh.financialYear),
                lastDate: WebAppDateLogic.getFYEnd(webPh.financialYear),
              );
              if (p != null) {
                setState(() {
                  batchBillDate = p;
                  for (var b in draftBills) {
                    if (b['status'] == 'DRAFT') b['date'] = p;
                  }
                });
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  "BILLING DATE FOR ALL: ${DateFormat('dd/MM/yyyy').format(batchBillDate)} (TAP TO EDIT)",
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit_rounded, size: 12, color: Colors.white70),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Action Toolbar
        Row(
          children: [
            Checkbox(
              value: allSelected,
              activeColor: color,
              onChanged: (v) => setState(() {
                for (var b in draftBills) {
                  if (b['status'] == 'DRAFT') b['isSelected'] = v;
                }
              }),
            ),
            const Text("SEL ALL", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _handleBatchSave(webPh),
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text("SAVE ALL INVOICES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _handleZipExport(webPh),
              icon: const Icon(Icons.folder_zip_rounded, size: 16),
              label: const Text("ZIP PDF BUNDLE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Review List of Draft Cards
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: draftBills.length,
          itemBuilder: (c, i) {
            final b = draftBills[i];
            bool isSaved = b['status'] == 'SAVED';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isSaved ? Colors.greenAccent : Colors.white10, width: isSaved ? 1.5 : 1.0),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Checkbox(
                      value: b['isSelected'],
                      activeColor: color,
                      onChanged: isSaved ? null : (v) => setState(() => b['isSelected'] = v),
                    ),
                    title: Row(
                      children: [
                        Text(b['party'].name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSaved ? const Color(0x3310B981) : const Color(0x33F59E0B),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isSaved ? b['billNo'] : "DRAFT",
                            style: TextStyle(color: isSaved ? Colors.greenAccent : Colors.orangeAccent, fontSize: 8.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      "${(b['items'] as List).length} Items • ${(b['challanIds'] as List).length} Challans • ${DateFormat('dd/MM/yyyy').format(b['date'])}",
                      style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                    ),
                    trailing: Text(
                      "₹${(b['total'] as double).toStringAsFixed(2)}",
                      style: const TextStyle(color: Color(0xFF2DD4BF), fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),

                  // 5 Action Buttons per Card (VIEW, EDIT, SAVE, PDF, DEL)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _cardAction(Icons.remove_red_eye_outlined, "VIEW", Colors.blueAccent, () => _viewDraft(b)),
                        _cardAction(Icons.edit_note_rounded, "EDIT", Colors.orangeAccent, () => _editDraft(b, i)),
                        _cardAction(isSaved ? Icons.verified_rounded : Icons.save_rounded, "SAVE", isSaved ? Colors.greenAccent : Colors.white70, () => _saveSingle(webPh, i)),
                        _cardAction(Icons.print_outlined, "PDF", const Color(0xFF38BDF8), () => _printSingle(webPh, i)),
                        _cardAction(Icons.delete_outline_rounded, "DEL", Colors.redAccent, () => setState(() => draftBills.removeAt(i))),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _cardAction(IconData icon, String label, Color c, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: c, size: 16),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: c, fontSize: 9.5, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
