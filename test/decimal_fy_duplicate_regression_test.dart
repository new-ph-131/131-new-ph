import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharoah_erp/fy_transfer_engine.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/sync_core/d1_sales_ledger_service.dart';
import 'package:pharoah_erp/sync_core/multi_fy_cloud_vault.dart';
import 'package:pharoah_erp/sync_core/modules/purchase_challan_sync_module.dart';
import 'package:pharoah_erp/sync_core/modules/purchase_sync_module.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory mockDocsDir;

  setUpAll(() async {
    mockDocsDir = await Directory.systemTemp.createTemp('pharoah_dec_fy_dup_');
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('1. Decimal Quantity Formatting', () {
    test('formatQty & formatQtyPair preserve 0.5 / loose fractions cleanly', () {
      expect(formatQty(0.5), equals('0.5'));
      expect(formatQty(1.0), equals('1'));
      expect(formatQty(1.250), equals('1.25'));
      expect(formatQty(0.005), equals('0.005'));
      expect(formatQty(-0.5), equals('-0.5'));
      expect(formatQtyPair(0.5, 0.5), equals('0.5 + 0.5'));
      expect(formatQtyPair(2.0, 0.0), equals('2'));
      expect(formatQtyPair(2.0, 1.5), equals('2 + 1.5'));
    });
  });

  group('2. Supplier Bill Duplicate Rules (Case & Punctuation Exactness)', () {
    final existingPurchases = <Purchase>[
      Purchase(
        id: 'PUR-ID-1',
        internalNo: 'PUR-1',
        billNo: 'ax1',
        partyId: 'PARTY-1',
        date: DateTime(2025, 5, 1),
        entryDate: DateTime(2025, 5, 1),
        distributorName: 'Alpha Pharma',
        items: const [],
        totalAmount: 500.0,
        paymentMode: 'CREDIT',
      ),
      Purchase(
        id: 'PUR-ID-DEL',
        internalNo: 'PUR-2',
        billNo: 'deleted1',
        partyId: 'PARTY-1',
        date: DateTime(2025, 5, 2),
        entryDate: DateTime(2025, 5, 2),
        distributorName: 'Alpha Pharma',
        items: const [],
        totalAmount: 100.0,
        paymentMode: 'CREDIT',
        isDeleted: 1,
      ),
    ];

    test('Same party + exact ax1 blocks; Ax1 / aX1 / ax-1 / ax 1 / other party allowed', () {
      expect(isSameSupplierInvoiceNo('ax1', ' ax1 '), isTrue);
      expect(isSameSupplierInvoiceNo('ax1', 'Ax1'), isFalse);
      expect(isSameSupplierInvoiceNo('ax1', 'aX1'), isFalse);
      expect(isSameSupplierInvoiceNo('ax1', 'ax-1'), isFalse);

      // Exact same party + exact billNo -> Duplicate!
      final dup = findDuplicateSupplierPurchase(
        purchases: existingPurchases,
        partyId: 'PARTY-1',
        partyName: 'Alpha Pharma',
        billNo: 'ax1',
      );
      expect(dup, isNotNull);
      expect(dup!.id, equals('PUR-ID-1'));

      // Case / punctuation variants on SAME party -> Allowed!
      for (final variant in ['Ax1', 'aX1', 'AX1', 'ax-1', 'ax 1', 'ax2']) {
        expect(
          findDuplicateSupplierPurchase(
            purchases: existingPurchases,
            partyId: 'PARTY-1',
            partyName: 'Alpha Pharma',
            billNo: variant,
          ),
          isNull,
          reason: 'Variant "$variant" must be allowed as distinct supplier bill',
        );
      }

      // Same exact 'ax1' on DIFFERENT party -> Allowed!
      expect(
        findDuplicateSupplierPurchase(
          purchases: existingPurchases,
          partyId: 'PARTY-2',
          partyName: 'Beta Distributors',
          billNo: 'ax1',
        ),
        isNull,
      );

      // Deleted record is ignored
      expect(
        findDuplicateSupplierPurchase(
          purchases: existingPurchases,
          partyId: 'PARTY-1',
          billNo: 'deleted1',
        ),
        isNull,
      );

      // Editing own bill skips self via excludeId / excludeInternalNo
      expect(
        findDuplicateSupplierPurchase(
          purchases: existingPurchases,
          partyId: 'PARTY-1',
          billNo: 'ax1',
          excludeId: 'PUR-ID-1',
        ),
        isNull,
      );
    });

    test('PurchaseChallan applies identical exact-case supplier duplicate rule', () {
      final challans = <PurchaseChallan>[
        PurchaseChallan(
          id: 'PC-1',
          internalNo: 'PCH-1',
          billNo: 'ax1',
          partyId: 'PARTY-1',
          date: DateTime(2025, 5, 1),
          distributorName: 'Alpha Pharma',
          items: const [],
          totalAmount: 300.0,
        ),
      ];

      expect(
        findDuplicateSupplierChallan(
          challans: challans,
          partyId: 'PARTY-1',
          billNo: 'ax1',
        ),
        isNotNull,
      );
      expect(
        findDuplicateSupplierChallan(
          challans: challans,
          partyId: 'PARTY-1',
          billNo: 'Ax1',
        ),
        isNull,
      );
      expect(
        findDuplicateSupplierChallan(
          challans: challans,
          partyId: 'PARTY-2',
          billNo: 'ax1',
        ),
        isNull,
      );
    });
  });

  group('3. FY Carry-Forward 0.5 Closing Stock Preservation', () {
    test('FYTransferEngine preserves 0.5 loose stock & nets split batches with filterZeroStock: true', () async {
      const String compId = 'COMP_FY_DEC_05';
      const String bizType = 'WHOLESALE';
      const String sourceFy = '2024-25';
      const String targetFy = '2025-26';

      final srcDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$sourceFy');
      await srcDir.create(recursive: true);

      final medLoose = Medicine(id: 'M_LOOSE', systemId: 'SYS_LOOSE', name: 'Syrup X', packing: '100ml');
      final medSplit = Medicine(id: 'M_SPLIT', systemId: 'SYS_SPLIT', name: 'Tab Y', packing: '10s');

      await File('${srcDir.path}/meds.json').writeAsString(jsonEncode([
        medLoose.toMap(),
        medSplit.toMap(),
      ]));

      await File('${srcDir.path}/bats.json').writeAsString(jsonEncode({
        medLoose.identityKey: [
          BatchInfo(batch: 'B-05', exp: '12/27', packing: '100ml', mrp: 120, rate: 80, openingQty: 0.5).toMap(),
        ],
        medSplit.identityKey: [
          BatchInfo(batch: 'B-POS', exp: '12/27', packing: '10s', mrp: 100, rate: 60, openingQty: 1.5).toMap(),
          BatchInfo(batch: 'B-NEG', exp: '12/27', packing: '10s', mrp: 100, rate: 60, openingQty: -1.0).toMap(),
        ],
      }));

      final ok = await FYTransferEngine.transferData(
        companyID: compId,
        businessType: bizType,
        sourceFY: sourceFy,
        targetFY: targetFy,
        filterZeroStock: true,
        filterExpired: false,
      );
      expect(ok, isTrue);

      final dstDir = Directory('${mockDocsDir.path}/Pharoah_Data/$compId/$bizType/$targetFy');
      final nextMeds = (jsonDecode(await File('${dstDir.path}/meds.json').readAsString()) as List)
          .map((e) => Medicine.fromMap(e))
          .toList();
      final nextBatsRaw = jsonDecode(await File('${dstDir.path}/bats.json').readAsString()) as Map<String, dynamic>;

      final nextLoose = nextMeds.firstWhere((m) => m.identityKey == medLoose.identityKey);
      expect(nextLoose.stock, closeTo(0.5, 0.0001));

      final looseBatches = (nextBatsRaw[medLoose.identityKey] as List).map((e) => BatchInfo.fromMap(e)).toList();
      expect(looseBatches.length, equals(1));
      expect(looseBatches.first.openingQty, closeTo(0.5, 0.0001));

      final nextSplit = nextMeds.firstWhere((m) => m.identityKey == medSplit.identityKey);
      expect(nextSplit.stock, closeTo(0.5, 0.0001));
    });
  });

  group('4. Case-Sensitive Purchase Sync & Tombstone Isolation', () {
    test('ax1 and Ax1 coexist across SyncModules and MultiFyCloudVault LWW without tombstone collision', () {
      const String fy = '2025-26';
      final pLower = Purchase(
        id: 'P-LOW',
        internalNo: 'PUR-1',
        billNo: 'ax1',
        partyId: 'PARTY-1',
        date: DateTime(2025, 5, 1),
        entryDate: DateTime(2025, 5, 1),
        distributorName: 'Alpha',
        items: const [],
        totalAmount: 100,
        paymentMode: 'CREDIT',
        updatedAt: 1000,
        version: 1,
      );
      final pUpper = Purchase(
        id: 'P-UP',
        internalNo: 'PUR-2',
        billNo: 'Ax1',
        partyId: 'PARTY-1',
        date: DateTime(2025, 5, 1),
        entryDate: DateTime(2025, 5, 1),
        distributorName: 'Alpha',
        items: const [],
        totalAmount: 200,
        paymentMode: 'CREDIT',
        updatedAt: 1100,
        version: 1,
      );

      final list = <Purchase>[pLower];
      PurchaseSyncModule.applyPurchaseMutation(list, pUpper);
      expect(list.length, equals(2));

      final chLower = PurchaseChallan(
        id: 'C-LOW',
        internalNo: 'PCH-1',
        billNo: 'ax1',
        partyId: 'PARTY-1',
        date: DateTime(2025, 5, 1),
        distributorName: 'Alpha',
        items: const [],
        totalAmount: 100,
        updatedAt: 1000,
      );
      final chUpper = PurchaseChallan(
        id: 'C-UP',
        internalNo: 'PCH-2',
        billNo: 'Ax1',
        partyId: 'PARTY-1',
        date: DateTime(2025, 5, 1),
        distributorName: 'Alpha',
        items: const [],
        totalAmount: 200,
        updatedAt: 1100,
      );
      final chList = <PurchaseChallan>[chLower];
      PurchaseChallanSyncModule.applyPurchaseChallanMutation(chList, chUpper);
      expect(chList.length, equals(2));

      // Tombstoning only ax1 (PARTY-1_ax1) must NOT kill Ax1 (PARTY-1_Ax1)!
      final scopedLower = D1SalesLedgerService.scopeSecondaryKey('PARTY-1_ax1', fy, true);
      final merged = MultiFyCloudVault.mergeJsonListLww(
        fileName: 'purc.json',
        localRaw: jsonEncode([pLower.toMap()]),
        cloudRaw: jsonEncode([pLower.toMap(), pUpper.toMap()]),
        fy: fy,
        localTombstones: {scopedLower},
        localRegistry: {scopedLower: 2000},
      );
      final out = (jsonDecode(merged.mergedJson) as List).cast<Map<String, dynamic>>();
      expect(out.length, equals(1));
      expect(out.first['billNo'], equals('Ax1'));
    });
  });
}
