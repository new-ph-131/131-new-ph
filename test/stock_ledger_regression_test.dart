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
import 'package:pharoah_erp/compliance/gst_offline_engine/gst_state_codes.dart';
import 'package:pharoah_erp/compliance/gst_offline_engine/gst_offline_json_builder.dart';
import 'package:pharoah_erp/compliance/gst_offline_engine/gst_offline_csv_builder.dart';
import 'package:pharoah_erp/compliance/gst_offline_engine/gst_preflight_validator.dart';
import 'package:pharoah_erp/logic/app_settings_model.dart';
import 'package:pharoah_erp/logic/gst_compliance_helper.dart';
import 'package:pharoah_erp/logic/app_billing_gst_engine.dart';
import 'package:pharoah_erp/web_live_sync/sub_views/web_billing/mechanism/web_billing_gst_engine.dart';
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
      // Sellable Debit Note (qty 3) MUST deduct good stock; Breakage Debit Note (qty 2) MUST NOT deduct good stock
      PurchaseReturn(
        id: 'PR1',
        billNo: 'DN-1',
        date: DateTime(2025, 5, 10, 22, 0),
        distributorName: 'PX',
        items: [
          PurchaseItem(id: '1', srNo: 1, medicineID: med.id, name: med.name, packing: med.packing, batch: 'B1', exp: '12/27', hsn: '3004', mrp: 100, qty: 3, purchaseRate: 60, gstRate: 12, total: 180, isBreakage: false),
          PurchaseItem(id: '2', srNo: 2, medicineID: med.id, name: med.name, packing: med.packing, batch: 'B1', exp: '12/27', hsn: '3004', mrp: 100, qty: 2, purchaseRate: 60, gstRate: 12, total: 120, isBreakage: true),
        ],
        totalAmount: 300,
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
    // 10 (open) + 2 (adj) + 20 (pur) - 5 (sale) - 3 (Sellable DN) = 24.0 (Breakage DN 2 ignored on good stock)
    expect(med.stock, equals(24.0));

    final flow = StockFlowEngine.getItemFlow(
      med: med,
      from: DateTime(2025, 5, 10),
      to: DateTime(2025, 5, 10),
      ph: ph,
    );
    expect(flow['opening'], equals(12.0));
    expect(flow['received'], equals(20.0));
    expect(flow['sale'], equals(8.0)); // 5 Sale + 3 Sellable DN
    expect(flow['closing'], equals(24.0));
  });

  test('PHASE-1: Loose stock preserved on Sale/DN and StockFlowEngine matches across differing medicineID via name fallback', () {
    final medLoose = Medicine(id: 'MED_LOOSE', systemId: 'SYS_LOOSE', name: 'Syrup Loose', packing: '100ml', stock: 25.0);
    final medNamed = Medicine(id: 'LOCAL_M1', systemId: 'SYS_M1', name: 'Pan 40', packing: '15s', mrp: 150, stock: 10.0);
    final ph = PharoahManager()
      ..medicines = [medLoose, medNamed]
      ..batchHistory = {
        medNamed.identityKey: [
          BatchInfo(batch: 'B1', exp: '12/27', packing: '15s', mrp: 150, rate: 100, openingQty: 10.0, qty: 10.0),
        ],
      }
      ..purchases = []
      ..sales = [
        Sale(
          id: 'S_LOOSE',
          billNo: 'SL-9',
          partyId: 'P1',
          date: DateTime(2025, 5, 10),
          partyName: 'P1',
          partyGstin: '',
          partyState: 'Rajasthan',
          items: [
            BillItem(id: '1', srNo: 1, medicineID: medLoose.id, name: medLoose.name, packing: '100ml', batch: '', exp: '', hsn: '3004', mrp: 90, qty: 2, rate: 80, gstRate: 12, total: 160),
          ],
          totalAmount: 160,
          paymentMode: 'CREDIT',
        ),
      ]
      ..saleReturns = [
        // Simulated Web Credit Note arriving with DIFFERENT medicineID ('WEB_DIFF_ID') but same name 'Pan 40'
        SaleReturn(
          id: 'SR_CROSS',
          billNo: 'WCN-9',
          date: DateTime(2025, 5, 10),
          partyName: 'P1',
          items: [
            BillItem(id: '1', srNo: 1, medicineID: 'WEB_DIFF_ID', name: 'Pan 40', packing: '15s', batch: 'B1', exp: '12/27', hsn: '3004', mrp: 150, qty: 4, rate: 110, gstRate: 12, total: 440, isBreakage: false),
          ],
          totalAmount: 440,
        ),
      ]
      ..purchaseReturns = [
        PurchaseReturn(
          id: 'PR_CROSS',
          billNo: 'WDN-9',
          date: DateTime(2025, 5, 10),
          distributorName: 'P1',
          items: [
            PurchaseItem(id: '1', srNo: 1, medicineID: 'WEB_DIFF_ID', name: 'Pan 40', packing: '15s', batch: 'B1', exp: '12/27', hsn: '3004', mrp: 150, qty: 1, purchaseRate: 95, gstRate: 12, total: 95, isBreakage: false),
            PurchaseItem(id: '2', srNo: 2, medicineID: 'WEB_DIFF_ID', name: 'Pan 40', packing: '15s', batch: 'B1', exp: '12/27', hsn: '3004', mrp: 150, qty: 3, purchaseRate: 95, gstRate: 12, total: 285, isBreakage: true),
          ],
          totalAmount: 380,
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

    // Loose item without batchHistory must NOT be wiped to 0.0
    expect(medLoose.stock, equals(25.0));
    expect(ph.batchHistory.containsKey(medLoose.identityKey), isFalse);

    // Cross-ID Pan 40: 10 (open) + 4 (Sellable CN) - 1 (Sellable DN) = 13.0 (Breakage DN 3 ignored)
    expect(medNamed.stock, equals(13.0));
    final flow = StockFlowEngine.getItemFlow(
      med: medNamed,
      from: DateTime(2025, 5, 10),
      to: DateTime(2025, 5, 10),
      ph: ph,
    );
    expect(flow['opening'], equals(10.0));
    expect(flow['received'], equals(4.0));
    expect(flow['sale'], equals(1.0));
    expect(flow['closing'], equals(13.0));
  });

  test('PHASE-2: Cash CN / DN accounting, POS state resolution, and Section 34 Commercial Note exemption', () {
    final ph = PharoahManager();
    ph.currentFY = '2025-26';
    final shop = CompanyProfile(
      id: 'C1',
      name: 'Pharoah Pharma',
      businessType: 'Wholesale',
      createdAt: DateTime(2025, 4, 1),
      password: '1234',
      gstin: '08AAAAA0000A1Z5',
      state: 'Rajasthan',
    );
    ph.activeCompany = shop;

    // 1. POS State Resolution via GstStateCodes & GstComplianceHelper
    expect(GstStateCodes.resolvePos('27AAAAA0000A1Z5', 'Maharashtra'), equals('27'));
    expect(GstStateCodes.resolvePos('', 'Rajasthan'), equals('08'));
    expect(
      GstComplianceHelper.isIntraStateReturn(
        shopGstin: '08AAAAA0000A1Z5',
        shopState: 'Rajasthan',
        partyGstin: '08BBBBB1111B1Z2',
        partyState: 'Rajsthan', // Typo state must be overridden by GSTIN code 08
      ),
      isTrue,
    );
    expect(
      GstComplianceHelper.isIntraStateReturn(
        shopGstin: '08AAAAA0000A1Z5',
        shopState: 'Rajasthan',
        partyGstin: '27BBBBB1111B1Z2',
        partyState: 'Rajasthan',
      ),
      isFalse,
    );

    // 1b. Section 34(2) Statutory Cutoff (30 Nov following end of FY of orig invoice)
    expect(
      GstComplianceHelper.isSection34Expired(
        origInvoiceDate: DateTime(2024, 10, 15), // FY 2024-25 -> cutoff Nov 30, 2025
        noteDate: DateTime(2025, 11, 30),
      ),
      isFalse,
    );
    expect(
      GstComplianceHelper.isSection34Expired(
        origInvoiceDate: DateTime(2024, 10, 15), // FY 2024-25 -> cutoff Nov 30, 2025
        noteDate: DateTime(2025, 12, 1),
      ),
      isTrue,
    );

    // 2. Cash CN/DN vs Credit CN/DN ledger & App/Web Parity
    final customer = Party(id: 'P1', name: 'Apollo Pharmacy', gst: '08BBBBB1111B1Z2', state: 'Rajasthan', group: 'Sundry Debtors', opBal: 1000.0);
    final cashLedger = Party(id: 'cash', name: 'Cash in Hand', group: 'Cash in Hand', opBal: 2000.0);
    ph.parties = [customer];
    ph.sales = [];
    ph.purchases = [];
    ph.vouchers = [];

    final billItem = BillItem(
      id: 'BI-1',
      srNo: 1,
      medicineID: 'M1',
      name: 'Paracetamol 650',
      packing: '15s',
      batch: 'B1',
      exp: '12/27',
      hsn: '3004',
      mrp: 30.0,
      rate: 20.0,
      gstRate: 12.0,
      qty: 10.0,
      freeQty: 0.0,
      total: 224.0,
    );
    final purItem = PurchaseItem(
      id: 'PI-1',
      srNo: 1,
      medicineID: 'M1',
      name: 'Paracetamol 650',
      packing: '15s',
      batch: 'B1',
      exp: '12/27',
      hsn: '3004',
      mrp: 30.0,
      qty: 10.0,
      purchaseRate: 15.0,
      gstRate: 12.0,
      total: 168.0,
    );

    final cashCn = SaleReturn(
      id: 'CN-CASH',
      billNo: 'CC-1',
      date: DateTime(2025, 5, 10),
      partyId: 'P1',
      partyName: 'Apollo Pharmacy',
      partyGstin: '08BBBBB1111B1Z2',
      partyState: 'Rajasthan',
      items: [billItem],
      totalAmount: 500.0,
      paymentMode: 'CASH',
      isCommercial: false,
    );
    final creditCn = SaleReturn(
      id: 'CN-CREDIT',
      billNo: 'CN-2',
      date: DateTime(2025, 5, 11),
      partyId: 'P1',
      partyName: 'Apollo Pharmacy',
      partyGstin: '08BBBBB1111B1Z2',
      partyState: 'Rajasthan',
      items: [billItem],
      totalAmount: 200.0,
      paymentMode: 'CREDIT',
      isCommercial: true,
    );
    final cashDn = PurchaseReturn(
      id: 'DN-CASH',
      billNo: 'DC-1',
      date: DateTime(2025, 5, 12),
      partyId: 'P1',
      distributorName: 'Apollo Pharmacy',
      partyGstin: '08BBBBB1111B1Z2',
      partyState: 'Rajasthan',
      items: [purItem],
      totalAmount: 150.0,
      paymentMode: 'CASH',
      origBillNo: 'INV-99',
      origBillDate: DateTime(2025, 4, 20),
      reason: '01-Sales Return',
      isCommercial: false,
    );
    ph.saleReturns = [cashCn, creditCn];
    ph.purchaseReturns = [cashDn];

    // Party balance: OpBal 1000 - Credit CN 200 = 800 (Cash CN & Cash DN are immediately settled!)
    final double appPartyBal = AppAccountsCalculator.calculatePartyBalance(
      party: customer,
      sales: ph.sales,
      purchases: ph.purchases,
      saleReturns: ph.saleReturns,
      purchaseReturns: ph.purchaseReturns,
      vouchers: ph.vouchers,
    );
    final double webPartyBal = WebAccountsCalculator.calculatePartyBalance(
      party: customer,
      sales: ph.sales,
      purchases: ph.purchases,
      saleReturns: ph.saleReturns,
      purchaseReturns: ph.purchaseReturns,
      vouchers: ph.vouchers,
    );
    expect(appPartyBal, equals(800.0));
    expect(webPartyBal, equals(appPartyBal));

    final appStmt = AppAccountsCalculator.getPartyStatementData(
      party: customer,
      sales: ph.sales,
      purchases: ph.purchases,
      saleReturns: ph.saleReturns,
      purchaseReturns: ph.purchaseReturns,
      vouchers: ph.vouchers,
      fromDate: DateTime(2025, 4, 1),
      toDate: DateTime(2026, 3, 31),
    );
    final webStmt = WebAccountsCalculator.getPartyStatementData(
      party: customer,
      sales: ph.sales,
      purchases: ph.purchases,
      saleReturns: ph.saleReturns,
      purchaseReturns: ph.purchaseReturns,
      vouchers: ph.vouchers,
      fromDate: DateTime(2025, 4, 1),
      toDate: DateTime(2026, 3, 31),
    );
    expect(appStmt.last['balance'], equals(appPartyBal));
    expect(webStmt.last['balance'], equals(appPartyBal));

    // Cash-in-Hand balance: 2000 - 500 (Cash CN) + 150 (Cash DN) = 1650
    final double appCashBal = AppAccountsCalculator.calculateCashInHandBalance(
      sales: ph.sales,
      purchases: ph.purchases,
      vouchers: ph.vouchers,
      saleReturns: ph.saleReturns,
      purchaseReturns: ph.purchaseReturns,
      openingCash: 2000.0,
    );
    final double appCashLedgerBal = AppAccountsCalculator.calculatePartyBalance(
      party: cashLedger,
      sales: ph.sales,
      purchases: ph.purchases,
      saleReturns: ph.saleReturns,
      purchaseReturns: ph.purchaseReturns,
      vouchers: ph.vouchers,
    );
    final double webCashLedgerBal = WebAccountsCalculator.calculatePartyBalance(
      party: cashLedger,
      sales: ph.sales,
      purchases: ph.purchases,
      saleReturns: ph.saleReturns,
      purchaseReturns: ph.purchaseReturns,
      vouchers: ph.vouchers,
    );
    expect(appCashBal, equals(1650.0));
    expect(appCashLedgerBal, equals(1650.0));
    expect(webCashLedgerBal, equals(1650.0));

    final cashBook = AppAccountsCalculator.getCashBookStatement(
      fromDate: DateTime(2025, 4, 1),
      toDate: DateTime(2026, 3, 31),
      sales: ph.sales,
      purchases: ph.purchases,
      vouchers: ph.vouchers,
      saleReturns: ph.saleReturns,
      purchaseReturns: ph.purchaseReturns,
    );
    expect(cashBook.any((e) => e['type'] == 'CASH CREDIT NOTE' && e['out'] == 500.0), isTrue);
    expect(cashBook.any((e) => e['type'] == 'CASH DEBIT NOTE' && e['in'] == 150.0), isTrue);

    // 3. Commercial Note (Sec 34) zeroes GST in App & Web engines & excludes from GSTR-1/2 exports
    final appCommCn = AppBillingGstEngine.calculate(items: [billItem], extraDiscount: 0.0, isLocal: true, isCommercial: true);
    final webCommDn = WebBillingGstEngine.calculateForPurchase(items: [purItem], extraDiscount: 0.0, isLocal: false, isCommercial: true);
    expect(appCommCn.totalTax, equals(0.0));
    expect(appCommCn.finalGrandTotal, equals(200.0));
    expect(webCommDn.totalTax, equals(0.0));
    expect(webCommDn.finalGrandTotal, equals(150.0));

    final gstr1 = GstOfflineJsonBuilder.buildGstr1Payload(
      sales: const [],
      returns: ph.saleReturns,
      parties: ph.parties,
      shop: shop,
      fromDate: DateTime(2025, 5, 1),
      toDate: DateTime(2025, 5, 31),
    );
    // Only CC-1 (isCommercial: false) should be included; CN-2 (isCommercial: true) excluded
    expect(gstr1.cdnr.length, equals(1));
    expect(gstr1.cdnr.first.nt.length, equals(1));
    expect(gstr1.cdnr.first.nt.first.ntNum, equals('CC-1'));

    final cdnrCsv = GstOfflineCsvBuilder.buildCdnrCsv(
      returns: ph.saleReturns,
      parties: ph.parties,
      shop: shop,
      fromDate: DateTime(2025, 5, 1),
      toDate: DateTime(2025, 5, 31),
    );
    expect(cdnrCsv.contains('CC-1'), isTrue);
    expect(cdnrCsv.contains('CN-2'), isFalse);
  });

  test('Phase 3: getMedicineHistory real exp/discount, updateSaleReturn/updatePurchaseReturn, DEBIT_NOTE series, B2CS vs CDNUR & HSN/DOCS returns', () async {
    final ph = PharoahManager();
    ph.activeCompany = CompanyProfile(
      id: 'c_p3',
      name: 'MedPlus Pharma',
      businessType: 'PHARMA_RETAIL',
      createdAt: DateTime(2025, 4, 1),
      password: 'admin',
      gstin: '08AABCP1234A1Z4',
      state: 'Rajasthan',
    );

    final custUnreg = Party(id: 'p_b2c', name: 'Retail Walkin', gst: '', state: 'Rajasthan');
    final custB2cl = Party(id: 'p_b2cl', name: 'MP Unreg', gst: '', state: 'Madhya Pradesh');
    final supp = Party(id: 's_1', name: 'Apex Distributors', gst: '27AABCA1111B1Z2', state: 'Maharashtra');
    ph.parties = [custUnreg, custB2cl, supp];

    final med = Medicine(id: 'm_p3', systemId: 'PH-999', name: 'Augmentin 625', packing: '1x10', hsnCode: '3004', gst: 12.0, mrp: 220.0, rateA: 150.0, purRate: 100.0);
    ph.medicines = [med];

    ph.sales = [
      Sale(
        id: 'sal_1',
        billNo: 'INV-100',
        partyId: custUnreg.id,
        partyName: custUnreg.name,
        partyGstin: '',
        partyState: 'Rajasthan',
        date: DateTime(2025, 6, 10),
        paymentMode: 'CASH',
        status: 'Active',
        items: [
          BillItem(
            id: 'bi_1',
            srNo: 1,
            medicineID: med.id,
            name: med.name,
            packing: '1x10',
            batch: 'AUG01',
            exp: '09/28',
            hsn: '3004',
            mrp: 220.0,
            qty: 10.0,
            rate: 100.0,
            discountPer: 10.0,
            discountRupees: 100.0,
            gstRate: 12.0,
            appliedRateType: 'B',
            total: 1008.0,
          ),
        ],
        totalAmount: 1008.0,
      ),
      // Cancelled bill should NOT show in Magic History
      Sale(
        id: 'sal_canc',
        billNo: 'INV-CANC',
        partyId: custUnreg.id,
        partyName: custUnreg.name,
        partyGstin: '',
        partyState: 'Rajasthan',
        date: DateTime(2025, 6, 11),
        paymentMode: 'CASH',
        status: 'Cancelled',
        items: [
          BillItem(id: 'bi_c', srNo: 1, medicineID: med.id, name: med.name, packing: '1x10', batch: 'BAD99', exp: '01/20', hsn: '3004', mrp: 220.0, qty: 5.0, rate: 100.0, gstRate: 12.0, total: 560.0),
        ],
        totalAmount: 560.0,
      ),
    ];

    ph.purchases = [
      Purchase(
        id: 'pur_1',
        internalNo: 'PUR-100',
        billNo: 'SUP-900',
        partyId: supp.id,
        distributorName: supp.name,
        date: DateTime(2025, 6, 5),
        entryDate: DateTime(2025, 6, 5),
        paymentMode: 'CREDIT',
        items: [
          PurchaseItem(
            id: 'pi_1',
            srNo: 1,
            medicineID: med.id,
            name: med.name,
            packing: '1x10',
            batch: 'AUG01',
            exp: '09/28',
            hsn: '3004',
            mrp: 220.0,
            qty: 20.0,
            purchaseRate: 80.0,
            discountPer: 5.0,
            discountRupees: 80.0,
            gstRate: 12.0,
            appliedRateType: 'C',
            total: 1702.4,
          ),
        ],
        totalAmount: 1702.4,
      ),
    ];

    // 1. Magic History preserves real expiry, discountPer, appliedRateType & excludes cancelled
    final saleHist = ph.getMedicineHistory(partyId: custUnreg.id, medicineId: med.id, isSale: true);
    expect(saleHist.length, equals(1));
    expect(saleHist.first['exp'], equals('09/28'));
    expect(saleHist.first['discountPer'], equals(10.0));
    expect(saleHist.first['appliedRateType'], equals('B'));

    final purHist = ph.getMedicineHistory(partyId: '', partyName: 'apex distributors', medicineId: '', medicineName: 'augmentin 625', isSale: false);
    expect(purHist.length, equals(1));
    expect(purHist.first['exp'], equals('09/28'));
    expect(purHist.first['discountPer'], equals(5.0));
    expect(purHist.first['appliedRateType'], equals('C'));

    // 2. DEBIT_NOTE numbering series fallback
    expect(ph.getDefaultSeries('DEBIT_NOTE').prefix, equals('DN-'));

    // 3. updateSaleReturn & updatePurchaseReturn dynamically compute returnType and bump version
    ph.saleReturns = [
      SaleReturn(
        id: 'sr_u1',
        billNo: 'TXN-1',
        partyId: custUnreg.id,
        partyName: custUnreg.name,
        partyGstin: '',
        partyState: 'Rajasthan',
        date: DateTime(2025, 6, 15),
        items: [
          BillItem(id: 'r1', srNo: 1, medicineID: med.id, name: med.name, packing: '1x10', batch: 'AUG01', exp: '09/28', hsn: '3004', mrp: 220.0, qty: 2.0, rate: 100.0, discountPer: 10.0, discountRupees: 20.0, gstRate: 12.0, isBreakage: false, total: 201.6),
        ],
        totalAmount: 201.6,
        returnType: 'Sellable',
        version: 1,
      ),
    ];
    await ph.updateSaleReturn(
      id: 'sr_u1',
      billNo: 'TXN-1',
      date: DateTime(2025, 6, 15),
      party: custUnreg,
      items: [
        BillItem(id: 'r1', srNo: 1, medicineID: med.id, name: med.name, packing: '1x10', batch: 'AUG01', exp: '09/28', hsn: '3004', mrp: 220.0, qty: 2.0, rate: 100.0, discountPer: 10.0, discountRupees: 20.0, gstRate: 12.0, isBreakage: true, total: 201.6),
      ],
      total: 201.6,
      reason: '07-Expired',
    );
    expect(ph.saleReturns.first.returnType, equals('Breakage'));
    expect(ph.saleReturns.first.version, equals(2));
    expect(ph.saleReturns.first.reason, equals('07-Expired'));

    // Reset to sellable unregistered B2C return (<= 1L) + add an unregistered B2CL return (> 1L inter-state)
    final b2cRet = SaleReturn(
      id: 'sr_b2c',
      billNo: 'TXN-2',
      partyId: custUnreg.id,
      partyName: custUnreg.name,
      partyGstin: '',
      partyState: 'Rajasthan',
      date: DateTime(2025, 6, 16),
      items: [
        BillItem(id: 'r2', srNo: 1, medicineID: med.id, name: med.name, packing: '1x10', batch: 'AUG01', exp: '09/28', hsn: '3004', mrp: 220.0, qty: 2.0, rate: 100.0, discountPer: 10.0, discountRupees: 20.0, gstRate: 12.0, total: 201.6),
      ],
      totalAmount: 201.6,
    );
    final b2clRet = SaleReturn(
      id: 'sr_b2cl',
      billNo: 'TXN-3',
      partyId: custB2cl.id,
      partyName: custB2cl.name,
      partyGstin: '',
      partyState: 'Madhya Pradesh',
      date: DateTime(2025, 6, 17),
      items: [
        BillItem(id: 'r3', srNo: 1, medicineID: med.id, name: med.name, packing: '1x10', batch: 'AUG01', exp: '09/28', hsn: '3004', mrp: 220.0, qty: 1000.0, rate: 100.0, gstRate: 12.0, total: 112000.0),
      ],
      totalAmount: 112000.0,
    );

    // 4. B2CS nets small unregistered return (900 - 180 = 720) & CDNUR only holds B2CL return
    final gstr1 = GstOfflineJsonBuilder.buildGstr1Payload(
      sales: [ph.sales.first],
      returns: [b2cRet, b2clRet],
      parties: ph.parties,
      shop: ph.activeCompany!,
      fromDate: DateTime(2025, 6, 1),
      toDate: DateTime(2025, 6, 30),
    );
    expect(gstr1.cdnur.length, equals(1));
    expect(gstr1.cdnur.first.ntNum, equals('TXN-3'));
    expect(gstr1.b2cs.length, equals(1));
    expect(gstr1.b2cs.first.txval, closeTo(720.0, 0.01));
    expect(gstr1.docIssue.any((d) => d.docTyp == 'Credit Note'), isTrue);

    // 5. B2CS & DOCS CSV net credit note / export doc types cleanly
    final b2csCsv = GstOfflineCsvBuilder.buildB2csCsv(
      sales: [ph.sales.first],
      returns: [b2cRet],
      parties: ph.parties,
      shop: ph.activeCompany!,
      fromDate: DateTime(2025, 6, 1),
      toDate: DateTime(2025, 6, 30),
    );
    expect(b2csCsv.contains('720.00'), isTrue);

    final docsCsv = GstOfflineCsvBuilder.buildDocsCsv(
      sales: [ph.sales.first],
      returns: [b2cRet],
      fromDate: DateTime(2025, 6, 1),
      toDate: DateTime(2025, 6, 30),
    );
    expect(docsCsv.contains('Credit Note'), isTrue);

    // 6. Preflight validator deducts active credit notes & warns on Sec 34(2) expiry
    final audit = GstPreflightValidator.audit(
      sales: [ph.sales.first],
      returns: [
        SaleReturn(
          id: 'sr_exp34',
          billNo: 'TXN-OLD',
          partyId: custUnreg.id,
          partyName: custUnreg.name,
          partyState: 'Rajasthan',
          date: DateTime(2026, 12, 15),
          origBillDate: DateTime(2025, 6, 10),
          isCommercial: false,
          items: b2cRet.items,
          totalAmount: 201.6,
        ),
      ],
      parties: ph.parties,
      shop: ph.activeCompany!,
      fromDate: DateTime(2025, 6, 1),
      toDate: DateTime(2026, 12, 31),
    );
    expect(audit.totalTaxable, closeTo(720.0, 0.01));
    expect(audit.issues.any((i) => i.title.contains('Sec 34(2)')), isTrue);
  });


  test('Phase 4: Cancellation reversal, Rule 53(1A) 7 reasons, Commercial Note User Control & CCN- isolation', () {
    // 1. AppConfig Commercial Note defaults, serialization & 2-tier User Control gate
    final cfgDefault = AppConfig();
    expect(cfgDefault.developerAllowCommercialNoteToUser, isFalse);
    expect(cfgDefault.userEnableCommercialNote, isFalse);
    expect(cfgDefault.commercialNotePrefix, equals('CCN-'));
    expect(GstComplianceHelper.isCommercialNoteAllowed(cfgDefault), isFalse);

    final cfgDevOnly = AppConfig(developerAllowCommercialNoteToUser: true, userEnableCommercialNote: false);
    expect(GstComplianceHelper.isCommercialNoteAllowed(cfgDevOnly), isFalse);

    final cfgAllowed = AppConfig.fromMap(
      AppConfig(
        developerAllowCommercialNoteToUser: true,
        userEnableCommercialNote: true,
        commercialNotePrefix: 'CCN-',
      ).toMap(),
    );
    expect(cfgAllowed.developerAllowCommercialNoteToUser, isTrue);
    expect(cfgAllowed.userEnableCommercialNote, isTrue);
    expect(cfgAllowed.commercialNotePrefix, equals('CCN-'));
    expect(GstComplianceHelper.isCommercialNoteAllowed(cfgAllowed), isTrue);

    // 2. GST Rule 53(1A) 7 standard reasons & custom remark parsing/formatting
    expect(GstComplianceHelper.standardReasons.length, equals(7));
    expect(GstComplianceHelper.standardReasons.first, equals('01-Sales Return'));
    expect(GstComplianceHelper.standardReasons.last, equals('07-Other / Expired / Damaged'));

    final parsedStd = GstComplianceHelper.parseReason('02-Post Sale Discount');
    expect(parsedStd.selectedReason, equals('02-Post Sale Discount'));
    expect(parsedStd.customRemark, isEmpty);

    final formattedCustom = GstComplianceHelper.formatReason('07-Other / Expired / Damaged', 'Transit breakage');
    expect(formattedCustom, equals('07-Other / Expired / Damaged: Transit breakage'));
    final parsedCustom = GstComplianceHelper.parseReason(formattedCustom);
    expect(parsedCustom.selectedReason, equals('07-Other / Expired / Damaged'));
    expect(parsedCustom.customRemark, equals('Transit breakage'));

    // 3. Dedicated COMMERCIAL_NOTE (CCN-) series fallback & Web numbering isolation
    final ph = PharoahManager();
    expect(ph.getDefaultSeries('COMMERCIAL_NOTE').prefix, equals('CCN-'));

    final webPh = PharoahWebManager();
    webPh.financialYear = '2025-26';
    expect(webPh.getDefaultSeries('COMMERCIAL_NOTE')?.prefix, equals('CCN-'));

    final med = Medicine(id: 'M_P4', systemId: 'SYS_P4', name: 'Paracetamol 650', packing: '1x10', mrp: 40, rateA: 30, purRate: 20);
    webPh.medicines = [med];
    final cust = Party(id: 'C_P4', name: 'Apollo Pharmacy', gst: '08AABCA1111B1Z2', state: 'Rajasthan');
    webPh.parties = [cust];
    webPh.purchases = [
      Purchase(
        id: 'P_P4',
        internalNo: 'WPUR-1',
        billNo: 'SUP-P4',
        partyId: cust.id,
        date: DateTime(2025, 5, 1),
        entryDate: DateTime(2025, 5, 1),
        distributorName: cust.name,
        items: [
          PurchaseItem(
            id: 'PI_P4',
            srNo: 1,
            medicineID: med.id,
            name: med.name,
            packing: med.packing,
            batch: 'B_P4',
            exp: '12/27',
            hsn: '3004',
            mrp: 40,
            qty: 10,
            purchaseRate: 20,
            gstRate: 12,
            total: 224,
          ),
        ],
        totalAmount: 224,
        paymentMode: 'CREDIT',
      ),
    ];

    final nextCcn1 = webPh.getNextBillNumber('COMMERCIAL_NOTE', 'CCN-', 1);
    expect(nextCcn1, equals('CCN-1'));

    final ccnReturn = SaleReturn(
      id: 'sr_ccn1',
      billNo: nextCcn1,
      partyId: cust.id,
      partyName: cust.name,
      partyGstin: cust.gst,
      partyState: cust.state,
      date: DateTime(2025, 6, 15),
      items: [
        BillItem(
          id: 'r_ccn1',
          srNo: 1,
          medicineID: med.id,
          name: med.name,
          packing: med.packing,
          batch: 'B_P4',
          exp: '12/27',
          hsn: '3004',
          mrp: 40,
          qty: 3,
          rate: 30,
          gstRate: 0,
          total: 90,
        ),
      ],
      totalAmount: 90,
      paymentMode: 'CREDIT',
      reason: formattedCustom,
      isCommercial: true,
      status: 'Active',
    );
    final gstReturn = SaleReturn(
      id: 'sr_gst1',
      billNo: 'WCN-1',
      partyId: cust.id,
      partyName: cust.name,
      partyGstin: cust.gst,
      partyState: cust.state,
      date: DateTime(2025, 6, 16),
      items: [
        BillItem(
          id: 'r_gst1',
          srNo: 1,
          medicineID: med.id,
          name: med.name,
          packing: med.packing,
          batch: 'B_P4',
          exp: '12/27',
          hsn: '3004',
          mrp: 40,
          qty: 2,
          rate: 30,
          gstRate: 12,
          total: 67.2,
        ),
      ],
      totalAmount: 67.2,
      paymentMode: 'CREDIT',
      reason: '01-Sales Return',
      isCommercial: false,
      status: 'Active',
    );

    webPh.saleReturns = [ccnReturn, gstReturn];
    webPh.rebuildInventory();
    // 10 purchased + 3 (CCN-1) + 2 (WCN-1) = 15
    expect(med.stock, equals(15.0));
    expect(webPh.getNextBillNumber('COMMERCIAL_NOTE', 'CCN-', 1), equals('CCN-2'));
    expect(webPh.getNextBillNumber('RETURN', 'WCN-', 1), equals('WCN-2'));

    // 4. Web cancelReturn reverses stock & sets status = 'Cancelled'
    webPh.cancelReturn('sr_gst1', true);
    expect(gstReturn.status, equals('Cancelled'));
    // 10 purchased + 3 (CCN-1) = 13 (WCN-1 stock reversed)
    expect(med.stock, equals(13.0));

    // 5. GSTR-1 Payload & DOCS CSV exclude both CCN- (isCommercial) and Cancelled returns
    final shop = CompanyProfile(
      id: 'c_p4',
      name: 'MedPlus Pharma',
      businessType: 'PHARMA_RETAIL',
      createdAt: DateTime(2025, 4, 1),
      password: 'admin',
      gstin: '08AABCP1234A1Z4',
      state: 'Rajasthan',
    );
    final gstr1 = GstOfflineJsonBuilder.buildGstr1Payload(
      sales: const [],
      returns: webPh.saleReturns,
      parties: webPh.parties,
      shop: shop,
      fromDate: DateTime(2025, 6, 1),
      toDate: DateTime(2025, 6, 30),
    );
    expect(gstr1.cdnr, isEmpty);
    expect(gstr1.docIssue.first.docs.first.from, equals('WCN-1'));
    expect(gstr1.docIssue.first.docs.first.canc, equals(1));

    final docsCsv = GstOfflineCsvBuilder.buildDocsCsv(
      sales: const [],
      returns: webPh.saleReturns,
      fromDate: DateTime(2025, 6, 1),
      toDate: DateTime(2025, 6, 30),
    );
    expect(docsCsv.contains('CCN-1'), isFalse);
    expect(docsCsv.contains('WCN-1'), isTrue);
  });
}
