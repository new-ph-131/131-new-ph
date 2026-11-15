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
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/sync_protocol/delta_merge_engine.dart';
import 'package:pharoah_erp/web_live_sync/sync_protocol/tombstone_engine.dart';
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

      expect(
        ChallanLinkMatcher.matchesSaleChallan(
          oldFyChallan,
          explicitIds: links.explicitIds,
          legacyNos: links.legacyNos,
          billFy: '2026-27',
        ),
        isFalse,
      );
      expect(
        ChallanLinkMatcher.matchesSaleChallan(
          newFyChallan,
          explicitIds: links.explicitIds,
          legacyNos: links.legacyNos,
          billFy: '2026-27',
        ),
        isTrue,
      );

      final legacyLinks = ChallanLinkMatcher.extractLinks(
        linkedChallanIds: const [],
        items: const [
          {'sourceChallanNo': 'Y-1'},
        ],
      );
      expect(
        ChallanLinkMatcher.matchesSaleChallan(
          oldFyChallan,
          explicitIds: legacyLinks.explicitIds,
          legacyNos: legacyLinks.legacyNos,
          billFy: '2026-27',
        ),
        isFalse,
      );
      expect(
        ChallanLinkMatcher.matchesSaleChallan(
          newFyChallan,
          explicitIds: legacyLinks.explicitIds,
          legacyNos: legacyLinks.legacyNos,
          billFy: '2026-27',
        ),
        isTrue,
      );
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

  group('Group 4: 10x Lifecycle, +45s Clock Skew, Tombstone Mutex & D1 Ledger Isolation', () {
    test('T13: 10x Create -> Modify -> Delete -> Re-create lifecycle for SaleChallan & PurchaseChallan via D1 & Orchestrator', () {
      const fy = '2026-27';
      final List<SaleChallan> appSaleChallans = [];
      final List<PurchaseChallan> appPurcChallans = [];
      final List<Sale> appSales = [];
      final List<Purchase> appPurchases = [];

      // 1. Create 10 Sale Challans (SCH-1..10) & 10 Purchase Challans (PCH-1..10)
      final List<Map<String, dynamic>> createEvents = [];
      for (int i = 1; i <= 10; i++) {
        final sc = makeSaleChallan(
          id: 'sc_v1_$i',
          billNo: 'SCH-$i',
          originalFy: fy,
          version: 1,
          updatedAt: 10000 + i,
        );
        final pc = makePurchaseChallan(
          id: 'pc_v1_$i',
          internalNo: 'PCH-$i',
          billNo: 'SUP-CH-$i',
          originalFy: fy,
          version: 1,
          updatedAt: 10000 + i,
        );
        createEvents.add({
          'bill_id': sc.id,
          'bill_no': sc.billNo,
          'version': 1,
          'action': 'INSERT',
          'fy': fy,
          'updated_at': sc.updatedAt,
          'sale_data': {...sc.toMap(), 'doc_type': 'SALE_CHALLAN', 'fy': fy},
        });
        createEvents.add({
          'bill_id': pc.id,
          'bill_no': pc.internalNo,
          'version': 1,
          'action': 'INSERT',
          'fy': fy,
          'updated_at': pc.updatedAt,
          'sale_data': {...pc.toMap(), 'doc_type': 'PURCHASE_CHALLAN', 'fy': fy},
        });
      }

      expect(D1SalesLedgerService.applyEventsToLocalSaleChallans(appSaleChallans, createEvents, fy), isTrue);
      expect(D1SalesLedgerService.applyEventsToLocalPurchaseChallans(appPurcChallans, createEvents, fy), isTrue);
      // Strict isolation: Sale & Purchase ledgers must ignore Challan events
      expect(D1SalesLedgerService.applyEventsToLocalSales(appSales, createEvents, fy), isFalse);
      expect(D1SalesLedgerService.applyEventsToLocalPurchases(appPurchases, createEvents, fy), isFalse);
      expect(appSaleChallans.length, equals(10));
      expect(appPurcChallans.length, equals(10));

      // 2. Modify all 10 Sale Challans & 10 Purchase Challans (version = 2)
      final List<Map<String, dynamic>> modifyEvents = [];
      for (int i = 1; i <= 10; i++) {
        final sc = makeSaleChallan(
          id: 'sc_v1_$i',
          billNo: 'SCH-$i',
          partyName: 'Updated Party $i',
          originalFy: fy,
          version: 2,
          updatedAt: 20000 + i,
        );
        final pc = makePurchaseChallan(
          id: 'pc_v1_$i',
          internalNo: 'PCH-$i',
          billNo: 'SUP-CH-$i',
          distributorName: 'Updated Supplier $i',
          originalFy: fy,
          version: 2,
          updatedAt: 20000 + i,
        );
        modifyEvents.add({
          'bill_id': sc.id,
          'bill_no': sc.billNo,
          'version': 2,
          'action': 'UPDATE',
          'fy': fy,
          'updated_at': sc.updatedAt,
          'sale_data': {...sc.toMap(), 'doc_type': 'SALE_CHALLAN', 'fy': fy},
        });
        modifyEvents.add({
          'bill_id': pc.id,
          'bill_no': pc.internalNo,
          'version': 2,
          'action': 'UPDATE',
          'fy': fy,
          'updated_at': pc.updatedAt,
          'sale_data': {...pc.toMap(), 'doc_type': 'PURCHASE_CHALLAN', 'fy': fy},
        });
      }

      expect(D1SalesLedgerService.applyEventsToLocalSaleChallans(appSaleChallans, modifyEvents, fy), isTrue);
      expect(D1SalesLedgerService.applyEventsToLocalPurchaseChallans(appPurcChallans, modifyEvents, fy), isTrue);
      expect(appSaleChallans.every((c) => c.version == 2 && c.partyName.startsWith('Updated Party')), isTrue);
      expect(appPurcChallans.every((c) => c.version == 2 && c.distributorName.startsWith('Updated Supplier')), isTrue);

      // 3. Delete all 10 Sale Challans & 10 Purchase Challans (version = 3)
      final List<Map<String, dynamic>> deleteEvents = [];
      for (int i = 1; i <= 10; i++) {
        deleteEvents.add({
          'bill_id': 'sc_v1_$i',
          'bill_no': 'SCH-$i',
          'version': 3,
          'action': 'DELETE_SALE_CHALLAN',
          'fy': fy,
          'updated_at': 30000 + i,
          'sale_data': {'id': 'sc_v1_$i', 'billNo': 'SCH-$i', 'doc_type': 'SALE_CHALLAN', 'fy': fy, 'isDeleted': 1},
        });
        deleteEvents.add({
          'bill_id': 'pc_v1_$i',
          'bill_no': 'PCH-$i',
          'version': 3,
          'action': 'DELETE_PURCHASE_CHALLAN',
          'fy': fy,
          'updated_at': 30000 + i,
          'sale_data': {'id': 'pc_v1_$i', 'internalNo': 'PCH-$i', 'billNo': 'SUP-CH-$i', 'partyId': 'SUP-1', 'doc_type': 'PURCHASE_CHALLAN', 'fy': fy, 'isDeleted': 1},
        });
      }

      expect(D1SalesLedgerService.applyEventsToLocalSaleChallans(appSaleChallans, deleteEvents, fy), isTrue);
      expect(D1SalesLedgerService.applyEventsToLocalPurchaseChallans(appPurcChallans, deleteEvents, fy), isTrue);
      expect(appSaleChallans, isEmpty);
      expect(appPurcChallans, isEmpty);

      // 4. Re-create all 10 Sale Challans (SCH-1..10) & 10 Purchase Challans (PCH-1..10) with fresh UUIDs
      final List<Map<String, dynamic>> recreateEvents = [];
      for (int i = 1; i <= 10; i++) {
        final scNew = makeSaleChallan(
          id: 'sc_recreated_$i',
          billNo: 'SCH-$i',
          partyName: 'Recreated Party $i',
          originalFy: fy,
          version: 1,
          updatedAt: 40000 + i,
        );
        final pcNew = makePurchaseChallan(
          id: 'pc_recreated_$i',
          internalNo: 'PCH-$i',
          billNo: 'SUP-CH-$i',
          distributorName: 'Recreated Supplier $i',
          originalFy: fy,
          version: 1,
          updatedAt: 40000 + i,
        );
        recreateEvents.add({
          'bill_id': scNew.id,
          'bill_no': scNew.billNo,
          'version': 1,
          'action': 'INSERT',
          'fy': fy,
          'updated_at': scNew.updatedAt,
          'sale_data': {...scNew.toMap(), 'doc_type': 'SALE_CHALLAN', 'fy': fy},
        });
        recreateEvents.add({
          'bill_id': pcNew.id,
          'bill_no': pcNew.internalNo,
          'version': 1,
          'action': 'INSERT',
          'fy': fy,
          'updated_at': pcNew.updatedAt,
          'sale_data': {...pcNew.toMap(), 'doc_type': 'PURCHASE_CHALLAN', 'fy': fy},
        });
      }

      expect(D1SalesLedgerService.applyEventsToLocalSaleChallans(appSaleChallans, recreateEvents, fy), isTrue);
      expect(D1SalesLedgerService.applyEventsToLocalPurchaseChallans(appPurcChallans, recreateEvents, fy), isTrue);
      expect(appSaleChallans.length, equals(10));
      expect(appPurcChallans.length, equals(10));
      for (int i = 1; i <= 10; i++) {
        expect(appSaleChallans.any((c) => c.id == 'sc_recreated_$i' && c.billNo == 'SCH-$i'), isTrue);
        expect(appPurcChallans.any((c) => c.id == 'pc_recreated_$i' && c.internalNo == 'PCH-$i'), isTrue);
        // Old deleted UUIDs must remain permanently tombstoned
        expect(D1SalesLedgerService.isSaleChallanIdDeleted('sc_v1_$i', fy), isTrue);
        expect(D1SalesLedgerService.isPurchaseIdDeleted('pc_v1_$i', fy), isTrue);
      }
    });

    test('T14: +45s Clock Skew resilience — Re-created challan with new UUID is never blocked by older deleted challan series tombstone', () {
      const fy = '2026-27';
      // Device A deletes WSCH-1 (id: w_sch_old) at skewed future clock T = 1045000
      D1SalesLedgerService.markSaleChallanPermanentlyDeleted('w_sch_old', 'WSCH-1', fy, 1045000);
      expect(D1SalesLedgerService.isSaleChallanDeleted('w_sch_old', 'WSCH-1', fy, 1045000), isTrue);

      // Device B re-creates WSCH-1 (id: w_sch_new) at local clock T = 1002000 (43s behind Device A!)
      expect(D1SalesLedgerService.isSaleChallanDeleted('w_sch_new', 'WSCH-1', fy, 1002000), isFalse);

      final ph = PharoahManager();
      ph.currentFY = fy;
      final recreatedSc = makeSaleChallan(
        id: 'w_sch_new',
        billNo: 'WSCH-1',
        originalFy: fy,
        version: 1,
        updatedAt: 1002000,
      );

      // Verify DeltaMergeEngine accepts w_sch_new even when tombstoneRegistry has 2026-27::WSCH-1 @ 1045000
      final Map<String, int> registry = {
        'w_sch_old': 1045000,
        'W_SCH_OLD': 1045000,
        '2026-27::WSCH-1': 1045000,
      };
      final Map<String, dynamic> cloudFiles = {
        's_challan.json': jsonEncode([recreatedSc.toMap()]),
      };
      final bool merged = DeltaMergeEngine.processCloudData(ph, cloudFiles, registry, {});
      expect(merged, isTrue);
      expect(ph.saleChallans.length, equals(1));
      expect(ph.saleChallans.first.id, equals('w_sch_new'));
      expect(ph.saleChallans.first.billNo, equals('WSCH-1'));
    });

    test('T15: TombstoneEngine concurrent 10-delete burst mutex prevents SharedPreferences race conditions', () async {
      const cid = 'COMP-BURST-1';
      const fy = '2026-27';

      // Fire 10 concurrent SaleChallan + 10 concurrent PurchaseChallan tombstones simultaneously
      await Future.wait([
        for (int i = 1; i <= 10; i++)
          TombstoneEngine.recordTombstoneWithTimestamp(
            cid,
            id: 'SC-BURST-$i',
            secondaryKey: 'SCH-$i',
            timestamp: 50000 + i,
            fy: fy,
          ),
        for (int i = 1; i <= 10; i++)
          TombstoneEngine.recordTombstoneWithTimestamp(
            cid,
            id: 'PC-BURST-$i',
            secondaryKey: 'PCH-$i',
            timestamp: 60000 + i,
            fy: fy,
          ),
      ]);

      final regAfterDelete = await TombstoneEngine.getTombstoneRegistry(cid);
      final tombsAfterDelete = await TombstoneEngine.getLocalTombstones(cid);
      for (int i = 1; i <= 10; i++) {
        expect(regAfterDelete.containsKey('SC-BURST-$i'), isTrue, reason: 'Missing SC-BURST-$i in registry');
        expect(regAfterDelete.containsKey('PC-BURST-$i'), isTrue, reason: 'Missing PC-BURST-$i in registry');
        expect(tombsAfterDelete.contains('SC-BURST-$i'), isTrue, reason: 'Missing SC-BURST-$i in tombstones');
        expect(tombsAfterDelete.contains('PC-BURST-$i'), isTrue, reason: 'Missing PC-BURST-$i in tombstones');
      }

      // Now fire 10 concurrent unmarks for re-created SCH-1..10 & PCH-1..10
      await Future.wait([
        for (int i = 1; i <= 10; i++)
          TombstoneEngine.unmarkTombstoneWithTimestamp(
            cid,
            id: 'SC-RECREATED-$i',
            secondaryKey: 'SCH-$i',
            timestamp: 70000 + i,
            fy: fy,
          ),
        for (int i = 1; i <= 10; i++)
          TombstoneEngine.unmarkTombstoneWithTimestamp(
            cid,
            id: 'PC-RECREATED-$i',
            secondaryKey: 'PCH-$i',
            timestamp: 80000 + i,
            fy: fy,
          ),
      ]);

      final unmarkReg = await TombstoneEngine.getUnmarkedRegistry(cid);
      for (int i = 1; i <= 10; i++) {
        expect(unmarkReg.containsKey('SC-RECREATED-$i'), isTrue);
        expect(unmarkReg.containsKey('PC-RECREATED-$i'), isTrue);
      }
    });

    test('T16: Outbox exactVersion alignment for SaleChallanSyncModule and PurchaseChallanSyncModule', () {
      SyncQueueManager.debugReset();
      final sc = makeSaleChallan(id: 'sc-ver-1', billNo: 'SCH-1', version: 1, updatedAt: 12345);
      SaleChallanSyncModule.onSaleChallanSaved(sc, 'TOK-1');
      var ops = SyncQueueManager.debugPendingOperations();
      expect(ops.length, equals(1));
      expect(ops.first.version, equals(1));
      expect(ops.first.action, equals('INSERT'));
      expect(ops.first.updatedAt, equals(12345));

      sc.version = 2;
      sc.updatedAt = 23456;
      SaleChallanSyncModule.onSaleChallanSaved(sc, 'TOK-1');
      ops = SyncQueueManager.debugPendingOperations();
      expect(ops.first.version, equals(2));
      expect(ops.first.action, equals('UPDATE'));

      SaleChallanSyncModule.onSaleChallanDeleted(sc, 'TOK-1');
      ops = SyncQueueManager.debugPendingOperations();
      expect(sc.version, equals(3));
      expect(ops.first.version, equals(3));
      expect(ops.first.action, equals('DELETE'));
      expect(ops.first.isDeleted, equals(1));
    });

    test('T17: PharoahWebManager.purgeDeletedIds(fromCumulativePoll: true) preserves unmarkedRecordIds and never deletes Billed challans', () {
      const fy = '2026-27';
      final webPh = PharoahWebManager();
      webPh.financialYear = fy;

      final billedSc = makeSaleChallan(
        id: 'sc-billed-99',
        billNo: 'WSCH-99',
        status: 'Billed',
        originalFy: fy,
      );
      final recreatedSc = makeSaleChallan(
        id: 'sc-fresh-1',
        billNo: 'WSCH-1',
        status: 'Pending',
        originalFy: fy,
        updatedAt: 50000,
      );
      webPh.saleChallans = [billedSc, recreatedSc];
      webPh.unmarkDeletedId('sc-fresh-1', referenceNo: 'WSCH-1', fy: fy);

      // Simulate 2s cumulative edge tombstone poll returning stale 2026-27::WSCH-1 and sc-billed-99
      webPh.purgeDeletedIds(['2026-27::WSCH-1', 'sc-billed-99'], fromCumulativePoll: true);

      // Neither Billed challan nor freshly unmarked WSCH-1 may be evicted!
      expect(webPh.saleChallans.length, equals(2));
      expect(webPh.unmarkedRecordIds.contains('2026-27::WSCH-1'), isTrue);
    });
  });
}
