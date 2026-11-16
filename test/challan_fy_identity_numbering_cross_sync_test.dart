import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharoah_erp/fy_transfer_engine.dart';
import 'package:pharoah_erp/gateway/company_registry_model.dart';
import 'package:pharoah_erp/logic/app_settings_model.dart';
import 'package:pharoah_erp/logic/party_integrity_service.dart';
import 'package:pharoah_erp/logic/pharoah_numbering_engine.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/sync_core/d1_sales_ledger_service.dart';
import 'package:pharoah_erp/sync_core/models/sync_envelope.dart';
import 'package:pharoah_erp/sync_core/modules/purchase_challan_sync_module.dart';
import 'package:pharoah_erp/sync_core/modules/sale_challan_sync_module.dart';
import 'package:pharoah_erp/sync_core/modules/settings_sync_module.dart';
import 'package:pharoah_erp/sync_core/multi_fy_cloud_vault.dart';
import 'package:pharoah_erp/sync_core/orchestrator/master_sync_orchestrator.dart';
import 'package:pharoah_erp/sync_core/outbox/sync_queue_manager.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_billing/web_item_entry_card.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_challans/web_purchase_challan_billing_view.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_challans/web_sale_challan_billing_view.dart';
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
    PharoahNumberingEngine.debugResetHwmCache();
    WebPharoahNumberingEngine.debugResetHwmCache();
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

  group('Group 2: Per-FY Sequential Numbering & Monotonic HWM Enforcement', () {
    test('T5: PharoahNumberingEngine enforces Monotonic HWM per FY ignoring Carry-Forward while blocking deleted-number reuse', () async {
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

      // Carry-forward Y-42 (2025-26) is ignored, while current-FY soft-deleted Y-99 advances monotonic HWM -> Y-100
      final nextSaleChallanNo = await PharoahNumberingEngine.getNextNumber(
        type: 'SALE_CHALLAN',
        companyID: 'COMP-1',
        prefix: 'Y-',
        startFrom: 1,
        targetFy: '2026-27',
        currentList: [carriedFromOldFy, softDeletedCurrentFy],
      );
      expect(nextSaleChallanNo, equals('Y-100'));

      // Fresh FY with only prior-FY Carry-Forward starts cleanly at Y-1
      final nextFreshFy = await PharoahNumberingEngine.getNextNumber(
        type: 'SALE_CHALLAN',
        companyID: 'COMP-1',
        prefix: 'Y-',
        startFrom: 1,
        targetFy: '2027-28',
        currentList: [carriedFromOldFy],
      );
      expect(nextFreshFy, equals('Y-1'));

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
        targetFy: '2026-27',
        currentList: [carriedPurChallan, currentPurChallan],
      );
      expect(nextPurChallanNo, equals('PC-2'));
    });

    test('T6: WebPharoahNumberingEngine isolates numbering by targetFy & WEB env and enforces monotonic HWM across deleted records', () {
      final list = [
        makeSaleChallan(
          id: 'SCH-WEB-OLD',
          billNo: 'Y-50',
          date: DateTime(2026, 3, 25),
          originalFy: '2025-26',
        )..salesmanName = 'WEB-PORTAL',
        makeSaleChallan(
          id: 'sc-app-99',
          billNo: 'Y-99',
          date: DateTime(2026, 4, 18),
          originalFy: '2026-27',
        ), // APP record must NEVER pollute WEB numbering
        makeSaleChallan(
          id: 'SCH-WEB-DEL',
          billNo: 'Y-8',
          date: DateTime(2026, 4, 15),
          originalFy: '2026-27',
          isDeleted: 1,
        )..salesmanName = 'WEB-PORTAL',
        makeSaleChallan(
          id: 'SCH-WEB-CUR',
          billNo: 'Y-1',
          date: DateTime(2026, 4, 20),
          originalFy: '2026-27',
        )..salesmanName = 'WEB-PORTAL',
      ];

      final nextNo = WebPharoahNumberingEngine.getNextNumber(
        prefix: 'Y-',
        startFrom: 1,
        currentList: list,
        targetFy: '2026-2027',
        env: 'WEB',
      );
      expect(nextNo, equals('Y-9'));
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
            id: 'SC-UUID-BURST-$i',
            secondaryKey: 'SCH-$i',
            timestamp: 50000 + i,
            fy: fy,
          ),
        for (int i = 1; i <= 10; i++)
          TombstoneEngine.recordTombstoneWithTimestamp(
            cid,
            id: 'PC-UUID-BURST-$i',
            secondaryKey: 'PCH-$i',
            timestamp: 60000 + i,
            fy: fy,
          ),
      ]);

      final regAfterDelete = await TombstoneEngine.getTombstoneRegistry(cid);
      final tombsAfterDelete = await TombstoneEngine.getLocalTombstones(cid);
      for (int i = 1; i <= 10; i++) {
        expect(regAfterDelete.containsKey('SC-UUID-BURST-$i'), isTrue, reason: 'Missing SC-UUID-BURST-$i in registry');
        expect(regAfterDelete.containsKey('PC-UUID-BURST-$i'), isTrue, reason: 'Missing PC-UUID-BURST-$i in registry');
        expect(tombsAfterDelete.contains('SC-UUID-BURST-$i'), isTrue, reason: 'Missing SC-UUID-BURST-$i in tombstones');
        expect(tombsAfterDelete.contains('PC-UUID-BURST-$i'), isTrue, reason: 'Missing PC-UUID-BURST-$i in tombstones');
      }

      // Now fire 10 concurrent unmarks for re-created SCH-1..10 & PCH-1..10
      await Future.wait([
        for (int i = 1; i <= 10; i++)
          TombstoneEngine.unmarkTombstoneWithTimestamp(
            cid,
            id: 'SC-UUID-RECREATED-$i',
            secondaryKey: 'SCH-$i',
            timestamp: 70000 + i,
            fy: fy,
          ),
        for (int i = 1; i <= 10; i++)
          TombstoneEngine.unmarkTombstoneWithTimestamp(
            cid,
            id: 'PC-UUID-RECREATED-$i',
            secondaryKey: 'PCH-$i',
            timestamp: 80000 + i,
            fy: fy,
          ),
      ]);

      final unmarkReg = await TombstoneEngine.getUnmarkedRegistry(cid);
      for (int i = 1; i <= 10; i++) {
        expect(unmarkReg.containsKey('SC-UUID-RECREATED-$i'), isTrue);
        expect(unmarkReg.containsKey('PC-UUID-RECREATED-$i'), isTrue);
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

    test('T18: App loadAllData, silent reload & pending cascade preserve both Old-FY CF WSCH-1 and New-FY WSCH-1 despite 2026-27::WSCH-1 secondary tombstone', () async {
      const compId = 'COMP_CH_T18_WSCH';
      const bizType = 'WHOLESALE';
      const oldFy = '2025-26';
      const newFy = '2026-27';

      expect(D1SalesLedgerService.isUnscopedSeriesKey('SCH-WEB-1712345678901'), isFalse);
      expect(D1SalesLedgerService.isUnscopedSeriesKey('PCH-WEB-1712345678901'), isFalse);

      final oldDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$oldFy');
      final newDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$newFy');
      await oldDir.create(recursive: true);
      await newDir.create(recursive: true);

      final scOldPending = makeSaleChallan(
        id: 'SCH-WEB-1710000000001',
        billNo: 'WSCH-1',
        date: DateTime(2026, 2, 15),
        status: 'Pending',
        originalFy: oldFy,
        version: 1,
        updatedAt: 10000,
      );
      final scNewPending = makeSaleChallan(
        id: 'SCH-WEB-1710000000002',
        billNo: 'WSCH-1',
        date: DateTime(2026, 5, 10),
        status: 'Pending',
        originalFy: newFy,
        version: 1,
        updatedAt: 20000,
      );

      // Poison secondary key 2026-27::WSCH-1 & 2025-26::WSCH-1 (simulating an earlier deleted copy on D1/Drive)
      D1SalesLedgerService.markSaleChallanPermanentlyDeleted('SCH-WEB-1710000000999', 'WSCH-1', newFy, 999999);
      await TombstoneEngine.recordBatchTombstones(
        compId,
        ['SCH-WEB-1710000000999', '2026-27::WSCH-1'],
        timestamp: 999999,
        fy: newFy,
      );

      await File('${oldDir.path}/s_challan.json').writeAsString(jsonEncode([scOldPending.toMap()]));
      await File('${newDir.path}/s_challan.json').writeAsString(jsonEncode([scOldPending.toMap(), scNewPending.toMap()]));

      final ph = PharoahManager();
      ph.activeCompany = CompanyProfile(
        id: compId,
        name: 'T18 ERP',
        businessType: bizType,
        createdAt: DateTime(2025, 4, 1),
        password: 'pw',
        fYears: [oldFy, newFy],
      );
      ph.currentFY = newFy;
      D1SalesLedgerService.activeFinancialYear = newFy;

      // 1) loadAllData must keep BOTH distinct-UUID WSCH-1 challans (Old CF + New FY)
      await ph.loadAllData();
      expect(ph.saleChallans.length, equals(2));
      expect(ph.saleChallans.map((c) => c.id).toSet(), equals({'SCH-WEB-1710000000001', 'SCH-WEB-1710000000002'}));

      // 2) syncPendingChallansFromPreviousYears must NOT evict SCH-WEB-1710000000001 due to 2026-27::WSCH-1
      await ph.syncPendingChallansFromPreviousYears(reloadActiveIfMutated: false);
      final newDiskAfterCascade = (jsonDecode(await File('${newDir.path}/s_challan.json').readAsString()) as List);
      expect(newDiskAfterCascade.length, equals(2));

      // 3) Silent maintenance reload must also keep both
      await ph.loadDataForMaintenanceSilently(newFy);
      expect(ph.saleChallans.length, equals(2));
    });

    test('T19: Reverse App->Web & App<->App: App-created Old-FY SCH-1 CF + New-FY SCH-1 survive on both App & Web', () async {
      const compId = 'COMP_CH_T19_REV';
      const bizType = 'WHOLESALE';
      const oldFy = '2025-26';
      const newFy = '2026-27';

      final oldDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$oldFy');
      final newDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$newFy');
      await oldDir.create(recursive: true);
      await newDir.create(recursive: true);

      final appOldSc = makeSaleChallan(
        id: '2026-02-10 10:15:00.123456',
        billNo: 'SCH-1',
        date: DateTime(2026, 2, 10),
        status: 'Pending',
        originalFy: oldFy,
        version: 1,
        updatedAt: 10000,
      );
      final appNewSc = makeSaleChallan(
        id: '2026-05-10 11:20:00.654321',
        billNo: 'SCH-1',
        date: DateTime(2026, 5, 10),
        status: 'Pending',
        originalFy: newFy,
        version: 1,
        updatedAt: 20000,
      );

      D1SalesLedgerService.markSaleChallanPermanentlyDeleted('2026-05-01 09:00:00.000999', 'SCH-1', newFy, 999999);
      await File('${oldDir.path}/s_challan.json').writeAsString(jsonEncode([appOldSc.toMap()]));
      await File('${newDir.path}/s_challan.json').writeAsString(jsonEncode([appNewSc.toMap()]));

      final ph = PharoahManager();
      ph.activeCompany = CompanyProfile(
        id: compId,
        name: 'T19 ERP',
        businessType: bizType,
        createdAt: DateTime(2025, 4, 1),
        password: 'pw',
        fYears: [oldFy, newFy],
      );
      ph.currentFY = newFy;
      D1SalesLedgerService.activeFinancialYear = newFy;

      await ph.syncPendingChallansFromPreviousYears(reloadActiveIfMutated: true);
      await ph.loadAllData();
      expect(ph.saleChallans.length, equals(2));
      expect(
        ph.saleChallans.map((c) => c.id).toSet(),
        equals({'2026-02-10 10:15:00.123456', '2026-05-10 11:20:00.654321'}),
      );

      final webPh = PharoahWebManager();
      webPh.availableFinancialYears = [oldFy, newFy];
      webPh.financialYear = newFy;
      webPh.debugParseDownloadedFiles({
        's_challan.json': jsonEncode([appOldSc.toMap(), appNewSc.toMap()]),
      });
      expect(webPh.saleChallans.length, equals(2));
    });

    test('T20: PurchaseChallan WPCH-1 / PCH-1 with shared supplier billNo across FYs survives App & Web load, parse & cascade despite secondary tombstone', () async {
      const compId = 'COMP_CH_T20_PUR';
      const bizType = 'WHOLESALE';
      const oldFy = '2025-26';
      const newFy = '2026-27';

      final oldDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$oldFy');
      final newDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$newFy');
      await oldDir.create(recursive: true);
      await newDir.create(recursive: true);

      final pcOldPending = makePurchaseChallan(
        id: 'PCH-WEB-1710000000001',
        internalNo: 'WPCH-1',
        billNo: 'SUP-INV-100',
        partyId: 'SUP-1',
        date: DateTime(2026, 2, 15),
        status: 'Pending',
        originalFy: oldFy,
        version: 1,
        updatedAt: 10000,
      );
      final pcNewPending = makePurchaseChallan(
        id: 'PCH-WEB-1710000000002',
        internalNo: 'WPCH-1',
        billNo: 'SUP-INV-100',
        partyId: 'SUP-1',
        date: DateTime(2026, 5, 10),
        status: 'Pending',
        originalFy: newFy,
        version: 1,
        updatedAt: 20000,
      );

      // Simulate an earlier deleted PurchaseChallan in 2026-27 or 2025-26 at a newer timestamp
      D1SalesLedgerService.markPurchasePermanentlyDeleted(
        'PCH-WEB-1710000000999',
        'SUP-1',
        'SUP-INV-100',
        'WPCH-1',
        newFy,
        999999,
      );
      expect(
        D1SalesLedgerService.isPurchaseChallanDeleted('PCH-WEB-1710000000999', 'SUP-1', 'SUP-INV-100', 'WPCH-1', newFy, 10000),
        isTrue,
      );
      expect(
        D1SalesLedgerService.isPurchaseChallanDeleted('PCH-WEB-1710000000002', 'SUP-1', 'SUP-INV-100', 'WPCH-1', newFy, 20000),
        isFalse,
      );

      await TombstoneEngine.recordBatchTombstones(
        compId,
        ['PCH-WEB-1710000000999', '2026-27::WPCH-1', '2026-27::SUP-1_SUP-INV-100_WPCH-1'],
        timestamp: 999999,
        fy: newFy,
      );

      await File('${oldDir.path}/p_challan.json').writeAsString(jsonEncode([pcOldPending.toMap()]));
      await File('${newDir.path}/p_challan.json').writeAsString(jsonEncode([pcNewPending.toMap()]));

      final ph = PharoahManager();
      ph.activeCompany = CompanyProfile(
        id: compId,
        name: 'T20 ERP',
        businessType: bizType,
        createdAt: DateTime(2025, 4, 1),
        password: 'pw',
        fYears: [oldFy, newFy],
      );
      ph.currentFY = newFy;
      D1SalesLedgerService.activeFinancialYear = newFy;

      await ph.syncPendingChallansFromPreviousYears(reloadActiveIfMutated: true);
      await ph.loadAllData();
      expect(ph.purchaseChallans.length, equals(2));
      expect(
        ph.purchaseChallans.map((c) => c.id).toSet(),
        equals({'PCH-WEB-1710000000001', 'PCH-WEB-1710000000002'}),
      );

      final webPh = PharoahWebManager();
      webPh.availableFinancialYears = [oldFy, newFy];
      webPh.financialYear = newFy;
      webPh.localTombstoneRegistry['2026-27::WPCH-1'] = 999999;
      webPh.localTombstoneRegistry['2025-26::WPCH-1'] = 999999;
      webPh.fyVault[oldFy] = {'p_challan.json': jsonEncode([pcOldPending.toMap()])};
      webPh.fyVault[newFy] = {'p_challan.json': jsonEncode([pcNewPending.toMap()])};
      webPh.debugCascadeVaultFrom(oldFy);
      final List cascadedWebPCh = jsonDecode(webPh.fyVault[newFy]!['p_challan.json']!) as List;
      expect(cascadedWebPCh.length, equals(2));
      webPh.debugParseDownloadedFiles({
        'p_challan.json': webPh.fyVault[newFy]!['p_challan.json']!,
      });
      expect(webPh.purchaseChallans.length, equals(2));
      expect(
        webPh.purchaseChallans.map((c) => c.id).toSet(),
        equals({'PCH-WEB-1710000000001', 'PCH-WEB-1710000000002'}),
      );
    });
  });

  group('Group 8: Monotonic HWM, Last-Draft Delete, Middle-Cancel, Cross-Env Isolation & Web FINISH Guard (Scenarios 1-12)', () {
    test('Scenario 1: Sale & Purchase SCH-1..5 / PCH-1..5 — only last eligible draft deletes and HWM stays locked at 5 -> next is 6', () async {
      const compId = 'COMP-SCEN-1';
      SharedPreferences.setMockInitialValues({'active_fy_$compId': '2026-27'});
      final ph = PharoahManager();
      ph.activeCompany = CompanyProfile(
        id: compId,
        name: 'Scen 1 Pharmacy',
        businessType: 'Retail',
        createdAt: DateTime(2026, 4, 1),
        password: 'pw',
        fYears: ['2026-27'],
      );
      ph.currentFY = '2026-27';
      D1SalesLedgerService.activeFinancialYear = '2026-27';
      final party = Party(id: 'P1', name: 'Customer One', state: 'Rajasthan');
      final sup = Party(id: 'S1', name: 'Supplier One', group: 'Sundry Creditors');

      for (int i = 1; i <= 5; i++) {
        await ph.finalizeSaleChallan(
          billNo: 'SCH-$i',
          date: DateTime(2026, 5, i),
          party: party,
          items: [
            BillItem(
              id: 'BI-$i',
              srNo: 1,
              medicineID: 'MED-1',
              name: 'PARA 500',
              packing: '10T',
              batch: 'B1',
              exp: '12/27',
              hsn: '3004',
              mrp: 50,
              qty: 1,
              rate: 40,
              gstRate: 12,
              total: 40,
            ),
          ],
          total: 40,
          partyId: 'P1',
          existingId: 'SC-UUID-$i',
        );
        await ph.finalizePurchaseChallan(
          billNo: 'SUP-$i',
          internalNo: 'PCH-$i',
          date: DateTime(2026, 5, i),
          party: sup,
          items: [
            PurchaseItem(
              id: 'PI-$i',
              srNo: 1,
              medicineID: 'MED-1',
              name: 'PARA 500',
              packing: '10T',
              batch: 'B1',
              exp: '12/27',
              hsn: '3004',
              mrp: 50,
              qty: 2,
              purchaseRate: 30,
              gstRate: 12,
              total: 60,
            ),
          ],
          total: 60,
          partyId: 'S1',
          existingId: 'PC-UUID-$i',
        );
      }

      // Only #5 is eligible for hard delete
      expect(ph.canDeleteSaleChallan('SC-UUID-2'), isFalse);
      expect(ph.canDeleteSaleChallan('SC-UUID-4'), isFalse);
      expect(ph.canDeleteSaleChallan('SC-UUID-5'), isTrue);
      expect(ph.canDeletePurchaseChallan('PC-UUID-3'), isFalse);
      expect(ph.canDeletePurchaseChallan('PC-UUID-5'), isTrue);

      // Middle delete refused
      expect(await ph.deleteSaleChallanAsync('SC-UUID-2'), isFalse);
      expect(await ph.deletePurchaseChallanAsync('PC-UUID-3'), isFalse);

      // Last-draft delete succeeds
      expect(await ph.deleteSaleChallanAsync('SC-UUID-5'), isTrue);
      expect(await ph.deletePurchaseChallanAsync('PC-UUID-5'), isTrue);

      // Now #4 MUST still be blocked from hard delete because HWM is locked at 5!
      expect(ph.canDeleteSaleChallan('SC-UUID-4'), isFalse);
      expect(ph.canDeletePurchaseChallan('PC-UUID-4'), isFalse);

      // Next generated numbers MUST be 6, never 5
      final nextSc = await PharoahNumberingEngine.getNextNumber(
        type: 'SALE_CHALLAN',
        companyID: compId,
        prefix: 'SCH-',
        startFrom: 1,
        targetFy: '2026-27',
        currentList: ph.saleChallans,
        configHwm: ph.config.challanHwm,
      );
      final nextPc = await PharoahNumberingEngine.getNextNumber(
        type: 'PURCHASE_CHALLAN',
        companyID: compId,
        prefix: 'PCH-',
        startFrom: 1,
        targetFy: '2026-27',
        currentList: ph.purchaseChallans,
        configHwm: ph.config.challanHwm,
      );
      expect(nextSc, equals('SCH-6'));
      expect(nextPc, equals('PCH-6'));
    });

    test('Scenario 2 & 10: Middle Challan Cancel preserves UUID/number, excludes Cancelled from stock/totals/party-block, allows Supplier Ref re-entry', () async {
      const compId = 'COMP-SCEN-2';
      SharedPreferences.setMockInitialValues({'active_fy_$compId': '2026-27'});
      final ph = PharoahManager();
      ph.activeCompany = CompanyProfile(
        id: compId,
        name: 'Scen 2 Pharmacy',
        businessType: 'Retail',
        createdAt: DateTime(2026, 4, 1),
        password: 'pw',
        fYears: ['2026-27'],
      );
      ph.currentFY = '2026-27';
      D1SalesLedgerService.activeFinancialYear = '2026-27';
      final party = Party(id: 'P2', name: 'Middle Party', state: 'Rajasthan');
      final sup = Party(id: 'S2', name: 'Middle Supplier', group: 'Sundry Creditors');

      ph.medicines = [
        Medicine(
          id: 'MED-ST',
          systemId: 'PH-900',
          name: 'AMOX 500',
          packing: '10C',
          mrp: 100,
          rateA: 80,
          purRate: 60,
          stock: 25,
        ),
      ];

      for (int i = 1; i <= 3; i++) {
        await ph.finalizeSaleChallan(
          billNo: 'SCH-$i',
          date: DateTime(2026, 6, i),
          party: party,
          items: [
            BillItem(
              id: 'SBI-$i',
              srNo: 1,
              medicineID: 'MED-ST',
              name: 'AMOX 500',
              packing: '10C',
              batch: 'B1',
              exp: '12/27',
              hsn: '3004',
              mrp: 100,
              qty: 2,
              rate: 80,
              gstRate: 12,
              total: 160,
            ),
          ],
          total: 160,
          partyId: 'P2',
          existingId: 'SC2-$i',
        );
        await ph.finalizePurchaseChallan(
          billNo: i == 2 ? 'SUP-202' : 'SUP-10$i',
          internalNo: 'PCH-$i',
          date: DateTime(2026, 6, i),
          party: sup,
          items: [
            PurchaseItem(
              id: 'PBI-$i',
              srNo: 1,
              medicineID: 'MED-ST',
              name: 'AMOX 500',
              packing: '10C',
              batch: 'B1',
              exp: '12/27',
              hsn: '3004',
              mrp: 100,
              qty: 5,
              purchaseRate: 60,
              gstRate: 12,
              total: 300,
            ),
          ],
          total: 300,
          partyId: 'S2',
          existingId: 'PC2-$i',
        );
      }

      final stockBeforeCancel = ph.medicines.first.stock;
      expect(await ph.cancelSaleChallan('SC2-2'), isTrue);
      expect(await ph.cancelPurchaseChallan('PC2-2'), isTrue);

      final cancelledSc = ph.saleChallans.firstWhere((c) => c.id == 'SC2-2');
      final cancelledPc = ph.purchaseChallans.firstWhere((c) => c.id == 'PC2-2');
      expect(cancelledSc.status, equals('Cancelled'));
      expect(cancelledSc.isDeleted, equals(0));
      expect(cancelledSc.billNo, equals('SCH-2'));
      expect(cancelledPc.status, equals('Cancelled'));
      expect(cancelledPc.isDeleted, equals(0));
      expect(cancelledPc.internalNo, equals('PCH-2'));

      // Scenario 10: Cancelling a Pending challan must have zero stock mutation
      expect(ph.medicines.first.stock, equals(stockBeforeCancel));

      // Supplier Ref SUP-202 can now be re-entered cleanly with new PCH-4
      final dupCheck = findDuplicateSupplierChallan(
        challans: ph.purchaseChallans,
        partyId: 'S2',
        partyName: sup.name,
        billNo: 'SUP-202',
        targetFy: '2026-27',
      );
      expect(dupCheck, isNull);
      expect(
        await ph.finalizePurchaseChallan(
          billNo: 'SUP-202',
          internalNo: 'PCH-4',
          date: DateTime(2026, 6, 10),
          party: sup,
          items: cancelledPc.items,
          total: 300,
          partyId: 'S2',
          existingId: 'PC2-4',
        ),
        isTrue,
      );

      // PartyIntegrityService ignores Cancelled challans
      final partyOnlyCancelled = Party(id: 'P-CANC', name: 'Cancelled Only Party');
      final elig = PartyIntegrityService.checkPartyDeletionEligibilityForLists(
        sales: const [],
        purchases: const [],
        vouchers: const [],
        saleChallans: [
          makeSaleChallan(id: 'SC-CANC', billNo: 'SCH-9', partyId: 'P-CANC', partyName: 'Cancelled Only Party', status: 'Cancelled'),
        ],
        purchaseChallans: [
          makePurchaseChallan(id: 'PC-CANC', internalNo: 'PCH-9', billNo: 'SUP-9', partyId: 'P-CANC', distributorName: 'Cancelled Only Party', status: 'Cancelled'),
        ],
        saleReturns: const [],
        purchaseReturns: const [],
        party: partyOnlyCancelled,
      );
      expect(elig.canDelete, isTrue);

      final nextSc = await PharoahNumberingEngine.getNextNumber(
        type: 'SALE_CHALLAN',
        companyID: compId,
        prefix: 'SCH-',
        startFrom: 1,
        targetFy: '2026-27',
        currentList: ph.saleChallans,
        configHwm: ph.config.challanHwm,
      );
      expect(nextSc, equals('SCH-4'));
    });

    test('Scenario 3, 4 & 5: App & Web counters and Delete/Cancel actions stay 100% isolated (even sharing SCH-/PCH- prefix)', () async {
      final appSales = [
        for (int i = 1; i <= 3; i++)
          makeSaleChallan(id: 'SC-APP-$i', billNo: 'SCH-$i', originalFy: '2026-27'),
      ];
      final webSales = [
        for (int i = 1; i <= 5; i++)
          makeSaleChallan(id: 'SCH-WEB-$i', billNo: 'SCH-$i', originalFy: '2026-27')
            ..salesmanName = 'WEB-PORTAL',
        for (int i = 1; i <= 5; i++)
          makeSaleChallan(id: 'SCH-WEB-W$i', billNo: 'WSCH-$i', originalFy: '2026-27')
            ..salesmanName = 'WEB-PORTAL',
      ];
      final combined = [...appSales, ...webSales];

      final nextApp = await PharoahNumberingEngine.getNextNumber(
        type: 'SALE_CHALLAN',
        companyID: 'COMP-ISO',
        prefix: 'SCH-',
        startFrom: 1,
        targetFy: '2026-27',
        env: 'APP',
        currentList: combined,
      );
      final nextWebSamePrefix = WebPharoahNumberingEngine.getNextNumber(
        prefix: 'SCH-',
        startFrom: 1,
        currentList: combined,
        targetFy: '2026-27',
        env: 'WEB',
        companyID: 'COMP-ISO',
      );
      final nextWebOwnPrefix = WebPharoahNumberingEngine.getNextNumber(
        prefix: 'WSCH-',
        startFrom: 1,
        currentList: combined,
        targetFy: '2026-27',
        env: 'WEB',
        companyID: 'COMP-ISO',
      );
      expect(nextApp, equals('SCH-4'));
      expect(nextWebSamePrefix, equals('SCH-6'));
      expect(nextWebOwnPrefix, equals('WSCH-6'));

      // Scenario 4 & 5: Cancel/Delete on Web does not touch App's SCH-2/SCH-3
      final webPh = PharoahWebManager();
      webPh.financialYear = '2026-27';
      webPh.saleChallans = List.from(combined);
      expect(webPh.cancelSaleChallan('SCH-WEB-2'), isTrue);
      expect(webPh.deleteSaleChallan('SCH-WEB-5'), isTrue);

      expect(webPh.saleChallans.firstWhere((c) => c.id == 'SC-APP-2').status, equals('Pending'));
      expect(webPh.saleChallans.any((c) => c.id == 'SC-APP-3'), isTrue);
      expect(
        WebPharoahNumberingEngine.getNextNumber(
          prefix: 'SCH-',
          startFrom: 1,
          currentList: webPh.saleChallans,
          targetFy: '2026-27',
          env: 'WEB',
          configHwm: webPh.appConfig.challanHwm,
        ),
        equals('SCH-6'),
      );
    });

    test('Scenario 6 & 7: Restart recovery loads persisted HWM from Prefs & 2-Device Offline HWM Sync merges via Math.max', () async {
      const compId = 'COMP-RST';
      SharedPreferences.setMockInitialValues({'active_fy_$compId': '2026-27'});

      await PharoahNumberingEngine.recordChallanHwm(
        companyID: compId,
        type: 'SALE_CHALLAN',
        prefix: 'SCH-',
        number: 'SCH-5',
        fy: '2026-27',
        env: 'APP',
      );
      WebPharoahNumberingEngine.recordChallanHwm(
        companyID: compId,
        prefix: 'WSCH-',
        number: 'WSCH-5',
        fy: '2026-27',
        env: 'WEB',
      );
      // Give microtask/SharedPreferences flush time to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Simulate cold app & web restart by wiping in-memory caches
      PharoahNumberingEngine.debugResetHwmCache();
      WebPharoahNumberingEngine.debugResetHwmCache();
      await PharoahNumberingEngine.loadFromPrefs();
      await WebPharoahNumberingEngine.loadFromPrefs();

      final afterRestartApp = await PharoahNumberingEngine.getNextNumber(
        type: 'SALE_CHALLAN',
        companyID: compId,
        prefix: 'SCH-',
        startFrom: 1,
        targetFy: '2026-27',
        env: 'APP',
        currentList: const [],
      );
      final afterRestartWeb = WebPharoahNumberingEngine.getNextNumber(
        companyID: compId,
        prefix: 'WSCH-',
        startFrom: 1,
        targetFy: '2026-27',
        env: 'WEB',
        currentList: const [],
      );
      expect(afterRestartApp, equals('SCH-6'));
      expect(afterRestartWeb, equals('WSCH-6'));

      // Scenario 7: 2-device offline HWM merge via SettingsSyncModule & AppConfig.mergeHwmMaps
      final cfgA = AppConfig(challanHwm: {
        '${compId}::2026-27::SALE_CHALLAN::APP::SCH-': 3,
        '${compId}::2026-27::SALE_CHALLAN::WEB::WSCH-': 8,
      });
      final cfgB = AppConfig(challanHwm: {
        '${compId}::2026-27::SALE_CHALLAN::APP::SCH-': 7,
        '${compId}::2026-27::SALE_CHALLAN::WEB::WSCH-': 4,
      });
      final merged = AppConfig.mergeHwmMaps(cfgA.challanHwm, cfgB.challanHwm);
      expect(merged['${compId}::2026-27::SALE_CHALLAN::APP::SCH-'], equals(7));
      expect(merged['${compId}::2026-27::SALE_CHALLAN::WEB::WSCH-'], equals(8));

      late AppConfig syncedCfg;
      final mutated = SettingsSyncModule.applyEdgeEventsToLocalConfig(
        currentConfig: cfgA,
        edgeEvents: [
          {
            'bill_id': SettingsSyncModule.syncIdConfig,
            'sale_data': {
              ...cfgB.toMap(),
              'fy': '2026-27',
              'version': 1,
              'updatedAt': 1000,
            },
          }
        ],
        onConfigMutated: (c) => syncedCfg = c,
      );
      expect(mutated, isTrue);
      expect(syncedCfg.challanHwm['${compId}::2026-27::SALE_CHALLAN::APP::SCH-'], equals(7));
      expect(syncedCfg.challanHwm['${compId}::2026-27::SALE_CHALLAN::WEB::WSCH-'], equals(8));
    });

    test('Scenario 8 & 9: Distinct UUIDs with same visible SCH-1/PCH-1 coexist; Billed & Signed Challans block Delete and Cancel', () async {
      const compId = 'COMP-SCEN-8';
      SharedPreferences.setMockInitialValues({'active_fy_$compId': '2026-27'});
      final ph = PharoahManager();
      ph.activeCompany = CompanyProfile(
        id: compId,
        name: 'Scen 8 Pharmacy',
        businessType: 'Retail',
        createdAt: DateTime(2026, 4, 1),
        password: 'pw',
        fYears: ['2026-27'],
      );
      ph.currentFY = '2026-27';
      D1SalesLedgerService.activeFinancialYear = '2026-27';
      final p1 = Party(id: 'P1', name: 'Party One', state: 'Rajasthan');
      final p2 = Party(id: 'P2', name: 'Party Two', state: 'Rajasthan');
      final sup1 = Party(id: 'S1', name: 'Sup One', group: 'Sundry Creditors');

      // Scenario 8: Two distinct UUIDs both numbered SCH-1 in same FY coexist without overwrite
      await ph.finalizeSaleChallan(
        billNo: 'SCH-1',
        date: DateTime(2026, 5, 1),
        party: p1,
        items: const [],
        total: 100,
        partyId: 'P1',
        existingId: 'UUID-APP-SCH-1',
      );
      await ph.finalizeSaleChallan(
        billNo: 'SCH-1',
        date: DateTime(2026, 5, 2),
        party: p2,
        items: const [],
        total: 200,
        partyId: 'P2',
        existingId: 'UUID-WEB-SCH-1',
      );
      expect(ph.saleChallans.where((c) => c.billNo == 'SCH-1').length, equals(2));

      // Distinct UUIDs for PurchaseChallan PCH-1 with distinct suppliers also coexist
      await ph.finalizePurchaseChallan(
        billNo: 'REF-A',
        internalNo: 'PCH-1',
        date: DateTime(2026, 5, 1),
        party: sup1,
        items: const [],
        total: 150,
        partyId: 'S1',
        existingId: 'UUID-APP-PCH-1',
      );
      await ph.finalizePurchaseChallan(
        billNo: 'REF-B',
        internalNo: 'PCH-1',
        date: DateTime(2026, 5, 2),
        party: Party(id: 'S2', name: 'Sup Two', group: 'Sundry Creditors'),
        items: const [],
        total: 250,
        partyId: 'S2',
        existingId: 'UUID-WEB-PCH-1',
      );
      expect(ph.purchaseChallans.where((c) => c.internalNo == 'PCH-1').length, equals(2));

      // Scenario 9: Signed SaleChallan & Billed Sale/Purchase Challan block Delete; Billed blocks Cancel too
      final signedSc = makeSaleChallan(id: 'SC-SIGNED', billNo: 'SCH-99', originalFy: '2026-27')
        ..isSigned = true;
      final billedSc = makeSaleChallan(id: 'SC-BILLED', billNo: 'SCH-100', status: 'Billed', originalFy: '2026-27');
      final billedPc = makePurchaseChallan(id: 'PC-BILLED', internalNo: 'PCH-100', billNo: 'REF-100', status: 'Billed', originalFy: '2026-27');
      ph.saleChallans.addAll([signedSc, billedSc]);
      ph.purchaseChallans.add(billedPc);

      expect(ph.canDeleteSaleChallan('SC-SIGNED'), isFalse);
      expect(await ph.deleteSaleChallanAsync('SC-SIGNED'), isFalse);
      expect(ph.canDeleteSaleChallan('SC-BILLED'), isFalse);
      expect(await ph.deleteSaleChallanAsync('SC-BILLED'), isFalse);
      expect(await ph.cancelSaleChallan('SC-BILLED'), isFalse);
      expect(ph.canDeletePurchaseChallan('PC-BILLED'), isFalse);
      expect(await ph.deletePurchaseChallanAsync('PC-BILLED'), isFalse);
      expect(await ph.cancelPurchaseChallan('PC-BILLED'), isFalse);
    });

    testWidgets('Scenario 11: Web Sale & Purchase Challan FINISH rapid double-tap creates ONLY 1 challan (no twin WSCH-1+WSCH-2)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final webPh = PharoahWebManager();
      webPh.financialYear = '2026-27';
      webPh.medicines = [
        Medicine(
          id: 'MED-DT',
          systemId: 'PH-DT1',
          name: 'PARACETAMOL 500',
          packing: '10T',
          mrp: 30.0,
          rateA: 24.0,
          purRate: 18.0,
          stock: 100.0,
        ),
      ];
      final customer = Party(id: 'C-DT', name: 'DoubleTap Customer', state: 'Rajasthan');
      final supplier = Party(id: 'S-DT', name: 'DoubleTap Supplier', group: 'Sundry Creditors');

      await tester.pumpWidget(
        ChangeNotifierProvider<PharoahWebManager>.value(
          value: webPh,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).push(
                        MaterialPageRoute(
                          builder: (_) => WebSaleChallanBillingView(
                            party: customer,
                            challanNo: 'WSCH-1',
                            challanDate: DateTime(2026, 7, 15),
                          ),
                        ),
                      ),
                      child: const Text('OPEN_SALE_DT'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).push(
                        MaterialPageRoute(
                          builder: (_) => WebPurchaseChallanBillingView(
                            supplier: supplier,
                            internalNo: 'WPCH-1',
                            supplierRefNo: 'SUP-DT-1',
                            challanDate: DateTime(2026, 7, 15),
                          ),
                        ),
                      ),
                      child: const Text('OPEN_PUR_DT'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // 1. WebSaleChallanBillingView double-tap FINISH test
      await tester.tap(find.text('OPEN_SALE_DT'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'PARA');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sc_med_MED-DT_0')));
      await tester.pumpAndSettle();
      expect(find.byType(WebItemEntryCard), findsOneWidget);
      await tester.tap(find.text('CONFIRM & ADD TO INVOICE'));
      await tester.pumpAndSettle();

      final finishSaleBtn = find.text('FINISH');
      expect(finishSaleBtn, findsOneWidget);
      // Rapid double tap before navigation completes
      await tester.tap(finishSaleBtn);
      await tester.tap(finishSaleBtn, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(webPh.saleChallans.length, equals(1));
      expect(webPh.saleChallans.single.billNo, equals('WSCH-1'));
      expect(find.text('OPEN_PUR_DT'), findsOneWidget);

      // 2. WebPurchaseChallanBillingView double-tap FINISH test
      await tester.tap(find.text('OPEN_PUR_DT'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'PARA');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pc_med_MED-DT_0')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('CONFIRM & ADD TO INWARD'));
      await tester.tap(find.text('CONFIRM & ADD TO INWARD'));
      await tester.pumpAndSettle();

      final finishPurBtn = find.text('FINISH');
      expect(finishPurBtn, findsOneWidget);
      await tester.tap(finishPurBtn);
      await tester.tap(finishPurBtn, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(webPh.purchaseChallans.length, equals(1));
      expect(webPh.purchaseChallans.single.internalNo, equals('WPCH-1'));
      expect(find.text('OPEN_SALE_DT'), findsOneWidget);
    });

    test('Scenario 12: Migration bootstrap picks max(persisted, active/cancelled, tombstones) + 1 safely', () async {
      const compId = 'COMP-MIG';
      SharedPreferences.setMockInitialValues({'active_fy_$compId': '2026-27'});

      final active = makeSaleChallan(id: 'SC-M-2', billNo: 'SCH-2', status: 'Pending', originalFy: '2026-27');
      final cancelled = makeSaleChallan(id: 'SC-M-4', billNo: 'SCH-4', status: 'Cancelled', originalFy: '2026-27');
      final wrongFyTombstone = '2025-26::APP::SCH-99';
      final validFyTombstone = '2026-27::APP::SCH-7';
      final crossEnvTombstone = '2026-27::WEB::SCH-50';

      final nextMigrated = await PharoahNumberingEngine.getNextNumber(
        type: 'SALE_CHALLAN',
        companyID: compId,
        prefix: 'SCH-',
        startFrom: 1,
        targetFy: '2026-27',
        env: 'APP',
        currentList: [active, cancelled],
        configHwm: {
          '${compId}::2026-27::SALE_CHALLAN::APP::SCH-': 5,
        },
        tombstones: [wrongFyTombstone, validFyTombstone, crossEnvTombstone],
      );
      // Must ignore 2025-26::APP::SCH-99 and 2026-27::WEB::SCH-50, and pick max(5, 4, 7) + 1 = SCH-8
      expect(nextMigrated, equals('SCH-8'));
    });
  });
}

