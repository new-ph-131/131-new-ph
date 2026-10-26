// FILE: lib/gst/gst_diary/gst_diary_calculator.dart
import 'package:intl/intl.dart';
import '../../models.dart';
import 'gst_diary_models.dart';

class GstDiaryCalculationResult {
  final List<GstProductDifferenceRow> productRows;
  final List<GstPartyDifferenceRow> partyRows;
  final List<GstBillDifferenceRow> billRows;
  final double totalPurchaseTaxable;
  final double totalPurchaseItc;
  final double totalSaleTaxable;
  final double totalSaleOutputGst;
  final double netGstPayable; // positive = payable, negative = carry forward surplus
  final int totalPurchaseBills;
  final int totalSaleBills;

  GstDiaryCalculationResult({
    required this.productRows,
    required this.partyRows,
    required this.billRows,
    required this.totalPurchaseTaxable,
    required this.totalPurchaseItc,
    required this.totalSaleTaxable,
    required this.totalSaleOutputGst,
    required this.netGstPayable,
    required this.totalPurchaseBills,
    required this.totalSaleBills,
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
  }) {
    // 0. Build Party Fast Lookup for GSTIN and ID matching
    final Map<String, String> partyGstLookup = {};
    for (var pt in parties) {
      if (pt.id.isNotEmpty) partyGstLookup[pt.id] = pt.gst;
      if (pt.name.isNotEmpty) {
        partyGstLookup[pt.name.trim().toLowerCase()] = pt.gst;
      }
    }

    // 1. Filter Purchases
    final filteredPurchases = purchases.where((p) {
      if (p.isDeleted == 1 || p.gstStatus == 'Cancelled') return false;
      if (!_isDateInRange(p.date, fromDate, toDate)) return false;
      if (selectedPurchasePartyIds.isNotEmpty) {
        final matchesId = selectedPurchasePartyIds.contains(p.partyId);
        final matchesName = selectedPurchasePartyIds.contains(p.distributorName);
        if (!matchesId && !matchesName) return false;
      }
      return true;
    }).toList();

    // 2. Filter Sales
    final filteredSales = sales.where((s) {
      if (s.isDeleted == 1 || s.status == 'Cancelled') return false;
      if (!_isDateInRange(s.date, fromDate, toDate)) return false;
      if (selectedSalePartyIds.isNotEmpty) {
        final matchesId = selectedSalePartyIds.contains(s.partyId);
        final matchesName = selectedSalePartyIds.contains(s.partyName);
        if (!matchesId && !matchesName) return false;
      }
      return true;
    }).toList();

    // 3. Aggregate Product-wise stats
    final Map<String, _ProductStat> productMap = {};

    // Process Purchases
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

    // Process Sales
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

    // Convert productMap to List<GstProductDifferenceRow>
    final List<GstProductDifferenceRow> productRows = [];
    double totalPurTaxable = 0.0;
    double totalPurItc = 0.0;
    double totalSalTaxable = 0.0;
    double totalSalOutput = 0.0;

    for (var stat in productMap.values) {
      final avgPurGst = stat.purchaseQty > 0 ? (stat.purchaseGst / stat.purchaseQty) : 0.0;
      final avgSalGst = stat.saleQty > 0 ? (stat.saleGst / stat.saleQty) : 0.0;

      // Weighted-average ITC eligible for units sold in this period
      final eligibleItc = avgPurGst * stat.saleQty;
      final diff = stat.saleGst - eligibleItc;

      totalPurTaxable += stat.purchaseTaxable;
      totalPurItc += stat.purchaseGst;
      totalSalTaxable += stat.saleTaxable;
      totalSalOutput += stat.saleGst;

      productRows.add(GstProductDifferenceRow(
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
      ));
    }
    productRows.sort((a, b) => b.saleGst.compareTo(a.saleGst));

    // 4. Aggregate Party-wise stats
    final Map<String, GstPartyDifferenceRow> partyRowMap = {};

    // Purchase Suppliers
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

    // Sale Customers
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

    // 5. Aggregate Bill-wise rows
    final DateFormat formatter = DateFormat('dd/MM/yyyy');
    final List<GstBillDifferenceRow> billRows = [];
    for (var s in filteredSales) {
      double gst = 0.0;
      double taxable = 0.0;
      for (var it in s.items) {
        taxable += (it.rate * it.qty) - it.discountRupees;
        gst += (it.cgst + it.sgst + it.igst);
      }
      final sGstin = s.partyGstin.isNotEmpty ? s.partyGstin : (partyGstLookup[s.partyId] ?? '');
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
      ));
    }

    for (var p in filteredPurchases) {
      double gst = 0.0;
      double taxable = 0.0;
      for (var it in p.items) {
        final t = it.purchaseRate * it.qty;
        taxable += t;
        gst += (t * (it.gstRate / 100));
      }
      final purGstin = partyGstLookup[p.partyId] ?? partyGstLookup[p.distributorName.trim().toLowerCase()] ?? '';
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
      ));
    }

    billRows.sort((a, b) => b.date.compareTo(a.date));

    final netPayable = totalSalOutput - totalPurItc;

    return GstDiaryCalculationResult(
      productRows: productRows,
      partyRows: partyRows,
      billRows: billRows,
      totalPurchaseTaxable: totalPurTaxable,
      totalPurchaseItc: totalPurItc,
      totalSaleTaxable: totalSalTaxable,
      totalSaleOutputGst: totalSalOutput,
      netGstPayable: netPayable,
      totalPurchaseBills: filteredPurchases.length,
      totalSaleBills: filteredSales.length,
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
