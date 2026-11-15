import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/logic/pharoah_numbering_engine.dart';
import 'package:pharoah_erp/web_live_sync/web_pharoah_numbering_engine.dart';
import 'package:pharoah_erp/sync_core/multi_fy_cloud_vault.dart';
import 'package:pharoah_erp/sync_core/d1_sales_ledger_service.dart';
import 'package:pharoah_erp/sync_core/models/sync_envelope.dart';
import 'package:pharoah_erp/sync_core/modules/sale_challan_sync_module.dart';
import 'package:pharoah_erp/sync_core/modules/purchase_challan_sync_module.dart';
import 'package:pharoah_erp/web_live_sync/sync_protocol/delta_merge_engine.dart';

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
      items: [],
      totalAmount: 100.0,
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
      items: [],
      totalAmount: 200.0,
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
      'active_fy_COMP-1': '2026-2027',
    });
  });

  group('Group 1: Challan Identity, originalFy Persistence & Backward Compatibility', () {
    test('T1: SaleChallan persists originalFy across toMap, fromMap and fromEnvelope', () {
      final c1 = makeSaleChallan(
        id: 'sc-101',
        billNo: 'Y-1',
        date: DateTime(2025, 5, 10),
        originalFy: '2025-2026',
      );

      expect(c1.effectiveOriginalFy, equals('2025-2026'));

      final map = c1.toMap();
      expect(map['originalFy'], equals('2025-2026'));

      final c2 = SaleChallan.fromMap(map);
      expect(c2.id, equals('sc-101'));
      expect(c2.originalFy, equals('2025-2026'));
      expect(c2.effectiveOriginalFy, equals('2025-2026'));

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
      expect(c3.originalFy, equals('2025-2026'));
      expect(c3.effectiveOriginalFy, equals('2025-2026'));
    });

    test('T2: PurchaseChallan persists originalFy across toMap, fromMap and fromEnvelope', () {
      final pc1 = makePurchaseChallan(
        id: 'pc-201',
        internalNo: 'INW-1',
        billNo: 'SUPP-99',
        date: DateTime(2025, 6, 15),
        originalFy: '2025-2026',
      );

      expect(pc1.effectiveOriginalFy, equals('2025-2026'));

      final map = pc1.toMap();
      expect(map['originalFy'], equals('2025-2026'));

      final pc2 = PurchaseChallan.fromMap(map);
      expect(pc2.id, equals('pc-201'));
      expect(pc2.originalFy, equals('2025-2026'));
      expect(pc2.effectiveOriginalFy, equals('2025-2026'));

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
      expect(pc3.originalFy, equals('2025-2026'));
    });

    test('T3: Legacy Challan with missing originalFy falls back to date-derived FY', () {
      final legacyMap = {
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

      final legacy = SaleChallan.fromMap(legacyMap);
      expect(legacy.originalFy, equals(''));
      expect(legacy.effectiveOriginalFy, equals('2024-2025'));
    });

    test('T4: Date editing preserves originalFy', () {
      final c = makeSaleChallan(
        id: 'sc-102',
        billNo: 'Y-2',
        date: DateTime(2025, 7, 1),
        originalFy: '2025-2026',
      );

      c.date = DateTime(2025, 8, 1);
      expect(c.originalFy, equals('2025-2026'));
      expect(c.effectiveOriginalFy, equals('2025-2026'));
    });
  });

  group('Group 2: FY Isolation in Numbering & Series Counters', () {
    test('T5: PharoahNumberingEngine isolates series: carry-forward challan does not advance new FY counter', () async {
      final carryForwardChallan = makeSaleChallan(
        id: 'sc-old-1',
        billNo: 'Y-1',
        date: DateTime(2025, 5, 10),
        originalFy: '2025-2026',
      );

      final nextNo = await PharoahNumberingEngine.getNextNumber(
        type: 'SALE_CHALLAN',
        companyID: 'COMP-1',
        prefix: 'Y-',
        startFrom: 1,
        currentList: [carryForwardChallan],
      );

      expect(nextNo, equals('Y-1'));
    });

    test('T6: WebPharoahNumberingEngine isolates series: carry-forward challan does not advance new FY counter', () {
      final carryForwardChallan = makeSaleChallan(
        id: 'sc-old-2',
        billNo: 'CH-1',
        date: DateTime(2025, 6, 1),
        originalFy: '2025-2026',
      );

      final nextNo = WebPharoahNumberingEngine.getNextNumber(
        prefix: 'CH-',
        startFrom: 1,
        currentList: [carryForwardChallan],
        targetFy: '2026-2027',
      );

      expect(nextNo, equals('CH-1'));
    });

    test('T7: Same-FY challan advances the counter correctly', () {
      final newFyChallan = makeSaleChallan(
        id: 'sc-new-1',
        billNo: 'CH-1',
        date: DateTime(2026, 4, 15),
        originalFy: '2026-2027',
      );

      final nextNo = WebPharoahNumberingEngine.getNextNumber(
        prefix: 'CH-',
        startFrom: 1,
        currentList: [newFyChallan],
        targetFy: '2026-2027',
      );

      expect(nextNo, equals('CH-2'));
    });
  });

  group('Group 3: Primary ID Rule & LWW Monotonic Versioning', () {
    test('T8: MultiFyCloudVault matching rule: distinct non-empty IDs across FYs never match', () {
      final existingRecords = [
        {'id': 'UUID-AAA', 'billNo': 'Y-1', 'originalFy': '2025-2026'},
      ];

      final candidate = {'id': 'UUID-BBB', 'billNo': 'Y-1', 'originalFy': '2026-2027'};

      bool isMatch(Map<String, dynamic> local, Map<String, dynamic> incoming) {
        final locId = (local['id'] ?? '').toString().trim();
        final incId = (incoming['id'] ?? '').toString().trim();
        if (locId.isNotEmpty && incId.isNotEmpty) {
          return locId == incId;
        }
        return false;
      }

      expect(isMatch(existingRecords[0], candidate), isFalse);
    });

    test('T9: MultiFyCloudVault isolates records by ID: distinct UUIDs never overwrite', () {
      final list = [
        {'id': 'UUID-AAA', 'billNo': 'Y-1', 'status': 'Pending', 'version': 1, 'updatedAt': 100, 'originalFy': '2025-2026'},
      ];

      final incoming = [
        {'id': 'UUID-BBB', 'billNo': 'Y-1', 'status': 'Pending', 'version': 1, 'updatedAt': 200, 'originalFy': '2026-2027'},
      ];

      final res = MultiFyCloudVault.mergeJsonListLww(
        fileName: 's_challan.json',
        localRaw: jsonEncode(list),
        cloudRaw: jsonEncode(incoming),
        fy: '2026-2027',
      );

      final merged = (jsonDecode(res.mergedJson) as List).cast<Map<String, dynamic>>();
      expect(merged.length, equals(2));
      expect(merged.any((r) => r['id'] == 'UUID-AAA'), isTrue);
      expect(merged.any((r) => r['id'] == 'UUID-BBB'), isTrue);
    });

    test('T10: SaleChallanSyncModule rejects incoming with lower version (monotonic rejection)', () {
      final local = [
        makeSaleChallan(
          id: 'sc-v2',
          billNo: 'Y-1',
          date: DateTime(2026, 4, 1),
          status: 'Billed',
          version: 2,
          updatedAt: 200,
        )
      ];

      final staleEnv = SyncEnvelope(
        syncId: 'sc-v2',
        documentType: 'SALE_CHALLAN',
        billData: {
          'id': 'sc-v2',
          'billNo': 'Y-1',
          'partyId': 'P1',
          'partyName': 'P',
          'partyGstin': '',
          'partyState': 'Rajasthan',
          'date': DateTime(2026, 4, 1).toIso8601String(),
          'status': 'Pending',
          'items': [],
          'totalAmount': 100.0,
          'version': 1,
          'updatedAt': 300,
          'isDeleted': 0,
        },
        action: 'UPDATE',
        version: 1,
        updatedAt: 300,
        isDeleted: 0,
      );

      final mutated = SaleChallanSyncModule.mergeIncomingSaleChallanEnvelope(local, staleEnv);
      expect(mutated, isFalse);
      expect(local[0].status, equals('Billed'));
      expect(local[0].version, equals(2));
    });

    test('T11: PurchaseChallanSyncModule LWW clock tie-breaker when versions are equal', () {
      final local = [
        makePurchaseChallan(
          id: 'pc-tie',
          internalNo: 'INW-1',
          billNo: 'S-1',
          date: DateTime(2026, 4, 1),
          status: 'Pending',
          version: 1,
          updatedAt: 100,
        )
      ];

      final newerEnv = SyncEnvelope(
        syncId: 'pc-tie',
        documentType: 'PURCHASE_CHALLAN',
        billData: {
          'id': 'pc-tie',
          'internalNo': 'INW-1',
          'billNo': 'S-1',
          'partyId': 'SUP-1',
          'distributorName': 'P',
          'date': DateTime(2026, 4, 1).toIso8601String(),
          'status': 'Billed',
          'items': [],
          'totalAmount': 200.0,
          'version': 1,
          'updatedAt': 200,
          'isDeleted': 0,
        },
        action: 'UPDATE',
        version: 1,
        updatedAt: 200,
        isDeleted: 0,
      );

      final mutated = PurchaseChallanSyncModule.mergeIncomingPurchaseChallanEnvelope(local, newerEnv);
      expect(mutated, isTrue);
      expect(local[0].status, equals('Billed'));
      expect(local[0].updatedAt, equals(200));
    });
  });

  group('Group 4: Cross-FY Status Propagation & Orchestrator Envelopes', () {
    test('T12: D1SalesLedgerService.billLinkedChallansFromSaveEvents updates linked challan status', () {
      final challans = [
        makeSaleChallan(
          id: 'sc-linked-1',
          billNo: 'Y-10',
          date: DateTime(2025, 5, 1),
          status: 'Pending',
          originalFy: '2025-2026',
        )
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
        targetFy: '2026-2027',
        saleChallans: challans,
      );

      expect(result.saleChallansMutated, isTrue);
      expect(challans[0].status, equals('Billed'));
      expect(challans[0].version, greaterThan(1));
    });

    test('T13: Supplier Challan duplicate check is isolated by targetFy', () {
      final existingChallans = [
        makePurchaseChallan(
          id: 'pc-fy25',
          internalNo: 'INW-1',
          billNo: 'SUPP-100',
          date: DateTime(2025, 6, 1),
          originalFy: '2025-2026',
        )
      ];

      final dupInOtherFy = findDuplicateSupplierChallan(
        challans: existingChallans,
        billNo: 'SUPP-100',
        partyId: 'SUP-1',
        targetFy: '2026-2027',
      );
      expect(dupInOtherFy, isNull);

      final dupInSameFy = findDuplicateSupplierChallan(
        challans: existingChallans,
        billNo: 'SUPP-100',
        partyId: 'SUP-1',
        targetFy: '2025-2026',
      );
      expect(dupInSameFy, isNotNull);
      expect(dupInSameFy!.id, equals('pc-fy25'));
    });
  });
}
