import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharoah_erp/fy_transfer_engine.dart';
import 'package:pharoah_erp/inventory_logic_center.dart';
import 'package:pharoah_erp/logic/batch_cascade_engine.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:pharoah_erp/realtime_signaling/transport/cloud_signal_channel.dart';
import 'package:pharoah_erp/sync_core/d1_sales_ledger_service.dart';
import 'package:pharoah_erp/sync_core/models/sync_envelope.dart';
import 'package:pharoah_erp/sync_core/modules/batch_delta_merge_module.dart';
import 'package:pharoah_erp/sync_core/modules/batch_sync_module.dart';
import 'package:pharoah_erp/sync_core/modules/purchase_sync_module.dart';
import 'package:pharoah_erp/sync_core/multi_fy_cloud_vault.dart';
import 'package:pharoah_erp/sync_core/orchestrator/master_sync_orchestrator.dart';
import 'package:pharoah_erp/sync_core/outbox/sync_queue_manager.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/services/web_batch_resolver.dart';
import 'package:pharoah_erp/web_live_sync/sync_protocol/delta_merge_engine.dart';
import 'package:pharoah_erp/web_live_sync/sync_protocol/tombstone_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory mockDocsDir;

  setUpAll(() async {
    mockDocsDir = await Directory.systemTemp.createTemp('pharoah_three_issues_');
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

  Medicine _buildTestMed() => Medicine(
        id: 'MED-NOBATCH',
        systemId: 'PH-NOBATCH',
        name: 'AMOXICILLIN 500',
        packing: '1*10',
        mrp: 100.0,
        purRate: 70.0,
        rateA: 90.0,
        stock: 0.0,
      );

  List<Purchase> _buildTwoNoBatchMrpPurchases({required DateTime dt}) => [
        Purchase(
          id: 'PUR-A',
          internalNo: 'PUR-1',
          billNo: 'Inv-A',
          partyId: 'SUP-1',
          distributorName: 'ALPHA DIST',
          date: dt,
          entryDate: dt,
          paymentMode: 'Credit',
          totalAmount: 700.0,
          items: [
            PurchaseItem(
              id: 'PI-A',
              srNo: 1,
              medicineID: 'MED-NOBATCH',
              name: 'AMOXICILLIN 500',
              packing: '1*10',
              batch: '',
              exp: '',
              hsn: '3004',
              mrp: 100.0,
              qty: 10.0,
              freeQty: 0.0,
              purchaseRate: 70.0,
              gstRate: 12.0,
              total: 700.0,
              rateA: 90.0,
            ),
          ],
        ),
        Purchase(
          id: 'PUR-B',
          internalNo: 'PUR-2',
          billNo: 'Inv-B',
          partyId: 'SUP-1',
          distributorName: 'ALPHA DIST',
          date: dt.add(const Duration(days: 1)),
          entryDate: dt.add(const Duration(days: 1)),
          paymentMode: 'Credit',
          totalAmount: 350.0,
          items: [
            PurchaseItem(
              id: 'PI-B',
              srNo: 1,
              medicineID: 'MED-NOBATCH',
              name: 'AMOXICILLIN 500',
              packing: '1*10',
              batch: '',
              exp: '',
              hsn: '3004',
              mrp: 50.0,
              qty: 10.0,
              freeQty: 0.0,
              purchaseRate: 35.0,
              gstRate: 12.0,
              total: 350.0,
              rateA: 45.0,
            ),
          ],
        ),
      ];

  group('ISSUE A & C: Unescaped Lot Keys, Multi-MRP NO BATCH Survival across FY, Web Resolver & Delete Isolation', () {
    test('makeLotKey & makeSyncKey produce distinct evaluated keys for different MRPs when batch & expiry are blank', () {
      final k100 = InventoryLogicCenter.makeLotKey('', exp: '', mrp: 100.0, purRate: 70.0);
      final k50 = InventoryLogicCenter.makeLotKey('', exp: '', mrp: 50.0, purRate: 35.0);
      expect(k100.contains(r'$'), isFalse);
      expect(k50.contains(r'$'), isFalse);
      expect(k100, equals('__NOBATCH__||100.00|70.00'));
      expect(k50, equals('__NOBATCH__||50.00|35.00'));
      expect(k100, isNot(equals(k50)));

      final s100 = BatchSyncModule.getBatchSyncId('PH-NOBATCH', '', exp: '', mrp: 100.0, purRate: 70.0);
      final s50 = BatchSyncModule.getBatchSyncId('PH-NOBATCH', '', exp: '', mrp: 50.0, purRate: 35.0);
      expect(s100.contains(r'$'), isFalse);
      expect(s50.contains(r'$'), isFalse);
      expect(s100, isNot(equals(s50)));
    });

    test('Issue C: WebBatchResolver returns BOTH distinct NO BATCH MRP lots without collapse (normal + post-FY zero purRate)', () {
      final med = _buildTestMed();
      final Map<String, List<BatchInfo>> batchHistory = {};
      final purchases = _buildTwoNoBatchMrpPurchases(dt: DateTime(2025, 5, 10));

      InventoryLogicCenter.rebuildAllInventory(
        medicines: [med],
        batchHistory: batchHistory,
        purchases: purchases,
        sales: [],
        saleReturns: [],
        purchaseReturns: [],
      );

      expect(med.stock, closeTo(20.0, 0.001));
      final resolved = WebBatchResolver.resolveBatchesForMedicine(med, batchHistory);
      expect(resolved.length, equals(2));
      expect(resolved.any((b) => b.batch.trim().isEmpty && b.mrp == 100.0 && b.qty == 10.0), isTrue);
      expect(resolved.any((b) => b.batch.trim().isEmpty && b.mrp == 50.0 && b.qty == 10.0), isTrue);
    });

    test('Issue A: Two NO BATCH MRP lots (100 & 50, qty 10 each) survive FY1 -> FY2 carry-forward, rebuild, and WebBatchResolver', () async {
      final med = _buildTestMed();
      final Map<String, List<BatchInfo>> fy1Batches = {};
      final fy1Purchases = _buildTwoNoBatchMrpPurchases(dt: DateTime(2025, 5, 10));

      InventoryLogicCenter.rebuildAllInventory(
        medicines: [med],
        batchHistory: fy1Batches,
        purchases: fy1Purchases,
        sales: [],
        saleReturns: [],
        purchaseReturns: [],
      );

      final carryFiles = FYTransferEngine.computeCarryForwardFromFiles(
        sourceFiles: {
          'meds.json': jsonEncode([med.toMap()]),
          'bats.json': jsonEncode(fy1Batches.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList()))),
          'purc.json': jsonEncode(fy1Purchases.map((p) => p.toMap()).toList()),
        },
        sourceFY: '2025-26',
        targetFY: '2026-27',
      );

      final List<Medicine> fy2Meds = (jsonDecode(carryFiles['meds.json']!) as List).map((m) => Medicine.fromMap(m)).toList();
      final Map<String, List<BatchInfo>> fy2Batches = {};
      final rawBats = jsonDecode(carryFiles['bats.json']!) as Map<String, dynamic>;
      rawBats.forEach((k, list) {
        fy2Batches[k] = (list as List).map((b) => BatchInfo.fromMap(b)).toList();
      });

      expect(fy2Meds.length, equals(1));
      expect(fy2Meds.first.stock, closeTo(20.0, 0.001));
      expect(fy2Batches['PH-NOBATCH']?.length, equals(2));

      // Verify rebuildAllInventory on FY2 keeps both opening NO BATCH lots distinct
      InventoryLogicCenter.rebuildAllInventory(
        medicines: fy2Meds,
        batchHistory: fy2Batches,
        purchases: [],
        sales: [],
        saleReturns: [],
        purchaseReturns: [],
      );

      expect(fy2Meds.first.stock, closeTo(20.0, 0.001));
      expect(fy2Batches['PH-NOBATCH']?.length, equals(2));

      // Verify WebBatchResolver in FY2 returns BOTH lots (MRP 100 qty 10 AND MRP 50 qty 10)
      final fy2Resolved = WebBatchResolver.resolveBatchesForMedicine(fy2Meds.first, fy2Batches);
      expect(fy2Resolved.length, equals(2));
      expect(fy2Resolved.any((b) => b.mrp == 100.0 && b.qty == 10.0), isTrue);
      expect(fy2Resolved.any((b) => b.mrp == 50.0 && b.qty == 10.0), isTrue);

      // Verify cloud vault LWW batch merge preserves both distinct NO BATCH lots across Web/App
      final Map<String, List<BatchInfo>> mergedCloudBats = {};
      final bool mergedChanged = BatchDeltaMergeModule.mergeBatchHistoryFromCloudJson(
        targetBatchHistory: mergedCloudBats,
        incomingJson: fy2Batches.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList())),
      );
      expect(mergedChanged, isTrue);
      expect(mergedCloudBats['PH-NOBATCH']?.length, equals(2));
    });

    test('Issue A: Deleting ONE blank-batch MRP lot via MasterSyncOrchestrator or BatchCascadeEngine preserves the OTHER MRP lot', () {
      final med = _buildTestMed();
      final ph = PharoahManager();
      ph.medicines = [med];
      ph.batchHistory = {
        'PH-NOBATCH': [
          BatchInfo(batch: '', exp: '', packing: '1*10', mrp: 100.0, rate: 70.0, purRate: 70.0, qty: 0.0),
          BatchInfo(batch: '', exp: '', packing: '1*10', mrp: 50.0, rate: 35.0, purRate: 35.0, qty: 10.0),
        ],
      };

      // 1. Delete ONLY the MRP 100 blank-batch lot via BatchCascadeEngine
      final delRes = BatchCascadeEngine.deleteBatchSafe(
        medicine: med,
        batchNo: '',
        exp: '',
        mrp: 100.0,
        purRate: 70.0,
        activeFY: '2026-27',
        batchHistory: ph.batchHistory,
        sales: [],
        purchases: [],
        saleChallans: [],
        purchaseChallans: [],
        saleReturns: [],
        purchaseReturns: [],
        medicines: ph.medicines,
        storeToken: 'TESTSTORE',
      );
      expect(delRes.success, isTrue);
      expect(ph.batchHistory['PH-NOBATCH']!.length, equals(1));
      expect(ph.batchHistory['PH-NOBATCH']!.first.mrp, equals(50.0));

      // 2. Restore both, then delete ONLY MRP 50 via MasterSyncOrchestrator BATCH DELETE envelope
      ph.batchHistory['PH-NOBATCH'] = [
        BatchInfo(batch: '', exp: '', packing: '1*10', mrp: 100.0, rate: 70.0, purRate: 70.0, qty: 10.0),
        BatchInfo(batch: '', exp: '', packing: '1*10', mrp: 50.0, rate: 35.0, purRate: 35.0, qty: 0.0),
      ];
      final envDel50 = SyncEnvelope(
        seq: 1,
        syncId: BatchSyncModule.getBatchSyncId('PH-NOBATCH', '', exp: '', mrp: 50.0, purRate: 35.0),
        storeToken: 'TESTSTORE',
        documentType: 'BATCH',
        action: 'DELETE',
        version: 2,
        updatedAt: 2000000,
        isDeleted: 1,
        billData: {
          'medKey': 'PH-NOBATCH',
          'fy': '2026-27',
          'batch': BatchInfo(batch: '', exp: '', packing: '1*10', mrp: 50.0, rate: 35.0, purRate: 35.0, qty: 0.0).toMap(),
        },
      );
      final bool didMutate = MasterSyncOrchestrator.dispatchEnvelope(envelope: envDel50, phApp: ph);
      expect(didMutate, isTrue);
      expect(ph.batchHistory['PH-NOBATCH']!.length, equals(1));
      expect(ph.batchHistory['PH-NOBATCH']!.first.mrp, equals(100.0));
    });
  });

  group('ISSUE B: Purchase Edit -> Delete Cross-Sync, Mixed-Case Keys, Unmark Overcome & Burst Coalescing', () {
    test('App Purchase (mixed-case billNo) -> Web Modify -> Web Delete cannot resurrect via stale UPDATE or Cloud JSON merge', () async {
      const companyId = 'COMP-B1';
      const fy = '2026-27';
      D1SalesLedgerService.activeFinancialYear = fy;

      final ph = PharoahManager();
      ph.currentFY = fy;
      final pur = Purchase(
        id: 'PUR-UUID-101',
        internalNo: 'PUR-7',
        billNo: 'Inv-Abc-01',
        partyId: 'SUP-9',
        distributorName: 'SUPPLIER NINE',
        date: DateTime(2026, 7, 10),
        entryDate: DateTime(2026, 7, 10),
        paymentMode: 'Credit',
        totalAmount: 500.0,
        version: 1,
        updatedAt: 100000,
        items: const [],
      );
      ph.purchases = [pur];

      // Step 1: Simulate Web modifying Purchase (v2 @ T=200000) and App receiving unmark
      final modEnv = SyncEnvelope(
        seq: 2,
        syncId: 'PUR-UUID-101',
        storeToken: 'TK1',
        documentType: 'PURCHASE',
        action: 'UPDATE',
        version: 2,
        updatedAt: 200000,
        isDeleted: 0,
        billData: {
          ...pur.toMap(),
          'totalAmount': 650.0,
          'version': 2,
          'updatedAt': 200000,
          'fy': fy,
        },
      );
      expect(MasterSyncOrchestrator.dispatchEnvelope(envelope: modEnv, phApp: ph), isTrue);
      expect(ph.purchases.first.totalAmount, equals(650.0));
      await TombstoneEngine.unmarkTombstoneWithTimestamp(companyId, id: 'PUR-UUID-101', fy: fy, timestamp: 200000);

      // Step 2: Web deletes Purchase at T=300000 -> verify newer tombstone overrides older unmark
      final cloudReg = <String, int>{'PUR-UUID-101': 300000, '2026-27::SUP-9_Inv-Abc-01': 300000};
      final sanitized = await TombstoneEngine.sanitizeCloudTombstones(
        companyId,
        ['PUR-UUID-101', '2026-27::SUP-9_Inv-Abc-01'],
        cloudRegistry: cloudReg,
      );
      expect(sanitized.contains('PUR-UUID-101'), isTrue);
      expect(sanitized.contains('2026-27::SUP-9_Inv-Abc-01'), isTrue);

      await TombstoneEngine.recordBatchTombstones(companyId, sanitized, timestamp: 300000, fy: fy);
      D1SalesLedgerService.markPurchasePermanentlyDeleted('PUR-UUID-101', 'SUP-9', 'Inv-Abc-01', 'PUR-7', fy);
      final loadedReg = await TombstoneEngine.getTombstoneRegistry(companyId);
      final loadedTombs = await TombstoneEngine.getLocalTombstones(companyId);

      // Purge in App memory
      TombstoneEngine.purgeDeletedRecordsWithRegistry(ph, loadedReg);
      TombstoneEngine.purgeDeletedRecords(ph, loadedTombs, loadedReg);
      expect(ph.purchases, isEmpty);

      // Step 3: Stale UPDATE envelope from D1/Outbox MUST NOT resurrect or unmark deleted Purchase
      final staleUpdateEnv = SyncEnvelope(
        seq: 3,
        syncId: 'PUR-UUID-101',
        storeToken: 'TK1',
        documentType: 'PURCHASE',
        action: 'UPDATE',
        version: 2,
        updatedAt: 250000,
        isDeleted: 0,
        billData: {
          ...pur.toMap(),
          'totalAmount': 650.0,
          'version': 2,
          'updatedAt': 250000,
          'fy': fy,
        },
      );
      expect(MasterSyncOrchestrator.dispatchEnvelope(envelope: staleUpdateEnv, phApp: ph), isFalse);
      expect(ph.purchases, isEmpty);

      // Step 4: Stale D1 sale_events delta replay MUST NOT resurrect deleted Purchase
      final d1Mutated = D1SalesLedgerService.applyEventsToLocalPurchases(
        ph.purchases,
        [
          {
            'bill_id': 'PUR-UUID-101',
            'bill_no': 'PUR-7',
            'version': 2,
            'action': 'UPDATE',
            'fy': fy,
            'sale_data': {
              ...pur.toMap(),
              'doc_type': 'PURCHASE',
              'version': 2,
              'updatedAt': 250000,
              'fy': fy,
            },
          }
        ],
        fy,
      );
      expect(d1Mutated, isFalse);
      expect(ph.purchases, isEmpty);

      // Step 5: Stale Cloud JSON snapshot containing old Purchase MUST NOT resurrect via DeltaMergeEngine
      final cloudMutated = DeltaMergeEngine.processCloudData(
        ph,
        {
          'purc.json': jsonEncode([
            {...pur.toMap(), 'version': 2, 'updatedAt': 250000}
          ]),
        },
        loadedReg,
        {},
      );
      expect(cloudMutated, isFalse);
      expect(ph.purchases, isEmpty);
    });

    test('isPurchaseDeleted checks composite keys even when UUID is non-empty and differs from tombstoned UUID', () {
      D1SalesLedgerService.activeFinancialYear = '2026-27';
      D1SalesLedgerService.markPurchasePermanentlyDeleted('OLD-UUID', 'SUP-5', 'Bill-MixCase-9', 'PUR-12', '2026-27');
      expect(
        D1SalesLedgerService.isPurchaseDeleted('DIFFERENT-UUID', 'SUP-5', 'Bill-MixCase-9', 'PUR-12', '2026-27'),
        isTrue,
      );
    });

    test('CloudSignalChannel.aggregateRemoteSignals sorts out-of-order modify+delete chronologically so delete wins', () {
      // Simulate server returning DELETE (ts=5000) and earlier UPDATE (ts=4000) out of order
      final agg = CloudSignalChannel.aggregateRemoteSignals(
        rawEvents: [
          {
            'id': 'ev-del',
            'source': 'WEB',
            'action': 'DELETE_PURCHASE',
            'entityId': 'PUR-X1',
            'timestamp': 5000,
            'deletedIds': ['PUR-X1', '2026-27::SUP-1_Inv-99'],
            'unmarkedIds': [],
            'financialYear': '2026-27',
          },
          {
            'id': 'ev-upd',
            'source': 'WEB',
            'action': 'DATA_SAVED',
            'entityId': 'PUR-X1',
            'timestamp': 4000,
            'deletedIds': [],
            'unmarkedIds': ['PUR-X1', '2026-27::SUP-1_Inv-99'],
            'financialYear': '2026-27',
          },
        ],
        mySource: 'app',
        lastSeenTs: 1000,
      );

      expect(agg.mergedEvent, isNotNull);
      expect(agg.mergedEvent!.deletedIds.contains('PUR-X1'), isTrue);
      expect(agg.mergedEvent!.deletedIds.contains('2026-27::SUP-1_Inv-99'), isTrue);
      expect(agg.mergedEvent!.unmarkedIds.contains('PUR-X1'), isFalse);
    });

    test('SyncQueueManager retains all 12 rapid Purchase delete operations in frame buffer without dropping any', () {
      for (int i = 1; i <= 12; i++) {
        final pur = Purchase(
          id: 'BURST-PUR-$i',
          internalNo: 'PUR-$i',
          billNo: 'Inv-$i',
          partyId: 'SUP-1',
          distributorName: 'ALPHA',
          date: DateTime(2026, 8, 1),
          entryDate: DateTime(2026, 8, 1),
          paymentMode: 'Credit',
          totalAmount: 100.0 * i,
          version: 2,
          items: const [],
        );
        // Simulate edit followed immediately by delete on all 12
        PurchaseSyncModule.onPurchaseSaved(pur, 'TOK-BURST');
        PurchaseSyncModule.onPurchaseDeleted(pur, 'TOK-BURST');
      }
      final pending = SyncQueueManager.debugPendingOperations();
      expect(pending.length, equals(12));
      expect(pending.every((op) => op.isDeleted == 1 && op.action == 'DELETE'), isTrue);
      SyncQueueManager.debugReset();
    });

    test('Sale edit -> delete workflow remains intact via MasterSyncOrchestrator and D1SalesLedgerService', () async {
      final ph = PharoahManager();
      ph.currentFY = '2026-27';
      final sale = Sale(
        id: 'SALE-1',
        billNo: 'INV-1',
        date: DateTime(2026, 6, 15),
        partyId: 'CUST-1',
        partyName: 'RETAIL',
        partyGstin: '',
        partyState: 'Rajasthan',
        paymentMode: 'Cash',
        totalAmount: 200.0,
        version: 1,
        updatedAt: 100000,
        items: const [],
      );
      ph.sales = [sale];

      final delRes = D1SalesLedgerService.applyEventsToLocalSales(
        ph.sales,
        [
          {
            'bill_id': 'SALE-1',
            'bill_no': 'INV-1',
            'version': 99999,
            'action': 'DELETE',
            'fy': '2026-27',
            'sale_data': {'id': 'SALE-1', 'billNo': 'INV-1', 'is_deleted': 1, 'fy': '2026-27'},
          }
        ],
        '2026-27',
      );
      expect(delRes, isTrue);
      expect(ph.sales, isEmpty);
      expect(D1SalesLedgerService.isBillDeleted('SALE-1', 'INV-1', '', '2026-27'), isTrue);
    });
  });
}
