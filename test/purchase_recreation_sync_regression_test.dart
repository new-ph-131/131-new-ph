import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:pharoah_erp/realtime_signaling/transport/cloud_signal_channel.dart';
import 'package:pharoah_erp/sync_core/d1_sales_ledger_service.dart';
import 'package:pharoah_erp/sync_core/models/sync_envelope.dart';
import 'package:pharoah_erp/sync_core/modules/purchase_sync_module.dart';
import 'package:pharoah_erp/sync_core/modules/sales_sync_module.dart';
import 'package:pharoah_erp/sync_core/orchestrator/master_sync_orchestrator.dart';
import 'package:pharoah_erp/sync_core/outbox/sync_queue_manager.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/sync_protocol/delta_merge_engine.dart';
import 'package:pharoah_erp/web_live_sync/sync_protocol/tombstone_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory mockDocsDir;

  setUpAll(() async {
    mockDocsDir = await Directory.systemTemp.createTemp('pharoah_pur_recreate_');
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

  Purchase _makePurchase({
    required String id,
    required String internalNo,
    required String billNo,
    String partyId = 'PARTY-X',
    String distributorName = 'PARTY X DIST',
    double totalAmount = 1200.0,
    int version = 1,
    int updatedAt = 100000,
    int isDeleted = 0,
  }) {
    return Purchase(
      id: id,
      internalNo: internalNo,
      billNo: billNo,
      partyId: partyId,
      distributorName: distributorName,
      date: DateTime(2026, 7, 15),
      entryDate: DateTime(2026, 7, 15),
      paymentMode: 'Credit',
      totalAmount: totalAmount,
      version: version,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
      items: const [],
    );
  }

  group('Purchase Create -> Delete -> Re-create App-to-Web Sync Regression', () {
    test('Scenarios A, B, C1: Create -> Delete -> Re-create with same gap-filled PUR-1 & same supplier billNo syncs to Web via D1, MasterSyncOrchestrator & Cloud merge', () async {
      const fy = '2026-27';
      D1SalesLedgerService.activeFinancialYear = fy;

      final webPh = PharoahWebManager();
      webPh.financialYear = fy;

      // Scenario A: First Purchase created in App & synced to Web
      final pur1 = _makePurchase(
        id: 'PUR-UUID-1',
        internalNo: 'PUR-1',
        billNo: 'SupBill-100',
        totalAmount: 1200.0,
        version: 1,
        updatedAt: 100000,
      );

      final createEnv1 = SyncEnvelope(
        seq: 1,
        syncId: pur1.id,
        storeToken: 'TK1',
        documentType: 'PURCHASE',
        action: 'INSERT',
        version: 1,
        updatedAt: 100000,
        isDeleted: 0,
        billData: {...pur1.toMap(), 'fy': fy},
      );

      expect(MasterSyncOrchestrator.dispatchEnvelope(envelope: createEnv1, phWeb: webPh), isTrue);
      expect(webPh.purchases.length, equals(1));
      expect(webPh.purchases.first.id, equals('PUR-UUID-1'));

      // Scenario B: Delete Purchase #1 on App -> Web receives DELETE + edge tombstones
      final delEnv1 = SyncEnvelope(
        seq: 2,
        syncId: pur1.id,
        storeToken: 'TK1',
        documentType: 'PURCHASE',
        action: 'DELETE',
        version: 999999,
        updatedAt: 200000,
        isDeleted: 1,
        billData: {...pur1.toMap(), 'isDeleted': 1, 'is_deleted': 1, 'fy': fy},
      );

      expect(MasterSyncOrchestrator.dispatchEnvelope(envelope: delEnv1, phWeb: webPh), isTrue);
      expect(webPh.purchases, isEmpty);
      expect(D1SalesLedgerService.isPurchaseIdDeleted('PUR-UUID-1', fy), isTrue);

      // Scenario C1: App re-creates Purchase #2 for Party X -> gap-filling reuses PUR-1 & same billNo, NEW UUID
      final pur2 = _makePurchase(
        id: 'PUR-UUID-2',
        internalNo: 'PUR-1',
        billNo: 'SupBill-100',
        totalAmount: 1550.0,
        version: 1,
        updatedAt: 300000,
      );

      // 1) Web receives re-creation via MasterSyncOrchestrator (erp_master_sync batch)
      final createEnv2 = SyncEnvelope(
        seq: 3,
        syncId: pur2.id,
        storeToken: 'TK1',
        documentType: 'PURCHASE',
        action: 'INSERT',
        version: 1,
        updatedAt: 300000,
        isDeleted: 0,
        billData: {...pur2.toMap(), 'fy': fy},
      );

      expect(MasterSyncOrchestrator.dispatchEnvelope(envelope: createEnv2, phWeb: webPh), isTrue);
      expect(webPh.purchases.length, equals(1));
      expect(webPh.purchases.first.id, equals('PUR-UUID-2'));
      expect(webPh.purchases.first.internalNo, equals('PUR-1'));
      expect(webPh.purchases.first.totalAmount, equals(1550.0));

      // Stale edge tombstone broadcast for old PUR-1 must NOT wipe out freshly unmarked PUR-UUID-2
      webPh.purgeDeletedIds(['PUR-UUID-1', '2026-27::PUR-1', '2026-27::PARTY-X_SupBill-100']);
      expect(webPh.purchases.length, equals(1));
      expect(webPh.purchases.first.id, equals('PUR-UUID-2'));

      // Old deleted UUID must STILL stay blocked forever against stale updates
      final staleResurrectEnv1 = SyncEnvelope(
        seq: 4,
        syncId: 'PUR-UUID-1',
        storeToken: 'TK1',
        documentType: 'PURCHASE',
        action: 'UPDATE',
        version: 2,
        updatedAt: 150000,
        isDeleted: 0,
        billData: {...pur1.toMap(), 'version': 2, 'updatedAt': 150000, 'fy': fy},
      );
      expect(MasterSyncOrchestrator.dispatchEnvelope(envelope: staleResurrectEnv1, phWeb: webPh), isFalse);
      expect(webPh.purchases.length, equals(1));
      expect(webPh.purchases.first.id, equals('PUR-UUID-2'));
    });

    test('Scenario C2: D1 sale_events chronological replay (DELETE id1 -> INSERT id2 reusing PUR-1) restores id2 on Web & preserves id1 tombstone', () {
      const fy = '2026-27';
      D1SalesLedgerService.activeFinancialYear = fy;

      final pur1 = _makePurchase(
        id: 'PUR-D1-1',
        internalNo: 'PUR-1',
        billNo: 'Bill-Alpha',
        totalAmount: 900.0,
        version: 1,
        updatedAt: 100000,
      );
      final pur2 = _makePurchase(
        id: 'PUR-D1-2',
        internalNo: 'PUR-1',
        billNo: 'Bill-Beta',
        totalAmount: 2400.0,
        version: 1,
        updatedAt: 300000,
      );

      final List<Purchase> webPurchases = [pur1];

      final events = [
        {
          'seq': 10,
          'bill_id': pur1.id,
          'bill_no': pur1.internalNo,
          'version': 2,
          'action': 'DELETE',
          'fy': fy,
          'created_at': 200000,
          'sale_data': {...pur1.toMap(), 'doc_type': 'PURCHASE', 'is_deleted': 1, 'updatedAt': 200000, 'fy': fy},
        },
        {
          'seq': 11,
          'bill_id': pur2.id,
          'bill_no': pur2.internalNo,
          'version': 1,
          'action': 'INSERT',
          'fy': fy,
          'created_at': 300000,
          'sale_data': {...pur2.toMap(), 'doc_type': 'PURCHASE', 'is_deleted': 0, 'updatedAt': 300000, 'fy': fy},
        },
      ];

      final mutated = D1SalesLedgerService.applyEventsToLocalPurchases(webPurchases, events, fy);
      expect(mutated, isTrue);
      expect(webPurchases.length, equals(1));
      expect(webPurchases.first.id, equals('PUR-D1-2'));
      expect(webPurchases.first.internalNo, equals('PUR-1'));
      expect(webPurchases.first.billNo, equals('Bill-Beta'));
      expect(webPurchases.first.totalAmount, equals(2400.0));
      expect(D1SalesLedgerService.isPurchaseIdDeleted('PUR-D1-1', fy), isTrue);
      expect(D1SalesLedgerService.isPurchaseIdDeleted('PUR-D1-2', fy), isFalse);
    });

    test('Scenario C3: Cloud snapshot DeltaMergeEngine accepts newer re-created Purchase entity (id2) after older Delete while blocking stale id1', () async {
      const companyId = 'COMP-REC-1';
      const fy = '2026-27';
      D1SalesLedgerService.activeFinancialYear = fy;

      final ph = PharoahManager();
      ph.currentFY = fy;

      await TombstoneEngine.recordBatchTombstones(
        companyId,
        ['PUR-SNAP-1', '2026-27::PUR-1', '2026-27::PARTY-X_Inv-10'],
        timestamp: 200000,
        fy: fy,
      );
      D1SalesLedgerService.markPurchasePermanentlyDeleted('PUR-SNAP-1', 'PARTY-X', 'Inv-10', 'PUR-1', fy, 200000);
      final reg = await TombstoneEngine.getTombstoneRegistry(companyId);

      final pur1Stale = _makePurchase(
        id: 'PUR-SNAP-1',
        internalNo: 'PUR-1',
        billNo: 'Inv-10',
        totalAmount: 500.0,
        updatedAt: 150000,
      );
      final pur2Fresh = _makePurchase(
        id: 'PUR-SNAP-2',
        internalNo: 'PUR-1',
        billNo: 'Inv-10',
        totalAmount: 850.0,
        updatedAt: 350000,
      );

      final didMutate = DeltaMergeEngine.processCloudData(
        ph,
        {
          'purc.json': jsonEncode([pur1Stale.toMap(), pur2Fresh.toMap()]),
        },
        reg,
        {},
      );

      expect(didMutate, isTrue);
      expect(ph.purchases.length, equals(1));
      expect(ph.purchases.first.id, equals('PUR-SNAP-2'));
      expect(ph.purchases.first.totalAmount, equals(850.0));
    });

    test('Scenario D: Rapid Delete -> Re-create burst preserves final re-created Purchase via Outbox, Signal Aggregation & PurchaseSyncModule', () {
      const fy = '2026-27';
      D1SalesLedgerService.activeFinancialYear = fy;

      final pur1 = _makePurchase(
        id: 'BURST-PUR-1',
        internalNo: 'PUR-1',
        billNo: 'Inv-55',
        version: 1,
        updatedAt: 100000,
      );
      final pur2 = _makePurchase(
        id: 'BURST-PUR-2',
        internalNo: 'PUR-1',
        billNo: 'Inv-55',
        totalAmount: 1999.0,
        version: 1,
        updatedAt: 105000,
      );

      PurchaseSyncModule.onPurchaseDeleted(pur1, 'TK1');
      PurchaseSyncModule.onPurchaseSaved(pur2, 'TK1');

      final pending = SyncQueueManager.debugPendingOperations();
      expect(pending.length, equals(2));
      expect(pending[0].syncId, equals('BURST-PUR-1'));
      expect(pending[0].isDeleted, equals(1));
      expect(pending[1].syncId, equals('BURST-PUR-2'));
      expect(pending[1].isDeleted, equals(0));

      // Replay into Web list sequentially
      final webPurchases = <Purchase>[pur1];
      expect(PurchaseSyncModule.mergeIncomingPurchaseEnvelope(webPurchases, pending[0], fy: fy), isTrue);
      expect(webPurchases, isEmpty);
      expect(PurchaseSyncModule.mergeIncomingPurchaseEnvelope(webPurchases, pending[1], fy: fy), isTrue);
      expect(webPurchases.length, equals(1));
      expect(webPurchases.first.id, equals('BURST-PUR-2'));
      expect(webPurchases.first.totalAmount, equals(1999.0));

      // Verify CloudSignalChannel keeps BURST-PUR-1 deleted and BURST-PUR-2 + 2026-27::PUR-1 unmarked
      final agg = CloudSignalChannel.aggregateRemoteSignals(
        rawEvents: [
          {
            'id': 'ev-del-1',
            'source': 'APP',
            'action': 'DELETE_PURCHASE',
            'entityId': 'BURST-PUR-1',
            'timestamp': 101000,
            'deletedIds': ['BURST-PUR-1', '2026-27::PUR-1', '2026-27::PARTY-X_Inv-55'],
            'unmarkedIds': [],
            'financialYear': fy,
          },
          {
            'id': 'ev-add-2',
            'source': 'APP',
            'action': 'PURCHASE_ADDED',
            'entityId': 'BURST-PUR-2',
            'timestamp': 105000,
            'deletedIds': [],
            'unmarkedIds': ['BURST-PUR-2', '2026-27::PUR-1', '2026-27::PARTY-X_Inv-55'],
            'financialYear': fy,
          },
        ],
        mySource: 'web',
        lastSeenTs: 99000,
      );

      expect(agg.mergedEvent, isNotNull);
      expect(agg.mergedEvent!.deletedIds.contains('BURST-PUR-1'), isTrue);
      expect(agg.mergedEvent!.deletedIds.contains('2026-27::PUR-1'), isFalse);
      expect(agg.mergedEvent!.unmarkedIds.contains('2026-27::PUR-1'), isTrue);
    });

    test('Scenario E: Sale Create -> Delete -> Re-create regression remains 100% intact', () {
      const fy = '2026-27';
      D1SalesLedgerService.activeFinancialYear = fy;

      final webPh = PharoahWebManager();
      webPh.financialYear = fy;

      final sale1 = Sale(
        id: 'SALE-UUID-1',
        billNo: 'INV-1',
        partyId: 'CUST-1',
        partyName: 'CUSTOMER ONE',
        partyGstin: '',
        partyState: '',
        date: DateTime(2026, 7, 15),
        items: const [],
        totalAmount: 500.0,
        paymentMode: 'Cash',
        version: 1,
        updatedAt: 100000,
      );

      final sale2 = Sale(
        id: 'SALE-UUID-2',
        billNo: 'INV-1',
        partyId: 'CUST-1',
        partyName: 'CUSTOMER ONE',
        partyGstin: '',
        partyState: '',
        date: DateTime(2026, 7, 15),
        items: const [],
        totalAmount: 750.0,
        paymentMode: 'Cash',
        version: 1,
        updatedAt: 300000,
      );

      expect(
        MasterSyncOrchestrator.dispatchEnvelope(
          envelope: SyncEnvelope(
            seq: 1,
            syncId: sale1.id,
            storeToken: 'TK1',
            documentType: 'SALE',
            action: 'INSERT',
            version: 1,
            updatedAt: 100000,
            isDeleted: 0,
            billData: {...sale1.toMap(), 'fy': fy},
          ),
          phWeb: webPh,
        ),
        isTrue,
      );
      expect(webPh.sales.length, equals(1));

      expect(
        MasterSyncOrchestrator.dispatchEnvelope(
          envelope: SyncEnvelope(
            seq: 2,
            syncId: sale1.id,
            storeToken: 'TK1',
            documentType: 'SALE',
            action: 'DELETE',
            version: 2,
            updatedAt: 200000,
            isDeleted: 1,
            billData: {...sale1.toMap(), 'isDeleted': 1, 'is_deleted': 1, 'fy': fy},
          ),
          phWeb: webPh,
        ),
        isTrue,
      );
      expect(webPh.sales, isEmpty);

      expect(
        MasterSyncOrchestrator.dispatchEnvelope(
          envelope: SyncEnvelope(
            seq: 3,
            syncId: sale2.id,
            storeToken: 'TK1',
            documentType: 'SALE',
            action: 'INSERT',
            version: 1,
            updatedAt: 300000,
            isDeleted: 0,
            billData: {...sale2.toMap(), 'fy': fy},
          ),
          phWeb: webPh,
        ),
        isTrue,
      );
      expect(webPh.sales.length, equals(1));
      expect(webPh.sales.first.id, equals('SALE-UUID-2'));
      expect(webPh.sales.first.totalAmount, equals(750.0));
      expect(SalesSyncModule.applySaleMutation(webPh.sales, sale1..isDeleted = 1), isFalse);
    });
  });
}
