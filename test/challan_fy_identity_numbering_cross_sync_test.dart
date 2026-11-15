import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharoah_erp/fy_transfer_engine.dart';
import 'package:pharoah_erp/logic/pharoah_numbering_engine.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/sync_core/d1_sales_ledger_service.dart';
import 'package:pharoah_erp/sync_core/models/sync_envelope.dart';
import 'package:pharoah_erp/sync_core/modules/purchase_challan_sync_module.dart';
import 'package:pharoah_erp/sync_core/modules/sale_challan_sync_module.dart';
import 'package:pharoah_erp/sync_core/multi_fy_cloud_vault.dart';
import 'package:pharoah_erp/sync_core/orchestrator/master_sync_orchestrator.dart';
import 'package:pharoah_erp/sync_core/outbox/sync_queue_manager.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/web_pharoah_numbering_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory mockDocsDir;

  SaleChallan makeSaleChallan({
    required String id,
    required String billNo,
    String partyId = 'P1',
    String partyName = 'Party A',
    DateTime? date,
    String status = 'Pending',
    String originalFy = '',
    int version = 1,
    int updatedAt = 1000,
    int isDeleted = 0,
  }) {
    return SaleChallan(
      id: id,
      billNo: billNo,
      partyId: partyId,
      partyName: partyName,
      partyGstin: '',
      partyState: 'Rajasthan',
      date: date ?? DateTime(2025, 5, 10),
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
      originalFy: originalFy,
      version: version,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }

  PurchaseChallan makePurchaseChallan({
    required String id,
    required String internalNo,
    required String billNo,
    String partyId = 'SUP-1',
    String distributorName = 'Supplier Z',
    DateTime? date,
    String status = 'Pending',
    String originalFy = '',
    int version = 1,
    int updatedAt = 1000,
    int isDeleted = 0,
  }) {
    return PurchaseChallan(
      id: id,
      internalNo: internalNo,
      billNo: billNo,
      partyId: partyId,
      distributorName: distributorName,
      date: date ?? DateTime(2025, 6, 15),
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
      originalFy: originalFy,
      version: version,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }

  setUpAll(() async {
    mockDocsDir = await Directory.systemTemp.createTemp('pharoah_challan_test_');
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
    SharedPreferences.setMockInitialValues({
      'active_fy_COMP-1': '2026-27',
    });
    await D1SalesLedgerService.loadPersistedGravestones();
    D1SalesLedgerService.activeFinancialYear = '2026-27';
    SyncQueueManager.debugReset();
  });

  group('Group 1: Challan Identity, FY Normalization, Sentinel Date & Backward Compatibility', () {
    test('T1: SaleChallan normalizes originalFy to YYYY-YY across toMap, fromMap and fromEnvelope', () {
      final c1 = makeSaleChallan(
        id: 'sc-101',
        billNo: 'Y-1',
        date: DateTime(2025, 5, 10),
        originalFy: '2025-2026',
      );

      expect(c1.originalFy, equals('2025-26'));
      expect(c1.effectiveOriginalFy, equals('2025-26'));
      expect(c1.hasValidDate, isTrue);

      final map = c1.toMap();
      expect(map['originalFy'], equals('2025-26'));

      final c2 = SaleChallan.fromMap(map);
      expect(c2.id, equals('sc-101'));
      expect(c2.originalFy, equals('2025-26'));
      expect(c2.effectiveOriginalFy, equals('2025-26'));

      final env = SyncEnvelope(
        syncId: 'sc-101',
        documentType: 'SALE_CHALLAN',
        billData: map,
        action: 'UPDATE',
        version: 2,
        updatedAt: 1000,
        isDeleted: 0,
      );
      final c3 = SaleChallan.fromEnvelope(env.toMap());
      expect(c3.id, equals('sc-101'));
      expect(c3.originalFy, equals('2025-26'));
      expect(c3.effectiveOriginalFy, equals('2025-26'));
    });

    test('T2: PurchaseChallan persists normalized originalFy across toMap, fromMap and fromEnvelope', () {
      final pc1 = makePurchaseChallan(
        id: 'pc-201',
        internalNo: 'INW-1',
        billNo: 'SUPP-99',
        date: DateTime(2025, 6, 15),
        originalFy: '2025-2026',
      );

      expect(pc1.effectiveOriginalFy, equals('2025-26'));

      final map = pc1.toMap();
      expect(map['originalFy'], equals('2025-26'));

      final pc2 = PurchaseChallan.fromMap(map);
      expect(pc2.id, equals('pc-201'));
      expect(pc2.originalFy, equals('2025-26'));
      expect(pc2.effectiveOriginalFy, equals('2025-26'));

      final env = SyncEnvelope(
        syncId: 'pc-201',
        documentType: 'PURCHASE_CHALLAN',
        billData: map,
        action: 'UPDATE',
        version: 3,
        updatedAt: 2000,
        isDeleted: 0,
      );
      final pc3 = PurchaseChallan.fromEnvelope(env.toMap());
      expect(pc3.id, equals('pc-201'));
      expect(pc3.originalFy, equals('2025-26'));
    });

    test('T3: Legacy Challan with corrupt/missing date yields hasValidDate=false and does not fabricate 1969-70', () {
      final corruptMap = {
        'id': 'legacy-corrupt-1',
        'billNo': 'Y-99',
        'partyId': 'P1',
        'partyName': 'Legacy Party',
        'partyGstin': '',
        'partyState': 'Rajasthan',
        'date': 'not-a-valid-date',
        'status': 'Pending',
        'items': [],
        'totalAmount': 50.0,
        'version': 1,
      };
      final corrupt = SaleChallan.fromMap(corruptMap);
      expect(corrupt.hasValidDate, isFalse);
      expect(corrupt.effectiveOriginalFy, equals(''));

      final validLegacyMap = {
        'id': 'legacy-sc-1',
        'billNo': 'Y-5',
        'partyId': 'P1',
        'partyName': 'Old Party',
        'partyGstin': '',
        'partyState': 'Rajasthan',
        'date': '2024-08-10T00:00:00.000',
        'status': 'Pending',
        'items': [],
        'totalAmount': 50.0,
        'version': 1,
      };
      final validLegacy = SaleChallan.fromMap(validLegacyMap);
      expect(validLegacy.hasValidDate, isTrue);
      expect(validLegacy.effectiveOriginalFy, equals('2024-25'));
    });

    test('T4: Date editing preserves originalFy and FYTransferEngine stamps originalFy explicitly', () {
      final c = makeSaleChallan(
        id: 'sc-102',
        billNo: 'Y-2',
        date: DateTime(2025, 7, 1),
        originalFy: '2025-26',
      );
      c.date = DateTime(2025, 8, 1);
      expect(c.effectiveOriginalFy, equals('2025-26'));

      final cfFiles = FYTransferEngine.computeCarryForwardFromFiles(
        sourceFiles: {
          's_challan.json': jsonEncode([
            makeSaleChallan(
              id: 'sc-cf-1',
              billNo: 'Y-7',
              date: DateTime(2026, 2, 10),
              status: 'Pending',
              originalFy: '',
            ).toMap(),
          ]),
          'p_challan.json': jsonEncode([
            makePurchaseChallan(
              id: 'pc-cf-1',
              internalNo: 'PC-7',
              billNo: 'SUP-7',
              date: DateTime(2026, 2, 12),
              status: 'Pending',
              originalFy: '',
            ).toMap(),
          ]),
        },
        sourceFY: '2025-26',
        targetFY: '2026-27',
      );
      final cfSc = jsonDecode(cfFiles['s_challan.json']!) as List;
      final cfPc = jsonDecode(cfFiles['p_challan.json']!) as List;
      expect(cfSc.first['originalFy'], equals('2025-26'));
      expect(cfPc.first['originalFy'], equals('2025-26'));
    });
  });

  group('Group 2: Per-FY Sequential Numbering & Soft-Delete Filtering', () {
    test('T5: PharoahNumberingEngine resets Sale/Purchase Challan numbering in new FY ignoring Carry-Forward & deleted records', () async {
      final carriedFromOldFy = makeSaleChallan(
        id: 'sc-old-1',
        billNo: 'Y-42',
        date: DateTime(2026, 2, 10),
        originalFy: '2025-26',
      );
      final softDeletedCurrentFy = makeSaleChallan(
        id: 'sc-del-1',
        billNo: 'Y-99',
        date: DateTime(2026, 5, 1),
        originalFy: '2026-27',
        isDeleted: 1,
      );

      final nextSaleChallanNo = await PharoahNumberingEngine.getNextNumber(
        type: 'SALE_CHALLAN',
        companyID: 'COMP-1',
        prefix: 'Y-',
        startFrom: 1,
        currentList: [carriedFromOldFy, softDeletedCurrentFy],
      );
      expect(nextSaleChallanNo, equals('Y-1'));

      final carriedPurChallan = makePurchaseChallan(
        id: 'pc-old-1',
        internalNo: 'PC-18',
        billNo: 'SUP-18',
        date: DateTime(2026, 2, 15),
        originalFy: '2025-26',
      );
      final currentPurChallan = makePurchaseChallan(
        id: 'pc-cur-1',
        internalNo: 'PC-1',
        billNo: 'SUP-1',
        date: DateTime(2026, 4, 20),
        originalFy: '2026-27',
      );
      final nextPurChallanNo = await PharoahNumberingEngine.getNextNumber(
        type: 'PURCHASE_CHALLAN',
        companyID: 'COMP-1',
        prefix: 'PC-',
        startFrom: 1,
        currentList: [carriedPurChallan, currentPurChallan],
      );
      expect(nextPurChallanNo, equals('PC-2'));
    });

    test('T6: WebPharoahNumberingEngine isolates numbering by targetFy and skips deleted records', () {
      final list = [
        makeSaleChallan(
          id: 'wsc-old',
          billNo: 'Y-50',
          date: DateTime(2026, 3, 25),
          originalFy: '2025-26',
        ),
        makeSaleChallan(
          id: 'wsc-del',
          billNo: 'Y-8',
          date: DateTime(2026, 4, 15),
          originalFy: '2026-27',
          isDeleted: 1,
        ),
        makeSaleChallan(
          id: 'wsc-cur',
          billNo: 'Y-1',
          date: DateTime(2026, 4, 20),
          originalFy: '2026-27',
        ),
      ];

      final nextNo = WebPharoahNumberingEngine.getNextNumber(
        prefix: 'Y-',
        startFrom: 1,
        currentList: list,
        targetFy: '2026-2027',
      );
      expect(nextNo, equals('Y-2'));
    });
  });

  group('Group 3: ChallanLinkMatcher, MultiFyCloudVault Identity & LWW Deterministic Tie-Breaker', () {
    test('T7: ChallanLinkMatcher refuses Y-1 cross-FY collision when typed UUIDs differ, allows scoped legacy fallback', () {
      final links = ChallanLinkMatcher.extractLinks(
        linkedChallanIds: const ['SC-NEW-UUID'],
        items: [
          {'sourceChallanId': 'SC-NEW-UUID', 'sourceChallanNo': 'Y-1'},
        ],
      );

      final oldFyChallan = makeSaleChallan(
        id: 'SC-OLD-UUID',
        billNo: 'Y-1',
        date: DateTime(2025, 5, 1),
        originalFy: '2025-26',
      );
      final newFyChallan = makeSaleChallan(
        id: 'SC-NEW-UUID',
        billNo: 'Y-1',
        date: DateTime(2026, 5, 1),
        originalFy: '2026-27',
      );

      expect(ChallanLinkMatcher.matchesSaleChallan(oldFyChallan, links, targetFy: '2026-27'), isFalse);
      expect(ChallanLinkMatcher.matchesSaleChallan(newFyChallan, links, targetFy: '2026-27'), isTrue);

      final legacyLinks = ChallanLinkMatcher.extractLinks(
        linkedChallanIds: const ['Y-1'],
        items: const [],
      );
      expect(ChallanLinkMatcher.matchesSaleChallan(oldFyChallan, legacyLinks, targetFy: '2026-27'), isFalse);
      expect(ChallanLinkMatcher.matchesSaleChallan(newFyChallan, legacyLinks, targetFy: '2026-27'), isTrue);
    });

    test('T8: MultiFyCloudVault isolates s_challan.json & p_challan.json distinct UUIDs and uses composite key for purc.json', () {
      final scRes = MultiFyCloudVault.mergeJsonListLww(
        fileName: 's_challan.json',
        localRaw: jsonEncode([
          {'id': 'UUID-AAA', 'billNo': 'Y-1', 'status': 'Pending', 'version': 1, 'updatedAt': 100, 'originalFy': '2025-26'},
        ]),
        cloudRaw: jsonEncode([
          {'id': 'UUID-BBB', 'billNo': 'Y-1', 'status': 'Pending', 'version': 1, 'updatedAt': 200, 'originalFy': '2026-27'},
        ]),
        fy: '2026-27',
      );
      final scMerged = (jsonDecode(scRes.mergedJson) as List).cast<Map<String, dynamic>>();
      expect(scMerged.length, equals(2));

      final pcRes = MultiFyCloudVault.mergeJsonListLww(
        fileName: 'p_challan.json',
        localRaw: jsonEncode([
          {'id': 'PC-UUID-1', 'internalNo': 'PC-1', 'billNo': 'SUP-10', 'partyId': 'SUP-1', 'status': 'Pending', 'version': 1, 'updatedAt': 100, 'originalFy': '2025-26'},
        ]),
        cloudRaw: jsonEncode([
          {'id': 'PC-UUID-2', 'internalNo': 'PC-1', 'billNo': 'SUP-10', 'partyId': 'SUP-1', 'status': 'Pending', 'version': 1, 'updatedAt': 200, 'originalFy': '2026-27'},
        ]),
        fy: '2026-27',
      );
      final pcMerged = (jsonDecode(pcRes.mergedJson) as List).cast<Map<String, dynamic>>();
      expect(pcMerged.length, equals(2));
    });

    test('T9: SaleChallanSyncModule & PurchaseChallanSyncModule deterministic equal-ver/equal-ts tie-breaker & Billed deletion guard', () {
      final local = [
        makeSaleChallan(
          id: 'sc-tie',
          billNo: 'Y-1',
          date: DateTime(2026, 4, 1),
          status: 'Pending',
          version: 2,
          updatedAt: 500,
        ),
      ];
      final billedSameClockEnv = SyncEnvelope(
        syncId: 'sc-tie',
        documentType: 'SALE_CHALLAN',
        billData: {
          'id': 'sc-tie',
          'billNo': 'Y-1',
          'partyId': 'P1',
          'partyName': 'Party A',
          'partyGstin': '',
          'partyState': 'Rajasthan',
          'date': DateTime(2026, 4, 1).toIso8601String(),
          'status': 'Billed',
          'items': [],
          'totalAmount': 80.0,
          'version': 2,
          'updatedAt': 500,
          'isDeleted': 0,
        },
        action: 'UPDATE',
        version: 2,
        updatedAt: 500,
        isDeleted: 0,
      );

      // Equal version + equal updatedAt settles deterministically to Billed!
      expect(SaleChallanSyncModule.mergeIncomingSaleChallanEnvelope(local, billedSameClockEnv), isTrue);
      expect(local[0].status, equals('Billed'));

      // Even a higher-version remote delete MUST NOT evict a locally Billed challan!
      final remoteDeleteEnv = SyncEnvelope(
        syncId: 'sc-tie',
        documentType: 'SALE_CHALLAN',
        billData: {'id': 'sc-tie', 'billNo': 'Y-1', 'isDeleted': 1, 'version': 9, 'updatedAt': 99999},
        action: 'DELETE',
        version: 9,
        updatedAt: 99999,
        isDeleted: 1,
      );
      expect(SaleChallanSyncModule.mergeIncomingSaleChallanEnvelope(local, remoteDeleteEnv), isFalse);
      expect(local.length, equals(1));
      expect(local[0].status, equals('Billed'));
    });
  });

  group('Group 4: End-to-End Old-FY Pending Edit/Delete Propagation & Billed Hard Lock', () {
    test('T10: Back-FY Pending Challan edit cascades forward; Billed Challan edit & delete are hard-blocked', () {
      const oldFy = '2025-26';
      const newFy = '2026-27';
      final webPh = PharoahWebManager();
      webPh.availableFinancialYears = [oldFy, newFy];
      webPh.financialYear = oldFy;

      final scOld = makeSaleChallan(
        id: 'SC-CF-PROP-1',
        billNo: 'Y-1',
        date: DateTime(2026, 2, 10),
        status: 'Pending',
        originalFy: oldFy,
        version: 1,
        updatedAt: 1000,
      );
      final scNewCopy = makeSaleChallan(
        id: 'SC-CF-PROP-1',
        billNo: 'Y-1',
        date: DateTime(2026, 2, 10),
        status: 'Pending',
        originalFy: oldFy,
        version: 1,
        updatedAt: 1000,
      );
      final scNewSameNo = makeSaleChallan(
        id: 'SC-NEW-Y1',
        billNo: 'Y-1',
        date: DateTime(2026, 5, 1),
        status: 'Pending',
        originalFy: newFy,
        version: 1,
        updatedAt: 1000,
      );

      webPh.saleChallans = [scOld];
      webPh.fyVault[oldFy] = {'s_challan.json': jsonEncode([scOld.toMap()])};
      webPh.fyVault[newFy] = {'s_challan.json': jsonEncode([scNewCopy.toMap(), scNewSameNo.toMap()])};

      // Dual-side shift check from Old FY
      final shiftBefore = webPh.getForwardChallanStatus('SC-CF-PROP-1', isPurchase: false);
      expect(shiftBefore.shiftedFy, equals(newFy));
      expect(shiftBefore.billedFy, isNull);

      // Edit Pending challan in Old FY -> auto-cascades to New FY while keeping Y-1 SC-NEW-Y1 intact
      final edited = SaleChallan(
        id: 'SC-CF-PROP-1',
        billNo: 'Y-1',
        partyId: 'P1',
        partyName: 'Party A Updated',
        partyGstin: '',
        partyState: 'Rajasthan',
        date: DateTime(2026, 2, 10),
        items: scOld.items,
        totalAmount: 199.0,
        status: 'Pending',
        originalFy: oldFy,
        version: 2,
      );
      webPh.addSaleChallanAndSync(edited);

      final List newAfterEdit = jsonDecode(webPh.fyVault[newFy]!['s_challan.json']!) as List;
      expect(newAfterEdit.length, equals(2));
      final updatedForward = newAfterEdit.firstWhere((e) => e['id'] == 'SC-CF-PROP-1');
      expect(updatedForward['partyName'], equals('Party A Updated'));
      expect((updatedForward['totalAmount'] as num).toDouble(), equals(199.0));

      // Pending delete in Old FY cascades to delete Pending copy in New FY, WITHOUT touching SC-NEW-Y1 (same billNo Y-1)
      expect(webPh.deleteSaleChallan('SC-CF-PROP-1'), isTrue);
      final List newAfterDelete = jsonDecode(webPh.fyVault[newFy]!['s_challan.json']!) as List;
      expect(newAfterDelete.length, equals(1));
      expect(newAfterDelete.first['id'], equals('SC-NEW-Y1'));
    });

    test('T11: Old-FY challan Billed in New FY shows billedFy and hard-blocks deletion in Old FY', () {
      const oldFy = '2025-26';
      const newFy = '2026-27';
      final webPh = PharoahWebManager();
      webPh.availableFinancialYears = [oldFy, newFy];
      webPh.financialYear = oldFy;

      final scOldStale = makeSaleChallan(
        id: 'SC-LOCK-1',
        billNo: 'Y-5',
        date: DateTime(2026, 2, 10),
        status: 'Pending',
        originalFy: oldFy,
        version: 1,
      );
      final scNewBilled = makeSaleChallan(
        id: 'SC-LOCK-1',
        billNo: 'Y-5',
        date: DateTime(2026, 2, 10),
        status: 'Billed',
        originalFy: oldFy,
        version: 2,
      );

      webPh.saleChallans = [scOldStale];
      webPh.fyVault[oldFy] = {'s_challan.json': jsonEncode([scOldStale.toMap()])};
      webPh.fyVault[newFy] = {'s_challan.json': jsonEncode([scNewBilled.toMap()])};

      final fwd = webPh.getForwardChallanStatus('SC-LOCK-1', isPurchase: false);
      expect(fwd.shiftedFy, equals(newFy));
      expect(fwd.billedFy, equals(newFy));

      // Hard-blocked even though local status in Old FY snapshot appeared Pending!
      expect(webPh.deleteSaleChallan('SC-LOCK-1'), isFalse);
      expect(webPh.saleChallans.length, equals(1));
    });

    test('T12: D1SalesLedgerService normalized targetFy bills linked challans cleanly', () {
      final challans = [
        makeSaleChallan(
          id: 'sc-linked-1',
          billNo: 'Y-10',
          date: DateTime(2025, 5, 1),
          status: 'Pending',
          originalFy: '2025-26',
        ),
      ];

      final events = [
        {
          'action': 'INSERT',
          'fy': '2026-2027',
          'sale_data': {
            'id': 'sale-bill-1',
            'billNo': 'INV-1',
            'linkedChallanIds': ['sc-linked-1'],
            'items': [],
          }
        }
      ];

      final result = D1SalesLedgerService.billLinkedChallansFromSaveEvents(
        events: events,
        targetFy: '2026-27',
        saleChallans: challans,
      );

      expect(result.saleChallansMutated, isTrue);
      expect(challans[0].status, equals('Billed'));
      expect(challans[0].version, greaterThan(1));
    });
  });
}
