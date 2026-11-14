import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharoah_erp/fy_transfer_engine.dart';
import 'package:pharoah_erp/gateway/company_registry_model.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:pharoah_erp/sync_core/d1_sales_ledger_service.dart';
import 'package:pharoah_erp/sync_core/models/sync_envelope.dart';
import 'package:pharoah_erp/sync_core/multi_fy_cloud_vault.dart';
import 'package:pharoah_erp/sync_core/orchestrator/master_sync_orchestrator.dart';
import 'package:pharoah_erp/sync_core/outbox/sync_queue_manager.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/sync_protocol/tombstone_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory mockDocsDir;

  setUpAll(() async {
    mockDocsDir = await Directory.systemTemp.createTemp('pharoah_challan_p0_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => mockDocsDir.path,
    );
  });

  tearDownAll(() async {
    if (await mockDocsDir.exists()) {
      await mockDocsDir.delete(recursive: true);
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await D1SalesLedgerService.loadPersistedGravestones();
    D1SalesLedgerService.activeFinancialYear = '2026-27';
    SyncQueueManager.debugReset();
  });

  SaleChallan _makeSaleChallan({
    required String id,
    required String billNo,
    String partyId = 'PARTY-S1',
    String status = 'Billed',
    DateTime? date,
    int version = 2,
    int updatedAt = 100000,
    int isDeleted = 0,
  }) {
    return SaleChallan(
      id: id,
      billNo: billNo,
      partyId: partyId,
      date: date ?? DateTime(2026, 2, 10),
      partyName: 'Alpha Medical',
      partyGstin: '',
      partyState: 'Rajasthan',
      items: [
        BillItem(
          id: 'BI-$id',
          srNo: 1,
          medicineID: 'MED-1',
          name: 'PARA 500',
          packing: '10T',
          batch: 'B1',
          exp: '12/27',
          hsn: '3004',
          mrp: 50.0,
          qty: 2,
          rate: 40.0,
          gstRate: 12.0,
          total: 80.0,
          sourceChallanId: id,
          sourceChallanNo: billNo,
        ),
      ],
      totalAmount: 80.0,
      status: status,
      updatedAt: updatedAt,
      version: version,
      isDeleted: isDeleted,
    );
  }

  PurchaseChallan _makePurchaseChallan({
    required String id,
    required String internalNo,
    required String billNo,
    String partyId = 'SUP-P1',
    String status = 'Billed',
    DateTime? date,
    int version = 2,
    int updatedAt = 100000,
    int isDeleted = 0,
  }) {
    return PurchaseChallan(
      id: id,
      internalNo: internalNo,
      billNo: billNo,
      partyId: partyId,
      date: date ?? DateTime(2026, 2, 12),
      distributorName: 'Omega Pharma',
      items: [
        PurchaseItem(
          id: 'PI-$id',
          srNo: 1,
          medicineID: 'MED-1',
          name: 'PARA 500',
          packing: '10T',
          batch: 'B1',
          exp: '12/27',
          hsn: '3004',
          mrp: 50.0,
          qty: 5,
          purchaseRate: 30.0,
          gstRate: 12.0,
          total: 150.0,
          sourceChallanId: id,
          sourceChallanNo: internalNo,
        ),
      ],
      totalAmount: 150.0,
      status: status,
      updatedAt: updatedAt,
      version: version,
      isDeleted: isDeleted,
    );
  }

  group('Phase 1 P0: FY Transfer, Converted Bill Deletion & Pending Challan Recovery', () {
    test('T1: App deleteBill in 2025-26 recovers SaleChallan to Pending and carries into 2026-27 on switchYear without altering opBal', () async {
      const compId = 'COMP_CH_T1';
      const bizType = 'WHOLESALE';
      const oldFy = '2025-26';
      const newFy = '2026-27';

      final oldDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$oldFy');
      final newDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$newFy');
      await oldDir.create(recursive: true);
      await newDir.create(recursive: true);

      final scOld = _makeSaleChallan(
        id: 'SC-UUID-1',
        billNo: 'SC-101',
        status: 'Billed',
        date: DateTime(2026, 2, 10),
        version: 2,
        updatedAt: 100000,
      );
      final saleOld = Sale(
        id: 'SALE-UUID-1',
        billNo: 'BILL-101',
        partyId: 'PARTY-S1',
        date: DateTime(2026, 2, 11),
        partyName: 'Alpha Medical',
        partyGstin: '',
        partyState: 'Rajasthan',
        items: [scOld.items.first],
        totalAmount: 80.0,
        paymentMode: 'CREDIT',
        linkedChallanIds: const ['SC-UUID-1'],
        version: 1,
        updatedAt: 100050,
      );
      final partyNew = Party(id: 'PARTY-S1', name: 'Alpha Medical', opBal: 5432.10, updatedAt: 100000);
      // Simulate stale carried-over Billed copy in 2026-27
      final scNewStale = _makeSaleChallan(
        id: 'SC-UUID-1',
        billNo: 'SC-101',
        status: 'Billed',
        date: DateTime(2026, 2, 10),
        version: 2,
        updatedAt: 100000,
      );

      await File('${oldDir.path}/s_challan.json').writeAsString(jsonEncode([scOld.toMap()]));
      await File('${oldDir.path}/sales.json').writeAsString(jsonEncode([saleOld.toMap()]));
      await File('${oldDir.path}/parts.json').writeAsString(jsonEncode([Party(id: 'PARTY-S1', name: 'Alpha Medical', opBal: 100.0).toMap()]));

      await File('${newDir.path}/s_challan.json').writeAsString(jsonEncode([scNewStale.toMap()]));
      await File('${newDir.path}/sales.json').writeAsString(jsonEncode([]));
      await File('${newDir.path}/parts.json').writeAsString(jsonEncode([partyNew.toMap()]));

      final ph = PharoahManager();
      ph.activeCompany = CompanyProfile(
        id: compId,
        name: 'Pharoah Challan ERP',
        businessType: bizType,
        createdAt: DateTime(2025, 4, 1),
        password: 'pw',
        fYears: [oldFy, newFy],
      );
      ph.currentFY = oldFy;
      D1SalesLedgerService.activeFinancialYear = oldFy;
      await ph.loadAllData();
      expect(ph.sales.length, 1);
      expect(ph.saleChallans.first.status, 'Billed');

      ph.deleteBill('SALE-UUID-1');
      // Allow background deleteBill async persistence & outbox/cascade Future to complete
      await Future.delayed(const Duration(milliseconds: 250));

      expect(ph.sales, isEmpty);
      expect(ph.saleChallans.first.status, 'Pending');
      expect(ph.saleChallans.first.version, greaterThan(2));

      // Verify back-FY cascade ALREADY updated 2026-27/s_challan.json on disk before switchYear!
      final newScDisk = jsonDecode(await File('${newDir.path}/s_challan.json').readAsString()) as List;
      expect(newScDisk.first['status'], 'Pending');

      // Verify Switch Year into 2026-27 brings Pending challan and does NOT touch Party opBal!
      await ph.switchYear(newFy);
      expect(ph.currentFY, newFy);
      expect(ph.saleChallans.length, 1);
      expect(ph.saleChallans.first.status, 'Pending');
      expect(ph.parties.first.opBal, 5432.10);
    });


    test('T2-App: App deletePurchase in 2025-26 recovers PurchaseChallan to Pending and carries into 2026-27 on switchYear without altering opBal', () async {
      const compId = 'COMP_CH_T2_APP';
      const bizType = 'WHOLESALE';
      const oldFy = '2025-26';
      const newFy = '2026-27';

      final oldDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$oldFy');
      final newDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$newFy');
      await oldDir.create(recursive: true);
      await newDir.create(recursive: true);

      final pcOld = _makePurchaseChallan(
        id: 'PC-APP-1',
        internalNo: 'PC-1',
        billNo: 'SupCh-AppCase',
        status: 'Billed',
        date: DateTime(2026, 2, 12),
        version: 2,
        updatedAt: 100000,
      );
      final purOld = Purchase(
        id: 'PUR-APP-1',
        internalNo: 'PUR-1',
        billNo: 'SupBill-App1',
        partyId: 'SUP-P1',
        date: DateTime(2026, 2, 14),
        entryDate: DateTime(2026, 2, 14),
        distributorName: 'Omega Pharma',
        items: [pcOld.items.first],
        totalAmount: 150.0,
        paymentMode: 'CREDIT',
        linkedChallanIds: const [],
        version: 1,
        updatedAt: 100050,
      );
      final pcNewStale = _makePurchaseChallan(
        id: 'PC-APP-1',
        internalNo: 'PC-1',
        billNo: 'SupCh-AppCase',
        status: 'Billed',
        date: DateTime(2026, 2, 12),
        version: 2,
        updatedAt: 100000,
      );

      await File('${oldDir.path}/p_challan.json').writeAsString(jsonEncode([pcOld.toMap()]));
      await File('${oldDir.path}/purc.json').writeAsString(jsonEncode([purOld.toMap()]));
      await File('${newDir.path}/p_challan.json').writeAsString(jsonEncode([pcNewStale.toMap()]));
      await File('${newDir.path}/purc.json').writeAsString(jsonEncode([]));
      await File('${newDir.path}/parts.json').writeAsString(jsonEncode([Party(id: 'SUP-P1', name: 'Omega Pharma', opBal: 3210.5).toMap()]));

      final ph = PharoahManager();
      ph.activeCompany = CompanyProfile(
        id: compId,
        name: 'Pharoah Purchase Challan ERP',
        businessType: bizType,
        createdAt: DateTime(2025, 4, 1),
        password: 'pw',
        fYears: [oldFy, newFy],
      );
      ph.currentFY = oldFy;
      D1SalesLedgerService.activeFinancialYear = oldFy;
      await ph.loadAllData();

      ph.deletePurchase('PUR-APP-1');
      await Future.delayed(const Duration(milliseconds: 250));

      expect(ph.purchases, isEmpty);
      expect(ph.purchaseChallans.first.status, 'Pending');
      final newPcDisk = jsonDecode(await File('${newDir.path}/p_challan.json').readAsString()) as List;
      expect(newPcDisk.first['status'], 'Pending');

      await ph.switchYear(newFy);
      expect(ph.purchaseChallans.length, 1);
      expect(ph.purchaseChallans.first.status, 'Pending');
      expect(ph.purchaseChallans.first.billNo, 'SupCh-AppCase');
      expect(ph.parties.first.opBal, 3210.5);
    });

    test('T2 & Cross-FY Web Vault: Cross-FY PURCHASE DELETE in MasterSyncOrchestrator reverts PurchaseChallan in back FY Vault & hot-swaps 2026-27 Web memory', () async {
      const oldFy = '2025-26';
      const newFy = '2026-27';
      D1SalesLedgerService.activeFinancialYear = newFy;

      final webPh = PharoahWebManager();
      webPh.financialYear = newFy;
      webPh.availableFinancialYears = [oldFy, newFy];

      final pcOld = _makePurchaseChallan(
        id: 'PC-UUID-1',
        internalNo: 'PC-1',
        billNo: 'SupCh-MixCase',
        status: 'Billed',
        date: DateTime(2026, 2, 12),
        version: 2,
        updatedAt: 100000,
      );
      final purOld = Purchase(
        id: 'PUR-UUID-1',
        internalNo: 'PUR-1',
        billNo: 'SupBill-10',
        partyId: 'SUP-P1',
        date: DateTime(2026, 2, 13),
        entryDate: DateTime(2026, 2, 13),
        distributorName: 'Omega Pharma',
        items: [pcOld.items.first],
        totalAmount: 150.0,
        paymentMode: 'CREDIT',
        linkedChallanIds: const ['PC-UUID-1'],
        version: 1,
        updatedAt: 100050,
      );
      final pcNewStale = _makePurchaseChallan(
        id: 'PC-UUID-1',
        internalNo: 'PC-1',
        billNo: 'SupCh-MixCase',
        status: 'Billed',
        date: DateTime(2026, 2, 12),
        version: 2,
        updatedAt: 100000,
      );

      webPh.fyVault[oldFy] = {
        'purc.json': jsonEncode([purOld.toMap()]),
        'p_challan.json': jsonEncode([pcOld.toMap()]),
      };
      webPh.fyVault[newFy] = {
        'purc.json': jsonEncode([]),
        'p_challan.json': jsonEncode([pcNewStale.toMap()]),
        'parts.json': jsonEncode([Party(id: 'SUP-P1', name: 'Omega Pharma', opBal: 777.0).toMap()]),
      };
      webPh.parties = [Party(id: 'SUP-P1', name: 'Omega Pharma', opBal: 777.0)];
      webPh.purchaseChallans = [pcNewStale];

      final delEnv = SyncEnvelope(
        seq: 10,
        syncId: purOld.id,
        storeToken: 'TK1',
        documentType: 'PURCHASE',
        action: 'DELETE',
        version: 999999,
        updatedAt: 200000,
        isDeleted: 1,
        billData: {...purOld.toMap(), 'isDeleted': 1, 'is_deleted': 1, 'fy': oldFy},
      );

      final handled = MasterSyncOrchestrator.dispatchEnvelope(envelope: delEnv, phWeb: webPh);
      expect(handled, isTrue);

      final List oldPurAfter = jsonDecode(webPh.fyVault[oldFy]!['purc.json']!) as List;
      final List oldPcAfter = jsonDecode(webPh.fyVault[oldFy]!['p_challan.json']!) as List;
      final List newPcAfter = jsonDecode(webPh.fyVault[newFy]!['p_challan.json']!) as List;

      expect(oldPurAfter, isEmpty);
      expect(oldPcAfter.first['status'], 'Pending');
      expect(newPcAfter.first['status'], 'Pending');
      expect(webPh.purchaseChallans.first.status, 'Pending');
      // Exact case preservation on supplier billNo
      expect(webPh.purchaseChallans.first.billNo, 'SupCh-MixCase');
    });

    test('Same-FY Web PURCHASE DELETE in MasterSyncOrchestrator extracts sourceChallanId before purgeDeletedIds removes Purchase from memory', () {
      const fy = '2026-27';
      D1SalesLedgerService.activeFinancialYear = fy;
      final webPh = PharoahWebManager();
      webPh.financialYear = fy;

      final pc = _makePurchaseChallan(
        id: 'PC-SAME-1',
        internalNo: 'PC-9',
        billNo: 'SupCh-9',
        status: 'Billed',
        date: DateTime(2026, 6, 10),
        version: 2,
        updatedAt: 100000,
      );
      final pur = Purchase(
        id: 'PUR-SAME-1',
        internalNo: 'PUR-9',
        billNo: 'SupBill-9',
        partyId: 'SUP-P1',
        date: DateTime(2026, 6, 11),
        entryDate: DateTime(2026, 6, 11),
        distributorName: 'Omega Pharma',
        items: [pc.items.first],
        totalAmount: 150.0,
        paymentMode: 'CREDIT',
        linkedChallanIds: const [], // Empty at header level: relies on pre-purge item sourceChallanId!
        version: 1,
        updatedAt: 100050,
      );
      webPh.purchases = [pur];
      webPh.purchaseChallans = [pc];

      final delEnv = SyncEnvelope(
        seq: 11,
        syncId: pur.id,
        storeToken: 'TK1',
        documentType: 'PURCHASE',
        action: 'DELETE',
        version: 999999,
        updatedAt: 200000,
        isDeleted: 1,
        billData: {'id': pur.id, 'internalNo': pur.internalNo, 'billNo': pur.billNo, 'partyId': pur.partyId, 'date': pur.date.toIso8601String(), 'fy': fy, 'isDeleted': 1},
      );

      MasterSyncOrchestrator.dispatchEnvelope(envelope: delEnv, phWeb: webPh);
      expect(webPh.purchases, isEmpty);
      expect(webPh.purchaseChallans.first.status, 'Pending');
    });

    test('T3: MultiFyCloudVault.applyCrossFyEdgeEventsToLocalDisk reverts linked challans & cascades Pending forward to active FY without altering opBal', () async {
      const compId = 'COMP_CH_T3';
      const bizType = 'WHOLESALE';
      const oldFy = '2025-26';
      const newFy = '2026-27';

      final oldDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$oldFy');
      final newDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$newFy');
      await oldDir.create(recursive: true);
      await newDir.create(recursive: true);

      final scOld = _makeSaleChallan(id: 'SC-ED-1', billNo: 'SC-50', status: 'Billed', date: DateTime(2026, 1, 15), version: 2, updatedAt: 100000);
      final saleOld = Sale(
        id: 'SALE-ED-1',
        billNo: 'BILL-50',
        partyId: 'PARTY-S1',
        date: DateTime(2026, 1, 16),
        partyName: 'Alpha Medical',
        partyGstin: '',
        partyState: 'Rajasthan',
        items: [scOld.items.first],
        totalAmount: 80.0,
        paymentMode: 'CREDIT',
        linkedChallanIds: const ['SC-ED-1'],
        version: 1,
        updatedAt: 100050,
      );

      await File('${oldDir.path}/s_challan.json').writeAsString(jsonEncode([scOld.toMap()]));
      await File('${oldDir.path}/sales.json').writeAsString(jsonEncode([saleOld.toMap()]));
      await File('${newDir.path}/s_challan.json').writeAsString(jsonEncode([]));
      await File('${newDir.path}/sales.json').writeAsString(jsonEncode([]));
      await File('${newDir.path}/parts.json').writeAsString(jsonEncode([Party(id: 'PARTY-S1', name: 'Alpha Medical', opBal: 987.65).toMap()]));

      final ph = PharoahManager();
      ph.activeCompany = CompanyProfile(
        id: compId,
        name: 'Pharoah Vault ERP',
        businessType: bizType,
        createdAt: DateTime(2025, 4, 1),
        password: 'pw',
        fYears: [oldFy, newFy],
      );
      ph.currentFY = newFy;
      D1SalesLedgerService.activeFinancialYear = newFy;
      await ph.loadAllData();
      expect(ph.saleChallans, isEmpty);

      final edgeEvents = [
        {
          'bill_id': 'SALE-ED-1',
          'bill_no': 'BILL-50',
          'action': 'DELETE',
          'fy': oldFy,
          'created_at': 250000,
          'sale_data': {...saleOld.toMap(), 'fy': oldFy, 'is_deleted': 1, 'updatedAt': 250000},
        }
      ];

      final changed = await MultiFyCloudVault.applyCrossFyEdgeEventsToLocalDisk(ph: ph, edgeEvents: edgeEvents);
      expect(changed, isTrue);

      await ph.syncPendingChallansFromPreviousYears(targetYear: newFy);
      await ph.loadAllData();

      expect(ph.saleChallans.length, 1);
      expect(ph.saleChallans.first.status, 'Pending');
      expect(ph.parties.first.opBal, 987.65);
    });

    test('LWW & Tombstone Isolation: Newer 2026-27 Billed status not downgraded & deleted 2026-27 Challan not resurrected; D1 sales/purchase ignore Challan docs', () {
      final prevSc = _makeSaleChallan(id: 'SC-LWW', billNo: 'SC-77', status: 'Pending', version: 2, updatedAt: 200000);
      final targetScNewerBilled = _makeSaleChallan(id: 'SC-LWW', billNo: 'SC-77', status: 'Billed', version: 3, updatedAt: 500000);
      final prevDeletedSc = _makeSaleChallan(id: 'SC-DEL', billNo: 'SC-78', status: 'Pending', version: 2, updatedAt: 200000);

      final res = FYTransferEngine.reconcileCarryForwardSaleChallans(
        prevChallans: [prevSc, prevDeletedSc],
        targetChallans: [targetScNewerBilled],
        isDeletedInTarget: (c) => c.id == 'SC-DEL',
      );

      expect(res.length, 1);
      expect(res.first.id, 'SC-LWW');
      expect(res.first.status, 'Billed'); // Newer Billed preserved!

      // Skip-guard verification on D1SalesLedgerService
      final localSales = <Sale>[];
      final localPurchases = <Purchase>[];
      final challanEvents = [
        {
          'bill_id': 'SC-1',
          'bill_no': 'SC-1',
          'action': 'INSERT',
          'fy': '2026-27',
          'sale_data': {'id': 'SC-1', 'doc_type': 'SALE_CHALLAN', 'fy': '2026-27'},
        },
        {
          'bill_id': 'PC-1',
          'bill_no': 'PC-1',
          'action': 'INSERT',
          'fy': '2026-27',
          'sale_data': {'id': 'PC-1', 'doc_type': 'PURCHASE_CHALLAN', 'fy': '2026-27'},
        },
      ];
      expect(D1SalesLedgerService.applyEventsToLocalSales(localSales, challanEvents, '2026-27'), isFalse);
      expect(D1SalesLedgerService.applyEventsToLocalPurchases(localPurchases, challanEvents, '2026-27'), isFalse);
      expect(localSales, isEmpty);
      expect(localPurchases, isEmpty);
    });
  });
}
