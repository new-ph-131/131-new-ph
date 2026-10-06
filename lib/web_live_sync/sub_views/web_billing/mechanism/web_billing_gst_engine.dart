// FILE: lib/web_live_sync/sub_views/web_billing/mechanism/web_billing_gst_engine.dart
import '../../web_models.dart';

/// BillGstSummary: Immutable Data Capsule containing exact Section 15 GST calculations
class BillGstSummary {
  final double grossTaxable;
  final double extraDiscount;
  final double netTaxable;
  final double totalCGST;
  final double totalSGST;
  final double totalIGST;
  final double totalTax;
  final double rawGrandTotal;
  final double finalGrandTotal;
  final double roundOff;
  final Map<double, double> slabTaxable;
  final Map<double, double> slabTax;

  const BillGstSummary({
    required this.grossTaxable,
    required this.extraDiscount,
    required this.netTaxable,
    required this.totalCGST,
    required this.totalSGST,
    required this.totalIGST,
    required this.totalTax,
    required this.rawGrandTotal,
    required this.finalGrandTotal,
    required this.roundOff,
    this.slabTaxable = const {},
    this.slabTax = const {},
  });
}

/// WebBillingGstEngine: Centralized Section 15 GST Calculation Engine for Web Workstations
class WebBillingGstEngine {
  static BillGstSummary calculate({
    required List<BillItem> items,
    required double extraDiscount,
    required bool isLocal,
  }) {
    if (items.isEmpty) {
      return const BillGstSummary(
        grossTaxable: 0.0,
        extraDiscount: 0.0,
        netTaxable: 0.0,
        totalCGST: 0.0,
        totalSGST: 0.0,
        totalIGST: 0.0,
        totalTax: 0.0,
        rawGrandTotal: 0.0,
        finalGrandTotal: 0.0,
        roundOff: 0.0,
      );
    }

    double totalGrossTaxable = 0.0;
    List<double> itemGrossTaxableList = [];

    for (var item in items) {
      double gross = (item.qty * item.rate) - item.discountRupees;
      if (gross < 0) gross = 0.0;
      itemGrossTaxableList.add(gross);
      totalGrossTaxable += gross;
    }

    double validExtraDiscount = extraDiscount;
    if (validExtraDiscount < 0) validExtraDiscount = 0.0;
    if (validExtraDiscount > totalGrossTaxable) validExtraDiscount = totalGrossTaxable;

    double discountRatio = totalGrossTaxable > 0 ? (validExtraDiscount / totalGrossTaxable) : 0.0;
    double netTaxableSum = totalGrossTaxable - validExtraDiscount;

    double calcCGST = 0.0;
    double calcSGST = 0.0;
    double calcIGST = 0.0;
    Map<double, double> slabTaxable = {};
    Map<double, double> slabTax = {};

    for (int i = 0; i < items.length; i++) {
      var item = items[i];
      double itemGrossTaxable = itemGrossTaxableList[i];
      double itemNetTaxable = itemGrossTaxable * (1.0 - discountRatio);
      double gstRate = item.gstRate;
      double itemTax = itemNetTaxable * (gstRate / 100.0);

      slabTaxable[gstRate] = (slabTaxable[gstRate] ?? 0.0) + itemNetTaxable;
      slabTax[gstRate] = (slabTax[gstRate] ?? 0.0) + itemTax;

      if (isLocal) {
        calcCGST += itemTax / 2.0;
        calcSGST += itemTax / 2.0;
      } else {
        calcIGST += itemTax;
      }
    }

    double totalTax = calcCGST + calcSGST + calcIGST;
    double rawGrandTotal = netTaxableSum + totalTax;
    double finalGrandTotal = rawGrandTotal.roundToDouble();
    double roundOff = double.parse((finalGrandTotal - rawGrandTotal).toStringAsFixed(2));

    return BillGstSummary(
      grossTaxable: double.parse(totalGrossTaxable.toStringAsFixed(2)),
      extraDiscount: double.parse(validExtraDiscount.toStringAsFixed(2)),
      netTaxable: double.parse(netTaxableSum.toStringAsFixed(2)),
      totalCGST: double.parse(calcCGST.toStringAsFixed(2)),
      totalSGST: double.parse(calcSGST.toStringAsFixed(2)),
      totalIGST: double.parse(calcIGST.toStringAsFixed(2)),
      totalTax: double.parse(totalTax.toStringAsFixed(2)),
      rawGrandTotal: double.parse(rawGrandTotal.toStringAsFixed(2)),
      finalGrandTotal: finalGrandTotal,
      roundOff: roundOff,
      slabTaxable: slabTaxable,
      slabTax: slabTax,
    );
  }
}
