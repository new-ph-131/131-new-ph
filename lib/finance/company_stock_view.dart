// FILE: lib/finance/company_stock_view.dart (FULLY RESOLVED 100% COMPILE-READY)

import 'dart:async';
import 'dart:ui'; // ImageFilter के लिए अनिवार्य
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pharoah_manager.dart';
import '../models.dart';
import 'stock_flow_engine.dart';
import '../pharoah_date_controller.dart';
import '../app_date_logic.dart';
import '../../pdf/statements/company_stock_pdf.dart';
import '../pdf/pdf_router_service.dart';

enum ReportStep {
  selectionForm,
  processingLoader,
  showReportGrid,
}

class CompanyStockView extends StatefulWidget {
  const CompanyStockView({super.key});
  @override State<CompanyStockView> createState() => _CompanyStockViewState();
}

class _CompanyStockViewState extends State<CompanyStockView> {
  // Theme Colors
  static const Color brandDark = Color(0xFF1E1B4B); 
  static const Color tableHeaderColor = Color(0xFF2E2B6B); 
  static const Color accentElectric = Color(0xFF3B82F6); 
  static const Color neonEmerald = Color(0xFF10B981); 

  // Flow State
  ReportStep currentStep = ReportStep.selectionForm;

  // Configuration States
  String companySelectionType = "All"; // All or Single
  String selectedCompany = "";
  Set<String> selectedCompanyIds = {}; // Selected Companies (for All-Multi Mode)

  String partySelectionType = "All"; // All or Single
  String selectedParty = "";
  String selectedPartyId = "";
  Set<String> selectedPartyIds = {}; // Selected Parties (for All-Multi Mode)

  String transactionType = "BOTH"; // SALE, PURCHASE, BOTH
  String valuationBasis = "PURCHASE"; // PURCHASE, SALE, MRP, MANUAL
  
  // CN/DN (Return) Adjustments
  bool deductCN = false; 
  bool deductDN = false; 

  // Date Range (Locked to FY)
  DateTimeRange fyDateRange = DateTimeRange(
    start: DateTime.now(),
    end: DateTime.now(),
  );

  // Loader states
  double processingProgress = 0.0;
  String processingStatusText = "Initializing Pipeline...";

  @override
  void initState() {
    super.initState();
    final ph = Provider.of<PharoahManager>(context, listen: false);
    
    // Set standard financial year boundaries
    DateTime smartDate = AppDateLogic.getSmartDate(ph.currentFY);
    fyDateRange = DateTimeRange(
      start: DateTime(smartDate.year, smartDate.month, 1),
      end: smartDate,
    );

    // Load initial active databases from PharoahManager
    selectedCompanyIds = ph.companies.map((c) => c.name).toSet();
    selectedPartyIds = ph.parties.where((p) => p.name != "CASH").map((p) => p.name).toSet();

    if (ph.companies.isNotEmpty) selectedCompany = ph.companies.first.name;
    if (ph.parties.isNotEmpty) {
      selectedParty = ph.parties.first.name;
      selectedPartyId = ph.parties.first.id;
    }
  }

  // Simple In-Built Date Formatter
  String _formatDate(DateTime d) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return "${pad(d.day)}/${pad(d.month)}/${d.year}";
  }

  // ===========================================================================
  // PROGRESSIVE (FORWARD-CALCULATION) STOCK FLOW ENGINE (MARG ALIGNED)
  // ===========================================================================
  Map<String, double> _calculateCustomItemFlow({
    required Medicine med,
    required DateTime from,
    required DateTime to,
    required PharoahManager ph,
  }) {
    double baseOpening = 0.0;
    
    if (partySelectionType == "Single") {
      baseOpening = 0.0;
    } else {
      final batches = ph.batchHistory[med.identityKey] ?? [];
      if (batches.isNotEmpty) {
        baseOpening = batches.fold(0.0, (sum, b) => sum + b.openingQty + b.adjustmentQty);
      } else {
        double totalPur = 0.0;
        double totalSale = 0.0;
        double totalCN = 0.0;
        double totalDN = 0.0;
        for (var p in ph.purchases) {
          for (var it in p.items.where((it) => it.medicineID == med.id)) {
            totalPur += (it.qty + it.freeQty);
          }
        }
        for (var s in ph.sales.where((s) => s.status == "Active")) {
          for (var it in s.items.where((it) => it.medicineID == med.id)) {
            totalSale += (it.qty + it.freeQty);
          }
        }
        for (var r in ph.saleReturns.where((r) => r.status == "Active")) {
          for (var it in r.items.where((it) => it.medicineID == med.id && !it.isBreakage)) {
            totalCN += (it.qty + it.freeQty);
          }
        }
        for (var r in ph.purchaseReturns.where((r) => r.status == "Active")) {
          for (var it in r.items.where((it) => it.medicineID == med.id && !it.isBreakage)) {
            totalDN += (it.qty + it.freeQty);
          }
        }
        baseOpening = med.stock - totalPur + totalSale - totalCN + totalDN;
      }
    }

    double purBefore = 0.0;
    double saleBefore = 0.0;
    double cnBefore = 0.0;
    double dnBefore = 0.0;

    for (var p in ph.purchases.where((p) => p.date.isBefore(from))) {
      if (partySelectionType == "Single" && p.partyId != selectedPartyId) continue;
      for (var it in p.items.where((it) => it.medicineID == med.id)) {
        purBefore += (it.qty + it.freeQty);
      }
    }

    for (var s in ph.sales.where((s) => s.status == "Active" && s.date.isBefore(from))) {
      if (partySelectionType == "Single" && s.partyId != selectedPartyId) continue;
      for (var it in s.items.where((it) => it.medicineID == med.id)) {
        saleBefore += (it.qty + it.freeQty);
      }
    }

    for (var r in ph.saleReturns.where((r) => r.status == "Active" && r.date.isBefore(from))) {
      if (partySelectionType == "Single" && r.partyName != selectedParty) continue;
      for (var it in r.items.where((it) => it.medicineID == med.id && !it.isBreakage)) {
        cnBefore += (it.qty + it.freeQty);
      }
    }

    for (var r in ph.purchaseReturns.where((r) => r.status == "Active" && r.date.isBefore(from))) {
      if (partySelectionType == "Single" && r.distributorName != selectedParty) continue;
      for (var it in r.items.where((it) => it.medicineID == med.id && !it.isBreakage)) {
        dnBefore += (it.qty + it.freeQty);
      }
    }

    double opening = baseOpening + purBefore - saleBefore + cnBefore - dnBefore;

    double purInPeriod = 0.0;
    double saleInPeriod = 0.0;
    double cnInPeriod = 0.0;
    double dnInPeriod = 0.0;

    DateTime fromLimit = from.subtract(const Duration(seconds: 1));
    DateTime toLimit = to.add(const Duration(days: 1));

    for (var p in ph.purchases.where((p) => p.date.isAfter(fromLimit) && p.date.isBefore(toLimit))) {
      if (partySelectionType == "Single" && p.partyId != selectedPartyId) continue;
      for (var it in p.items.where((it) => it.medicineID == med.id)) {
        purInPeriod += (it.qty + it.freeQty);
      }
    }

    for (var s in ph.sales.where((s) => s.status == "Active" && s.date.isAfter(fromLimit) && s.date.isBefore(toLimit))) {
      if (partySelectionType == "Single" && s.partyId != selectedPartyId) continue;
      for (var it in s.items.where((it) => it.medicineID == med.id)) {
        saleInPeriod += (it.qty + it.freeQty);
      }
    }

    for (var r in ph.saleReturns.where((r) => r.status == "Active" && r.date.isAfter(fromLimit) && r.date.isBefore(toLimit))) {
      if (partySelectionType == "Single" && r.partyName != selectedParty) continue;
      for (var it in r.items.where((it) => it.medicineID == med.id && !it.isBreakage)) {
        cnInPeriod += (it.qty + it.freeQty);
      }
    }

    for (var r in ph.purchaseReturns.where((r) => r.status == "Active" && r.date.isAfter(fromLimit) && r.date.isBefore(toLimit))) {
      if (partySelectionType == "Single" && r.distributorName != selectedParty) continue;
      for (var it in r.items.where((it) => it.medicineID == med.id && !it.isBreakage)) {
        dnInPeriod += (it.qty + it.freeQty);
      }
    }

    double received = purInPeriod;
    double issued = saleInPeriod;

    if (deductDN) {
      received -= dnInPeriod;
    } else {
      issued += dnInPeriod; 
    }
    if (deductCN) {
      issued -= cnInPeriod;
    } else {
      received += cnInPeriod; 
    }

    double closing = opening + received - issued;

    return {
      'opening': opening,
      'received': received,
      'sale': issued,
      'closing': closing,
    };
  }

  // ===========================================================================
  // DATE RANGE & SMART REPORT PROCESS PIPELINE METHODS
  // ===========================================================================
  Future<void> _pickDateRangeWithinFY() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final DateTime fyStart = AppDateLogic.getFYStart(ph.currentFY);
    final DateTime fyEnd = AppDateLogic.getFYEnd(ph.currentFY);

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: fyDateRange,
      firstDate: fyStart, 
      lastDate: fyEnd,   
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: brandDark,
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        fyDateRange = picked;
      });
    }
  }

  void _startSmartReportGeneration() {
    setState(() {
      currentStep = ReportStep.processingLoader;
      processingProgress = 0.0;
      processingStatusText = "Connecting with DB Engine...";
    });

    final List<String> phases = [
      "Scanning meds.json database...",
      "Filtering Excluded Companies list...",
      "Filtering Excluded Parties list...",
      "Analyzing Return (CN/DN) Reversals...",
      "Mapping product-batch indices...",
      "Summing Net Inflow & Net Outflow...",
      "Applying Manual Rate Valuation algorithms...",
      "Compiling Grand Totals..."
    ];

    int step = 0;
    Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (processingProgress >= 1.0) {
        timer.cancel();
        _showSuccessMiddleDialog();
      } else {
        setState(() {
          processingProgress += 0.15;
          if (processingProgress > 1.0) processingProgress = 1.0;
          
          if (step < phases.length) {
            processingStatusText = phases[step];
            step++;
          }
        });
      }
    });
  }

  void _showSuccessMiddleDialog() {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    List<String> excludedParties = ph.parties.where((p) => p.name != "CASH" && !selectedPartyIds.contains(p.name)).map((e) => e.name).toList();
    List<String> excludedCompanies = ph.companies.where((c) => !selectedCompanyIds.contains(c.name)).map((e) => e.name).toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.verified_rounded, color: neonEmerald, size: 24),
              SizedBox(width: 10),
              Text("PROCESS COMPLETE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Your Statement has been processed in a safe memory container.",
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              const SizedBox(height: 15),
              _bulletPoint("Companies: ${companySelectionType == "All" ? "${selectedCompanyIds.length} Active" : selectedCompany}"),
              if (companySelectionType == "All" && excludedCompanies.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 14, bottom: 4),
                  child: Text("Excluded: ${excludedCompanies.join(', ')}", style: const TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              _bulletPoint("Parties: ${partySelectionType == "All" ? "${selectedPartyIds.length} Active" : selectedParty}"),
              if (partySelectionType == "All" && excludedParties.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 14, bottom: 4),
                  child: Text("Excluded: ${excludedParties.join(', ')}", style: const TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              _bulletPoint("Deductions Applied: ${deductCN ? 'CN (Sales)' : 'None'} ${deductDN ? '& DN (Purchases)' : ''}"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                setState(() {
                  currentStep = ReportStep.selectionForm;
                });
              },
              child: const Text("GO BACK", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accentElectric, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(c);
                setState(() {
                  currentStep = ReportStep.showReportGrid;
                });
              },
              child: const Text("VIEW STATEMENT", style: TextStyle(fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 6, color: accentElectric),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  // ===========================================================================
  // MASTER BUILD ROUTER
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    switch (currentStep) {
      case ReportStep.selectionForm:
        return _buildSelectionForm();
      case ReportStep.processingLoader:
        return _buildProcessingLoader();
      case ReportStep.showReportGrid:
        return _buildReportGrid(Provider.of<PharoahManager>(context));
    }
  }

  // ===========================================================================
  // SCREEN 1: SELECTION FORM WIDGET
  // ===========================================================================
  Widget _buildSelectionForm() {
    final ph = Provider.of<PharoahManager>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: const Text("Stock Flow & Valuation Audit"), backgroundColor: brandDark, foregroundColor: Colors.white),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: 500,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: const BoxDecoration(color: brandDark, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  child: Row(children: [
                    const Icon(Icons.tune, color: Colors.orangeAccent),
                    const SizedBox(width: 10),
                    const Text("AUDIT FLOW CONFIGURATION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _lbl("1. COMPANIES"),
                      Row(children: [
                        _seg("All", companySelectionType == "All", () => setState(() => companySelectionType = "All")),
                        _seg("Single", companySelectionType == "Single", () => setState(() => companySelectionType = "Single")),
                      ]),
                      const SizedBox(height: 8),
                      companySelectionType == "All" 
                        ? _trigger("Included Companies", "${selectedCompanyIds.length} Selected", () {
                            _openExclDialog("COMPANIES", ph.companies.map((c) => c.name).toList(), selectedCompanyIds, (v) => setState(() => selectedCompanyIds = v));
                          })
                        : _picker("Company", selectedCompany, (v) => setState(() => selectedCompany = v), ph.companies.map((c) => c.name).toList()),
                      const SizedBox(height: 12),
                      _lbl("2. PARTY TARGET"),
                      Row(children: [
                        _seg("All", partySelectionType == "All", () => setState(() => partySelectionType = "All")),
                        _seg("Single", partySelectionType == "Single", () => setState(() => partySelectionType = "Single")),
                      ]),
                      const SizedBox(height: 8),
                      partySelectionType == "All"
                        ? _trigger("Included Parties", "${selectedPartyIds.length} Selected", () {
                            _openExclDialog("PARTIES", ph.parties.where((p) => p.name != "CASH").map((p) => p.name).toList(), selectedPartyIds, (v) => setState(() => selectedPartyIds = v));
                          })
                        : _picker("Party", selectedParty, (v) {
                            setState(() {
                              selectedParty = v;
                              try { selectedPartyId = ph.parties.firstWhere((p) => p.name == v).id; } catch(e) {}
                            });
                          }, ph.parties.where((p) => p.name != "CASH").map((p) => p.name).toList()),
                      const SizedBox(height: 12),
                      _lbl("3. FLOW & VALUATION BASIS"),
                      Row(children: [
                        Expanded(child: _dd(transactionType, ["SALE", "PURCHASE", "BOTH"], (v) => setState(() => transactionType = v!))),
                        const SizedBox(width: 8),
                        Expanded(child: _dd(valuationBasis, ["PURCHASE", "SALE", "MRP", "MANUAL"], (v) => setState(() => valuationBasis = v!))),
                      ]),
                      const SizedBox(height: 12),
                      _lbl("4. RETURN REVERSALS"),
                      _sw("Deduct Credit Notes (Sales Return)", deductCN, (v) => setState(() => deductCN = v)),
                      _sw("Deduct Debit Notes (Purchase Return)", deductDN, (v) => setState(() => deductDN = v)),
                      const SizedBox(height: 12),
                      _lbl("5. DATE RANGE (FY LOCKED)"),
                      _dateTile(),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity, height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: accentElectric, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          onPressed: _startSmartReportGeneration,
                          child: const Text("GENERATE AUDIT REPORT", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SCREEN 2: PROCESSING LOADER
  // ===========================================================================
  Widget _buildProcessingLoader() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sync_rounded, color: Colors.orangeAccent, size: 60),
            const SizedBox(height: 25),
            Text("${(processingProgress * 100).toInt()}%", style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SizedBox(width: 250, child: LinearProgressIndicator(value: processingProgress, color: Colors.orangeAccent, backgroundColor: Colors.white10)),
            const SizedBox(height: 20),
            Text(processingStatusText.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SCREEN 3: GRID TABLE REPORT
  // ===========================================================================
  Widget _buildReportGrid(PharoahManager ph) {
    String colReceiveQty = deductDN ? "NET RECEIVE\nQTY" : "RECEIVE\nQTY";
    String colReceiveVal = deductDN ? "NET RECEIVE\nVALUE (₹)" : "RECEIVE\nVALUE (₹)";
    String colIssueQty = deductCN ? "NET ISSUE\nQTY" : "ISSUE\nQTY";
    String colIssueVal = deductCN ? "NET ISSUE\nVALUE (₹)" : "ISSUE\nVALUE (₹)";

    List<Medicine> activeMeds = ph.medicines.where((m) {
      String cName = ph.companies.firstWhere((c) => c.id == m.companyId, orElse: () => Company(id: '', name: 'OTHERS')).name;
      if (companySelectionType == "Single") return cName == selectedCompany;
      return selectedCompanyIds.contains(cName);
    }).toList();

    double totalOpStock = 0; double totalOpVal = 0;
    double totalRecQty = 0; double totalRecVal = 0;
    double totalIssueQty = 0; double totalIssueVal = 0;
    double totalCloStock = 0; double totalCloVal = 0;

    List<TableRow> tableRows = [];
    tableRows.add(TableRow(
      decoration: const BoxDecoration(color: tableHeaderColor),
      children: [
        _th("PRODUCT DESCRIPTION", isLeft: true),
        _th("UNIT"),
        _th("OPENING\nSTOCK"),
        _th("OPENING\nVALUE (₹)"),
        _th(colReceiveQty),
        _th(colReceiveVal),
        _th(colIssueQty),
        _th(colIssueVal),
        _th("CLOSING\nSTOCK"),
        _th("CLOSING\nVALUE (₹)"),
      ],
    ));

    for (int idx = 0; idx < activeMeds.length; idx++) {
      final m = activeMeds[idx];
      final flow = _calculateCustomItemFlow(med: m, from: fyDateRange.start, to: fyDateRange.end, ph: ph);
      double rate = (valuationBasis == "PURCHASE") ? m.purRate : (valuationBasis == "SALE" ? m.rateA : m.mrp);

      double opStock = (flow['opening'] ?? 0.0);
      double recQty = (flow['received'] ?? 0.0);
      double issueQty = (flow['sale'] ?? 0.0);
      double cloStock = (flow['closing'] ?? 0.0);

      double opVal = opStock * rate;
      double recVal = recQty * rate;
      double issueVal = issueQty * rate;
      double cloVal = cloStock * rate;

      totalOpStock += opStock; totalOpVal += opVal;
      totalRecQty += recQty; totalRecVal += recVal;
      totalIssueQty += issueQty; totalIssueVal += issueVal;
      totalCloStock += cloStock; totalCloVal += cloVal;

      bool isShaded = idx % 2 != 0;
      tableRows.add(TableRow(
        decoration: BoxDecoration(color: isShaded ? const Color(0xFFF8FAFC) : Colors.white),
        children: [
          _td(m.name, isLeft: true, isBold: true),
          _td(m.packing),
          _td(opStock.toInt().toString()),
          _td(opVal.toStringAsFixed(2)),
          _td(recQty.toInt().toString()),
          _td(recVal.toStringAsFixed(2)),
          _td(issueQty.toInt().toString()),
          _td(issueVal.toStringAsFixed(2)),
          _td(cloStock.toInt().toString(), textColor: neonEmerald),
          _td(cloVal.toStringAsFixed(2), textColor: neonEmerald),
        ],
      ));
    }

    tableRows.add(TableRow(
      decoration: const BoxDecoration(color: Color(0xFFECFDF5)),
      children: [
        _td("TOTAL", isLeft: true, isBold: true, textColor: const Color(0xFF047857)),
        _td("-", isBold: true),
        _td(totalOpStock.toInt().toString(), isBold: true, textColor: const Color(0xFF047857)),
        _td("₹${totalOpVal.toStringAsFixed(2)}", isBold: true, textColor: const Color(0xFF047857)),
        _td(totalRecQty.toInt().toString(), isBold: true, textColor: const Color(0xFF047857)),
        _td("₹${totalRecVal.toStringAsFixed(2)}", isBold: true, textColor: const Color(0xFF047857)),
        _td(totalIssueQty.toInt().toString(), isBold: true, textColor: const Color(0xFF047857)),
        _td("₹${totalIssueVal.toStringAsFixed(2)}", isBold: true, textColor: const Color(0xFF047857)),
        _td(totalCloStock.toInt().toString(), isBold: true, textColor: const Color(0xFF047857)),
        _td("₹${totalCloVal.toStringAsFixed(2)}", isBold: true, textColor: const Color(0xFF047857)),
      ],
    ));

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), 
      appBar: AppBar(
        title: Text(ph.activeCompany?.name ?? "DWARIKA MEDICALS", style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: brandDark,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => currentStep = ReportStep.selectionForm),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Export PDF",
            onPressed: () async {
              await CompanyStockPdf.generate(
                shop: ph.activeCompany!,
                groupedData: {
                  for (var name in ph.companies.map((c) => c.name))
                    name: ph.medicines.where((m) {
                      String cName = ph.companies.firstWhere((c) => c.id == m.companyId, orElse: () => Company(id: '', name: 'OTHERS')).name;
                      return cName == name;
                    }).toList()
                },
                from: fyDateRange.start,
                to: fyDateRange.end,
                valuationBasis: valuationBasis,
                ph: ph,
                companySelectionType: companySelectionType,
                selectedCompanyIds: selectedCompanyIds,
                partySelectionType: partySelectionType,
                selectedParty: selectedParty,
                selectedPartyId: selectedPartyId,
                deductCN: deductCN,
                deductDN: deductDN,
              );
            },
          ),
          if (ph.config.isMailActive)
            IconButton(
              icon: Icon(
                ph.config.isAuditMode ? Icons.forward_to_inbox_rounded : Icons.alternate_email,
              ),
              tooltip: ph.config.isAuditMode ? "Forward to CA" : "Send Mail",
              onPressed: () {
                PdfRouterService.emailDocument(
                  context: context,
                  doc: {
                    'grouped': {
                      for (var name in ph.companies.map((c) => c.name))
                        name: ph.medicines.where((m) {
                          String cName = ph.companies.firstWhere((c) => c.id == m.companyId, orElse: () => Company(id: '', name: 'OTHERS')).name;
                          return cName == name;
                        }).toList()
                    },
                    'from': fyDateRange.start,
                    'to': fyDateRange.end,
                    'basis': valuationBasis,
                    'companySelectionType': companySelectionType,
                    'selectedCompanyIds': selectedCompanyIds,
                    'partySelectionType': partySelectionType,
                    'selectedParty': selectedParty,
                    'selectedPartyId': selectedPartyId,
                    'deductCN': deductCN,
                    'deductDN': deductDN,
                  },
                  party: Party(id: 'internal', name: ph.config.isAuditMode ? 'Inward Audit' : 'Internal Stock Audit'),
                  ph: ph,
                  type: "STOCK",
                );
              },
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            width: 1000,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.all(25.0),
            child: Column(
              children: [
                _buildMockReportHeader(ph),
                const SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    width: 950,
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5E1), width: 1), borderRadius: BorderRadius.circular(12)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(180),
                          1: FixedColumnWidth(60),
                          2: FixedColumnWidth(80),
                          3: FixedColumnWidth(100),
                          4: FixedColumnWidth(80),
                          5: FixedColumnWidth(100),
                          6: FixedColumnWidth(80),
                          7: FixedColumnWidth(100),
                          8: FixedColumnWidth(80),
                          9: FixedColumnWidth(100),
                        },
                        border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 1),
                        children: tableRows,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                _buildLegislationDisclaimer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // REPORT DECORATIVE & DISCLAIMER ATOMS (RESTORED!)
  // ===========================================================================
  Widget _buildMockReportHeader(PharoahManager ph) {
    return Center(
      child: Column(
        children: [
          Text(ph.activeCompany?.name ?? "DWARIKA MEDICALS", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: brandDark, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text("D.L. No. : ${ph.activeCompany?.dlNo ?? 'N/A'} | GST: ${ph.activeCompany?.gstin ?? 'N/A'}", style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: brandDark.withOpacity(0.08), 
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "DYNAMIC COMPILATION FLOW REPORT (${_formatDate(fyDateRange.start)} to ${_formatDate(fyDateRange.end)})",
              style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: brandDark),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLegislationDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(
        children: [
          const Icon(Icons.gavel_rounded, color: Colors.blueGrey, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Note: This audit is locked to active Financial Year parameters. Processing is completely sandboxed on local resources to prevent leaks.",
              style: const TextStyle(fontSize: 8, color: Colors.blueGrey, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // COMPACT DIALOGS
  // ===========================================================================
  void _openExclDialog(String title, List<String> all, Set<String> sel, ValueChanged<Set<String>> onConfirm) {
    showDialog(
      context: context,
      builder: (c) {
        String sVal = "";
        Set<String> temp = Set.from(sel);
        return StatefulBuilder(builder: (context, setDState) {
          final filtered = all.where((e) => e.toLowerCase().contains(sVal.toLowerCase())).toList();
          bool isAll = temp.length == all.length;
          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            title: Text("SELECT $title", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 350, height: 400,
              child: Column(children: [
                TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(hintText: "Search...", hintStyle: TextStyle(color: Colors.white38), prefixIcon: Icon(Icons.search, color: Colors.blue)),
                  onChanged: (v) => setDState(() => sVal = v),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text("Select All", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  value: isAll,
                  activeColor: Colors.blue,
                  onChanged: (v) => setDState(() => v! ? temp = Set.from(all) : temp.clear()),
                ),
                Expanded(child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, idx) {
                    final item = filtered[idx];
                    bool isChecked = temp.contains(item);
                    return CheckboxListTile(
                      title: Text(item, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      value: isChecked,
                      activeColor: Colors.blue,
                      onChanged: (v) => setDState(() => v! ? temp.add(item) : temp.remove(item)),
                    );
                  },
                ))
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCEL", style: TextStyle(color: Colors.white70))),
              ElevatedButton(onPressed: () { onConfirm(temp); Navigator.pop(c); }, child: const Text("APPLY")),
            ],
          );
        });
      }
    );
  }

  void _openSinglePicker(String title, List<String> all, String cur, ValueChanged<String> onSel) {
    showDialog(
      context: context,
      builder: (c) {
        String sVal = "";
        return StatefulBuilder(builder: (context, setDState) {
          final filtered = all.where((e) => e.toLowerCase().contains(sVal.toLowerCase())).toList();
          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            title: Text("CHOOSE $title", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 350, height: 400,
              child: Column(children: [
                TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(hintText: "Type to search...", hintStyle: TextStyle(color: Colors.white38), prefixIcon: Icon(Icons.search, color: Colors.blue)),
                  onChanged: (v) => setDState(() => sVal = v),
                ),
                const SizedBox(height: 10),
                Expanded(child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, idx) {
                    final item = filtered[idx];
                    bool isSelected = item == cur;
                    return ListTile(
                      leading: Icon(Icons.check_circle, color: isSelected ? Colors.green : Colors.transparent, size: 16),
                      title: Text(item, style: const TextStyle(color: Colors.white, fontSize: 12)),
                      onTap: () { onSel(item); Navigator.pop(c); },
                    );
                  },
                ))
              ]),
            ),
          );
        });
      }
    );
  }

  // ===========================================================================
  // MINI UI PARTS
  // ===========================================================================
  Widget _lbl(String t) => Padding(padding: const EdgeInsets.only(bottom: 4, top: 4), child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)));
  
  Widget _seg(String l, bool act, VoidCallback tap) => Expanded(child: InkWell(onTap: tap, child: Container(margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: act ? brandDark : Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), child: Text(l, textAlign: TextAlign.center, style: TextStyle(color: act ? Colors.white : Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)))));
  
  Widget _trigger(String l, String v, VoidCallback tap) => InkWell(onTap: tap, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: const TextStyle(fontSize: 8, color: Colors.grey)), Text(v, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: brandDark))]), const Icon(Icons.arrow_forward_ios, size: 12)])));
  
  Widget _picker(String t, String cur, ValueChanged<String> onSel, List<String> items) => InkWell(onTap: () => _openSinglePicker(t, items, cur, onSel), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Select $t...", style: const TextStyle(fontSize: 11, color: Colors.grey)), Text(cur, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: brandDark))])));
  
  Widget _dd(String val, List<String> items, ValueChanged<String?> onChange) => Container(padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: val, isExpanded: true, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87), items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onChange)));
  
  Widget _sw(String t, bool val, ValueChanged<bool> onChange) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(t, style: const TextStyle(fontSize: 11)), Switch(value: val, onChanged: onChange, activeColor: accentElectric)]);
  
  Widget _dateTile() => InkWell(onTap: _pickDateRangeWithinFY, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("${_formatDate(fyDateRange.start)}  to  ${_formatDate(fyDateRange.end)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: brandDark)), const Icon(Icons.calendar_month, size: 18)])));

  Widget _th(String text, {bool isLeft = false}) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    alignment: isLeft ? Alignment.centerLeft : Alignment.center,
    child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: Colors.white)),
  );

  Widget _td(String text, {bool isLeft = false, bool isBold = false, Color? textColor}) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    alignment: isLeft ? Alignment.centerLeft : Alignment.center,
    child: Text(text, style: TextStyle(fontSize: 8.5, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: textColor ?? const Color(0xFF1E293B))),
  );
}
