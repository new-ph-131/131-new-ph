import 'package:flutter_test/flutter_test.dart';
import 'package:pharoah_erp/logic/item_net_rate_helper.dart';

void main() {
  test('Computes Taxable & Landed Net Rate accurately with Free Qty and Discount', () {
    // 10 + 1 Free @ Rs 100, 0% disc, 12% GST
    final taxNet = ItemNetRateHelper.computeTaxableNetRate(
      qty: 10,
      freeQty: 1,
      rate: 100,
      discRupees: 0,
    );
    expect(taxNet, closeTo(90.909, 0.001));

    final landedNet = ItemNetRateHelper.computeLandedNetRate(
      qty: 10,
      freeQty: 1,
      rate: 100,
      discRupees: 0,
      gstRate: 12,
    );
    expect(landedNet, closeTo(101.818, 0.001));

    // With 10% discount (Rs 100 off -> Rs 900 taxable / 11 = 81.818)
    final discTaxNet = ItemNetRateHelper.computeTaxableNetRate(
      qty: 10,
      freeQty: 1,
      rate: 100,
      discRupees: 100,
    );
    expect(discTaxNet, closeTo(81.818, 0.001));
  });

  test('Reverse computes Unit Rate from Net Rate (Excl. GST and Incl. GST)', () {
    final r1 = ItemNetRateHelper.reverseComputeRate(
      targetNetRate: 90.91,
      qty: 10,
      freeQty: 1,
      discPer: 0,
      gstRate: 12,
      isInclGst: false,
    );
    expect(r1, closeTo(100.0, 0.01));

    final r2 = ItemNetRateHelper.reverseComputeRate(
      targetNetRate: 101.82,
      qty: 10,
      freeQty: 1,
      discPer: 0,
      gstRate: 12,
      isInclGst: true,
    );
    expect(r2, closeTo(100.0, 0.01));

    // With 10% disc intact
    final r3 = ItemNetRateHelper.reverseComputeRate(
      targetNetRate: 81.82,
      qty: 10,
      freeQty: 1,
      discPer: 10,
      gstRate: 12,
      isInclGst: false,
    );
    expect(r3, closeTo(100.0, 0.01));
  });

  test('Reverse computes Discount % & Rs from Net Rate while keeping Unit Rate fixed', () {
    final d1 = ItemNetRateHelper.reverseComputeDiscount(
      targetNetRate: 85.0,
      qty: 10,
      freeQty: 0,
      rate: 100,
      gstRate: 12,
      isInclGst: false,
    );
    expect(d1.discAmt, closeTo(150.0, 0.01));
    expect(d1.discPer, closeTo(15.0, 0.01));

    // With Free Qty 10+1 at Rate 100, target landed net = 90.91 (12% GST)
    // Taxable needed = 90.91 * 11 / 1.12 = 892.866 -> Disc = 107.134 (10.71%)
    final d2 = ItemNetRateHelper.reverseComputeDiscount(
      targetNetRate: 90.91,
      qty: 10,
      freeQty: 1,
      rate: 100,
      gstRate: 12,
      isInclGst: true,
    );
    expect(d2.discAmt, closeTo(107.13, 0.05));
    expect(d2.discPer, closeTo(10.71, 0.05));
  });
}
