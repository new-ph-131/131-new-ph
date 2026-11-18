import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pharoah_erp/challans/challan_stitcher_wizard.dart';
import 'package:pharoah_erp/logic/pharoah_numbering_engine.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/realtime_signaling/coordinators/app_realtime_coordinator.dart';
import 'package:pharoah_erp/sync_core/d1_sales_ledger_service.dart';
import 'package:pharoah_erp/sync_core/modules/purchase_challan_sync_module.dart';
import 'package:pharoah_erp/sync_core/modules/sale_challan_sync_module.dart';
import 'package:pharoah_erp/sync_core/multi_fy_cloud_vault.dart';
import 'package:pharoah_erp/sync_core/outbox/sync_queue_manager.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/sync_protocol/snapshot_watcher.dart';
import 'package:pharoah_erp/web_live_sync/web_challan_stitcher_wizard.dart';
import 'package:pharoah_erp/web_live_sync/web_pharoah_numbering_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory mockDocsDir;

  SaleChallan makeSaleChallan({
    required String id,
    required String billNo,
    String partyId = 'P1',
    String partyName = 'Party Alpha',
    DateTime? date,
    String status = 'Pending',
    String originalFy = '',
    int version = 1,
    int updatedAt = 1000,
    int isDeleted = 0,
    String billedInFy = '',
    String billedInvoiceId = '',
    String billedInvoiceNo = '',
    String billedDate = '',
  }) {
    return SaleChallan(
      id: id,
      billNo: billNo,
      partyId: partyId,
      partyName: partyName,
      partyGstin: '',
      partyState: 'Rajasthan',
      date: date ?? DateTime(2026, 4, 10),
      items: [
        BillItem(
          id: 'BI-$id',
          srNo: 1,
          medicineID: 'MED-1',
          name: 'PARA 500',
          packing: '10T',
          batch: 'B1',
          exp: '12/28',
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
      billedInFy: billedInFy,
      billedInvoiceId: billedInvoiceId,
      billedInvoiceNo: billedInvoiceNo,
      billedDate: billedDate,
    );
  }

  PurchaseChallan makePurchaseChallan({
    required String id,
    required String internalNo,
    required String billNo,
    String partyId = 'SUP-1',
    String distributorName = 'Supplier Alpha',
    DateTime? date,
    String status = 'Pending',
    String originalFy = '',
    int version = 1,
    int updatedAt = 1000,
    int isDeleted = 0,
    String billedInFy = '',
    String billedInvoiceId = '',
    String billedInvoiceNo = '',
    String billedDate = '',
  }) {
    return PurchaseChallan(
      id: id,
      internalNo: internalNo,
      billNo: billNo,
      partyId: partyId,
      distributorName: distributorName,
      date: date ?? DateTime(2026, 4, 10),
      items: [
        PurchaseItem(
          id: 'PI-$id',
          srNo: 1,
          medicineID: 'MED-1',
          name: 'PARA 500',
          packing: '10T',
          batch: 'B1',
          exp: '12/28',
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
      billedInFy: billedInFy,
      billedInvoiceId: billedInvoiceId,
      billedInvoiceNo: billedInvoiceNo,
      billedDate: billedDate,
    );
  }

  setUpAll(() async {
    mockDocsDir = await Directory.systemTemp.createTemp('pharoah_stitcher_revert_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => mockDocsDir.path,
    );
  });

  tearDownAll(() async {
    AppRealtimeCoordinator.instance.stop();
    if (await mockDocsDir.exists()) {
      try {
        await mockDocsDir.delete(recursive: true);
      } on FileSystemException {
        await Future.delayed(const Duration(milliseconds: 100));
        if (await mockDocsDir.exists()) {
          await mockDocsDir.delete(recursive: true);
        }
      }
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'active_fy_COMP-1': '2027-28',
    });
    PharoahNumberingEngine.debugResetHwmCache();
    WebPharoahNumberingEngine.debugResetHwmCache();
    await D1SalesLedgerService.loadPersistedGravestones();
    D1SalesLedgerService.activeFinancialYear = '2027-28';
    SyncQueueManager.debugReset();
  });

  group('Point 1: Stitcher Carry-Forward Isolation & Party Matching', () {
    test('S1: MONTHLY default excludes Carry-Forward challans while CARRY_ONLY isolates prior-FY challans', () {
      const currentFy = '2027-28';
      const priorFy = '2026-27';
      final aprStart = DateTime(2027, 4, 1);
      final aprEnd = DateTime(2027, 4, 30);

      final cfDateInMar = DateTime(2027, 3, 25);
      final currentAprDate = DateTime(2027, 4, 12);
      final currentMayDate = DateTime(2027, 5, 2);

      // Default MONTHLY (includeCarryForward: false): CF is excluded, April current-FY included, May excluded
      expect(
        WebChallanStitcherWizard.evaluateEligibility(
          date: cfDateInMar,
          effectiveOriginalFy: priorFy,
          currentFy: currentFy,
          selectionMode: 'MONTHLY',
          includeCarryForward: false,
          fromDate: aprStart,
          toDate: aprEnd,
        ),
        isFalse,
      );
      expect(
        WebChallanStitcherWizard.evaluateEligibility(
          date: currentAprDate,
          effectiveOriginalFy: currentFy,
          currentFy: currentFy,
          selectionMode: 'MONTHLY',
          includeCarryForward: false,
          fromDate: aprStart,
          toDate: aprEnd,
        ),
        isTrue,
      );
      expect(
        WebChallanStitcherWizard.evaluateEligibility(
          date: currentMayDate,
          effectiveOriginalFy: currentFy,
          currentFy: currentFy,
          selectionMode: 'MONTHLY',
          includeCarryForward: false,
          fromDate: aprStart,
          toDate: aprEnd,
        ),
        isFalse,
      );

      // App Stitcher mirrors identical MONTHLY behavior
      expect(
        ChallanStitcherWizard.evaluateEligibility(
          date: cfDateInMar,
          effectiveOriginalFy: priorFy,
          currentFy: currentFy,
          selectionMode: 'MONTHLY',
          includeCarryForward: false,
          fromDate: aprStart,
          toDate: aprEnd,
        ),
        isFalse,
      );
      expect(
        ChallanStitcherWizard.evaluateEligibility(
          date: currentAprDate,
          effectiveOriginalFy: currentFy,
          currentFy: currentFy,
          selectionMode: 'MONTHLY',
          includeCarryForward: false,
          fromDate: aprStart,
          toDate: aprEnd,
        ),
        isTrue,
      );

      // Opt-in includeCarryForward: true includes CF in MONTHLY when explicitly checked
      expect(
        WebChallanStitcherWizard.evaluateEligibility(
          date: cfDateInMar,
          effectiveOriginalFy: priorFy,
          currentFy: currentFy,
          selectionMode: 'MONTHLY',
          includeCarryForward: true,
          fromDate: aprStart,
          toDate: aprEnd,
        ),
        isTrue,
      );

      // CARRY_ONLY includes prior-FY challans regardless of date and excludes current-FY challans
      expect(
        WebChallanStitcherWizard.evaluateEligibility(
          date: cfDateInMar,
          effectiveOriginalFy: priorFy,
          currentFy: currentFy,
          selectionMode: 'CARRY_ONLY',
          includeCarryForward: true,
          fromDate: aprStart,
          toDate: aprEnd,
        ),
        isTrue,
      );
      expect(
        WebChallanStitcherWizard.evaluateEligibility(
          date: currentAprDate,
          effectiveOriginalFy: currentFy,
          currentFy: currentFy,
          selectionMode: 'CARRY_ONLY',
          includeCarryForward: true,
          fromDate: aprStart,
          toDate: aprEnd,
        ),
        isFalse,
      );
      expect(
        ChallanStitcherWizard.evaluateEligibility(
          date: cfDateInMar,
          effectiveOriginalFy: priorFy,
          currentFy: currentFy,
          selectionMode: 'CARRY_ONLY',
          includeCarryForward: true,
          fromDate: aprStart,
          toDate: aprEnd,
        ),
        isTrue,
      );
      expect(
        ChallanStitcherWizard.evaluateEligibility(
          date: currentAprDate,
          effectiveOriginalFy: currentFy,
          currentFy: currentFy,
          selectionMode: 'CARRY_ONLY',
          includeCarryForward: true,
          fromDate: aprStart,
          toDate: aprEnd,
        ),
        isFalse,
      );
    });

    test('S2: partyMatchesChallan matches by partyId (even if renamed) and case-insensitive partyName', () {
      expect(
        WebChallanStitcherWizard.partyMatchesChallan(
          partyId: 'PTY-42',
          partyName: 'New Pharma Name',
          challanPartyId: 'PTY-42',
          challanPartyName: 'Old Pharma Name',
        ),
        isTrue,
      );
      expect(
        ChallanStitcherWizard.partyMatchesChallan(
          partyId: 'PTY-42',
          partyName: 'New Pharma Name',
          challanPartyId: 'PTY-42',
          challanPartyName: 'Old Pharma Name',
        ),
        isTrue,
      );
      expect(
        WebChallanStitcherWizard.partyMatchesChallan(
          partyId: 'PTY-42',
          partyName: 'Medlife Agencies',
          challanPartyId: '',
          challanPartyName: '  MEDLIFE AGENCIES ',
        ),
        isTrue,
      );
      expect(
        ChallanStitcherWizard.partyMatchesChallan(
          partyId: 'PTY-42',
          partyName: 'Medlife Agencies',
          challanPartyId: 'PTY-99',
          challanPartyName: 'Other Pharmacy',
        ),
        isFalse,
      );
    });
  });

  group('Point 2A: SnapshotWatcher Protection for WSCH/WPCH, Billed & Cross-FY Challans', () {
    test('S3: SnapshotWatcher never tombstones WEB challans, Billed/cross-FY challans, or empty partial lists', () {
      final snapshot = <String, dynamic>{
        'sales': <String>['INV-1'],
        'purchases': <String>[],
        'saleChallans': <String>[
          'SCH-WEB-100',
          'PCH-WEB-200',
          'SCH-BILLED-1',
          'SCH-CROSS-FY-1',
          'SCH-LOCAL-KEEP',
          'SCH-LOCAL-DEL',
        ],
        'purchaseChallans': <String>['PCH-WEB-9', 'PCH-LOCAL-1'],
        'saleReturns': <String>[],
        'purchaseReturns': <String>[],
        'vouchers': <String>[],
        'gstSessions': <String>[],
        'billedChallanIds': <String>['SCH-BILLED-1'],
        'crossFyChallanIds': <String>['SCH-CROSS-FY-1'],
      };

      // Non-empty saleChallans missing Web/Billed/CrossFY/DEL -> ONLY SCH-LOCAL-DEL is flagged!
      // Empty purchaseChallans (partial pull / switch) -> skips passive deletion completely!
      final deleted = SnapshotWatcher.detectDeletionsFromSnapshotMap(
        snapshot: snapshot,
        currentSaleIds: const ['INV-1'],
        currentPurchaseIds: const [],
        currentSaleChallanIds: const ['SCH-LOCAL-KEEP'],
        currentPurchaseChallanIds: const [],
        currentSaleReturnIds: const [],
        currentPurchaseReturnIds: const [],
        currentVoucherIds: const [],
        currentGstSessionIds: const [],
      );

      expect(deleted, contains('SCH-LOCAL-DEL'));
      expect(deleted, isNot(contains('SCH-WEB-100')));
      expect(deleted, isNot(contains('PCH-WEB-200')));
      expect(deleted, isNot(contains('SCH-BILLED-1')));
      expect(deleted, isNot(contains('SCH-CROSS-FY-1')));
      expect(deleted, isNot(contains('PCH-WEB-9')));
      expect(deleted, isNot(contains('PCH-LOCAL-1')));
    });
  });

  group('Point 2B: Equal-Version Newer-Timestamp Pending Revert Over Billed & Batch Delete Safety', () {
    test('S4: MultiFyCloudVault, SyncModules, and D1 apply allow equal-version newer Pending to revert Billed while equal-ts preserves Billed', () {
      // 1. MultiFyCloudVault.mergeJsonListLww: v3 Billed (ts=1000) vs v3 Pending (ts=2000) -> Pending wins!
      final lwwRevert = MultiFyCloudVault.mergeJsonListLww(
        fileName: 's_challan.json',
        localRaw: jsonEncode([
          {
            'id': 'SCH-WEB-1',
            'billNo': 'WSCH-1',
            'status': 'Billed',
            'billedInFy': '2027-28',
            'billedInvoiceId': 'INV-1',
            'billedInvoiceNo': 'S-1',
            'version': 3,
            'updatedAt': 1000,
            'originalFy': '2026-27',
          },
        ]),
        cloudRaw: jsonEncode([
          {
            'id': 'SCH-WEB-1',
            'billNo': 'WSCH-1',
            'status': 'Pending',
            'billedInFy': '',
            'billedInvoiceId': '',
            'billedInvoiceNo': '',
            'version': 3,
            'updatedAt': 2000,
            'originalFy': '2026-27',
          },
        ]),
        fy: '2026-27',
      );
      final lwwMerged = (jsonDecode(lwwRevert.mergedJson) as List).cast<Map<String, dynamic>>();
      expect(lwwMerged.single['status'], equals('Pending'));
      expect(lwwMerged.single['billedInvoiceNo'], equals(''));

      // Equal version AND equal timestamp -> Billed tie-break remains protected
      final lwwEqualTs = MultiFyCloudVault.mergeJsonListLww(
        fileName: 's_challan.json',
        localRaw: jsonEncode([
          {
            'id': 'SCH-TIE-1',
            'billNo': 'WSCH-2',
            'status': 'Billed',
            'version': 3,
            'updatedAt': 1500,
            'originalFy': '2026-27',
          },
        ]),
        cloudRaw: jsonEncode([
          {
            'id': 'SCH-TIE-1',
            'billNo': 'WSCH-2',
            'status': 'Pending',
            'version': 3,
            'updatedAt': 1500,
            'originalFy': '2026-27',
          },
        ]),
        fy: '2026-27',
      );
      final tieMerged = (jsonDecode(lwwEqualTs.mergedJson) as List).cast<Map<String, dynamic>>();
      expect(tieMerged.single['status'], equals('Billed'));

      // 2. SaleChallanSyncModule equal-version newer-ts Pending wins; equal-ts Billed holds
      final scList = [
        makeSaleChallan(
          id: 'SCH-MOD-1',
          billNo: 'WSCH-1',
          status: 'Billed',
          version: 3,
          updatedAt: 1000,
          billedInFy: '2027-28',
          billedInvoiceId: 'INV-1',
          billedInvoiceNo: 'S-1',
        ),
      ];
      expect(
        SaleChallanSyncModule.applySaleChallanMutation(
          scList,
          makeSaleChallan(id: 'SCH-MOD-1', billNo: 'WSCH-1', status: 'Pending', version: 3, updatedAt: 1000),
        ),
        isFalse,
      );
      expect(scList.single.status, equals('Billed'));
      expect(
        SaleChallanSyncModule.applySaleChallanMutation(
          scList,
          makeSaleChallan(id: 'SCH-MOD-1', billNo: 'WSCH-1', status: 'Pending', version: 3, updatedAt: 2000),
        ),
        isTrue,
      );
      expect(scList.single.status, equals('Pending'));

      // 3. PurchaseChallanSyncModule equal-version newer-ts Pending wins
      final pcList = [
        makePurchaseChallan(
          id: 'PCH-MOD-1',
          internalNo: 'WPCH-1',
          billNo: 'SUP-10',
          status: 'Billed',
          version: 3,
          updatedAt: 1000,
        ),
      ];
      expect(
        PurchaseChallanSyncModule.applyPurchaseChallanMutation(
          pcList,
          makePurchaseChallan(
            id: 'PCH-MOD-1',
            internalNo: 'WPCH-1',
            billNo: 'SUP-10',
            status: 'Pending',
            version: 3,
            updatedAt: 2500,
          ),
        ),
        isTrue,
      );
      expect(pcList.single.status, equals('Pending'));

      // 4. D1SalesLedgerService.applyEventsToLocalSaleChallans & applyEventsToLocalPurchaseChallans
      final d1Sc = [
        makeSaleChallan(
          id: 'SCH-WEB-9',
          billNo: 'WSCH-9',
          status: 'Billed',
          originalFy: '2026-27',
          version: 3,
          updatedAt: 1000,
          billedInFy: '2027-28',
          billedInvoiceId: 'INV-9',
          billedInvoiceNo: 'S-9',
        ),
      ];
      final scRevertCh = makeSaleChallan(
        id: 'SCH-WEB-9',
        billNo: 'WSCH-9',
        status: 'Pending',
        originalFy: '2026-27',
        version: 3,
        updatedAt: 5000,
      );
      final scMap = scRevertCh.toMap()..['doc_type'] = 'SALE_CHALLAN';
      final scApplied = D1SalesLedgerService.applyEventsToLocalSaleChallans(
        d1Sc,
        [
          {
            'bill_id': 'SCH-WEB-9',
            'bill_no': 'WSCH-9',
            'action': 'UPDATE',
            'version': 3,
            'updated_at': 5000,
            'fy': '2026-27',
            'sale_data': scMap,
          }
        ],
        '2026-27',
      );
      expect(scApplied, isTrue);
      expect(d1Sc.single.status, equals('Pending'));

      final d1Pc = [
        makePurchaseChallan(
          id: 'PCH-WEB-9',
          internalNo: 'WPCH-9',
          billNo: 'SUP-9',
          status: 'Billed',
          originalFy: '2026-27',
          version: 3,
          updatedAt: 1000,
          billedInFy: '2027-28',
          billedInvoiceId: 'PUR-9',
          billedInvoiceNo: 'WPUR-9',
        ),
      ];
      final pcRevertCh = makePurchaseChallan(
        id: 'PCH-WEB-9',
        internalNo: 'WPCH-9',
        billNo: 'SUP-9',
        status: 'Pending',
        originalFy: '2026-27',
        version: 3,
        updatedAt: 6000,
      );
      final pcMap = pcRevertCh.toMap()..['doc_type'] = 'PURCHASE_CHALLAN';
      final pcApplied = D1SalesLedgerService.applyEventsToLocalPurchaseChallans(
        d1Pc,
        [
          {
            'bill_id': 'PCH-WEB-9',
            'bill_no': 'SUP-9',
            'action': 'UPDATE',
            'version': 3,
            'updated_at': 6000,
            'fy': '2026-27',
            'sale_data': pcMap,
          }
        ],
        '2026-27',
      );
      expect(pcApplied, isTrue);
      expect(d1Pc.single.status, equals('Pending'));
    });

    test('S5: D1 batch containing both SALE INSERT and SALE DELETE skips re-billing and unmarks both FYs for mixed challans', () {
      const priorFy = '2026-27';
      const curFy = '2027-28';

      // Simulate poisoned tombstones on BOTH FYs for Web & App challans before revert
      D1SalesLedgerService.markSaleChallanPermanentlyDeleted('SCH-WEB-5', 'WSCH-5', priorFy);
      D1SalesLedgerService.markSaleChallanPermanentlyDeleted('SCH-WEB-5', 'WSCH-5', curFy);

      final appCh = makeSaleChallan(
        id: 'SCH-APP-5',
        billNo: 'SCH-5',
        status: 'Billed',
        originalFy: priorFy,
        version: 2,
        updatedAt: 2000,
        billedInFy: curFy,
        billedInvoiceId: 'INV-MIX-1',
        billedInvoiceNo: 'S-100',
      );
      final webCh = makeSaleChallan(
        id: 'SCH-WEB-5',
        billNo: 'WSCH-5',
        status: 'Billed',
        originalFy: priorFy,
        version: 2,
        updatedAt: 2000,
        billedInFy: curFy,
        billedInvoiceId: 'INV-MIX-1',
        billedInvoiceNo: 'S-100',
      );

      final salePayload = Sale(
        id: 'INV-MIX-1',
        billNo: 'S-100',
        partyId: 'P1',
        date: DateTime(2027, 4, 15),
        partyName: 'Party Alpha',
        partyGstin: '',
        partyState: 'Rajasthan',
        items: [...appCh.items, ...webCh.items],
        totalAmount: 160.0,
        paymentMode: 'CREDIT',
        linkedChallanIds: const ['SCH-APP-5', 'SCH-WEB-5'],
        version: 1,
        updatedAt: 2000,
      ).toMap()
        ..['doc_type'] = 'SALE';

      final batchEvents = <Map<String, dynamic>>[
        {
          'bill_id': 'INV-MIX-1',
          'bill_no': 'S-100',
          'action': 'INSERT',
          'version': 1,
          'updated_at': 2000,
          'fy': curFy,
          'sale_data': salePayload,
        },
        {
          'bill_id': 'INV-MIX-1',
          'bill_no': 'S-100',
          'action': 'DELETE',
          'version': 2,
          'updated_at': 3000,
          'fy': curFy,
          'sale_data': {'id': 'INV-MIX-1', 'billNo': 'S-100', 'doc_type': 'SALE', 'updatedAt': 3000},
        },
      ];

      final list = [appCh, webCh];

      // Even if a deleted bill's INSERT appears in the same batch, billLinkedChallansFromSaveEvents skips it
      final pendApp = makeSaleChallan(id: 'SCH-APP-5', billNo: 'SCH-5', status: 'Pending', originalFy: priorFy, version: 1, updatedAt: 1000);
      final pendWeb = makeSaleChallan(id: 'SCH-WEB-5', billNo: 'WSCH-5', status: 'Pending', originalFy: priorFy, version: 1, updatedAt: 1000);
      final billCheck = [pendApp, pendWeb];
      D1SalesLedgerService.billLinkedChallansFromSaveEvents(
        events: batchEvents,
        targetFy: curFy,
        saleChallans: billCheck,
      );
      expect(pendApp.status, equals('Pending'));
      expect(pendWeb.status, equals('Pending'));

      // revertLinkedChallansFromDeleteEvents reverts BOTH APP & WEB challans and unmarks BOTH FYs
      final revRes = D1SalesLedgerService.revertLinkedChallansFromDeleteEvents(
        events: batchEvents,
        targetFy: curFy,
        saleChallans: list,
      );
      expect(revRes.saleChallansMutated, isTrue);
      expect(appCh.status, equals('Pending'));
      expect(webCh.status, equals('Pending'));
      expect(appCh.version, greaterThan(2));
      expect(webCh.version, greaterThan(2));
      expect(D1SalesLedgerService.isSaleChallanIdDeleted('SCH-WEB-5', priorFy), isFalse);
      expect(D1SalesLedgerService.isSaleChallanIdDeleted('SCH-WEB-5', curFy), isFalse);
    });
  });

  group('Point 2C: End-to-End Mixed APP + WEB CF Challan Bill Delete & Vault/Cloud Preservation', () {
    test('S6: Deleting stitched Sale in New FY reverts both APP & WEB CF challans across FYs and survives poisoned tombstones via unmarked map', () {
      const oldFy = '2026-27';
      const newFy = '2027-28';
      final webPh = PharoahWebManager();
      webPh.availableFinancialYears = [oldFy, newFy];
      webPh.financialYear = newFy;

      final appCf = makeSaleChallan(
        id: 'SCH-APP-1',
        billNo: 'SCH-1',
        date: DateTime(2027, 2, 10),
        status: 'Pending',
        originalFy: oldFy,
        version: 1,
        updatedAt: 1000,
      );
      final webCf = makeSaleChallan(
        id: 'SCH-WEB-1',
        billNo: 'WSCH-1',
        date: DateTime(2027, 2, 12),
        status: 'Pending',
        originalFy: oldFy,
        version: 1,
        updatedAt: 1000,
      );

      webPh.saleChallans = [appCf, webCf];
      webPh.fyVault[oldFy] = {
        's_challan.json': jsonEncode([
          makeSaleChallan(
            id: 'SCH-APP-1',
            billNo: 'SCH-1',
            date: DateTime(2027, 2, 10),
            status: 'Pending',
            originalFy: oldFy,
            version: 1,
            updatedAt: 1000,
          ).toMap(),
          makeSaleChallan(
            id: 'SCH-WEB-1',
            billNo: 'WSCH-1',
            date: DateTime(2027, 2, 12),
            status: 'Pending',
            originalFy: oldFy,
            version: 1,
            updatedAt: 1000,
          ).toMap(),
        ]),
        'sales.json': '[]',
      };
      webPh.fyVault[newFy] = {
        's_challan.json': jsonEncode([appCf.toMap(), webCf.toMap()]),
        'sales.json': '[]',
      };

      // Bill both APP & WEB challans into a stitched Sale in 2027-28
      final stitchedSale = Sale(
        id: 'INV-STITCH-1',
        billNo: 'S-201',
        partyId: 'P1',
        date: DateTime(2027, 4, 15),
        partyName: 'Party Alpha',
        partyGstin: '',
        partyState: 'Rajasthan',
        items: [...appCf.items, ...webCf.items],
        totalAmount: 160.0,
        paymentMode: 'CREDIT',
        linkedChallanIds: const ['SCH-APP-1', 'SCH-WEB-1'],
        version: 1,
        updatedAt: 2000,
      );
      webPh.addSaleAndSync(stitchedSale);

      expect(appCf.status, equals('Billed'));
      expect(webCf.status, equals('Billed'));

      // Simulate stale poisoned tombstone from an old snapshot for SCH-WEB-1 before bill delete
      webPh.deletedRecordIds.add('SCH-WEB-1');
      webPh.deletedRecordIds.add('${oldFy}::SCH-WEB-1');
      webPh.localTombstoneRegistry['SCH-WEB-1'] = 2500;
      D1SalesLedgerService.markSaleChallanPermanentlyDeleted('SCH-WEB-1', 'WSCH-1', oldFy, 2500);

      // Delete the stitched bill
      webPh.deleteSale('INV-STITCH-1');

      // Active FY challans: BOTH APP & WEB must be Pending and unmarked!
      expect(appCf.status, equals('Pending'));
      expect(webCf.status, equals('Pending'));
      expect(appCf.billedInvoiceNo, isEmpty);
      expect(webCf.billedInvoiceNo, isEmpty);
      expect(webPh.deletedRecordIds.contains('SCH-WEB-1'), isFalse);
      expect(webPh.deletedRecordIds.contains('${oldFy}::SCH-WEB-1'), isFalse);
      expect(D1SalesLedgerService.isSaleChallanIdDeleted('SCH-WEB-1', oldFy), isFalse);
      expect(D1SalesLedgerService.isSaleChallanIdDeleted('SCH-WEB-1', newFy), isFalse);

      // Back-Year vault (2026-27) must ALSO have BOTH SCH-APP-1 & SCH-WEB-1 Pending!
      final backYearList = (jsonDecode(webPh.fyVault[oldFy]!['s_challan.json']!) as List)
          .cast<Map<String, dynamic>>();
      expect(backYearList.length, equals(2));
      for (final m in backYearList) {
        expect(m['status'], equals('Pending'));
        expect(m['billedInvoiceNo'] ?? '', isEmpty);
      }

      // Now simulate cloud download where stale tombstones.json still lists SCH-WEB-1@2500
      // while unmarked_tombstones.json (Map format) has newer timestamp 9999999999999!
      final futureUnmarkTs = DateTime.now().millisecondsSinceEpoch + 60000;
      final downloadedFiles = <String, dynamic>{
        'tombstones.json': jsonEncode(['SCH-WEB-1', '${oldFy}::SCH-WEB-1']),
        'tombstone_registry.json': jsonEncode({'SCH-WEB-1': 2500, '${oldFy}::SCH-WEB-1': 2500}),
        'unmarked_tombstones.json': jsonEncode({'SCH-WEB-1': futureUnmarkTs, '${oldFy}::SCH-WEB-1': futureUnmarkTs}),
        's_challan.json': jsonEncode([appCf.toMap(), webCf.toMap()]),
        'sales.json': '[]',
      };
      webPh.debugParseDownloadedFiles(downloadedFiles);
      expect(webPh.saleChallans.any((c) => c.id == 'SCH-APP-1' && c.status == 'Pending'), isTrue);
      expect(webPh.saleChallans.any((c) => c.id == 'SCH-WEB-1' && c.status == 'Pending'), isTrue);
    });

    test('S7: Deleting stitched Purchase in New FY reverts both PCH-APP & PCH-WEB CF challans across FYs & unmarks both FYs', () {
      const oldFy = '2026-27';
      const newFy = '2027-28';
      final webPh = PharoahWebManager();
      webPh.availableFinancialYears = [oldFy, newFy];
      webPh.financialYear = newFy;

      final appPch = makePurchaseChallan(
        id: 'PCH-APP-1',
        internalNo: 'PCH-1',
        billNo: 'SUP-11',
        date: DateTime(2027, 2, 10),
        status: 'Pending',
        originalFy: oldFy,
        version: 1,
        updatedAt: 1000,
      );
      final webPch = makePurchaseChallan(
        id: 'PCH-WEB-1',
        internalNo: 'WPCH-1',
        billNo: 'SUP-12',
        date: DateTime(2027, 2, 12),
        status: 'Pending',
        originalFy: oldFy,
        version: 1,
        updatedAt: 1000,
      );

      webPh.purchaseChallans = [appPch, webPch];
      webPh.fyVault[oldFy] = {
        'p_challan.json': jsonEncode([
          makePurchaseChallan(
            id: 'PCH-APP-1',
            internalNo: 'PCH-1',
            billNo: 'SUP-11',
            date: DateTime(2027, 2, 10),
            status: 'Pending',
            originalFy: oldFy,
            version: 1,
            updatedAt: 1000,
          ).toMap(),
          makePurchaseChallan(
            id: 'PCH-WEB-1',
            internalNo: 'WPCH-1',
            billNo: 'SUP-12',
            date: DateTime(2027, 2, 12),
            status: 'Pending',
            originalFy: oldFy,
            version: 1,
            updatedAt: 1000,
          ).toMap(),
        ]),
        'purc.json': '[]',
      };
      webPh.fyVault[newFy] = {
        'p_challan.json': jsonEncode([appPch.toMap(), webPch.toMap()]),
        'purc.json': '[]',
      };

      final stitchedPurchase = Purchase(
        id: 'PUR-STITCH-1',
        internalNo: 'WPUR-201',
        billNo: 'SUP-MIX-201',
        partyId: 'SUP-1',
        date: DateTime(2027, 4, 15),
        entryDate: DateTime(2027, 4, 15),
        distributorName: 'Supplier Alpha',
        items: [...appPch.items, ...webPch.items],
        totalAmount: 300.0,
        paymentMode: 'CREDIT',
        linkedChallanIds: const ['PCH-APP-1', 'PCH-WEB-1'],
        version: 1,
        updatedAt: 2000,
      );
      expect(webPh.addPurchaseAndSync(stitchedPurchase), isTrue);
      expect(appPch.status, equals('Billed'));
      expect(webPch.status, equals('Billed'));

      // Poison PCH-WEB-1 tombstone before delete
      webPh.deletedRecordIds.add('PCH-WEB-1');
      webPh.deletedRecordIds.add('${oldFy}::PCH-WEB-1');
      D1SalesLedgerService.markPurchasePermanentlyDeleted('PCH-WEB-1', 'SUP-1', 'SUP-12', 'WPCH-1', oldFy, 2500);

      webPh.deletePurchase('PUR-STITCH-1');

      expect(appPch.status, equals('Pending'));
      expect(webPch.status, equals('Pending'));
      expect(appPch.billedInvoiceNo, isEmpty);
      expect(webPch.billedInvoiceNo, isEmpty);
      expect(webPh.deletedRecordIds.contains('PCH-WEB-1'), isFalse);
      expect(webPh.deletedRecordIds.contains('${oldFy}::PCH-WEB-1'), isFalse);
      expect(D1SalesLedgerService.isPurchaseIdDeleted('PCH-WEB-1', oldFy), isFalse);
      expect(D1SalesLedgerService.isPurchaseIdDeleted('PCH-WEB-1', newFy), isFalse);

      final backYearPchList = (jsonDecode(webPh.fyVault[oldFy]!['p_challan.json']!) as List)
          .cast<Map<String, dynamic>>();
      expect(backYearPchList.length, equals(2));
      for (final m in backYearPchList) {
        expect(m['status'], equals('Pending'));
        expect(m['billedInvoiceNo'] ?? '', isEmpty);
      }
    });
  });
}
