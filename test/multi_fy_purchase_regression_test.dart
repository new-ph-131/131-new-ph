import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharoah_erp/gateway/company_registry_model.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:pharoah_erp/sync_core/d1_sales_ledger_service.dart';
import 'package:pharoah_erp/sync_core/multi_fy_cloud_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory mockDocsDir;

  setUpAll(() async {
    mockDocsDir = await Directory.systemTemp.createTemp('pharoah_mock_docs_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return mockDocsDir.path;
      },
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

  Map<String, dynamic> makePurchaseMap({
    required String id,
    required String internalNo,
    required String billNo,
    required String partyId,
    required double totalAmount,
    required int updatedAt,
    required int version,
    String dateIso = '2024-05-10T00:00:00.000Z',
  }) {
    return {
      'id': id,
      'internalNo': internalNo,
      'billNo': billNo,
      'partyId': partyId,
      'distributorName': 'Test Supplier $partyId',
      'date': dateIso,
      'entryDate': dateIso,
      'items': [],
      'totalAmount': totalAmount,
      'paymentMode': 'CREDIT',
      'updatedAt': updatedAt,
      'version': version,
      'isDeleted': 0,
    };
  }

  test('RC-2 & Multi-FY E2E Sequence: Old-FY Edit Preserves Both App & Web New-FY Purchases Across Switch', () async {
    final tempRoot = await Directory.systemTemp.createTemp('pharoah_rc2_e2e_');
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    const String compId = 'COMP_RC2_TEST';
    const String bizType = 'WHOLESALE';
    const String oldFy = '2023-24';
    const String newFy = '2024-25';

    final ph = PharoahManager();
    ph.activeCompany = CompanyProfile(
      id: compId,
      name: 'Pharoah Test Enterprise',
      businessType: bizType,
      createdAt: DateTime.utc(2023, 4, 1),
      password: 'secret',
      fYears: [oldFy, newFy],
    );

    final oldFyDir = Directory('${tempRoot.path}/Pharoah_Data/$compId/$bizType/$oldFy');
    final newFyDir = Directory('${tempRoot.path}/Pharoah_Data/$compId/$bizType/$newFy');
    await oldFyDir.create(recursive: true);
    await newFyDir.create(recursive: true);

    // Old FY: App Purchase (OLD-APP-1) + Web Purchase (OLD-WEB-1)
    final oldAppPurcV1 = makePurchaseMap(
      id: 'OLD-APP-1',
      internalNo: 'PUR-1',
      billNo: 'SUP-INV-1',
      partyId: 'PARTY-1',
      totalAmount: 1000.0,
      updatedAt: 1000,
      version: 1,
      dateIso: '2023-06-10T00:00:00.000Z',
    );
    final oldWebPurcV1 = makePurchaseMap(
      id: 'OLD-WEB-1',
      internalNo: 'WPUR-1',
      billNo: 'SUP-INV-2',
      partyId: 'PARTY-2',
      totalAmount: 2000.0,
      updatedAt: 1100,
      version: 1,
      dateIso: '2023-06-15T00:00:00.000Z',
    );

    // New FY: App Purchase (NEW-APP-1) + Web Purchase (NEW-WEB-1)
    final newAppPurcV1 = makePurchaseMap(
      id: 'NEW-APP-1',
      internalNo: 'PUR-1',
      billNo: 'SUP-INV-101',
      partyId: 'PARTY-1',
      totalAmount: 5000.0,
      updatedAt: 1200,
      version: 1,
      dateIso: '2024-06-10T00:00:00.000Z',
    );
    final newWebPurcV1 = makePurchaseMap(
      id: 'NEW-WEB-1',
      internalNo: 'WPUR-1',
      billNo: 'SUP-INV-102',
      partyId: 'PARTY-2',
      totalAmount: 6000.0,
      updatedAt: 1300,
      version: 1,
      dateIso: '2024-06-15T00:00:00.000Z',
    );

    // Remote Cloud Vault (contains both App and Web bills across Old FY and New FY)
    final Map<String, dynamic> remotePullResponse = {
      'status': 'SUCCESS',
      'fy': newFy,
      'files': {
        'purc.json': jsonEncode([newAppPurcV1, newWebPurcV1]),
        'fy_vault.json': jsonEncode({
          oldFy: {
            'purc.json': jsonEncode([oldAppPurcV1, oldWebPurcV1]),
          },
          newFy: {
            'purc.json': jsonEncode([newAppPurcV1, newWebPurcV1]),
          },
        }),
        'registered_fyears.json': jsonEncode([oldFy, newFy]),
      },
    };

    // App switches to Old FY (2023-24) and edits OLD-APP-1 (1000.0 -> 1750.0, v2)
    // Meanwhile, App's local New-FY disk only had NEW-APP-1 before Web created NEW-WEB-1
    ph.currentFY = oldFy;
    final oldAppPurcV2 = {
      ...oldAppPurcV1,
      'totalAmount': 1750.0,
      'updatedAt': 2500,
      'version': 2,
    };
    await File('${oldFyDir.path}/purc.json').writeAsString(jsonEncode([oldAppPurcV2]));
    await File('${newFyDir.path}/purc.json').writeAsString(jsonEncode([newAppPurcV1]));

    // Build Multi-FY Cloud Payload with outer cloudData response (verifying 'files' unwrapping + RC-2 merge)
    final bundle = await MultiFyCloudVault.buildMultiFyCloudPayload(
      ph: ph,
      coreFiles: const ['purc.json', 'sales.json', 'meds.json', 'parts.json'],
      localTombstones: <String>{},
      localRegistry: <String, int>{},
      targetFyOverride: oldFy,
      remoteCloudFiles: remotePullResponse,
      rootDirOverride: tempRoot,
    );

    final parsedUploadedVault = MultiFyCloudVault.parseFyVault(bundle.filesPayload);
    expect(parsedUploadedVault.containsKey(oldFy), isTrue);
    expect(parsedUploadedVault.containsKey(newFy), isTrue);

    final uploadedOldPurchases = jsonDecode(parsedUploadedVault[oldFy]!['purc.json']!) as List;
    expect(uploadedOldPurchases.length, equals(2));
    final editedOld = uploadedOldPurchases.firstWhere((p) => p['id'] == 'OLD-APP-1');
    expect((editedOld['totalAmount'] as num).toDouble(), equals(1750.0));
    expect(editedOld['version'], equals(2));
    expect(uploadedOldPurchases.any((p) => p['id'] == 'OLD-WEB-1'), isTrue);

    // Switch back to New FY and verify BOTH New-FY bills exist exactly once!
    final uploadedNewPurchases = jsonDecode(parsedUploadedVault[newFy]!['purc.json']!) as List;
    expect(uploadedNewPurchases.length, equals(2));
    expect(uploadedNewPurchases.where((p) => p['id'] == 'NEW-APP-1').length, equals(1));
    expect(uploadedNewPurchases.where((p) => p['id'] == 'NEW-WEB-1').length, equals(1));
  });

  test('RC-2 Edge Cases: Remote New-FY Records Survive When Local FY Folder is Missing, Incomplete, or Empty', () async {
    final tempRoot = await Directory.systemTemp.createTemp('pharoah_rc2_missing_');
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    const String compId = 'COMP_RC2_EDGE';
    const String bizType = 'WHOLESALE';
    const String oldFy = '2023-24';
    const String newFy = '2024-25';

    final ph = PharoahManager();
    ph.activeCompany = CompanyProfile(
      id: compId,
      name: 'Pharoah Edge Test',
      businessType: bizType,
      createdAt: DateTime.utc(2023, 4, 1),
      password: 'secret',
      fYears: [oldFy, newFy],
    );
    ph.currentFY = oldFy;

    final oldFyDir = Directory('${tempRoot.path}/Pharoah_Data/$compId/$bizType/$oldFy');
    final newFyDir = Directory('${tempRoot.path}/Pharoah_Data/$compId/$bizType/$newFy');
    await oldFyDir.create(recursive: true);

    final oldBill = makePurchaseMap(
      id: 'OLD-1',
      internalNo: 'PUR-1',
      billNo: 'B-1',
      partyId: 'P1',
      totalAmount: 900.0,
      updatedAt: 2000,
      version: 2,
    );
    final newAppBill = makePurchaseMap(
      id: 'NEW-APP-1',
      internalNo: 'PUR-1',
      billNo: 'B-101',
      partyId: 'P1',
      totalAmount: 4100.0,
      updatedAt: 1500,
      version: 1,
    );
    final newWebBill = makePurchaseMap(
      id: 'NEW-WEB-1',
      internalNo: 'WPUR-1',
      billNo: 'B-102',
      partyId: 'P2',
      totalAmount: 5200.0,
      updatedAt: 1600,
      version: 1,
    );

    await File('${oldFyDir.path}/purc.json').writeAsString(jsonEncode([oldBill]));

    final Map<String, dynamic> remoteCloudData = {
      'status': 'SUCCESS',
      'fy': newFy,
      'files': {
        'fy_vault.json': jsonEncode({
          oldFy: {'purc.json': jsonEncode([oldBill])},
          newFy: {'purc.json': jsonEncode([newAppBill, newWebBill])},
        }),
      },
    };

    // Case A: Local New-FY folder does NOT exist at all
    expect(await newFyDir.exists(), isFalse);
    var bundle = await MultiFyCloudVault.buildMultiFyCloudPayload(
      ph: ph,
      coreFiles: const ['purc.json'],
      localTombstones: <String>{},
      localRegistry: <String, int>{},
      targetFyOverride: oldFy,
      remoteCloudFiles: remoteCloudData,
      rootDirOverride: tempRoot,
    );
    var vault = MultiFyCloudVault.parseFyVault(bundle.filesPayload);
    var newPurc = jsonDecode(vault[newFy]!['purc.json']!) as List;
    expect(newPurc.length, equals(2));

    // Case B: Local New-FY folder exists, has meds.json, but purc.json is missing (incomplete)
    await newFyDir.create(recursive: true);
    await File('${newFyDir.path}/meds.json').writeAsString('[]');
    bundle = await MultiFyCloudVault.buildMultiFyCloudPayload(
      ph: ph,
      coreFiles: const ['purc.json', 'meds.json'],
      localTombstones: <String>{},
      localRegistry: <String, int>{},
      targetFyOverride: oldFy,
      remoteCloudFiles: remoteCloudData,
      rootDirOverride: tempRoot,
    );
    vault = MultiFyCloudVault.parseFyVault(bundle.filesPayload);
    newPurc = jsonDecode(vault[newFy]!['purc.json']!) as List;
    expect(newPurc.length, equals(2));

    // Case C: Local New-FY folder has an empty purc.json ('[]')
    await File('${newFyDir.path}/purc.json').writeAsString('[]');
    bundle = await MultiFyCloudVault.buildMultiFyCloudPayload(
      ph: ph,
      coreFiles: const ['purc.json'],
      localTombstones: <String>{},
      localRegistry: <String, int>{},
      targetFyOverride: oldFy,
      remoteCloudFiles: remoteCloudData,
      rootDirOverride: tempRoot,
    );
    vault = MultiFyCloudVault.parseFyVault(bundle.filesPayload);
    newPurc = jsonDecode(vault[newFy]!['purc.json']!) as List;
    expect(newPurc.length, equals(2));
    expect(newPurc.map((e) => e['id']).toSet(), equals({'NEW-APP-1', 'NEW-WEB-1'}));
  });

  test('LWW Conflict Resolution, Duplicate Identities, Distinct IDs Same InternalNo, & Scoped Tombstones', () {
    const String oldFy = '2023-24';
    const String newFy = '2024-25';

    // 1. Local newer edit vs Remote newer edit + Duplicate identity deduplication + Distinct IDs coexistence
    final localPurchases = [
      // Local has newer edit (v3 > remote v2)
      makePurchaseMap(
        id: 'P-LOCAL-NEWER',
        internalNo: 'PUR-1',
        billNo: 'INV-1',
        partyId: 'SUP-1',
        totalAmount: 3300.0,
        updatedAt: 3000,
        version: 3,
      ),
      // Remote will have newer edit (local v1 < remote v2)
      makePurchaseMap(
        id: 'P-REMOTE-NEWER',
        internalNo: 'PUR-2',
        billNo: 'INV-2',
        partyId: 'SUP-1',
        totalAmount: 1000.0,
        updatedAt: 1000,
        version: 1,
      ),
      // Duplicate identity A (same partyId + billNo + internalNo, older v1)
      makePurchaseMap(
        id: 'DUP-ID-A',
        internalNo: 'PUR-3',
        billNo: 'INV-3',
        partyId: 'SUP-2',
        totalAmount: 4000.0,
        updatedAt: 1000,
        version: 1,
      ),
      // Distinct ID with same supplier invoice but different internalNo (PUR-4 vs PUR-5)
      makePurchaseMap(
        id: 'DISTINCT-1',
        internalNo: 'PUR-4',
        billNo: 'INV-SHARED',
        partyId: 'SUP-3',
        totalAmount: 700.0,
        updatedAt: 1000,
        version: 1,
      ),
      // Record to be deleted via scoped tombstone in 2024-25
      makePurchaseMap(
        id: 'DEL-TARGET-1',
        internalNo: 'PUR-9',
        billNo: 'INV-9',
        partyId: 'SUP-9',
        totalAmount: 999.0,
        updatedAt: 1500,
        version: 1,
      ),
    ];

    final remotePurchases = [
      makePurchaseMap(
        id: 'P-LOCAL-NEWER',
        internalNo: 'PUR-1',
        billNo: 'INV-1',
        partyId: 'SUP-1',
        totalAmount: 2200.0,
        updatedAt: 2000,
        version: 2,
      ),
      makePurchaseMap(
        id: 'P-REMOTE-NEWER',
        internalNo: 'PUR-2',
        billNo: 'INV-2',
        partyId: 'SUP-1',
        totalAmount: 2800.0,
        updatedAt: 2500,
        version: 2,
      ),
      // Duplicate identity B (same partyId + billNo + internalNo, newer v2)
      makePurchaseMap(
        id: 'DUP-ID-B',
        internalNo: 'PUR-3',
        billNo: 'INV-3',
        partyId: 'SUP-2',
        totalAmount: 4500.0,
        updatedAt: 2200,
        version: 2,
      ),
      // Distinct ID with same supplier invoice but internalNo PUR-5 -> must NOT overwrite PUR-4!
      makePurchaseMap(
        id: 'DISTINCT-2',
        internalNo: 'PUR-5',
        billNo: 'INV-SHARED',
        partyId: 'SUP-3',
        totalAmount: 850.0,
        updatedAt: 1200,
        version: 1,
      ),
      // Stale snapshot of deleted record DEL-TARGET-1 -> must NOT resurrect!
      makePurchaseMap(
        id: 'DEL-TARGET-1',
        internalNo: 'PUR-9',
        billNo: 'INV-9',
        partyId: 'SUP-9',
        totalAmount: 999.0,
        updatedAt: 1500,
        version: 1,
      ),
    ];

    // Old FY has PUR-1 deleted ('2023-24::PUR-1'), which must NOT delete New FY's PUR-1!
    // New FY has DEL-TARGET-1 / '2024-25::PUR-9' deleted at ts=2000.
    final Set<String> tombstones = {
      D1SalesLedgerService.scopeSecondaryKey('PUR-1', oldFy),
      D1SalesLedgerService.scopeSecondaryKey('PUR-9', newFy),
    };
    final Map<String, int> registry = {
      D1SalesLedgerService.scopeSecondaryKey('PUR-1', oldFy): 5000,
      D1SalesLedgerService.scopeSecondaryKey('PUR-9', newFy): 2000,
    };

    final mergedRes = MultiFyCloudVault.mergeJsonListLww(
      fileName: 'purc.json',
      localRaw: jsonEncode(localPurchases),
      cloudRaw: jsonEncode(remotePurchases),
      fy: newFy,
      localTombstones: tombstones,
      localRegistry: registry,
    );

    final merged = (jsonDecode(mergedRes.mergedJson) as List).cast<Map<String, dynamic>>();

    // DEL-TARGET-1 (PUR-9 in 2024-25) must be permanently purged
    expect(merged.any((p) => p['id'] == 'DEL-TARGET-1'), isFalse);

    // P-LOCAL-NEWER (PUR-1 in 2024-25) must survive Old-FY PUR-1 tombstone and keep local v3 (3300.0)
    final pLocalNewer = merged.firstWhere((p) => p['id'] == 'P-LOCAL-NEWER');
    expect((pLocalNewer['totalAmount'] as num).toDouble(), equals(3300.0));
    expect(pLocalNewer['version'], equals(3));

    // P-REMOTE-NEWER must update to remote v2 (2800.0)
    final pRemoteNewer = merged.firstWhere((p) => p['id'] == 'P-REMOTE-NEWER');
    expect((pRemoteNewer['totalAmount'] as num).toDouble(), equals(2800.0));
    expect(pRemoteNewer['version'], equals(2));

    // Duplicate identity (SUP-2 + INV-3 + PUR-3) must collapse to a single record with amount 4500.0
    final dupMatches = merged.where((p) => p['internalNo'] == 'PUR-3').toList();
    expect(dupMatches.length, equals(1));
    expect((dupMatches.first['totalAmount'] as num).toDouble(), equals(4500.0));

    // Distinct IDs with same supplier invoice but different internalNo (PUR-4 and PUR-5) must both survive
    expect(merged.where((p) => p['id'] == 'DISTINCT-1').length, equals(1));
    expect(merged.where((p) => p['id'] == 'DISTINCT-2').length, equals(1));
  });
}
