// FILE: lib/pdf/statements/company_stock_pdf.dart (FULLY UPDATED - STABLE PROGRESSIVE METHOD)

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import '../../models.dart';
import '../../gateway/company_registry_model.dart';
import '../../pharoah_manager.dart';

class CompanyStockPdf {
  
  // ===========================================================================
  // PROGRESSIVE ENGINE: STOCK CALCULATION FOR PDF (MUST MATCH SCREEN TOTALLY)
  // ===========================================================================
  static Map<String, double> _calculateCustomItemFlow({
    required Medicine med,
    required DateTime from,
    required DateTime to,
    required PharoahManager ph,
    required String partySelectionType,
    required String selectedParty,
    required String selectedPartyId,
    required bool deductCN,
    required bool deductDN,
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

  static Future<void> generate({
    required CompanyProfile shop,
    required Map<String, List<Medicine>> groupedData,
    required DateTime from,
    required DateTime to,
    required String valuationBasis,
    required PharoahManager ph,
    String companySelectionType = "All",
    Set<String>? selectedCompanyIds,
    String partySelectionType = "All",
    String selectedParty = "",
    String selectedPartyId = "",
    bool deductCN = false,
    bool deductDN = false,
  }) async {
    final pdf = pw.Document();

    String colReceiveQty = deductDN ? "NET RECEIVE\nQTY" : "RECEIVE\nQTY";
    String colReceiveVal = deductDN ? "NET RECEIVE\nVALUE" : "RECEIVE\nVALUE";
    String colIssueQty = deductCN ? "NET ISSUE\nQTY" : "ISSUE\nQTY";
    String colIssueVal = deductCN ? "NET ISSUE\nVALUE" : "ISSUE\nVALUE";

    for (var companyName in groupedData.keys) {
      if (companySelectionType == "Single" && companyName != ph.companies.firstWhere((c) => c.name == companyName, orElse: () => Company(id: '', name: 'OTHERS')).name) {
        continue;
      }
      if (companySelectionType == "All" && selectedCompanyIds != null && !selectedCompanyIds.contains(companyName)) {
        continue;
      }

      List<Medicine> meds = groupedData[companyName]!;
      if (meds.isEmpty) continue;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          header: (context) => _buildHeader(shop, companyName, from, to, valuationBasis, partySelectionType, selectedParty),
          build: (context) {
            double totalOpStock = 0; double totalOpVal = 0;
            double totalRecQty = 0; double totalRecVal = 0;
            double totalIssueQty = 0; double totalIssueVal = 0;
            double totalCloStock = 0; double totalCloVal = 0;

            List<List<String>> tableRows = [];

            for (int i = 0; i < meds.length; i++) {
              var m = meds[i];
              final flow = _calculateCustomItemFlow(
                med: m, from: from, to: to, ph: ph, 
                partySelectionType: partySelectionType, 
                selectedParty: selectedParty, 
                selectedPartyId: selectedPartyId, 
                deductCN: deductCN, 
                deductDN: deductDN
              );
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

              tableRows.add([
                m.name,
                m.packing,
                opStock.toInt().toString(),
                opVal.toStringAsFixed(2),
                recQty.toInt().toString(),
                recVal.toStringAsFixed(2),
                issueQty.toInt().toString(),
                issueVal.toStringAsFixed(2),
                cloStock.toInt().toString(),
                cloVal.toStringAsFixed(2),
              ]);
            }

            tableRows.add([
              "TOTAL",
              "-",
              totalOpStock.toInt().toString(),
              totalOpVal.toStringAsFixed(2),
              totalRecQty.toInt().toString(),
              totalRecVal.toStringAsFixed(2),
              totalIssueQty.toInt().toString(),
              totalIssueVal.toStringAsFixed(2),
              totalCloStock.toInt().toString(),
              totalCloVal.toStringAsFixed(2),
            ]);

            return [
              _buildDataTable(tableRows, colReceiveQty, colReceiveVal, colIssueQty, colIssueVal),
            ];
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Stock_Statement_${DateFormat('ddMMMyy').format(from)}',
    );
  }

  static Future<Uint8List> generateBytes({
    required CompanyProfile shop,
    required Map<String, List<Medicine>> groupedData,
    required DateTime from,
    required DateTime to,
    required String valuationBasis,
    required PharoahManager ph,
    String companySelectionType = "All",
    Set<String>? selectedCompanyIds,
    String partySelectionType = "All",
    String selectedParty = "",
    String selectedPartyId = "",
    bool deductCN = false,
    bool deductDN = false,
  }) async {
    final pdf = pw.Document();

    String colReceiveQty = deductDN ? "NET RECEIVE\nQTY" : "RECEIVE\nQTY";
    String colReceiveVal = deductDN ? "NET RECEIVE\nVALUE" : "RECEIVE\nVALUE";
    String colIssueQty = deductCN ? "NET ISSUE\nQTY" : "ISSUE\nQTY";
    String colIssueVal = deductCN ? "NET ISSUE\nVALUE" : "ISSUE\nVALUE";

    for (var companyName in groupedData.keys) {
      if (companySelectionType == "Single" && companyName != ph.companies.firstWhere((c) => c.name == companyName, orElse: () => Company(id: '', name: 'OTHERS')).name) {
        continue;
      }
      if (companySelectionType == "All" && selectedCompanyIds != null && !selectedCompanyIds.contains(companyName)) {
        continue;
      }

      List<Medicine> meds = groupedData[companyName]!;
      if (meds.isEmpty) continue;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          header: (context) => _buildHeader(shop, companyName, from, to, valuationBasis, partySelectionType, selectedParty),
          build: (context) {
            double totalOpStock = 0; double totalOpVal = 0;
            double totalRecQty = 0; double totalRecVal = 0;
            double totalIssueQty = 0; double totalIssueVal = 0;
            double totalCloStock = 0; double totalCloVal = 0;

            List<List<String>> tableRows = [];

            for (int i = 0; i < meds.length; i++) {
              var m = meds[i];
              final flow = _calculateCustomItemFlow(
                med: m, from: from, to: to, ph: ph, 
                partySelectionType: partySelectionType, 
                selectedParty: selectedParty, 
                selectedPartyId: selectedPartyId, 
                deductCN: deductCN, 
                deductDN: deductDN
              );
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

              tableRows.add([
                m.name,
                m.packing,
                opStock.toInt().toString(),
                opVal.toStringAsFixed(2),
                recQty.toInt().toString(),
                recVal.toStringAsFixed(2),
                issueQty.toInt().toString(),
                issueVal.toStringAsFixed(2),
                cloStock.toInt().toString(),
                cloVal.toStringAsFixed(2),
              ]);
            }

            tableRows.add([
              "TOTAL",
              "-",
              totalOpStock.toInt().toString(),
              totalOpVal.toStringAsFixed(2),
              totalRecQty.toInt().toString(),
              totalRecVal.toStringAsFixed(2),
              totalIssueQty.toInt().toString(),
              totalIssueVal.toStringAsFixed(2),
              totalCloStock.toInt().toString(),
              totalCloVal.toStringAsFixed(2),
            ]);

            return [
              _buildDataTable(tableRows, colReceiveQty, colReceiveVal, colIssueQty, colIssueVal),
            ];
          },
        ),
      );
    }
    return pdf.save();
  }

  static pw.Widget _buildHeader(CompanyProfile shop, String company, DateTime from, DateTime to, String basis, String partyType, String selParty) {
    String partyLabel = partyType == "Single" ? "PARTY TARGET: $selParty" : "ALL ACTIVE PARTIES";
    return pw.Column(children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, 
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start, 
            children: [
              pw.Text(shop.name.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
              pw.Text(shop.address.toUpperCase(), style: const pw.TextStyle(fontSize: 7.5)),
              pw.Text("D.L.No. : ${shop.dlNo} | GST: ${shop.gstin}", style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
            ]
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end, 
            children: [
              pw.Text("STOCK & SALES STATEMENT REPORT", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text("Period: ${DateFormat('dd/MM/yyyy').format(from)} to ${DateFormat('dd/MM/yyyy').format(to)}", style: const pw.TextStyle(fontSize: 8.5)),
              pw.Text("Valuation: $basis RATE", style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
            ]
          ),
        ]
      ),
      pw.SizedBox(height: 10),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Container(
            width: 350,
            padding: const pw.EdgeInsets.all(5),
            decoration: const pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border(left: pw.BorderSide(width: 3, color: PdfColors.indigo900))),
            child: pw.Text("COMPANY / BRAND: $company", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Container(
            width: 350,
            padding: const pw.EdgeInsets.all(5),
            decoration: const pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border(left: pw.BorderSide(width: 3, color: PdfColors.orange900))),
            child: pw.Text(partyLabel.toUpperCase(), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
          ),
        ]
      ),
      pw.SizedBox(height: 10),
    ]);
  }

  static pw.Widget _buildDataTable(List<List<String>> rows, String colRecQty, String colRecVal, String colIssQty, String colIssVal) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(180), 
        1: const pw.FixedColumnWidth(40),  
        2: const pw.FixedColumnWidth(55),  
        3: const pw.FixedColumnWidth(75),  
        4: const pw.FixedColumnWidth(55),  
        5: const pw.FixedColumnWidth(75),  
        6: const pw.FixedColumnWidth(55),  
        7: const pw.FixedColumnWidth(75),  
        8: const pw.FixedColumnWidth(55),  
        9: const pw.FixedColumnWidth(75),  
      },
      headers: [
        'PRODUCT DESCRIPTION', 'UNIT', 'OPENING\nSTOCK', 'OPENING\nVALUE', 
        colRecQty, colRecVal, colIssQty, colIssVal, 
        'CLOSING\nSTOCK', 'CLOSING\nVALUE'
      ],
      data: rows,
    );
  }
}
