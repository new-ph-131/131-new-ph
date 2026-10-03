import 'package:flutter_test/flutter_test.dart';
import 'package:pharoah_erp/sync_bridge/core/sync_identity_guard.dart';
import 'package:pharoah_erp/sync_bridge/core/sync_tombstone_hub.dart';
import 'package:pharoah_erp/sync_bridge/engines/universal_delta_merger.dart';
import 'package:pharoah_erp/models.dart';

void main() {
  test('E2E TEST 1: Edit Invoice on App updates in-place on Web without Duplicates', () {
    // 1. Initial Invoice created on App
    const String billId = "SALE-E2E-101";
    final List<Sale> webSalesList = [
      Sale(
        id: billId,
        billNo: "INV-101",
        partyId: "P1",
        date: DateTime.now(),
        partyName: "Sharma Medicals",
        partyGstin: "08ABCDE1234F1Z5",
        partyState: "Rajasthan",
        items: [],
        totalAmount: 500.0,
        paymentMode: "CREDIT",
      )
    ];

    // 2. User Edits Bill on App (Amount changed from 500 to 1200)
    final Map<String, dynamic> modifiedBillFromApp = {
      "id": billId, // ID strictly preserved!
      "billNo": "INV-101",
      "partyId": "P1",
      "date": DateTime.now().toIso8601String(),
      "partyName": "Sharma Medicals",
      "partyGstin": "08ABCDE1234F1Z5",
      "partyState": "Rajasthan",
      "items": [],
      "totalAmount": 1200.0,
      "paymentMode": "CREDIT",
    };

    final Set<String> tombstones = {};

    // 3. Web merges incoming delta from Cloud
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
    expect(webSalesList.length, equals(1)); // No duplicates!
    expect(webSalesList.first.totalAmount, equals(1200.0)); // In-place updated!
  });

  test('E2E TEST 2: Delete Voucher on Web purges permanently on App (No Zombie Resurrect)', () {
    const String voucherId = "VCT-999";
    final List<Voucher> appVouchersList = [
      Voucher(
        id: voucherId,
        type: "RECEIPT",
        voucherNo: "RCT-999",
        date: DateTime.now(),
        partyId: "P1",
        partyName: "Sharma Medicals",
        amount: 800.0,
        paymentMode: "Cash",
      )
    ];

    // Web deletes the voucher and marks it in tombstones
    final Set<String> tombstones = {voucherId, "RCT-999"};

    // Cloud still holds old data, but App pulls with Tombstone Shield active
    final List<dynamic> oldCloudData = [
      {
        "id": voucherId,
        "type": "RECEIPT",
        "voucherNo": "RCT-999",
        "date": DateTime.now().toIso8601String(),
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
    expect(appVouchersList.isEmpty, isTrue); // Purged from App, 0 zombie records!
  });
}
