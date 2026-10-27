// FILE: lib/gst/gst_diary/gst_diary_calculator.dart
import 'package:intl/intl.dart';
import '../../models.dart';
import 'gst_diary_models.dart';

class GstDiaryCalculationResult {
  final List<GstProductDifferenceRow> productRows;
  final List<GstPartyDifferenceRow> partyRows;
  final List<GstBillDifferenceRow> billRows; // All bills matching period/party/status filter
  final Set<String> activeSelectedBillIds; // Bills currently ticked (✓) for tax calculation

  final double totalPurchaseTaxable;
  final double totalPurchaseItc;
  final double totalSaleTaxable;
  final double totalSaleOutputGst;
  final double netGstPayable; // positive = payable, negative = carry forward surplus

  final int totalPurchaseBills;
  final int totalSaleBills;
  final int selectedPurchaseBillsCount;
  final int selectedSaleBillsCount;
  final int totalDeductedBills;
  final int totalPendingBills;
  final double totalDeductedTax;

  GstDiaryCalculationResult({
    required this.productRows,
    required this.partyRows,
    required this.billRows,
    required this.activeSelectedBillIds,
    required this.totalPurchaseTaxable,
    required this.totalPurchaseItc,
    required this.totalSaleTaxable,
    required this.totalSaleOutputGst,
    required this.netGstPayable,
    required this.totalPurchaseBills,
    required this.totalSaleBills,
    this.selectedPurchaseBillsCount = 0,
    this.selectedSaleBillsCount = 0,
    this.totalDeductedBills = 0,
    this.totalPendingBills = 0,
    this.totalDeductedTax = 0.0,
  });
}

class GstDiaryCalculator {
  static bool _isDateInRange(DateTime d, DateTime from, DateTime to) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  static GstDiaryCalculationResult compute({
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<Party> parties,
    required DateTime fromDate,
    required DateTime toDate,
    Set<String> selectedPurchasePartyIds = const {},
    Set<String> selectedSalePartyIds = const {},
    List<GstDiarySession> existingSessions = const [],
    String deductionFilter = 'ALL', // 'ALL', 'PENDING', 'DEDUCTED'
    Set<String>? customSelectedBillIds, // If non-null, ONLY ticked bills are calculated!
    Set<String>? customSelectedProductKeys, // If non-null, ONLY ticked products are summed in Product tab
    Set<String>? customSelectedPartyKeys, // If non-null, ONLY ticked parties are summed in Party tab
  }) {
    // 0. Build Party Fast Lookup for GSTIN and ID matching
    final Map<String, String> partyGstLookup = {};
    for (var pt in parties) {
      if (pt.id.isNotEmpty) partyGstLookup[pt.id] = pt.gst;
      if (pt.name.isNotEmpty) {
        partyGstLookup[pt.name.trim().toLowerCase()] = pt.gst;
      }
    }

    // 0b. Build Map of already deducted bill IDs from existing sessions
    final Map<String, GstDiarySession> deductedBillsMap = {};
    for (var sess in existingSessions) {
      if (sess.isDeleted == 1) continue;
      if (sess.status == 'DEDUCTED' || sess.status == 'SETTLED') {
        for (var bId in sess.includedBillIds) {
          deductedBillsMap[bId] = sess;
        }
      }
    }

    // 1. Filter Purchases matching period, party, and deduction status (ignore ghost/0-amount empty records)
    final allMatchingPurchases = purchases.where((p) {
      if (p.isDeleted == 1 || p.gstStatus == 'Cancelled' || p.gstStatus == 'Deleted') return false;
      if (p.id.startsWith('SESS_') || p.id == 'APP_CONFIG_MASTER') return false;
      if (p.billNo.trim().isEmpty && p.internalNo.trim().isEmpty) return false;
      if (p.items.isEmpty && p.totalAmount <= 0) return false;
      if (!_isDateInRange(p.date, fromDate, toDate)) return false;
      if (selectedPurchasePartyIds.isNotEmpty) {
        final matchesId = selectedPurchasePartyIds.contains(p.partyId);
        final matchesName = selectedPurchasePartyIds.contains(p.distributorName);
        if (!matchesId && !matchesName) return false;
      }
      final isDeducted = deductedBillsMap.containsKey(p.id);
      if (deductionFilter == 'PENDING' && isDeducted) return false;
      if (deductionFilter == 'DEDUCTED' && !isDeducted) return false;
      return true;
    }).toList();

    // 2. Filter Sales matching period, party, and deduction status (ignore ghost/0-amount empty records)
    final allMatchingSales = sales.where((s) {
      if (s.isDeleted == 1 || s.status == 'Cancelled' || s.status == 'Deleted') return false;
      if (s.id.startsWith('SESS_') || s.id == 'APP_CONFIG_MASTER') return false;
      if (s.billNo.trim().isEmpty) return false;
      if (s.items.isEmpty && s.totalAmount <= 0) return false;
      if (!_isDateInRange(s.date, fromDate, toDate)) return false;
      if (selectedSalePartyIds.isNotEmpty) {
        final matchesId = selectedSalePartyIds.contains(s.partyId);
        final matchesName = selectedSalePartyIds.contains(s.partyName);
        if (!matchesId && !matchesName) return false;
      }
      final isDeducted = deductedBillsMap.containsKey(s.id);
      if (deductionFilter == 'PENDING' && isDeducted) return false;
      if (deductionFilter == 'DEDUCTED' && !isDeducted) return false;
      return true;
    }).toList();

    // 3. Build full Bill-wise rows (so Bill-wise table always displays all candidate bills with checkboxes)
    final DateFormat formatter = DateFormat('dd/MM/yyyy');
    final List<GstBillDifferenceRow> billRows = [];
    final Set<String> allCandidateBillIds = {};
    int deductedCount = 0;
    int pendingCount = 0;
    double deductedTax = 0.0;

    for (var s in allMatchingSales) {
      allCandidateBillIds.add(s.id);
      double gst = 0.0;
      double taxable = 0.0;
      for (var it in s.items) {
        taxable += (it.rate * it.qty) - it.discountRupees;
        gst += (it.cgst + it.sgst + it.igst);
      }
      final sGstin = s.partyGstin.isNotEmpty ? s.partyGstin : (partyGstLookup[s.partyId] ?? '');
      final sessionMatch = deductedBillsMap[s.id];
      final isDeducted = sessionMatch != null;
      if (isDeducted) {
        deductedCount++;
        deductedTax += gst;
      } else {
        pendingCount++;
      }

      billRows.add(GstBillDifferenceRow(
        billId: s.id,
        billNo: s.billNo,
        date: formatter.format(s.date),
        partyName: s.partyName,
        partyGstin: sGstin,
        voucherType: 'SALE',
        taxableAmount: taxable,
        gstAmount: gst,
        netBillAmount: s.totalAmount,
        isDeducted: isDeducted,
        deductedSessionName: sessionMatch?.title ?? '',
        deductedSessionId: sessionMatch?.id ?? '',
      ));
    }

    for (var p in allMatchingPurchases) {
      allCandidateBillIds.add(p.id);
      double gst = 0.0;
      double taxable = 0.0;
      for (var it in p.items) {
        final t = it.purchaseRate * it.qty;
        taxable += t;
        gst += (t * (it.gstRate / 100));
      }
      final purGstin = partyGstLookup[p.partyId] ?? partyGstLookup[p.distributorName.trim().toLowerCase()] ?? '';
      final sessionMatch = deductedBillsMap[p.id];
      final isDeducted = sessionMatch != null;
      if (isDeducted) {
        deductedCount++;
        deductedTax += gst;
      } else {
        pendingCount++;
      }

      billRows.add(GstBillDifferenceRow(
        billId: p.id,
        billNo: p.billNo,
        date: formatter.format(p.date),
        partyName: p.distributorName,
        partyGstin: purGstin,
        voucherType: 'PURCHASE',
        taxableAmount: taxable,
        gstAmount: gst,
        netBillAmount: p.totalAmount,
        isDeducted: isDeducted,
        deductedSessionName: sessionMatch?.title ?? '',
        deductedSessionId: sessionMatch?.id ?? '',
      ));
    }

    billRows.sort((a, b) => b.date.compareTo(a.date));

    // 4. Determine which bills are actively ticked (✓) for tax calculation
    final Set<String> effectiveSelectedBillIds = customSelectedBillIds != null
        ? customSelectedBillIds.intersection(allCandidateBillIds)
        : allCandidateBillIds;

    final filteredPurchases = allMatchingPurchases
        .where((p) => effectiveSelectedBillIds.contains(p.id))
        .toList();
    final filteredSales = allMatchingSales
        .where((s) => effectiveSelectedBillIds.contains(s.id))
        .toList();

    // 5. Aggregate Product-wise stats strictly from ticked bills
    final Map<String, _ProductStat> productMap = {};

    for (var p in filteredPurchases) {
      for (var it in p.items) {
        final key = (it.medicineID.isNotEmpty ? it.medicineID : it.name.trim().toLowerCase());
        final stat = productMap.putIfAbsent(key, () => _ProductStat(
          id: it.medicineID,
          name: it.name,
          packing: it.packing,
          hsn: it.hsn,
        ));
        final qty = it.qty + it.freeQty;
        final taxable = it.purchaseRate * it.qty;
        final gst = taxable * (it.gstRate / 100);

        stat.purchaseQty += qty;
        stat.purchaseTaxable += taxable;
        stat.purchaseGst += gst;
      }
    }

    for (var s in filteredSales) {
      for (var it in s.items) {
        final key = (it.medicineID.isNotEmpty ? it.medicineID : it.name.trim().toLowerCase());
        final stat = productMap.putIfAbsent(key, () => _ProductStat(
          id: it.medicineID,
          name: it.name,
          packing: it.packing,
          hsn: it.hsn,
        ));
        final qty = it.qty + it.freeQty;
        final taxable = (it.rate * it.qty) - it.discountRupees;
        final gst = it.cgst + it.sgst + it.igst;

        stat.saleQty += qty;
        stat.saleTaxable += taxable;
        stat.saleGst += gst;
      }
    }

    final List<GstProductDifferenceRow> productRows = [];
    double totalPurTaxable = 0.0;
    double totalPurItc = 0.0;
    double totalSalTaxable = 0.0;
    double totalSalOutput = 0.0;

    for (var stat in productMap.values) {
      final avgPurGst = stat.purchaseQty > 0 ? (stat.purchaseGst / stat.purchaseQty) : 0.0;
      final avgSalGst = stat.saleQty > 0 ? (stat.saleGst / stat.saleQty) : 0.0;
      final eligibleItc = avgPurGst * stat.saleQty;
      final diff = stat.saleGst - eligibleItc;

      final row = GstProductDifferenceRow(
        productId: stat.id,
        productName: stat.name,
        packing: stat.packing,
        hsn: stat.hsn,
        purchaseQty: stat.purchaseQty,
        purchaseTaxable: stat.purchaseTaxable,
        purchaseGst: stat.purchaseGst,
        avgPurchaseGstPerUnit: avgPurGst,
        saleQty: stat.saleQty,
        saleTaxable: stat.saleTaxable,
        saleGst: stat.saleGst,
        avgSaleGstPerUnit: avgSalGst,
        eligibleItcForSoldUnits: eligibleItc,
        gstDifference: diff,
      );
      productRows.add(row);

      final bool isProductTicked = customSelectedProductKeys == null ||
          customSelectedProductKeys.contains(row.selectionKey);
      if (isProductTicked && customSelectedPartyKeys == null) {
        totalPurTaxable += stat.purchaseTaxable;
        totalPurItc += stat.purchaseGst;
        totalSalTaxable += stat.saleTaxable;
        totalSalOutput += stat.saleGst;
      }
    }

    productRows.sort((a, b) => b.saleGst.compareTo(a.saleGst));

    // 6. Aggregate Party-wise stats strictly from ticked bills
    final Map<String, GstPartyDifferenceRow> partyRowMap = {};

    for (var p in filteredPurchases) {
      final pKey = 'PUR_${p.partyId.isNotEmpty ? p.partyId : p.distributorName.trim().toLowerCase()}';
      final pGstLookup = partyGstLookup[p.partyId] ?? partyGstLookup[p.distributorName.trim().toLowerCase()] ?? '';
      double pTaxable = 0.0;
      double pGst = 0.0;
      for (var it in p.items) {
        final t = it.purchaseRate * it.qty;
        pTaxable += t;
        pGst += (t * (it.gstRate / 100));
      }

      final existing = partyRowMap[pKey];
      if (existing == null) {
        partyRowMap[pKey] = GstPartyDifferenceRow(
          partyId: p.partyId.isNotEmpty ? p.partyId : p.distributorName,
          partyName: p.distributorName,
          gstin: pGstLookup,
          type: 'PURCHASE_SUPPLIER',
          totalBills: 1,
          taxableAmount: pTaxable,
          cgst: pGst / 2,
          sgst: pGst / 2,
          igst: 0.0,
          totalGst: pGst,
        );
      } else {
        partyRowMap[pKey] = GstPartyDifferenceRow(
          partyId: existing.partyId,
          partyName: existing.partyName,
          gstin: existing.gstin.isNotEmpty ? existing.gstin : pGstLookup,
          type: 'PURCHASE_SUPPLIER',
          totalBills: existing.totalBills + 1,
          taxableAmount: existing.taxableAmount + pTaxable,
          cgst: existing.cgst + (pGst / 2),
          sgst: existing.sgst + (pGst / 2),
          igst: existing.igst,
          totalGst: existing.totalGst + pGst,
        );
      }
    }

    for (var s in filteredSales) {
      final sKey = 'SAL_${s.partyId.isNotEmpty ? s.partyId : s.partyName.trim().toLowerCase()}';
      final sGstin = s.partyGstin.isNotEmpty ? s.partyGstin : (partyGstLookup[s.partyId] ?? partyGstLookup[s.partyName.trim().toLowerCase()] ?? '');
      double sTaxable = 0.0;
      double sCgst = 0.0;
      double sSgst = 0.0;
      double sIgst = 0.0;
      for (var it in s.items) {
        sTaxable += (it.rate * it.qty) - it.discountRupees;
        sCgst += it.cgst;
        sSgst += it.sgst;
        sIgst += it.igst;
      }
      final totalGst = sCgst + sSgst + sIgst;

      final existing = partyRowMap[sKey];
      if (existing == null) {
        partyRowMap[sKey] = GstPartyDifferenceRow(
          partyId: s.partyId.isNotEmpty ? s.partyId : s.partyName,
          partyName: s.partyName,
          gstin: sGstin,
          type: 'SALE_CUSTOMER',
          totalBills: 1,
          taxableAmount: sTaxable,
          cgst: sCgst,
          sgst: sSgst,
          igst: sIgst,
          totalGst: totalGst,
        );
      } else {
        partyRowMap[sKey] = GstPartyDifferenceRow(
          partyId: existing.partyId,
          partyName: existing.partyName,
          gstin: existing.gstin.isNotEmpty ? existing.gstin : sGstin,
          type: 'SALE_CUSTOMER',
          totalBills: existing.totalBills + 1,
          taxableAmount: existing.taxableAmount + sTaxable,
          cgst: existing.cgst + sCgst,
          sgst: existing.sgst + sSgst,
          igst: existing.igst + sIgst,
          totalGst: existing.totalGst + totalGst,
        );
      }
    }

    final partyRows = partyRowMap.values.toList();
    partyRows.sort((a, b) => b.totalGst.compareTo(a.totalGst));

    if (customSelectedPartyKeys != null) {
      totalPurTaxable = 0.0;
      totalPurItc = 0.0;
      totalSalTaxable = 0.0;
      totalSalOutput = 0.0;
      for (var pr in partyRows) {
        if (customSelectedPartyKeys.contains(pr.selectionKey)) {
          if (pr.type == 'PURCHASE_SUPPLIER') {
            totalPurTaxable += pr.taxableAmount;
            totalPurItc += pr.totalGst;
          } else {
            totalSalTaxable += pr.taxableAmount;
            totalSalOutput += pr.totalGst;
          }
        }
      }
    }

    final netPayable = totalSalOutput - totalPurItc;

    return GstDiaryCalculationResult(
      productRows: productRows,
      partyRows: partyRows,
      billRows: billRows,
      activeSelectedBillIds: effectiveSelectedBillIds,
      totalPurchaseTaxable: totalPurTaxable,
      totalPurchaseItc: totalPurItc,
      totalSaleTaxable: totalSalTaxable,
      totalSaleOutputGst: totalSalOutput,
      netGstPayable: netPayable,
      totalPurchaseBills: allMatchingPurchases.length,
      totalSaleBills: allMatchingSales.length,
      selectedPurchaseBillsCount: filteredPurchases.length,
      selectedSaleBillsCount: filteredSales.length,
      totalDeductedBills: deductedCount,
      totalPendingBills: pendingCount,
      totalDeductedTax: deductedTax,
    );
  }
}

class _ProductStat {
  final String id;
  final String name;
  final String packing;
  final String hsn;

  double purchaseQty = 0.0;
  double purchaseTaxable = 0.0;
  double purchaseGst = 0.0;

  double saleQty = 0.0;
  double saleTaxable = 0.0;
  double saleGst = 0.0;

  _ProductStat({
    required this.id,
    required this.name,
    required this.packing,
    required this.hsn,
  });
}
