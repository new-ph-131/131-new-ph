import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharoah_erp/batch_sync_engine.dart';
import 'package:pharoah_erp/finance/stock_flow_engine.dart';
import 'package:pharoah_erp/fy_transfer_engine.dart';
import 'package:pharoah_erp/gateway/company_registry_model.dart';
import 'package:pharoah_erp/inventory_logic_center.dart';
import 'package:pharoah_erp/logic/app_accounts_calculator.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import 'package:pharoah_erp/sync_bridge/engines/universal_delta_merger.dart';
import 'package:pharoah_erp/sync_core/d1_sales_ledger_service.dart';
import 'package:pharoah_erp/sync_core/models/sync_envelope.dart';
import 'package:pharoah_erp/sync_core/modules/batch_sync_module.dart';
import 'package:pharoah_erp/sync_core/modules/medicine_sync_module.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_accounts/services/web_accounts_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory mockDocsDir;

  setUpAll(() async {
    mockDocsDir = await Directory.systemTemp.createTemp('pharoah_sl_test_docs_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => mockDocsDir.path,
    );
  });

  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      if (await mockDocsDir.exists()) {
        await mockDocsDir.delete(recursive: true);
      }
    } catch (_) {
      // Background async file flushes from unawaited manager saves may race with temp cleanup.
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    D1SalesLedgerService.activeFinancialYear = '2025-26';
  });

  PharoahManager createIsolatedAppManager({String fy = '2025-26'}) {
    final ph = PharoahManager();
    ph.currentFY = fy;
    ph.activeCompany = CompanyProfile(
      id: 'COMP_SL_TEST',
      name: 'Pharoah Stock & Ledger Test Co',
      businessType: 'WHOLESALE',
      createdAt: DateTime.utc(2025, 4, 1),
      password: 'secret',
      fYears: ['2024-25', '2025-26', '2026-27'],
    );
    return ph;
  }

  test('BUG-01: App Purchase(100) -> Sale(5+5) -> deleteBill(sale2) -> cancelBill(sale1) updates stock & batch immediately', () async {
    final ph = createIsolatedAppManager();
    final partyX = Party(id: 'PX', name: 'Party X');
    final med = Medicine(
      id: 'MED1',
      systemId: 'SYS_MED1',
      name: 'Paracetamol 650',
      packing: '10x10',
      mrp: 30.0,
      purRate: 15.0,
      rateA: 20.0,
    );
    ph.parties = [Party(id: 'cash', name: 'CASH', group: 'Cash in Hand'), partyX];
    ph.medicines = [med];

    await ph.finalizePurchase(
      internalNo: 'PUR-1',
      billNo: 'SUP-100',
      date: DateTime(2025, 5, 10),
      party: partyX,
      items: [
        PurchaseItem(
          id: 'PI1',
          srNo: 1,
          medicineID: med.id,
          name: med.name,
          packing: med.packing,
          batch: 'B1',
          exp: '12/27',
          hsn: '3004',
          mrp: 30.0,
          qty: 100.0,
          purchaseRate: 15.0,
          gstRate: 12.0,
          total: 1500.0,
        ),
      ],
      total: 1500.0,
      mode: 'CREDIT',
    );
    expect(med.stock, equals(100.0));
    expect(ph.batchHistory[med.identityKey]!.first.qty, equals(100.0));

    await ph.finalizeSale(
      billNo: 'INV-1',
      date: DateTime(2025, 5, 11),
      party: partyX,
      items: [
        BillItem(
          id: 'SI1',
          srNo: 1,
          medicineID: med.id,
          name: med.name,
          packing: med.packing,
          batch: 'B1',
          exp: '12/27',
          hsn: '3004',
          mrp: 30.0,
          qty: 5.0,
          rate: 20.0,
          gstRate: 12.0,
          total: 100.0,
        ),
      ],
      total: 100.0,
      mode: 'CREDIT',
    );
    await ph.finalizeSale(
      billNo: 'INV-2',
      date: DateTime(2025, 5, 12),
      party: partyX,
      items: [
        BillItem(
          id: 'SI2',
          srNo: 1,
          medicineID: med.id,
          name: med.name,
          packing: med.packing,
          batch: 'B1',
          exp: '12/27',
          hsn: '3004',
          mrp: 30.0,
          qty: 5.0,
          rate: 20.0,
          gstRate: 12.0,
          total: 100.0,
        ),
      ],
      total: 100.0,
      mode: 'CREDIT',
    );
    expect(med.stock, equals(90.0));
    expect(ph.batchHistory[med.identityKey]!.first.qty, equals(90.0));

    // Delete INV-2 -> must immediately become 95 without restart
    final sale2Id = ph.sales.firstWhere((s) => s.billNo == 'INV-2').id;
    ph.deleteBill(sale2Id);
    expect(med.stock, equals(95.0));
    expect(ph.batchHistory[med.identityKey]!.first.qty, equals(95.0));

    // Cancel INV-1 -> must bump version and immediately restore to 100
    final sale1 = ph.sales.firstWhere((s) => s.billNo == 'INV-1');
    final int prevVer = sale1.version;
    ph.cancelBill(sale1.id);
    expect(sale1.status, equals('Cancelled'));
    expect(sale1.version, equals(prevVer + 1));
    expect(med.stock, equals(100.0));
    expect(ph.batchHistory[med.identityKey]!.first.qty, equals(100.0));
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });

  test('BUG-02 & BUG-15: No phantom opening stock after Purchase deletion, legacy map still heals, last batch removal zeros stock', () {
    final med = Medicine(
      id: 'MED_P',
      systemId: 'SYS_P',
      name: 'Amoxycillin',
      packing: '10s',
    );
    final medLoose = Medicine(
      id: 'MED_L',
      systemId: 'SYS_L',
      name: 'Loose Item',
      packing: '1s',
      stock: 25.0,
    );

    // 1. Purchase creates batch B1 with openingQty = 0, qty = 100
    final Map<String, List<BatchInfo>> batchHistory = {
      med.identityKey: [
        BatchInfo(batch: 'B1', exp: '10/27', packing: '10s', mrp: 50, rate: 30, qty: 100, openingQty: 0),
      ],
    };
    final deletedPurchase = Purchase(
      id: 'PUR-DEL-1',
      internalNo: 'PUR-1',
      billNo: 'P100',
      partyId: 'P1',
      date: DateTime(2025, 5, 1),
      entryDate: DateTime(2025, 5, 1),
      distributorName: 'Party X',
      items: [
        PurchaseItem(
          id: 'PI1',
          srNo: 1,
          medicineID: med.id,
          name: med.name,
          packing: med.packing,
          batch: 'B1',
          exp: '10/27',
          hsn: '3004',
          mrp: 50,
          qty: 100,
          purchaseRate: 30,
          gstRate: 12,
          total: 3000,
        ),
      ],
      totalAmount: 3000,
      paymentMode: 'CREDIT',
      isDeleted: 1,
    );

    InventoryLogicCenter.rebuildAllInventory(
      medicines: [med, medLoose],
      batchHistory: batchHistory,
      purchases: [deletedPurchase],
      sales: [],
      saleReturns: [],
      purchaseReturns: [],
    );

    // Must NOT heal openingQty to 100!
    expect(batchHistory[med.identityKey]!.first.openingQty, equals(0.0));
    expect(batchHistory[med.identityKey]!.first.qty, equals(0.0));
    expect(med.stock, equals(0.0));
    // Loose item with no batchHistory key preserves its loose stock
    expect(medLoose.stock, equals(25.0));

    // 2. Legacy map without openingQty key MUST heal once
    final legacyBatch = BatchInfo.fromMap({'batch': 'OLD1', 'qty': 40.0, 'mrp': 20.0, 'rate': 10.0});
    expect(legacyBatch.legacyOpeningHealPending, isTrue);
    final Map<String, List<BatchInfo>> legacyHistory = {med.identityKey: [legacyBatch]};
    InventoryLogicCenter.rebuildAllInventory(
      medicines: [med],
      batchHistory: legacyHistory,
      purchases: [],
      sales: [],
      saleReturns: [],
      purchaseReturns: [],
    );
    expect(legacyBatch.openingQty, equals(40.0));
    expect(legacyBatch.legacyOpeningHealPending, isFalse);
    expect(med.stock, equals(40.0));

    // 3. Removing the last batch (empty list under key) must reset med.stock to 0.0
    legacyHistory[med.identityKey] = [];
    InventoryLogicCenter.rebuildAllInventory(
      medicines: [med],
      batchHistory: legacyHistory,
      purchases: [],
      sales: [],
      saleReturns: [],
      purchaseReturns: [],
    );
    expect(med.stock, equals(0.0));
  });

  test('BUG-03, BUG-11 & BUG-13: Web SaleReturn adds qty ONCE, deleteSaleReturn rebuilds immediately, case-insensitive batch, WRCT-/WPAY- series', () {
    final webPh = PharoahWebManager();
    webPh.financialYear = '2025-26';
    final med = Medicine(id: 'M1', systemId: 'SYS_M1', name: 'Dolo 650', packing: '15s', mrp: 35, rateA: 25);
    webPh.medicines = [med];
    webPh.parties = [Party(id: 'PX', name: 'Party X')];
    webPh.purchases = [
      Purchase(
        id: 'WPUR-1',
        internalNo: 'WPUR-1',
        billNo: 'SUP-1',
        partyId: 'PX',
        date: DateTime(2025, 5, 1),
        entryDate: DateTime(2025, 5, 1),
        distributorName: 'Party X',
        items: [
          PurchaseItem(
            id: 'WPI-1',
            srNo: 1,
            medicineID: med.id,
            name: med.name,
            packing: med.packing,
            batch: 'B1',
            exp: '12/27',
            hsn: '3004',
            mrp: 35,
            qty: 100,
            purchaseRate: 20,
            gstRate: 12,
            total: 2000,
          ),
        ],
        totalAmount: 2000,
        paymentMode: 'CREDIT',
      ),
    ];
    webPh.batchHistory[med.identityKey] = [
      BatchInfo(batch: 'B1', exp: '12/27', packing: '15s', mrp: 35, rate: 20, openingQty: 0),
    ];
    webPh.rebuildInventory();
    expect(med.stock, equals(100.0));

    // Case-insensitive batch update must NOT create duplicate 'b1' entry
    webPh.registerBatchActivity(
      productKey: med.identityKey,
      batchNo: 'b1',
      exp: '12/27',
      packing: '15s',
      mrp: 35,
      rate: 20,
    );
    expect(webPh.batchHistory[med.identityKey]!.length, equals(1));

    // Sellable SaleReturn on batch 'B2' (not yet in batchHistory) must add 5 ONCE (total 105, not 110)
    final sr = SaleReturn(
      id: 'WSR-1',
      billNo: 'WCN-1',
      date: DateTime(2025, 5, 12),
      partyName: 'Party X',
      returnType: 'Sellable',
      items: [
        BillItem(
          id: 'SRI-1',
          srNo: 1,
          medicineID: med.id,
          name: med.name,
          packing: med.packing,
          batch: 'B2',
          exp: '12/27',
          hsn: '3004',
          mrp: 35,
          qty: 5,
          rate: 25,
          gstRate: 12,
          total: 125,
        ),
      ],
      totalAmount: 125,
    );
    webPh.addSaleReturnAndSync(sr);
    expect(med.stock, equals(105.0));

    // Deleting SaleReturn must immediately revert stock to 100.0
    webPh.deleteSaleReturn('WSR-1');
    expect(med.stock, equals(100.0));
    expect(webPh.saleReturns, isEmpty);

    // Web Receipt/Payment series isolation: App RCT-1 & Web WRCT-1 coexist
    expect(webPh.getNextBillNumber('RECEIPT', 'RCT-', 101), equals('WRCT-1'));
    expect(webPh.getNextBillNumber('PAYMENT', 'PAY-', 101), equals('WPAY-1'));
    final List<Voucher> localVouchers = [
      Voucher(
        id: 'V-APP-1',
        type: 'Receipt',
        voucherNo: 'RCT-1',
        date: DateTime(2025, 5, 15),
        partyId: 'PX',
        partyName: 'Party X',
        amount: 500,
        paymentMode: 'Cash',
        updatedAt: 1000,
        version: 1,
      ),
    ];
    UniversalDeltaMerger.mergeEntityList<Voucher>(
      cloudList: [
        Voucher(
          id: 'V-WEB-1',
          type: 'Receipt',
          voucherNo: 'WRCT-1',
          date: DateTime(2025, 5, 15),
          partyId: 'PX',
          partyName: 'Party X',
          amount: 300,
          paymentMode: 'Cash',
          updatedAt: 2000,
          version: 1,
        ).toMap(),
      ],
      localList: localVouchers,
      tombstones: {},
      getId: (v) => v.id,
      getRefNo: (v) => v.voucherNo,
      fromMap: (m) => Voucher.fromMap(m),
      toMap: (v) => v.toMap(),
    );
    expect(localVouchers.length, equals(2));
    expect(localVouchers.map((v) => v.voucherNo).toSet(), equals({'RCT-1', 'WRCT-1'}));
  });

  test('BUG-05: Cross-FY BATCH envelope blocked and MEDICINE envelope preserves local active-FY stock', () {
    D1SalesLedgerService.activeFinancialYear = '2025-26';
    final Map<String, List<BatchInfo>> batchHistory = {
      'SYS_M1': [
        BatchInfo(batch: 'B1', exp: '12/26', packing: '10s', mrp: 10, rate: 5, openingQty: 10, qty: 10, version: 1),
      ],
    };

    // Cross-FY insert of B99 from 2026-27 must NOT leak into 2025-26
    final crossInsert = SyncEnvelope(
      syncId: 'BATCH_SYSM1_B99',
      documentType: 'BATCH',
      action: 'INSERT',
      version: 2,
      updatedAt: 5000,
      isDeleted: 0,
      billData: {
        'fy': '2026-27',
        'medKey': 'SYS_M1',
        'batch': {'batch': 'B99', 'exp': '12/28', 'openingQty': 50.0, 'qty': 50.0},
      },
    );
    expect(BatchSyncModule.mergeIncomingBatchEnvelope(batchHistory, crossInsert), isFalse);
    expect(batchHistory['SYS_M1']!.any((b) => b.batch == 'B99'), isFalse);

    // Cross-FY delete of B1 from 2026-27 must NOT delete B1 in 2025-26
    final crossDelete = SyncEnvelope(
      syncId: 'BATCH_SYSM1_B1',
      documentType: 'BATCH',
      action: 'DELETE',
      version: 5,
      updatedAt: 6000,
      isDeleted: 1,
      billData: {
        'fy': '2026-27',
        'medKey': 'SYS_M1',
        'batch': {'batch': 'B1'},
      },
    );
    expect(BatchSyncModule.mergeIncomingBatchEnvelope(batchHistory, crossDelete), isFalse);
    expect(batchHistory['SYS_M1']!.length, equals(1));

    // Medicine envelope updates MRP cleanly but preserves local computed stock (10.0)
    final localMeds = [
      Medicine(id: 'M1', systemId: 'SYS_M1', name: 'Med 1', packing: '10s', mrp: 10, stock: 10.0, version: 1, updatedAt: 1000),
    ];
    final medEnv = SyncEnvelope(
      syncId: 'M1',
      documentType: 'MEDICINE',
      action: 'UPDATE',
      version: 3,
      updatedAt: 9000,
      isDeleted: 0,
      billData: {
        'id': 'M1',
        'systemId': 'SYS_M1',
        'name': 'Med 1',
        'packing': '10s',
        'mrp': 22.0,
        'stock': 999.0, // stale stock from another FY
      },
    );
    expect(MedicineSyncModule.mergeIncomingMedicineEnvelope(localMeds, medEnv), isTrue);
    expect(localMeds.first.mrp, equals(22.0));
    expect(localMeds.first.stock, equals(10.0));
  });

  test('BUG-07, BUG-09, BUG-10 & BUG-16: App & Web Ledger Parity, Cash/UPI zero debt, toDate 23:59:59, and Party-Scoped Pending Bills', () {
    final partyX = Party(id: 'PX', name: 'Party X', group: 'Sundry Debtors', opBal: 0.0);
    final partyY = Party(id: 'PY', name: 'Party Y', group: 'Sundry Debtors', opBal: 0.0);

    final sales = [
      // Credit sale ₹100 on May 10 (billNo 101)
      Sale(
        id: 'S1',
        billNo: '101',
        partyId: 'PX',
        date: DateTime(2025, 5, 10, 11, 0),
        partyName: 'Party X',
        partyGstin: '',
        partyState: 'Rajasthan',
        items: [],
        totalAmount: 100.0,
        paymentMode: 'CREDIT',
      ),
      // Cash sale ₹50 on May 10 evening (22:30) -> must NOT alter Party X net balance, must be included on May 10 toDate
      Sale(
        id: 'S2',
        billNo: '102',
        partyId: 'PX',
        date: DateTime(2025, 5, 10, 22, 30),
        partyName: 'Party X',
        partyGstin: '',
        partyState: 'Rajasthan',
        items: [],
        totalAmount: 50.0,
        paymentMode: 'CASH',
      ),
      // UPI sale ₹25 on May 10 -> must NOT alter Party X net balance either
      Sale(
        id: 'S3',
        billNo: '103',
        partyId: 'PX',
        date: DateTime(2025, 5, 10, 23, 0),
        partyName: 'Party X',
        partyGstin: '',
        partyState: 'Rajasthan',
        items: [],
        totalAmount: 25.0,
        paymentMode: 'UPI',
      ),
      // Deleted credit sale ₹999 on May 10 -> must be ignored everywhere
      Sale(
        id: 'S4',
        billNo: '104',
        partyId: 'PX',
        date: DateTime(2025, 5, 10, 12, 0),
        partyName: 'Party X',
        partyGstin: '',
        partyState: 'Rajasthan',
        items: [],
        totalAmount: 999.0,
        paymentMode: 'CREDIT',
        isDeleted: 1,
      ),
      // Party Y also has billNo '101' for ₹200
      Sale(
        id: 'S5',
        billNo: '101',
        partyId: 'PY',
        date: DateTime(2025, 5, 10, 14, 0),
        partyName: 'Party Y',
        partyGstin: '',
        partyState: 'Rajasthan',
        items: [],
        totalAmount: 200.0,
        paymentMode: 'CREDIT',
      ),
      // Next day sale on May 11 -> must NOT appear in May 10 statement
      Sale(
        id: 'S6',
        billNo: '105',
        partyId: 'PX',
        date: DateTime(2025, 5, 11, 9, 0),
        partyName: 'Party X',
        partyGstin: '',
        partyState: 'Rajasthan',
        items: [],
        totalAmount: 300.0,
        paymentMode: 'CREDIT',
      ),
    ];

    // Receipt for Party X fully settling billNo '101' (₹100) — must NOT settle Party Y's '101'
    final vouchers = [
      Voucher(
        id: 'V1',
        type: 'Receipt',
        voucherNo: 'RCT-1',
        date: DateTime(2025, 5, 12),
        partyId: 'PX',
        partyName: 'Party X',
        amount: 100.0,
        paymentMode: 'Cash',
        billAllocations: {'101': 100.0},
      ),
      // Deleted voucher for Party Y must be ignored
      Voucher(
        id: 'V2',
        type: 'Receipt',
        voucherNo: 'RCT-2',
        date: DateTime(2025, 5, 12),
        partyId: 'PY',
        partyName: 'Party Y',
        amount: 200.0,
        paymentMode: 'Cash',
        billAllocations: {'101': 200.0},
        isDeleted: 1,
      ),
    ];

    // App & Web statement for Party X on May 10 only: Credit ₹100 + May 10 Cash/UPI immediate settlements -> closing balance = -100.0
    final appStmtMay10 = AppAccountsCalculator.getPartyStatementData(
      party: partyX,
      fromDate: DateTime(2025, 5, 10),
      toDate: DateTime(2025, 5, 10),
      sales: sales,
      purchases: [],
      saleReturns: [],
      purchaseReturns: [],
      vouchers: [],
    );
    final webStmtMay10 = WebAccountsCalculator.getPartyStatementData(
      party: partyX,
      fromDate: DateTime(2025, 5, 10),
      toDate: DateTime(2025, 5, 10),
      sales: sales,
      purchases: [],
      saleReturns: [],
      purchaseReturns: [],
      vouchers: [],
    );
    expect(appStmtMay10.last['balance'], equals(100.0));
    expect(webStmtMay10.last['balance'], equals(100.0));
    expect(appStmtMay10.any((r) => r['ref'] == '104' || r['ref'] == '105'), isFalse);

    // Full balance parity (Credit S1=100 + Credit S6=300 - Receipt V1=100 => -300.0)
    final double appBalX = AppAccountsCalculator.calculatePartyBalance(
      party: partyX,
      sales: sales,
      purchases: [],
      saleReturns: [],
      purchaseReturns: [],
      vouchers: vouchers,
    );
    final double webBalX = WebAccountsCalculator.calculatePartyBalance(
      party: partyX,
      sales: sales,
      purchases: [],
      saleReturns: [],
      purchaseReturns: [],
      vouchers: vouchers,
    );
    expect(appBalX, equals(300.0));
    expect(webBalX, equals(300.0));

    // Pending bills: Party X's '101' is settled, Party Y's '101' remains ₹200 pending!
    final carried = [
      {'billNo': 'OLD-99', 'partyId': 'PX', 'partyName': 'Party X', 'date': '2025-03-15T00:00:00.000', 'amount': 40.0, 'type': 'SALE'},
    ];
    final appPendingX = AppAccountsCalculator.getPendingBills(
      partyId: 'PX',
      isReceipt: true,
      sales: sales,
      purchases: [],
      vouchers: vouchers,
      parties: [partyX, partyY],
      carriedPendingInvoices: carried,
    );
    final webPendingX = WebAccountsCalculator.getPendingBills(
      partyId: 'PX',
      isReceipt: true,
      sales: sales,
      purchases: [],
      vouchers: vouchers,
      parties: [partyX, partyY],
      carriedPendingInvoices: carried,
    );
    expect(appPendingX.map((e) => e['billNo']).toSet(), equals({'105', 'OLD-99'}));
    expect(webPendingX.map((e) => e['billNo']).toSet(), equals({'105', 'OLD-99'}));

    final appPendingY = AppAccountsCalculator.getPendingBills(
      partyId: 'PY',
      isReceipt: true,
      sales: sales,
      purchases: [],
      vouchers: vouchers,
      parties: [partyX, partyY],
    );
    expect(appPendingY.length, equals(1));
    expect(appPendingY.first['billNo'], equals('101'));
    expect(appPendingY.first['amount'], equals(200.0));

    // FYTransferEngine.buildPendingInvoices must also keep PY's '101' pending
    final fyPending = FYTransferEngine.buildPendingInvoices(
      sales: sales,
      purchases: [],
      vouchers: vouchers,
    );
    expect(fyPending.any((e) => e['partyId'] == 'PY' && e['billNo'] == '101' && e['amount'] == 200.0), isTrue);
    expect(fyPending.any((e) => e['partyId'] == 'PX' && e['billNo'] == '101'), isFalse);
  });

  test('BUG-08: StockFlowEngine matches InventoryLogicCenter across Opening, Purchase, Sale, DN/CN & toDate 23:59:59', () {
    final ph = createIsolatedAppManager();
    final med = Medicine(id: 'M1', systemId: 'SYS_M1', name: 'Azithro 500', packing: '5s');
    ph.medicines = [med];
    ph.batchHistory[med.identityKey] = [
      BatchInfo(batch: 'B1', exp: '12/27', packing: '5s', mrp: 100, rate: 60, openingQty: 10.0, adjustmentQty: 2.0),
    ];
    ph.purchases = [
      Purchase(
        id: 'P1',
        internalNo: 'PUR-1',
        billNo: '1',
        partyId: 'PX',
        date: DateTime(2025, 5, 10, 10, 0),
        entryDate: DateTime(2025, 5, 10, 10, 0),
        distributorName: 'PX',
        items: [
          PurchaseItem(id: '1', srNo: 1, medicineID: med.identityKey, name: med.name, packing: med.packing, batch: 'B1', exp: '12/27', hsn: '3004', mrp: 100, qty: 20, purchaseRate: 60, gstRate: 12, total: 1200),
        ],
        totalAmount: 1200,
        paymentMode: 'CREDIT',
      ),
    ];
    ph.sales = [
      Sale(
        id: 'S1',
        billNo: 'INV-1',
        partyId: 'PX',
        date: DateTime(2025, 5, 10, 21, 0),
        partyName: 'PX',
        partyGstin: '',
        partyState: 'Rajasthan',
        items: [
          BillItem(id: '1', srNo: 1, medicineID: med.id, name: med.name, packing: med.packing, batch: 'B1', exp: '12/27', hsn: '3004', mrp: 100, qty: 5, rate: 80, gstRate: 12, total: 400),
        ],
        totalAmount: 400,
        paymentMode: 'CREDIT',
      ),
    ];
    ph.purchaseReturns = [
      PurchaseReturn(
        id: 'PR1',
        billNo: 'DN-1',
        date: DateTime(2025, 5, 10, 22, 0),
        distributorName: 'PX',
        items: [
          PurchaseItem(id: '1', srNo: 1, medicineID: med.id, name: med.name, packing: med.packing, batch: 'B1', exp: '12/27', hsn: '3004', mrp: 100, qty: 3, purchaseRate: 60, gstRate: 12, total: 180, isBreakage: true),
        ],
        totalAmount: 180,
      ),
    ];

    InventoryLogicCenter.rebuildAllInventory(
      medicines: ph.medicines,
      batchHistory: ph.batchHistory,
      purchases: ph.purchases,
      sales: ph.sales,
      saleReturns: ph.saleReturns,
      purchaseReturns: ph.purchaseReturns,
    );
    // 10 (open) + 2 (adj) + 20 (pur) - 5 (sale) - 3 (DN) = 24.0
    expect(med.stock, equals(24.0));

    final flow = StockFlowEngine.getItemFlow(
      med: med,
      from: DateTime(2025, 5, 10),
      to: DateTime(2025, 5, 10),
      ph: ph,
    );
    expect(flow['opening'], equals(12.0));
    expect(flow['received'], equals(20.0));
    expect(flow['sale'], equals(8.0)); // 5 Sale + 3 DN
    expect(flow['closing'], equals(24.0));
  });
}
