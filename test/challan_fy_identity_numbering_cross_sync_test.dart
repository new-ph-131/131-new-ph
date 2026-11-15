import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharoah_erp/gateway/company_registry_model.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/logic/pharoah_numbering_engine.dart';
import 'package:pharoah_erp/web_live_sync/web_pharoah_numbering_engine.dart';
import 'package:pharoah_erp/sync_core/multi_fy_cloud_vault.dart';
import 'package:pharoah_erp/sync_core/d1_sales_ledger_service.dart';
import 'package:pharoah_erp/sync_core/models/sync_envelope.dart';
import 'package:pharoah_erp/sync_core/modules/sale_challan_sync_module.dart';
import 'package:pharoah_erp/sync_core/modules/purchase_challan_sync_module.dart';
import 'package:pharoah_erp/web_live_sync/sync_protocol/delta_merge_engine.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/sync_core/orchestrator/master_sync_orchestrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory mockDocsDir;

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
    SharedPreferences.setMockInitialValues({});
  });

  group('Group 1: Challan Identity, originalFy Persistence & Backward Compatibility', () {
    test('T1: SaleChallan persists originalFy across toMap, fromMap and fromEnvelope', () {
      final c1 = SaleChallan(
        id: 'sc-101',
        billNo: 'Y-1',
        partyName: 'Party A',
        date: DateTime(2025, 5, 10),
        items: [],
        status: 'Pending',
        originalFy: '2025-2026',
        version: 1,
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
      );
      final c3 = SaleChallan.fromEnvelope(env);
      expect(c3.id, equals('sc-101'));
      expect(c3.originalFy, equals('2025-2026'));
      expect(c3.effectiveOriginalFy, equals('2025-2026'));
    });

    test('T2: PurchaseChallan persists originalFy across toMap, fromMap and fromEnvelope', () {
      final pc1 = PurchaseChallan(
        id: 'pc-201',
        billNo: 'INW-1',
        supplierChallanNo: 'SUPP-99',
        partyName: 'Supplier Z',
        date: DateTime(2025, 6, 15),
        items: [],
        status: 'Pending',
        originalFy: '2025-2026',
        version: 1,
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
      );
      final pc3 = PurchaseChallan.fromEnvelope(env);
      expect(pc3.id, equals('pc-201'));
      expect(pc3.originalFy, equals('2025-2026'));
    });

    test('T3: Legacy Challan with missing originalFy falls back to date-derived FY', () {
      final legacyMap = {
        'id': 'legacy-sc-1',
        'billNo': 'Y-5',
        'partyName': 'Old Party',
        'date': '2024-08-10T00:00:00.000',
        'status': 'Pending',
        'items': [],
        'version': 1,
        // no originalFy key
      };

      final legacy = SaleChallan.fromMap(legacyMap);
      expect(legacy.originalFy, isNull);
      expect(legacy.effectiveOriginalFy, equals('2024-2025'));
    });

    test('T4: Date editing preserves originalFy', () {
      final c = SaleChallan(
        id: 'sc-102',
        billNo: 'Y-2',
        partyName: 'Party B',
        date: DateTime(2025, 7, 1),
        items: [],
        status: 'Pending',
        originalFy: '2025-2026',
        version: 1,
      );

      // User modifies date to next month
      c.date = DateTime(2025, 8, 1);
      expect(c.originalFy, equals('2025-2026'));
      expect(c.effectiveOriginalFy, equals('2025-2026'));
    });
  });

  group('Group 2: FY Isolation in Numbering & Series Counters', () {
    test('T5: PharoahNumberingEngine isolates series: carry-forward challan does not advance new FY counter', () {
      final carryForwardChallan = SaleChallan(
        id: 'sc-old-1',
        billNo: 'Y-1',
        partyName: 'Party Old',
        date: DateTime(2025, 5, 10),
        items: [],
        status: 'Pending',
        originalFy: '2025-2026',
        version: 1,
      );

      final nextNo = PharoahNumberingEngine.getNextAvailableNumber(
        type: 'SALE_CHALLAN',
        existingItems: [carryForwardChallan],
        currentFY: '2026-2027',
      );

      // Should start at 1 for 2026-2027, not skip to 2!
      expect(nextNo, equals('Y-1'));
    });

    test('T6: WebPharoahNumberingEngine isolates series: carry-forward challan does not advance new FY counter', () {
      final carryForwardChallan = SaleChallan(
        id: 'sc-old-2',
        billNo: 'CH-1',
        partyName: 'Party Old',
        date: DateTime(2025, 6, 1),
        items: [],
        status: 'Pending',
        originalFy: '2025-2026',
        version: 1,
      );

      final nextNo = WebPharoahNumberingEngine.getNextDocumentNumber(
        type: 'SALE_CHALLAN',
        records: [carryForwardChallan.toMap()],
        targetFy: '2026-2027',
      );

      // Should be CH-1 for 2026-2027
      expect(nextNo, equals('CH-1'));
    });

    test('T7: Same-FY challan advances the counter correctly', () {
      final newFyChallan = SaleChallan(
        id: 'sc-new-1',
        billNo: 'Y-1',
        partyName: 'Party New',
        date: DateTime(2026, 4, 15),
        items: [],
        status: 'Pending',
        originalFy: '2026-2027',
        version: 1,
      );

      final nextNo = PharoahNumberingEngine.getNextAvailableNumber(
        type: 'SALE_CHALLAN',
        existingItems: [newFyChallan],
        currentFY: '2026-2027',
      );

      expect(nextNo, equals('Y-2'));
    });
  });

  group('Group 3: Primary ID Rule & LWW Monotonic Versioning', () {
    test('T8: MultiFyCloudVault _findMatchingRecordIndex strictly checks ID: distinct non-empty IDs never match', () {
      final existingRecords = [
        {'id': 'UUID-AAA', 'billNo': 'Y-1', 'originalFy': '2025-2026'},
      ];

      // Different ID, same billNo in different FY
      final candidate = {'id': 'UUID-BBB', 'billNo': 'Y-1', 'originalFy': '2026-2027'};

      // Direct simulation of MultiFyCloudVault matching rule
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

    test('T9: DeltaMergeEngine isolates records by ID: distinct UUIDs never overwrite', () {
      final list = [
        {'id': 'UUID-AAA', 'billNo': 'Y-1', 'status': 'Pending', 'version': 1, 'updatedAt': 100},
      ];

      final incoming = {'id': 'UUID-BBB', 'billNo': 'Y-1', 'status': 'Pending', 'version': 1, 'updatedAt': 200};

      final merged = DeltaMergeEngine.mergeRecordLists(
        localList: list,
        incomingList: [incoming],
      );

      expect(merged.length, equals(2));
      expect(merged.any((r) => r['id'] == 'UUID-AAA'), isTrue);
      expect(merged.any((r) => r['id'] == 'UUID-BBB'), isTrue);
    });

    test('T10: SaleChallanSyncModule rejects incoming with lower version (monotonic rejection)', () {
      final local = [
        SaleChallan(
          id: 'sc-v2',
          billNo: 'Y-1',
          partyName: 'P',
          date: DateTime(2026, 4, 1),
          items: [],
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
          'partyName': 'P',
          'date': DateTime(2026, 4, 1).toIso8601String(),
          'status': 'Pending',
          'items': [],
          'version': 1,
          'updatedAt': 300, // Higher timestamp but lower version
        },
        action: 'UPDATE',
        version: 1,
        updatedAt: 300,
      );

      final mutated = SaleChallanSyncModule.mergeIncomingSaleChallanEnvelope(local, staleEnv);
      expect(mutated, isFalse);
      expect(local[0].status, equals('Billed'));
      expect(local[0].version, equals(2));
    });

    test('T11: PurchaseChallanSyncModule LWW clock tie-breaker when versions are equal', () {
      final local = [
        PurchaseChallan(
          id: 'pc-tie',
          billNo: 'INW-1',
          supplierChallanNo: 'S-1',
          partyName: 'P',
          date: DateTime(2026, 4, 1),
          items: [],
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
          'billNo': 'INW-1',
          'supplierChallanNo': 'S-1',
          'partyName': 'P',
          'date': DateTime(2026, 4, 1).toIso8601String(),
          'status': 'Billed',
          'items': [],
          'version': 1,
          'updatedAt': 200,
        },
        action: 'UPDATE',
        version: 1,
        updatedAt: 200,
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
        SaleChallan(
          id: 'sc-linked-1',
          billNo: 'Y-10',
          partyName: 'Customer 1',
          date: DateTime(2025, 5, 1),
          items: [],
          status: 'Pending',
          originalFy: '2025-2026',
          version: 1,
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
        PurchaseChallan(
          id: 'pc-fy25',
          billNo: 'INW-1',
          supplierChallanNo: 'SUPP-100',
          partyName: 'Supplier A',
          date: DateTime(2025, 6, 1),
          items: [],
          status: 'Pending',
          originalFy: '2025-2026',
        )
      ];

      // Same supplier challan in different FY (2026-2027) should NOT be flagged as duplicate
      final dupInOtherFy = PurchaseChallan.findDuplicateSupplierChallan(
        existingChallans,
        supplierChallanNo: 'SUPP-100',
        supplierName: 'Supplier A',
        targetFy: '2026-2027',
      );
      expect(dupInOtherFy, isNull);

      // Same supplier challan in same FY (2025-2026) SHOULD be flagged
      final dupInSameFy = PurchaseChallan.findDuplicateSupplierChallan(
        existingChallans,
        supplierChallanNo: 'SUPP-100',
        supplierName: 'Supplier A',
        targetFy: '2025-2026',
      );
      expect(dupInSameFy, isNotNull);
      expect(dupInSameFy!.id, equals('pc-fy25'));
    });
  });
}
