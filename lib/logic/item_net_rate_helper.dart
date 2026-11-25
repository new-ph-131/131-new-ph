// FILE: lib/logic/item_net_rate_helper.dart
// Shared Two-Way Net Rate Calculator for App & Web Product Entry Dialogs

class NetRateDiscountResult {
  final double discPer;
  final double discAmt;

  const NetRateDiscountResult({
    required this.discPer,
    required this.discAmt,
  });
}

class ItemNetRateHelper {
  static double computeTaxableNetRate({
    required double qty,
    required double freeQty,
    required double rate,
    required double discRupees,
  }) {
    final double totalUnits = qty + freeQty;
    if (qty <= 0 || totalUnits <= 0) return 0.0;
    double taxable = (qty * rate) - discRupees;
    if (taxable < 0) taxable = 0.0;
    return taxable / totalUnits;
  }

  static double computeLandedNetRate({
    required double qty,
    required double freeQty,
    required double rate,
    required double discRupees,
    required double gstRate,
  }) {
    final double totalUnits = qty + freeQty;
    if (qty <= 0 || totalUnits <= 0) return 0.0;
    double taxable = (qty * rate) - discRupees;
    if (taxable < 0) taxable = 0.0;
    final double totalWithTax = taxable * (1.0 + (gstRate > 0 ? gstRate : 0.0) / 100.0);
    return totalWithTax / totalUnits;
  }

  static double reverseComputeRate({
    required double targetNetRate,
    required double qty,
    required double freeQty,
    required double discPer,
    required double gstRate,
    required bool isInclGst,
  }) {
    final double totalUnits = qty + freeQty;
    if (qty <= 0 || totalUnits <= 0 || targetNetRate <= 0) return 0.0;
    final double taxFactor =
        isInclGst ? (1.0 + (gstRate > 0 ? gstRate : 0.0) / 100.0) : 1.0;
    final double targetTaxableTotal =
        (targetNetRate * totalUnits) / (taxFactor > 0 ? taxFactor : 1.0);
    final double safeDisc = discPer.clamp(0.0, 99.99);
    final double discFactor = 1.0 - (safeDisc / 100.0);
    if (discFactor <= 0.0001) return 0.0;
    return targetTaxableTotal / (qty * discFactor);
  }

  static NetRateDiscountResult reverseComputeDiscount({
    required double targetNetRate,
    required double qty,
    required double freeQty,
    required double rate,
    required double gstRate,
    required bool isInclGst,
  }) {
    final double totalUnits = qty + freeQty;
    final double gross = qty * rate;
    if (qty <= 0 || totalUnits <= 0 || gross <= 0) {
      return const NetRateDiscountResult(discPer: 0.0, discAmt: 0.0);
    }
    final double taxFactor =
        isInclGst ? (1.0 + (gstRate > 0 ? gstRate : 0.0) / 100.0) : 1.0;
    final double targetTaxableTotal =
        (targetNetRate * totalUnits) / (taxFactor > 0 ? taxFactor : 1.0);
    final double discAmt = (gross - targetTaxableTotal).clamp(0.0, gross);
    final double discPer = (discAmt / gross) * 100.0;
    return NetRateDiscountResult(discPer: discPer, discAmt: discAmt);
  }
}
