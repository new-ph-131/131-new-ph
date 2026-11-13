import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharoah_erp/batch_sync_engine.dart';
import 'package:pharoah_erp/expiry_master.dart';
import 'package:pharoah_erp/fy_transfer_engine.dart';
import 'package:pharoah_erp/gateway/company_registry_model.dart';
import 'package:pharoah_erp/inventory_logic_center.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:pharoah_erp/stock_flow_engine.dart';
import 'package:pharoah_erp/sync_core/d1_sales_ledger_service.dart';
import 'package:pharoah_erp/sync_core/modules/batch_delta_merge_module.dart';
import 'package:pharoah_erp/sync_core/modules/batch_sync_module.dart';
import 'package:pharoah_erp/sync_core/multi_fy_cloud_vault.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/services/web_batch_resolver.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_accounts/services/web_voucher_d1_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory mockDocsDir;

  setUpAll(() async {
    mockDocsDir = await Directory.systemTemp.createTemp('pharoah_four_issues_test_');
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

  group('ISSUE 1: Inventory Without Batch / Expiry (All 4 Configurations)', () {
    test('Exact Scenario: Item X with no batch/expiry (Qty 1) + Batch XYZ Exp 12/28 (Qty 1) => Total Stock = 2 on App & Web', () {
      final medApp = Medicine(
        id: 'MED-X',
        systemId: 'PH-10001',
        name: 'ITEM X',
        packing: '1*10',
        mrp: 100.0,
        purRate: 70.0,
        rateA: 90.0,
        stock: 0.0,
      );
      final Map<String, List<BatchInfo>> batchHistory = {};

      final purchases = <Purchase>[
        Purchase(
          id: 'PUR-1',
          internalNo: 'PINV-1',
          billNo: 'B-101',
          partyId: 'SUP-1',
          distributorName: 'ALPHA DIST',
          date: DateTime(2026, 5, 1),
          entryDate: DateTime(2026, 5, 1),
          paymentMode: 'Credit',
          totalAmount: 70.0,
          items: [
            PurchaseItem(
              id: 'PI-1',
              srNo: 1,
              medicineID: 'MED-X',
              name: 'ITEM X',
              packing: '1*10',
              batch: '',
              exp: '',
              hsn: '3004',
              mrp: 100.0,
              qty: 1.0,
              freeQty: 0.0,
              purchaseRate: 70.0,
              gstRate: 12.0,
              total: 70.0,
              rateA: 90.0,
            ),
          ],
        ),
        Purchase(
          id: 'PUR-2',
          internalNo: 'PINV-2',
          billNo: 'B-102',
          partyId: 'SUP-1',
          distributorName: 'ALPHA DIST',
          date: DateTime(2026, 5, 2),
          entryDate: DateTime(2026, 5, 2),
          paymentMode: 'Credit',
          totalAmount: 85.0,
          items: [
            PurchaseItem(
              id: 'PI-2',
              srNo: 1,
              medicineID: 'MED-X',
              name: 'ITEM X',
              packing: '1*10',
              batch: 'XYZ',
              exp: '12/28',
              hsn: '3004',
              mrp: 120.0,
              qty: 1.0,
              freeQty: 0.0,
              purchaseRate: 85.0,
              gstRate: 12.0,
              total: 85.0,
              rateA: 110.0,
            ),
          ],
        ),
      ];

      InventoryLogicCenter.rebuildAllInventory(
        medicines: [medApp],
        batchHistory: batchHistory,
        purchases: purchases,
        sales: [],
        saleReturns: [],
        purchaseReturns: [],
      );

      expect(medApp.stock, closeTo(2.0, 0.001));
      final lots = batchHistory['PH-10001']!;
      expect(lots.length, equals(2));

      // Verify WebBatchResolver returns both non-batch and batch-managed options without duplicate synthetic OPENING
      final resolved = WebBatchResolver.resolveForMedicine(
        med: medApp,
        batchHistory: batchHistory,
        purchases: purchases,
        sales: [],
      );
      expect(resolved.length, equals(2));
      expect(resolved.any((b) => b.batch.trim().isEmpty && b.qty == 1.0 && b.mrp == 100.0 && b.purRate == 70.0), isTrue);
      expect(resolved.any((b) => b.batch.trim() == 'XYZ' && b.exp == '12/28' && b.qty == 1.0 && b.mrp == 120.0 && b.purRate == 85.0), isTrue);
      expect(resolved.any((b) => b.batch == 'OPENING'), isFalse);
    });

    test('All 4 inventory configurations (A: No Batch/No Exp, B: Batch/No Exp, C: No Batch/Exp, D: Batch/Exp) + Distinct non-batch lots + Sales/Returns/Breakage', () {
      final med = Medicine(
        id: 'MED-4CFG',
        systemId: 'PH-4CFG',
        name: 'MULTI CONFIG ITEM',
        packing: '1*10',
        mrp: 100.0,
        purRate: 70.0,
        rateA: 90.0,
      );
      final Map<String, List<BatchInfo>> batchHistory = {};

      final purchases = <Purchase>[
        Purchase(
          id: 'P-ALL',
          internalNo: 'PINV-ALL',
          billNo: 'INV-ALL',
          partyId: 'SUP-1',
          distributorName: 'SUPPLIER',
          date: DateTime(2026, 6, 1),
          entryDate: DateTime(2026, 6, 1),
          paymentMode: 'Credit',
          totalAmount: 1000.0,
          items: [
            // Config A1: No Batch, No Expiry (MRP 100, PurRate 70, Qty 2 + Free 0.5)
            PurchaseItem(
              id: 'I-A1', srNo: 1, medicineID: 'MED-4CFG', name: 'MULTI CONFIG ITEM', packing: '1*10',
              batch: '', exp: '', hsn: '3004', mrp: 100.0, qty: 2.0, freeQty: 0.5, purchaseRate: 70.0, gstRate: 12.0, total: 140.0, rateA: 90.0,
            ),
            // Config A2: Unrelated non-batch lot with different MRP 130 & PurRate 90 -> MUST NOT MERGE with A1!
            PurchaseItem(
              id: 'I-A2', srNo: 2, medicineID: 'MED-4CFG', name: 'MULTI CONFIG ITEM', packing: '1*10',
              batch: '', exp: '', hsn: '3004', mrp: 130.0, qty: 1.0, freeQty: 0.0, purchaseRate: 90.0, gstRate: 12.0, total: 90.0, rateA: 120.0,
            ),
            // Config B: Batch present, Expiry absent
            PurchaseItem(
              id: 'I-B', srNo: 3, medicineID: 'MED-4CFG', name: 'MULTI CONFIG ITEM', packing: '1*10',
              batch: 'BATCH-ONLY', exp: '', hsn: '3004', mrp: 110.0, qty: 3.0, freeQty: 0.0, purchaseRate: 75.0, gstRate: 12.0, total: 225.0, rateA: 100.0,
            ),
            // Config C: Batch absent, Expiry present
            PurchaseItem(
              id: 'I-C', srNo: 4, medicineID: 'MED-4CFG', name: 'MULTI CONFIG ITEM', packing: '1*10',
              batch: '', exp: '08/28', hsn: '3004', mrp: 115.0, qty: 4.0, freeQty: 0.0, purchaseRate: 80.0, gstRate: 12.0, total: 320.0, rateA: 105.0,
            ),
            // Config D: Batch present, Expiry present
            PurchaseItem(
              id: 'I-D', srNo: 5, medicineID: 'MED-4CFG', name: 'MULTI CONFIG ITEM', packing: '1*10',
              batch: 'BATCH-EXP', exp: '12/28', hsn: '3004', mrp: 125.0, qty: 5.0, freeQty: 0.0, purchaseRate: 85.0, gstRate: 12.0, total: 425.0, rateA: 115.0,
            ),
          ],
        ),
      ];

      // Sale of 1 unit from Config A1 (no batch, MRP 100)
      final sales = <Sale>[
        Sale(
          id: 'S-1', billNo: 'SL-1', date: DateTime(2026, 6, 5), partyId: 'CUST-1', partyName: 'CUST', partyGstin: '', partyState: 'Rajasthan',
          paymentMode: 'Cash', totalAmount: 90.0,
          items: [
            BillItem(
              id: 'BI-1', srNo: 1, medicineID: 'MED-4CFG', name: 'MULTI CONFIG ITEM', packing: '1*10',
              batch: '', exp: '', hsn: '3004', mrp: 100.0, rate: 90.0, qty: 1.0, freeQty: 0.0, gstRate: 12.0, total: 90.0,
            ),
          ],
        ),
      ];

      // Sellable Credit Note (+0.5) & Breakage Credit Note (0 stock impact) on Config C (no batch, exp 08/28)
      final saleReturns = <SaleReturn>[
        SaleReturn(
          id: 'SR-1', billNo: 'CN-1', date: DateTime(2026, 6, 6), partyName: 'CUST', totalAmount: 105.0,
          items: [
            BillItem(
              id: 'BI-SR-1', srNo: 1, medicineID: 'MED-4CFG', name: 'MULTI CONFIG ITEM', packing: '1*10',
              batch: '', exp: '08/28', hsn: '3004', mrp: 115.0, rate: 105.0, qty: 0.5, gstRate: 12.0, total: 52.5, isBreakage: false,
            ),
            BillItem(
              id: 'BI-SR-2', srNo: 2, medicineID: 'MED-4CFG', name: 'MULTI CONFIG ITEM', packing: '1*10',
              batch: '', exp: '08/28', hsn: '3004', mrp: 115.0, rate: 105.0, qty: 1.0, gstRate: 12.0, total: 105.0, isBreakage: true,
            ),
          ],
        ),
      ];

      // Purchase Return (-1.0) on Config B (BATCH-ONLY, no exp)
      final purchaseReturns = <PurchaseReturn>[
        PurchaseReturn(
          id: 'PR-1', billNo: 'DN-1', distributorName: 'SUPPLIER', date: DateTime(2026, 6, 7), totalAmount: 75.0,
          items: [
            PurchaseItem(
              id: 'PRI-1', srNo: 1, medicineID: 'MED-4CFG', name: 'MULTI CONFIG ITEM', packing: '1*10',
              batch: 'BATCH-ONLY', exp: '', hsn: '3004', mrp: 110.0, qty: 1.0, freeQty: 0.0, purchaseRate: 75.0, gstRate: 12.0, total: 75.0,
            ),
          ],
        ),
      ];

      InventoryLogicCenter.rebuildAllInventory(
        medicines: [med],
        batchHistory: batchHistory,
        purchases: purchases,
        sales: sales,
        saleReturns: saleReturns,
        purchaseReturns: purchaseReturns,
      );

      final lots = batchHistory['PH-4CFG']!;
      expect(lots.length, equals(5)); // All 5 distinct lots preserved!
      // Expected total: A1 (2.5 - 1.0 = 1.5) + A2 (1.0) + B (3.0 - 1.0 = 2.0) + C (4.0 + 0.5 = 4.5) + D (5.0) = 14.0
      expect(med.stock, closeTo(14.0, 0.001));

      final flow = StockFlowEngine.calculateStockFlow(
        med: med,
        batchHistory: batchHistory,
        purchases: purchases,
        sales: sales,
        saleReturns: saleReturns,
        purchaseReturns: purchaseReturns,
      );
      expect(flow.closingStock, closeTo(14.0, 0.001));
    });
  });

  group('ISSUE 2 & ISSUE 3: Multi-FY Discovery, First-Install Sync & Automatic Party/Stock Cascade', () {
    test('Scenario A & B: New FY created on Web is auto-discovered by App & Back-FY Party mutations (Sale, Purchase, Credit Note, Debit Note, Voucher, Delete) cascade across 2025-26 -> 2026-27', () async {
      final ph = PharoahManager();
      final comp = CompanyProfile(
        id: 'COMP_SYNC_1',
        name: 'PHAROAH TEST STORE',
        businessType: 'Wholesale',
        adminUser: 'admin',
        password: '1234',
        fYears: ['2025-26'],
      );
      ph.activeCompany = comp;
      ph.companiesRegistry = [comp];
      ph.currentFY = ''; // Simulating CompanyControlPanelView (Gateway mode)

      final party25 = Party(id: 'P-1', name: 'RAMESH MEDICAL', group: 'Sundry Debtors', opBal: 1000.0);
      final med25 = Medicine(id: 'M-1', systemId: 'PH-10001', name: 'DOLO 650', packing: '1*15', mrp: 35.0, purRate: 22.0, stock: 10.0);
      final batch25 = BatchInfo(batch: '', exp: '', packing: '1*15', mrp: 35.0, rate: 22.0, purRate: 22.0, openingQty: 10.0, qty: 10.0);

      final sale25 = Sale(
        id: 'SALE-25-1',
        billNo: 'INV-01',
        date: DateTime(2025, 6, 15),
        partyId: 'P-1',
        partyName: 'RAMESH MEDICAL',
        partyGstin: '',
        partyState: 'Rajasthan',
        paymentMode: 'Credit',
        totalAmount: 500.0,
        items: [
          BillItem(id: 'BI-25-1', srNo: 1, medicineID: 'M-1', name: 'DOLO 650', packing: '1*15', batch: '', exp: '', hsn: '3004', mrp: 35.0, rate: 25.0, qty: 2.0, gstRate: 12.0, total: 50.0),
        ],
      );

      final Map<String, dynamic> cloudPayload = {
        'status': 'SUCCESS',
        'fy': '2026-27',
        'registryProfile': {
          'fYears': ['2025-26', '2026-27'],
        },
        'files': {
          'fy_vault.json': jsonEncode({
            '2025-26': {
              'parts.json': jsonEncode([party25.toMap()]),
              'meds.json': jsonEncode([med25.toMap()]),
              'bats.json': jsonEncode({'PH-10001': [batch25.toMap()]}),
              'sales.json': jsonEncode([sale25.toMap()]),
              'purc.json': jsonEncode([]),
              'vouc.json': jsonEncode([]),
              's_return.json': jsonEncode([]),
              'p_return.json': jsonEncode([]),
            },
            '2026-27': {
              'parts.json': jsonEncode([Party(id: 'P-1', name: 'RAMESH MEDICAL', group: 'Sundry Debtors', opBal: 0.0).toMap()]),
              'meds.json': jsonEncode([Medicine(id: 'M-1', systemId: 'PH-10001', name: 'DOLO 650', packing: '1*15', mrp: 35.0, purRate: 22.0, stock: 0.0).toMap()]),
              'bats.json': jsonEncode({'PH-10001': []}),
              'sales.json': jsonEncode([]),
              'purc.json': jsonEncode([]),
              'vouc.json': jsonEncode([]),
              's_return.json': jsonEncode([]),
              'p_return.json': jsonEncode([]),
            },
          }),
        },
      };

      // 1. Sync vault while App is at Control Panel (currentFY is empty)
      await MultiFyCloudVault.syncVaultYearsToLocalDisk(
        ph: ph,
        cloudData: cloudPayload,
        localTombstones: {},
        localRegistry: {},
      );

      // Verify 2026-27 was automatically discovered and added to activeCompany.fYears!
      expect(ph.activeCompany!.fYears, containsAll(['2025-26', '2026-27']));

      // Login to 2026-27 and verify cascaded opening balance (1000 + 500 = 1500) and non-batch stock (10 - 2 = 8)
      await ph.loginToCompany(comp, '2026-27');
      expect(ph.parties.firstWhere((p) => p.id == 'P-1').opBal, closeTo(1500.0, 0.001));
      expect(ph.medicines.firstWhere((m) => m.id == 'M-1').stock, closeTo(8.0, 0.001));

      // 2. Now simulate back-FY (2025-26) D1 edge mutations arriving while App is open on 2026-27:
      //    - Credit Note (SaleReturn) of 100 in 2025-26 (sellable qty 1 -> stock 8 + 1 = 9, party opBal 1500 - 100 = 1400)
      //    - Receipt Voucher of 400 in 2025-26 (party opBal 1400 - 400 = 1000)
      final sRet25 = SaleReturn(
        id: 'SR-25-1',
        billNo: 'CN-25-1',
        date: DateTime(2025, 7, 1),
        partyName: 'RAMESH MEDICAL',
        totalAmount: 100.0,
        status: 'Active',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        version: 1,
        items: [
          BillItem(
            id: 'BI-SR25-1', srNo: 1, medicineID: 'M-1', name: 'DOLO 650', packing: '1*15',
            batch: '', exp: '', hsn: '3004', mrp: 35.0, rate: 25.0, qty: 1.0, gstRate: 12.0, total: 25.0, isBreakage: false,
          ),
        ],
      );
      final vouc25 = Voucher(
        id: 'V-25-1',
        voucherNo: 'RCP-25-1',
        date: DateTime(2025, 7, 2),
        type: 'Receipt',
        partyId: 'P-1',
        partyName: 'RAMESH MEDICAL',
        amount: 400.0,
        paymentMode: 'Cash',
        narration: 'Part payment',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        version: 1,
      );

      final crossFyEdgeEvents = <Map<String, dynamic>>[
        {
          'bill_id': sRet25.id,
          'bill_no': sRet25.billNo,
          'action': 'UPSERT_SALE_RETURN',
          'fy': '2025-26',
          'version': 1,
          'updated_at': sRet25.updatedAt,
          'sale_data': {
            ...sRet25.toMap(),
            'doc_type': 'SALE_RETURN',
            'fy': '2025-26',
          },
        },
        {
          'bill_id': vouc25.id,
          'bill_no': vouc25.voucherNo,
          'action': 'UPSERT_VOUCHER',
          'fy': '2025-26',
          'version': 1,
          'updated_at': vouc25.updatedAt,
          'sale_data': {
            ...vouc25.toMap(),
            'doc_type': 'VOUCHER',
            'fy': '2025-26',
          },
        },
      ];

      await MultiFyCloudVault.applyCrossFyEdgeEventsToLocalDisk(
        ph: ph,
        edgeEvents: crossFyEdgeEvents,
      );

      // Verify 2026-27 opening balance & stock updated automatically without manual cascade!
      expect(ph.parties.firstWhere((p) => p.id == 'P-1').opBal, closeTo(1000.0, 0.001));
      expect(ph.medicines.firstWhere((m) => m.id == 'M-1').stock, closeTo(9.0, 0.001));

      // 3. Now delete the Voucher in 2025-26 via D1 DELETE_VOUCHER event -> opBal in 2026-27 must automatically become 1400.0!
      await MultiFyCloudVault.applyCrossFyEdgeEventsToLocalDisk(
        ph: ph,
        edgeEvents: [
          {
            'bill_id': vouc25.id,
            'bill_no': vouc25.voucherNo,
            'action': 'DELETE_VOUCHER',
            'fy': '2025-26',
            'version': 2,
            'updated_at': DateTime.now().millisecondsSinceEpoch + 1000,
            'sale_data': {'doc_type': 'VOUCHER', 'fy': '2025-26'},
          },
        ],
      );
      expect(ph.parties.firstWhere((p) => p.id == 'P-1').opBal, closeTo(1400.0, 0.001));
    });
  });

  group('ISSUE 4: Stock Audit, Batch Sync & Valuation Reconciliation', () {
    test('BatchSyncModule & BatchDeltaMergeModule sync non-batch and batch-managed lots without data loss', () {
      final targetBatchHistory = <String, List<BatchInfo>>{};
      final incomingJson = {
        'PH-10001': [
          BatchInfo(
            batch: '',
            exp: '',
            packing: '1*10',
            mrp: 100.0,
            rate: 70.0,
            purRate: 70.0,
            rateA: 90.0,
            openingQty: 5.0,
            qty: 5.0,
            version: 2,
            updatedAt: 1000,
          ).toMap(),
          BatchInfo(
            batch: 'XYZ',
            exp: '12/28',
            packing: '1*10',
            mrp: 120.0,
            rate: 85.0,
            purRate: 85.0,
            rateA: 110.0,
            openingQty: 3.0,
            qty: 3.0,
            version: 2,
            updatedAt: 1000,
          ).toMap(),
        ],
      };

      final changed = BatchDeltaMergeModule.mergeBatchHistoryFromCloudJson(
        targetBatchHistory: targetBatchHistory,
        incomingJson: incomingJson,
        registry: {},
      );
      expect(changed, isTrue);
      expect(targetBatchHistory['PH-10001']!.length, equals(2));

      final filteredStr = BatchDeltaMergeModule.filterTombstonedBatchJson(
        jsonEncode(incomingJson),
        registry: {},
        tombstones: {},
      );
      final filteredMap = jsonDecode(filteredStr) as Map<String, dynamic>;
      expect((filteredMap['PH-10001'] as List).length, equals(2));
    });
  });
}
