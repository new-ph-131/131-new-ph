// FILE: lib/web_live_sync/web_challan_stitcher_wizard.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'web_models.dart';
import 'pharoah_web_manager.dart';
import 'web_app_date_logic.dart';
import 'web_pharoah_numbering_engine.dart';

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

  final List<String> fyMonths = ["April", "May", "June", "July", "August", "September", "October", "November", "December", "January", "February", "March"];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    batchBillDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
    fromDate = WebAppDateLogic.getFYStart(webPh.financialYear);
    toDate = WebAppDateLogic.getSmartDate(webPh.financialYear);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _generateDrafts(PharoahWebManager webPh) {
    setState(() => isProcessing = true);
    List<Map<String, dynamic>> temp = [];
    bool isSale = _tabController.index == 0;

    for (var pName in selectedPartyNames) {
      Party? pObj;
      try {
        pObj = webPh.parties.firstWhere((p) => p.name == pName);
      } catch (_) {
        pObj = Party(id: 'temp', name: pName);
      }

      var chs = isSale
          ? webPh.saleChallans.where((c) => c.partyName.trim().toUpperCase() == pName.trim().toUpperCase() && c.status == "Pending").toList()
          : webPh.purchaseChallans.where((c) => c.distributorName.trim().toUpperCase() == pName.trim().toUpperCase() && c.status == "Pending").toList();

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

  Future<void> _handleBatchSave(PharoahWebManager webPh) async {
    var selected = draftBills.where((b) => b['isSelected'] && b['status'] == 'DRAFT').toList();
    if (selected.isEmpty) return;

    setState(() { isProcessing = true; progressText = "Finalizing Batch..."; progressValue = 0.5; });
    bool isSale = _tabController.index == 0;

    if (isSale) {
      String prefix = "INV-";
      int start = 101;
      try {
        final defSeries = webPh.numberingSeries.firstWhere((s) => s.type == "SALE" && s.isDefault && s.isActive);
        prefix = defSeries.prefix;
        start = defSeries.startNumber;
      } catch (_) {}

      for (var b in selected) {
        String finalBillNo = WebPharoahNumberingEngine.getNextNumber(prefix: prefix, startFrom: start, currentList: webPh.sales);
        final Party pRef = b['party'] as Party;
        final newSale = Sale(
          id: "SALE-WEB-${DateTime.now().millisecondsSinceEpoch}-$finalBillNo", billNo: finalBillNo, partyId: pRef.id, partyName: pRef.name, partyGstin: pRef.gst, partyState: pRef.state, partyAddress: pRef.address, partyCity: pRef.city, partyPhone: pRef.phone, partyEmail: pRef.email, partyDl: pRef.dl, partyPan: pRef.pan, date: b['date'], paymentMode: "CREDIT", totalAmount: b['total'], items: (b['items'] as List).cast<BillItem>(), linkedChallanIds: List<String>.from(b['challanIds']), sourceTag: "WEB-PORTAL",
        );
        webPh.sales.add(newSale);
        for (var cId in b['challanIds']) {
          int idx = webPh.saleChallans.indexWhere((c) => c.id == cId);
          if (idx != -1) {
            webPh.saleChallans[idx].status = "Billed";
          }
        }
        b['status'] = 'SAVED'; b['billNo'] = finalBillNo;
      }
    } else {
      for (var b in selected) {
        String finalInternalNo = WebPharoahNumberingEngine.getNextNumber(prefix: "PUR-", startFrom: 1, currentList: webPh.purchases);
        final Party pRef = b['party'] as Party;
        final newPurchase = Purchase(
          id: "PUR-WEB-${DateTime.now().millisecondsSinceEpoch}-$finalInternalNo", internalNo: finalInternalNo, billNo: "CH-CONV-${finalInternalNo.replaceAll('PUR-', '')}", partyId: pRef.id, distributorName: pRef.name, date: b['date'], entryDate: DateTime.now(), paymentMode: "CREDIT", totalAmount: b['total'], items: (b['items'] as List).cast<PurchaseItem>(), linkedChallanIds: List<String>.from(b['challanIds']), sourceTag: "WEB-PORTAL",
        );
        webPh.purchases.add(newPurchase);
        for (var cId in b['challanIds']) {
          int idx = webPh.purchaseChallans.indexWhere((c) => c.id == cId);
          if (idx != -1) {
            webPh.purchaseChallans[idx].status = "Billed";
          }
        }
        b['status'] = 'SAVED'; b['billNo'] = finalInternalNo;
      }
    }

    webPh.rebuildInventory();
    await webPh.pushUpdatedDataToCloud();
    setState(() => isProcessing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ ${selected.length} Invoices Created from Challans!"), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);
    bool isSale = _tabController.index == 0;
    Color color = isSale ? const Color(0xFF2563EB) : const Color(0xFFD97706);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: funnelStep != "MODE" ? () => setState(() => funnelStep = "MODE") : widget.onBack,
              ),
              const SizedBox(width: 8),
              const Text("CHALLAN TO BILL STITCHER WIZARD", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (funnelStep == "MODE")
                SizedBox(
                  width: 320,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: color,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    tabs: const [Tab(text: "OUTWARD CHALLANS"), Tab(text: "INWARD CHALLANS")],
                  ),
                ),
            ],
          ),
          const Divider(color: Colors.white10, height: 20),

          if (isProcessing)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Center(child: Column(children: [CircularProgressIndicator(color: color), const SizedBox(height: 12), Text(progressText, style: const TextStyle(color: Colors.white, fontSize: 12))])),
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

  Widget _buildModeStep(PharoahWebManager webPh, Color color) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _showMonthPicker(webPh.financialYear),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withAlpha(100))),
                child: Column(
                  children: [
                    Icon(Icons.calendar_month_rounded, color: color, size: 28),
                    const SizedBox(height: 10),
                    const Text("MONTHLY BATCH STITCH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    const Text("Select a financial month to convert", style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: InkWell(
              onTap: () => _pickCustomRange(webPh.financialYear),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2DD4BF))),
                child: const Column(
                  children: [
                    Icon(Icons.date_range_rounded, color: Color(0xFF2DD4BF), size: 28),
                    SizedBox(height: 10),
                    Text("CUSTOM DATE RANGE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                    SizedBox(height: 4),
                    Text("Choose custom date period in FY", style: TextStyle(color: Colors.white54, fontSize: 10)),
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
        title: const Text("Select Month", style: TextStyle(color: Colors.white, fontSize: 14)),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: fyMonths.length,
            itemBuilder: (ctx, i) => ListTile(
              title: Text(fyMonths[i], style: const TextStyle(color: Colors.white, fontSize: 12)),
              onTap: () {
                Navigator.pop(c);
                int yr = int.parse(fy.split('-')[0]); if (yr < 2000) yr += 2000;
                int tM = i + 4; if (tM > 12) { tM -= 12; yr++; }
                setState(() { fromDate = DateTime(yr, tM, 1); toDate = DateTime(yr, tM + 1, 0); funnelStep = "ROUTE"; selectionMode = "MONTHLY"; });
              },
            ),
          ),
        ),
      ),
    );
  }

  void _pickCustomRange(String fy) async {
    final picked = await showDateRangePicker(context: context, firstDate: WebAppDateLogic.getFYStart(fy), lastDate: WebAppDateLogic.getFYEnd(fy));
    if (picked != null) {
      setState(() { fromDate = picked.start; toDate = picked.end; funnelStep = "ROUTE"; selectionMode = "CUSTOM"; });
    }
  }

  Widget _buildRouteStep(PharoahWebManager webPh, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("STEP 2: FILTER BY AREA / ROUTE", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ListTile(
          tileColor: Colors.black26, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFF2DD4BF))),
          leading: const Icon(Icons.done_all, color: Color(0xFF2DD4BF)),
          title: const Text("SHOW ALL ROUTES / CUSTOMERS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          onTap: () => setState(() { selectedRoute = null; funnelStep = "PARTY"; }),
        ),
        const SizedBox(height: 10),
        ...webPh.routes.map((r) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            dense: true, title: Text(r.name, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
            onTap: () => setState(() { selectedRoute = r.name; funnelStep = "PARTY"; }),
          ),
        )),
      ],
    );
  }

  Widget _buildPartyStep(PharoahWebManager webPh, Color color) {
    bool isSale = _tabController.index == 0;
    final list = webPh.parties.where((p) {
      bool hasPending = isSale
          ? webPh.saleChallans.any((c) => c.partyName.trim().toUpperCase() == p.name.trim().toUpperCase() && c.status == "Pending")
          : webPh.purchaseChallans.any((c) => c.distributorName.trim().toUpperCase() == p.name.trim().toUpperCase() && c.status == "Pending");
      bool matchesRoute = selectedRoute == null || p.route == selectedRoute;
      return hasPending && matchesRoute;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("STEP 3: SELECT PARTIES TO STITCH", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () => setState(() {
                if (selectedPartyNames.length == list.length) {
                  selectedPartyNames.clear();
                } else {
                  selectedPartyNames = list.map((e) => e.name).toList();
                }
              }),
              child: Text(selectedPartyNames.length == list.length ? "UNSELECT ALL" : "SELECT ALL", style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11)),
            )
          ],
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.all(25), child: Center(child: Text("No parties with pending challans.", style: TextStyle(color: Colors.white38, fontSize: 11))))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            itemBuilder: (c, i) {
              final p = list[i];
              bool isChecked = selectedPartyNames.contains(p.name);
              return CheckboxListTile(
                dense: true,
                activeColor: color,
                value: isChecked,
                title: Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text("${p.city} • Route: ${p.route}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                onChanged: (v) => setState(() { v == true ? selectedPartyNames.add(p.name) : selectedPartyNames.remove(p.name); }),
              );
            },
          ),
        if (selectedPartyNames.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity, height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
              onPressed: () => _generateDrafts(webPh),
              icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
              label: Text("STITCH ${selectedPartyNames.length} INVOICES", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          )
        ]
      ],
    );
  }

  Widget _buildReviewStep(PharoahWebManager webPh, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("REVIEW STITCHED DRAFTS (${draftBills.length})", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              onPressed: () => _handleBatchSave(webPh),
              icon: const Icon(Icons.save_rounded, size: 14),
              label: const Text("SAVE ALL INVOICES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            )
          ],
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: draftBills.length,
          itemBuilder: (c, i) {
            final b = draftBills[i];
            bool isSaved = b['status'] == 'SAVED';

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: isSaved ? Colors.greenAccent : Colors.white10)),
              child: ListTile(
                dense: true,
                title: Text(b['party'].name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                subtitle: Text("Items: ${(b['items'] as List).length} • Status: ${b['status']}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                trailing: Text("₹${(b['total'] as double).toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            );
          },
        ),
      ],
    );
  }
}
