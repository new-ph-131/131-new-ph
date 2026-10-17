import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharoah_erp/sync_bridge/engines/universal_delta_merger.dart';
import 'package:pharoah_erp/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

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

  test('E2E TEST 3: Reborn Bill & Number Renaming (INV-1 to INV-300) without Duplicates', () {
    const String billId = "SALE-REBORN-101";
    final List<Sale> localSalesList = [];
    final List<dynamic> cloudList = [
      {
        "id": billId,
        "billNo": "INV-300",
        "partyId": "P1",
        "date": DateTime.utc(2025, 1, 1).toIso8601String(),
        "partyName": "Sharma Medicals",
        "partyGstin: ": "08ABCDE1234F1Z5",
        "partyState": "Rajasthan",
        "items": [],
        "totalAmount": 900.0,
        "paymentMode": "CREDIT",
        "updatedAt": 3000,
        "version": 2,
      }
    ];

    final Set<String> tombstones = {"INV-300"}; // "INV-300" was previously tombstoned but is reborn with higher version

    final bool changed = UniversalDeltaMerger.mergeEntityList<Sale>(
      cloudList: cloudList,
      localList: localSalesList,
      tombstones: tombstones,
      getId: (s) => s.id,
      getRefNo: (s) => s.billNo,
      fromMap: (m) => Sale.fromMap(m),
      toMap: (s) => s.toMap(),
    );

    expect(changed, isTrue);
    expect(localSalesList.length, equals(1));
    expect(localSalesList.first.billNo, equals("INV-300"));
    expect(tombstones.contains("INV-300"), isFalse); // Stale tombstone revoked upon rebirth
  });

  test('E2E TEST 4: Purchase Full Lifecycle (Create -> Modify -> Delete -> Recreate PUR-1 & Multi-Supplier Same BillNo)', () {
    final List<Purchase> purchasesList = [];
    final Set<String> tombstones = {};

    // 1. Create PUR-1 (Supplier P1, Bill 105, Total 2500, v1)
    final Map<String, dynamic> pur1Create = {
      "id": "PUR-APP-1001",
      "internalNo": "PUR-1",
      "billNo": "105",
      "partyId": "P1",
      "distributorName": "Apex Pharma",
      "date": DateTime.utc(2025, 1, 10).toIso8601String(),
      "entryDate": DateTime.utc(2025, 1, 10).toIso8601String(),
      "items": [],
      "totalAmount": 2500.0,
      "paymentMode": "CREDIT",
      "updatedAt": 1000,
      "version": 1,
    };

    UniversalDeltaMerger.mergeEntityList<Purchase>(
      cloudList: [pur1Create],
      localList: purchasesList,
      tombstones: tombstones,
      getId: (e) => e.id,
      getRefNo: (e) => "${e.partyId}_${e.billNo}",
      getCompositeKey: (e) => "${e.partyId}_${e.billNo}",
      getCloudCompositeKey: (m) => "${m['partyId']}_${m['billNo']}",
      fromMap: (m) => Purchase.fromMap(m),
      toMap: (e) => e.toMap(),
    );
    expect(purchasesList.length, equals(1));
    expect(purchasesList.first.totalAmount, equals(2500.0));

    // 2. Modify PUR-1 (Total 3800, v2)
    final Map<String, dynamic> pur1Modify = {
      ...pur1Create,
      "totalAmount": 3800.0,
      "updatedAt": 2000,
      "version": 2,
    };
    UniversalDeltaMerger.mergeEntityList<Purchase>(
      cloudList: [pur1Modify],
      localList: purchasesList,
      tombstones: tombstones,
      getId: (e) => e.id,
      getRefNo: (e) => "${e.partyId}_${e.billNo}",
      getCompositeKey: (e) => "${e.partyId}_${e.billNo}",
      getCloudCompositeKey: (m) => "${m['partyId']}_${m['billNo']}",
      fromMap: (m) => Purchase.fromMap(m),
      toMap: (e) => e.toMap(),
    );
    expect(purchasesList.length, equals(1));
    expect(purchasesList.first.totalAmount, equals(3800.0));
    expect(purchasesList.first.version, equals(2));

    // 3. Delete PUR-1 & verify Supplier P2 with same BillNo 105 is NOT blocked!
    tombstones.addAll(["PUR-APP-1001", "P1_105", "PUR-1"]);
    final Map<String, dynamic> pur2DifferentSupplierSameBill = {
      "id": "PUR-WEB-2002",
      "internalNo": "PUR-2",
      "billNo": "105",
      "partyId": "P2",
      "distributorName": "Medilente Biotech",
      "date": DateTime.utc(2025, 1, 11).toIso8601String(),
      "entryDate": DateTime.utc(2025, 1, 11).toIso8601String(),
      "items": [],
      "totalAmount": 6100.0,
      "paymentMode": "CREDIT",
      "updatedAt": 3000,
      "version": 1,
    };
    UniversalDeltaMerger.mergeEntityList<Purchase>(
      cloudList: [pur1Modify, pur2DifferentSupplierSameBill],
      localList: purchasesList,
      tombstones: tombstones,
      getId: (e) => e.id,
      getRefNo: (e) => "${e.partyId}_${e.billNo}",
      getCompositeKey: (e) => "${e.partyId}_${e.billNo}",
      getCloudCompositeKey: (m) => "${m['partyId']}_${m['billNo']}",
      fromMap: (m) => Purchase.fromMap(m),
      toMap: (e) => e.toMap(),
    );
    expect(purchasesList.length, equals(1));
    expect(purchasesList.first.id, equals("PUR-WEB-2002"));
    expect(purchasesList.first.internalNo, equals("PUR-2"));
  });

  test('E2E TEST 5: Dual-Series Purchase (App PUR-1, PUR-2 + Web WPUR-1, WPUR-2 -> Next App PUR-3 & Zero Overwrite)', () async {
    final List<Purchase> purchasesList = [
      Purchase(
        id: "PUR-APP-1",
        internalNo: "PUR-1",
        billNo: "101",
        partyId: "SUP-1",
        distributorName: "Apex Pharma",
        date: DateTime.utc(2025, 1, 10),
        entryDate: DateTime.utc(2025, 1, 10),
        items: [],
        totalAmount: 1000.0,
        paymentMode: "CREDIT",
        updatedAt: 1000,
        version: 1,
      ),
      Purchase(
        id: "PUR-APP-2",
        internalNo: "PUR-2",
        billNo: "102",
        partyId: "SUP-1",
        distributorName: "Apex Pharma",
        date: DateTime.utc(2025, 1, 10),
        entryDate: DateTime.utc(2025, 1, 10),
        items: [],
        totalAmount: 2000.0,
        paymentMode: "CREDIT",
        updatedAt: 2000,
        version: 1,
      ),
    ];

    final List<dynamic> cloudWebPurchases = [
      {
        "id": "PUR-WEB-1",
        "internalNo": "WPUR-1",
        "billNo": "101", // Even with same supplier and same billNo!
        "partyId": "SUP-1",
        "distributorName": "Apex Pharma",
        "date": DateTime.utc(2025, 1, 10).toIso8601String(),
        "entryDate": DateTime.utc(2025, 1, 10).toIso8601String(),
        "items": [],
        "totalAmount": 3000.0,
        "paymentMode": "CREDIT",
        "updatedAt": 3000,
        "version": 1,
      },
      {
        "id": "PUR-WEB-2",
        "internalNo": "WPUR-2",
        "billNo": "103",
        "partyId": "SUP-1",
        "distributorName": "Apex Pharma",
        "date": DateTime.utc(2025, 1, 10).toIso8601String(),
        "entryDate": DateTime.utc(2025, 1, 10).toIso8601String(),
        "items": [],
        "totalAmount": 4000.0,
        "paymentMode": "CREDIT",
        "updatedAt": 4000,
        "version": 1,
      },
    ];

    final Set<String> tombstones = {};
    UniversalDeltaMerger.reconcileAllCollections(
      cloudFiles: {'purc.json': '[${cloudWebPurchases.map((m) => '''{"id":"${m['id']}","internalNo":"${m['internalNo']}","billNo":"${m['billNo']}","partyId":"${m['partyId']}","distributorName":"${m['distributorName']}","date":"${m['date']}","entryDate":"${m['entryDate']}","items":[],"totalAmount":${m['totalAmount']},"paymentMode":"CREDIT","updatedAt":${m['updatedAt']},"version":1}''').join(",")}]'},
      tombstones: tombstones,
      sales: [],
      purchases: purchasesList,
      vouchers: [],
      saleChallans: [],
      purchaseChallans: [],
      saleReturns: [],
      purchaseReturns: [],
    );

    // All 4 bills (PUR-1, PUR-2, WPUR-1, WPUR-2) must coexist without overwriting!
    expect(purchasesList.length, equals(4));
    expect(purchasesList.map((p) => p.internalNo).toSet(), equals({"PUR-1", "PUR-2", "WPUR-1", "WPUR-2"}));
  });
}
