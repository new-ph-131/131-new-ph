import 'package:flutter_test/flutter_test.dart';
import 'package:pharoah_erp/sync_bridge/engines/universal_delta_merger.dart';
import 'package:pharoah_erp/models.dart';

void main() {
  test('E2E TEST 1: Edit Invoice on App updates in-place on Web without Duplicates', () {
    const String billId = "SALE-E2E-MERGE-TEST-101";
    final List<Sale> webSalesList = [
      Sale(
        id: billId,
        billNo: "INV-E2E-MERGE-TEST-101",
        partyId: "P1",
        date: DateTime.utc(2025, 1, 1),
        partyName: "Sharma Medicals",
        partyGstin: "08ABCDE1234F1Z5",
        partyState: "Rajasthan",
        items: [],
        totalAmount: 500.0,
        paymentMode: "CREDIT",
      )
    ];

    final Map<String, dynamic> modifiedBillFromApp = {
      "id": billId,
      "billNo": "INV-E2E-MERGE-TEST-101",
      "partyId": "P1",
      "date": DateTime.utc(2025, 1, 1).toIso8601String(),
      "partyName": "Sharma Medicals",
      "partyGstin": "08ABCDE1234F1Z5",
      "partyState": "Rajasthan",
      "items": [],
      "totalAmount": 1200.0,
      "paymentMode": "CREDIT",
      "updatedAt": 2000,
      "version": 2,
    };

    final Set<String> tombstones = {};
    final bool changed = UniversalDeltaMerger.mergeEntityList<Sale>(
      cloudList: [modifiedBillFromApp],
      localList: webSalesList,
      tombstones: tombstones,
      getId: (s) => s.id,
      getRefNo: (s) => s.billNo,
      fromMap: (m) => Sale.fromMap(m),
      toMap: (s) => s.toMap(),
    );

    expect(changed, isTrue);
    expect(webSalesList.length, equals(1));
    expect(webSalesList.first.totalAmount, equals(1200.0));
  });

  test('E2E TEST 2: Delete Voucher on Web purges permanently on App (No Zombie Resurrect)', () {
    const String voucherId = "VCT-999";
    final List<Voucher> appVouchersList = [
      Voucher(
        id: voucherId,
        type: "RECEIPT",
        voucherNo: "RCT-999",
        date: DateTime.utc(2025, 1, 1),
        partyId: "P1",
        partyName: "Sharma Medicals",
        amount: 800.0,
        paymentMode: "Cash",
      )
    ];

    final Set<String> tombstones = {voucherId, "RCT-999"};
    final List<dynamic> oldCloudData = [
      {
        "id": voucherId,
        "type": "RECEIPT",
        "voucherNo": "RCT-999",
        "date": DateTime.utc(2025, 1, 1).toIso8601String(),
        "partyId": "P1",
        "partyName": "Sharma Medicals",
        "amount": 800.0,
        "paymentMode": "Cash",
      }
    ];

    final bool changed = UniversalDeltaMerger.mergeEntityList<Voucher>(
      cloudList: oldCloudData,
      localList: appVouchersList,
      tombstones: tombstones,
      getId: (v) => v.id,
      getRefNo: (v) => v.voucherNo,
      fromMap: (m) => Voucher.fromMap(m),
      toMap: (v) => v.toMap(),
    );

    expect(changed, isTrue);
    expect(appVouchersList.isEmpty, isTrue);
  });
}
